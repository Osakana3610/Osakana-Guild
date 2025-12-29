// ==============================================================================
// ExplorationRecords.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 探索セッションのSwiftData永続化モデル
//   - 探索実行・イベント履歴・戦闘ログの保存
//
// 【データ構造】
//   - ExplorationRunRecord (@Model): 探索実行レコード
//     - partyId, dungeonId, difficulty, targetFloor, startedAt, seed
//     - randomState: RNG状態（中断復帰用）
//     - superRareJstDate, superRareHasTriggered: 超レア日次状態（スカラ）
//     - droppedItemIdsData: ドロップ済みアイテムID（バイナリ）
//     - endedAt, result, finalFloor, totalExp, totalGold
//     - events: イベントレコード（1対多リレーション）
//
//   - ExplorationAutoSellRecord (@Model): 探索完了時の自動売却サマリー
//   - ExplorationEventRecord (@Model): 探索イベントレコード
//     - floor, kind, enemyId, battleResult, scriptedEventId
//     - exp, gold, occurredAt, run
//     - drops: ドロップレコード（1対多リレーション）
//     - battleLog: 戦闘ログレコード（1対1リレーション）
//
//   - ExplorationDropRecord (@Model): ドロップレコード
//   - BattleLogRecord (@Model): 戦闘ログレコード（logDataにバイナリBLOBで詳細保存）
//
// 【使用箇所】
//   - ExplorationProgressService: 探索履歴の永続化
//   - AppServices.ExplorationResume: 探索再開時の状態復元
//
// ==============================================================================

import Foundation
import SwiftData

// MARK: - ExplorationDropRecord

/// 探索ドロップレコード
///
/// 各ドロップアイテムを個別レコードとして保存。
/// ExplorationEventRecordと1対多のリレーションを持つ。
@Model
final class ExplorationDropRecord {
    var superRareTitleId: UInt8?
    var normalTitleId: UInt8?
    var itemId: UInt16 = 0
    var quantity: UInt16 = 0
    var event: ExplorationEventRecord?

    init(superRareTitleId: UInt8?, normalTitleId: UInt8?, itemId: UInt16, quantity: UInt16) {
        self.superRareTitleId = superRareTitleId
        self.normalTitleId = normalTitleId
        self.itemId = itemId
        self.quantity = quantity
    }
}

// MARK: - ExplorationAutoSellRecord

/// 自動売却サマリーレコード
///
/// 探索完了時に自動売却されたアイテムの集計を保存する。
@Model
final class ExplorationAutoSellRecord {
    var superRareTitleId: UInt8 = 0
    var normalTitleId: UInt8 = 2
    var itemId: UInt16 = 0
    var quantity: UInt16 = 0
    var run: ExplorationRunRecord?

    init(superRareTitleId: UInt8,
         normalTitleId: UInt8,
         itemId: UInt16,
         quantity: UInt16) {
        self.superRareTitleId = superRareTitleId
        self.normalTitleId = normalTitleId
        self.itemId = itemId
        self.quantity = quantity
    }
}

// MARK: - BattleLogRecord

/// 戦闘ログレコード
///
/// BattleLogArchiveをバイナリBLOBで保存するSwiftDataモデル。
/// 詳細データ（initialHP、actions、participants）はlogDataにまとめて格納。
@Model
final class BattleLogRecord {
    var enemyId: UInt16 = 0
    var enemyName: String = ""
    var result: UInt8 = 0  // 0=victory, 1=defeat, 2=retreat
    var turns: UInt8 = 0
    var timestamp: Date = Date()
    var outcome: UInt8 = 0  // BattleLog.outcome

    var event: ExplorationEventRecord?

    /// 戦闘ログ詳細（バイナリBLOB）
    /// フォーマット: ExplorationProgressService.encodeBattleLogData() 参照
    var logData: Data = Data()

    init() {}
}

// MARK: - ExplorationEventRecord

/// 探索イベントレコード
///
/// 各探索イベント（戦闘、スクリプトイベント等）を個別レコードとして保存。
/// ExplorationRunRecordと1対多のリレーションを持つ。
@Model
final class ExplorationEventRecord {
    var floor: UInt8 = 0
    var kind: UInt8 = 0  // EventKind.rawValue
    var enemyId: UInt16?
    var battleResult: UInt8?
    var scriptedEventId: UInt8?
    var exp: UInt32 = 0
    var gold: UInt32 = 0
    var occurredAt: Date = Date()

    /// 親への参照
    var run: ExplorationRunRecord?

    /// ドロップアイテム（正規化されたリレーション）
    @Relationship(deleteRule: .cascade, inverse: \ExplorationDropRecord.event)
    var drops: [ExplorationDropRecord] = []

    /// 戦闘ログ（正規化されたリレーション）
    @Relationship(deleteRule: .cascade, inverse: \BattleLogRecord.event)
    var battleLog: BattleLogRecord?

    init(floor: UInt8,
         kind: UInt8,
         enemyId: UInt16?,
         battleResult: UInt8?,
         scriptedEventId: UInt8?,
         exp: UInt32,
         gold: UInt32,
         occurredAt: Date) {
        self.floor = floor
        self.kind = kind
        self.enemyId = enemyId
        self.battleResult = battleResult
        self.scriptedEventId = scriptedEventId
        self.exp = exp
        self.gold = gold
        self.occurredAt = occurredAt
    }
}

// MARK: - ExplorationRunRecord

/// 探索実行レコード
@Model
final class ExplorationRunRecord {
    /// パーティID
    var partyId: UInt8 = 1

    /// ダンジョンID（MasterData）
    var dungeonId: UInt16 = 0

    /// 難易度（0〜255）
    var difficulty: UInt8 = 0

    /// 目標フロア
    var targetFloor: UInt8 = 0

    /// 探索開始日時（識別子の一部として使用）
    var startedAt: Date = Date()

    /// 決定論的乱数のシード
    /// Note: iOS 17.2以下でSwiftDataのUInt64アクセスがクラッシュするためInt64を使用
    var seed: Int64 = 0

    /// 最新イベント処理後のRNG状態（0 = まだ保存なし）
    /// Note: iOS 17.2以下でSwiftDataのUInt64アクセスがクラッシュするためInt64を使用
    var randomState: Int64 = 0

    /// 超レア抽選の日次状態：JST日付（YYYYMMDD形式）
    var superRareJstDate: UInt32 = 0

    /// 超レア抽選の日次状態：発動済みフラグ
    var superRareHasTriggered: Bool = false

    /// ドロップ済みアイテムID（バイナリフォーマット：2バイト件数 + 各2バイトID）
    var droppedItemIdsData: Data = Data()

    /// 探索終了日時
    var endedAt: Date = Date()

    /// 探索結果: 0=running, 1=completed, 2=defeated, 3=cancelled
    var result: UInt8 = 0

    /// 到達フロア
    var finalFloor: UInt8 = 0

    /// 獲得経験値合計
    var totalExp: UInt32 = 0

    /// 獲得ゴールド合計
    var totalGold: UInt32 = 0

    /// 自動売却で獲得したゴールド
    var autoSellGold: UInt32 = 0

    /// 自動売却アイテム（正規化されたリレーション）
    @Relationship(deleteRule: .cascade, inverse: \ExplorationAutoSellRecord.run)
    var autoSellItems: [ExplorationAutoSellRecord] = []

    /// イベントレコード（正規化されたリレーション）
    @Relationship(deleteRule: .cascade, inverse: \ExplorationEventRecord.run)
    var events: [ExplorationEventRecord] = []

    init(partyId: UInt8,
         dungeonId: UInt16,
         difficulty: UInt8,
         targetFloor: UInt8,
         startedAt: Date,
         seed: Int64) {
        self.partyId = partyId
        self.dungeonId = dungeonId
        self.difficulty = difficulty
        self.targetFloor = targetFloor
        self.startedAt = startedAt
        self.seed = seed
    }
}

// MARK: - Result Helpers

extension ExplorationRunRecord {
    var explorationResult: ExplorationResult {
        ExplorationResult(rawValue: result) ?? .running
    }

    var isFinished: Bool {
        result != ExplorationResult.running.rawValue
    }
}
