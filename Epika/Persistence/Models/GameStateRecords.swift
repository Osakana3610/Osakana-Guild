// ==============================================================================
// GameStateRecords.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ゲーム状態のSwiftData永続化モデル
//   - プレイヤー資産・日次処理状態・パンドラボックスの保存
//
// 【データ構造】
//   - GameStateRecord (@Model): ゲーム状態（シングルトン）
//     - schemaVersion: スキーマバージョン
//     - updatedAt: 更新日時
//     - lastDailyProcessedDate: 日次処理実行日（YYYYMMDD）
//     - superRareLastTriggeredDate: 超レア発生日（YYYYMMDD）
//     - gold: 所持金
//     - catTickets: 猫チケット
//     - partySlots: 解放済みパーティスロット数
//     - pandoraBoxItems: パンドラボックス内アイテム（UInt64パック配列）
//
//   - PlayerWallet (Codable): プレイヤー財布（gold/catTickets）
//
// 【ユーティリティ】
//   - JSTDateUtility: JST日付変換（today, dateAsInt, date(from:)）
//
// 【使用箇所】
//   - GameStateService: プレイヤー資産・日次処理の管理
//
// ==============================================================================

import Foundation
import SwiftData

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
    /// パンドラボックスに登録されたアイテム（最大5件）- StackKeyをUInt64にパックした配列
    /// パンドラに入れたアイテムはインベントリから1個減らされ、ここに実体として保持される
    var pandoraBoxItems: [UInt64] = []

    init(schemaVersion: UInt8 = 1,
         updatedAt: Date = Date(),
         lastDailyProcessedDate: UInt32? = nil,
         superRareLastTriggeredDate: UInt32? = nil,
         gold: UInt32 = 0,
         catTickets: UInt16 = 0,
         partySlots: UInt8 = UInt8(AppConstants.Progress.defaultPartySlotCount),
         pandoraBoxItems: [UInt64] = []) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.lastDailyProcessedDate = lastDailyProcessedDate
        self.superRareLastTriggeredDate = superRareLastTriggeredDate
        self.gold = gold
        self.catTickets = catTickets
        self.partySlots = partySlots
        self.pandoraBoxItems = pandoraBoxItems
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
