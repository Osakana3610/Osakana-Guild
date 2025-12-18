import Foundation
import SwiftData

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
    var battleLogData: Data?
    var scriptedEventId: UInt8?
    var exp: UInt32 = 0
    var gold: UInt32 = 0
    /// [DropEntry]をJSONエンコード（1イベントあたり0〜数件なので許容）
    var dropsData: Data = Data()
    var occurredAt: Date = Date()

    /// 親への参照
    var run: ExplorationRunRecord?

    init(floor: UInt8,
         kind: UInt8,
         enemyId: UInt16?,
         battleResult: UInt8?,
         battleLogData: Data?,
         scriptedEventId: UInt8?,
         exp: UInt32,
         gold: UInt32,
         dropsData: Data,
         occurredAt: Date) {
        self.floor = floor
        self.kind = kind
        self.enemyId = enemyId
        self.battleResult = battleResult
        self.battleLogData = battleLogData
        self.scriptedEventId = scriptedEventId
        self.exp = exp
        self.gold = gold
        self.dropsData = dropsData
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

    /// 超レア抽選の日次状態（SuperRareDailyStateをJSONエンコード）
    var superRareStateData: Data = Data()

    /// ドロップ済みアイテムID（Set<UInt16>をJSONエンコード）
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
