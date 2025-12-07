import Foundation
import SwiftData

/// パンドラボックスに登録するアイテムの構成要素
struct PandoraBoxItem: Codable, Sendable, Hashable {
    var superRareTitleId: UInt8
    var normalTitleId: UInt8
    var itemId: UInt16
    var socketSuperRareTitleId: UInt8
    var socketNormalTitleId: UInt8
    var socketItemId: UInt16

    init(superRareTitleId: UInt8 = 0,
         normalTitleId: UInt8 = 0,
         itemId: UInt16 = 0,
         socketSuperRareTitleId: UInt8 = 0,
         socketNormalTitleId: UInt8 = 0,
         socketItemId: UInt16 = 0) {
        self.superRareTitleId = superRareTitleId
        self.normalTitleId = normalTitleId
        self.itemId = itemId
        self.socketSuperRareTitleId = socketSuperRareTitleId
        self.socketNormalTitleId = socketNormalTitleId
        self.socketItemId = socketItemId
    }

    /// stackKey文字列から生成
    init?(stackKey: String) {
        guard let components = StackKeyComponents(stackKey: stackKey) else { return nil }
        self.superRareTitleId = components.superRareTitleId
        self.normalTitleId = components.normalTitleId
        self.itemId = components.itemId
        self.socketSuperRareTitleId = components.socketSuperRareTitleId
        self.socketNormalTitleId = components.socketNormalTitleId
        self.socketItemId = components.socketItemId
    }

    /// stackKey文字列に変換
    var stackKey: String {
        "\(superRareTitleId)|\(normalTitleId)|\(itemId)|\(socketSuperRareTitleId)|\(socketNormalTitleId)|\(socketItemId)"
    }
}

/// プレイヤーの財布（ゴールド・チケット）
struct PlayerWallet: Codable, Sendable, Hashable {
    var gold: UInt32
    var catTickets: UInt16
}

/// ゲーム状態を管理するシングルトンRecord
/// - 旧ProgressMetadataRecordとPlayerProfileRecordを統合
@Model
final class GameStateRecord {
    // MARK: - メタ情報
    var schemaVersion: UInt8 = 1
    var updatedAt: Date = Date()

    // MARK: - 日次処理
    /// 日次処理（ショップ更新、チケット付与）を実行した日（YYYYMMDD形式）
    var lastDailyProcessedDate: UInt32? = nil
    /// 超レアが発生した日（YYYYMMDD形式、1日1回制限）
    var superRareLastTriggeredDate: UInt32? = nil

    // MARK: - プレイヤー資産
    var gold: UInt32 = 0
    var catTickets: UInt16 = 0
    var partySlots: UInt8 = UInt8(AppConstants.Progress.defaultPartySlotCount)

    // MARK: - パンドラボックス
    /// パンドラボックスに登録されたアイテム（最大5件）- stackKey文字列の配列
    var pandoraBoxStackKeys: [String] = []

    init(schemaVersion: UInt8 = 1,
         updatedAt: Date = Date(),
         lastDailyProcessedDate: UInt32? = nil,
         superRareLastTriggeredDate: UInt32? = nil,
         gold: UInt32 = 0,
         catTickets: UInt16 = 0,
         partySlots: UInt8 = UInt8(AppConstants.Progress.defaultPartySlotCount),
         pandoraBoxStackKeys: [String] = []) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.lastDailyProcessedDate = lastDailyProcessedDate
        self.superRareLastTriggeredDate = superRareLastTriggeredDate
        self.gold = gold
        self.catTickets = catTickets
        self.partySlots = partySlots
        self.pandoraBoxStackKeys = pandoraBoxStackKeys
    }
}

// MARK: - JST日付ユーティリティ

enum JSTDateUtility: Sendable {
    private static nonisolated let jstTimeZone = TimeZone(identifier: "Asia/Tokyo")!

    /// 現在のJST日付をYYYYMMDD形式のUInt32で取得
    nonisolated static func today() -> UInt32 {
        dateAsInt(from: Date())
    }

    /// DateをYYYYMMDD形式のUInt32に変換
    nonisolated static func dateAsInt(from date: Date) -> UInt32 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jstTimeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return UInt32(year * 10000 + month * 100 + day)
    }

    /// YYYYMMDD形式のUInt32からDateに変換（JST午前0時）
    nonisolated static func date(from dateInt: UInt32) -> Date? {
        let intValue = Int(dateInt)
        let year = intValue / 10000
        let month = (intValue / 100) % 100
        let day = intValue % 100
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jstTimeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
