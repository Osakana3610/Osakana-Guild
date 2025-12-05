import Foundation
import SwiftData

/// パンドラボックスに登録するアイテムの構成要素
struct PandoraBoxItem: Codable, Sendable, Hashable {
    var superRareTitleIndex: Int16
    var normalTitleIndex: UInt8
    var masterDataIndex: Int16
    var socketSuperRareTitleIndex: Int16
    var socketNormalTitleIndex: UInt8
    var socketMasterDataIndex: Int16

    init(superRareTitleIndex: Int16 = 0,
         normalTitleIndex: UInt8 = 0,
         masterDataIndex: Int16 = 0,
         socketSuperRareTitleIndex: Int16 = 0,
         socketNormalTitleIndex: UInt8 = 0,
         socketMasterDataIndex: Int16 = 0) {
        self.superRareTitleIndex = superRareTitleIndex
        self.normalTitleIndex = normalTitleIndex
        self.masterDataIndex = masterDataIndex
        self.socketSuperRareTitleIndex = socketSuperRareTitleIndex
        self.socketNormalTitleIndex = socketNormalTitleIndex
        self.socketMasterDataIndex = socketMasterDataIndex
    }

    /// stackKey文字列から生成
    init?(stackKey: String) {
        guard let components = StackKeyComponents(stackKey: stackKey) else { return nil }
        self.superRareTitleIndex = components.superRareTitleIndex
        self.normalTitleIndex = components.normalTitleIndex
        self.masterDataIndex = components.masterDataIndex
        self.socketSuperRareTitleIndex = components.socketSuperRareTitleIndex
        self.socketNormalTitleIndex = components.socketNormalTitleIndex
        self.socketMasterDataIndex = components.socketMasterDataIndex
    }

    /// stackKey文字列に変換
    var stackKey: String {
        "\(superRareTitleIndex)|\(normalTitleIndex)|\(masterDataIndex)|\(socketSuperRareTitleIndex)|\(socketNormalTitleIndex)|\(socketMasterDataIndex)"
    }
}

/// プレイヤーの財布（ゴールド・チケット）
struct PlayerWallet: Codable, Sendable, Hashable {
    var gold: Int
    var catTickets: Int
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
    var lastDailyProcessedDate: Int? = nil
    /// 超レアが発生した日（YYYYMMDD形式、1日1回制限）
    var superRareLastTriggeredDate: Int? = nil

    // MARK: - プレイヤー資産
    var gold: Int = 0
    var catTickets: Int = 0
    var partySlots: Int = AppConstants.Progress.defaultPartySlotCount

    // MARK: - パンドラボックス
    /// パンドラボックスに登録されたアイテム（最大5件）- stackKey文字列の配列
    var pandoraBoxStackKeys: [String] = []

    init(schemaVersion: UInt8 = 1,
         updatedAt: Date = Date(),
         lastDailyProcessedDate: Int? = nil,
         superRareLastTriggeredDate: Int? = nil,
         gold: Int = 0,
         catTickets: Int = 0,
         partySlots: Int = AppConstants.Progress.defaultPartySlotCount,
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

    /// 現在のJST日付をYYYYMMDD形式のIntで取得
    nonisolated static func today() -> Int {
        dateAsInt(from: Date())
    }

    /// DateをYYYYMMDD形式のIntに変換
    nonisolated static func dateAsInt(from date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jstTimeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return year * 10000 + month * 100 + day
    }

    /// YYYYMMDD形式のIntからDateに変換（JST午前0時）
    nonisolated static func date(from dateInt: Int) -> Date? {
        let year = dateInt / 10000
        let month = (dateInt / 100) % 100
        let day = dateInt % 100
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jstTimeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
