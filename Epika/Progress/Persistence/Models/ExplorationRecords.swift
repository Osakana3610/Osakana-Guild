import Foundation
import SwiftData

/// 探索実行レコード
///
/// 以前は4つの@Model（ExplorationRunRecord, ExplorationEventRecord,
/// ExplorationEventDropRecord, ExplorationBattleLogRecord）で構成されていたが、
/// ストレージ効率化のため1レコードに統合。
/// イベント情報はEventEntry配列をエンコードしてeventsDataに格納。
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

    /// イベント情報（EventEntry配列をJSONエンコード）
    var eventsData: Data = Data()

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

    // MARK: - Events Encoding/Decoding

    /// eventsDataをデコードしてEventEntry配列を取得
    func decodeEvents() throws -> [EventEntry] {
        guard !eventsData.isEmpty else { return [] }
        return try JSONDecoder().decode([EventEntry].self, from: eventsData)
    }

    /// EventEntry配列をエンコードしてeventsDataに保存
    func encodeEvents(_ events: [EventEntry]) throws {
        eventsData = try JSONEncoder().encode(events)
    }

    /// イベントを追加
    func appendEvent(_ event: EventEntry) throws {
        var events = try decodeEvents()
        events.append(event)
        try encodeEvents(events)
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
