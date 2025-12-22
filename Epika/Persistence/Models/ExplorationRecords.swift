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
//   - ExplorationEventRecord (@Model): 探索イベントレコード
//     - floor, kind, enemyId, battleResult, scriptedEventId
//     - exp, gold, occurredAt, run
//     - drops: ドロップレコード（1対多リレーション）
//     - battleLog: 戦闘ログレコード（1対1リレーション）
//
//   - ExplorationDropRecord (@Model): ドロップレコード
//   - BattleLogRecord (@Model): 戦闘ログレコード
//   - BattleLogInitialHPRecord, BattleLogActionRecord, BattleLogParticipantRecord
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

// MARK: - BattleLogRecord

/// 戦闘ログレコード
///
/// BattleLogArchiveを正規化したSwiftDataモデル。
/// JSONではなくリレーションで全データを保持。
@Model
final class BattleLogRecord {
    var enemyId: UInt16 = 0
    var enemyName: String = ""
    var result: UInt8 = 0  // 0=victory, 1=defeat, 2=retreat
    var turns: UInt8 = 0
    var timestamp: Date = Date()
    var outcome: UInt8 = 0  // BattleLog.outcome

    var event: ExplorationEventRecord?

    @Relationship(deleteRule: .cascade, inverse: \BattleLogInitialHPRecord.battleLog)
    var initialHPs: [BattleLogInitialHPRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \BattleLogActionRecord.battleLog)
    var actions: [BattleLogActionRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \BattleLogParticipantRecord.battleLog)
    var participants: [BattleLogParticipantRecord] = []

    init() {}
}

// MARK: - BattleLogInitialHPRecord

/// 戦闘開始時HPレコード
@Model
final class BattleLogInitialHPRecord {
    var actorIndex: UInt16 = 0
    var hp: UInt32 = 0
    var battleLog: BattleLogRecord?

    init(actorIndex: UInt16, hp: UInt32) {
        self.actorIndex = actorIndex
        self.hp = hp
    }
}

// MARK: - BattleLogActionRecord

/// 戦闘アクションレコード
@Model
final class BattleLogActionRecord {
    var sortOrder: UInt16 = 0
    var turn: UInt8 = 0
    var kind: UInt8 = 0
    var actor: UInt16 = 0
    var target: UInt16 = 0  // 0 = nil
    var value: UInt32 = 0   // 0 = nil
    var skillIndex: UInt16 = 0  // 0 = nil
    var extra: UInt16 = 0   // 0 = nil
    var battleLog: BattleLogRecord?

    init() {}
}

// MARK: - BattleLogParticipantRecord

/// 戦闘参加者レコード
@Model
final class BattleLogParticipantRecord {
    var isPlayer: Bool = true
    var actorId: String = ""
    var partyMemberId: UInt8 = 0  // 0 = nil
    var characterId: UInt8 = 0    // 0 = nil
    var name: String = ""
    var avatarIndex: UInt16 = 0   // 0 = nil
    var level: UInt16 = 0         // 0 = nil
    var maxHP: UInt32 = 0
    var battleLog: BattleLogRecord?

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
    var seed: UInt64 = 0

    /// 最新イベント処理後のRNG状態（0 = まだ保存なし）
    var randomState: UInt64 = 0

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

    /// イベントレコード（正規化されたリレーション）
    @Relationship(deleteRule: .cascade, inverse: \ExplorationEventRecord.run)
    var events: [ExplorationEventRecord] = []

    init(partyId: UInt8,
         dungeonId: UInt16,
         difficulty: UInt8,
         targetFloor: UInt8,
         startedAt: Date,
         seed: UInt64) {
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
