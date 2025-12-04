import Foundation
import SwiftData

struct ItemSnapshot: Sendable {
    /// Int Indexベースの強化情報
    struct Enhancement: Sendable, Equatable, Hashable {
        var superRareTitleIndex: Int16
        var normalTitleIndex: Int8
        var socketSuperRareTitleIndex: Int16
        var socketNormalTitleIndex: Int8
        var socketMasterDataIndex: Int16

        nonisolated init(superRareTitleIndex: Int16 = 0,
                         normalTitleIndex: Int8 = 0,
                         socketSuperRareTitleIndex: Int16 = 0,
                         socketNormalTitleIndex: Int8 = 0,
                         socketMasterDataIndex: Int16 = 0) {
            self.superRareTitleIndex = superRareTitleIndex
            self.normalTitleIndex = normalTitleIndex
            self.socketSuperRareTitleIndex = socketSuperRareTitleIndex
            self.socketNormalTitleIndex = socketNormalTitleIndex
            self.socketMasterDataIndex = socketMasterDataIndex
        }

        /// 宝石改造が施されているか
        var hasSocket: Bool {
            socketMasterDataIndex != 0
        }
    }

    let persistentIdentifier: PersistentIdentifier

    /// スタック識別キー（6つのindexの組み合わせ）
    var stackKey: String
    var masterDataIndex: Int16
    var quantity: Int
    var storage: ItemStorage
    var enhancements: Enhancement

    /// 自動売却ルール用キー（ソケット情報を除く3要素）
    var autoTradeKey: String {
        "\(enhancements.superRareTitleIndex)|\(enhancements.normalTitleIndex)|\(masterDataIndex)"
    }
}

extension ItemSnapshot: Identifiable {
    var id: String { stackKey }
}

extension ItemSnapshot: Equatable {
    static func == (lhs: ItemSnapshot, rhs: ItemSnapshot) -> Bool {
        lhs.stackKey == rhs.stackKey &&
        lhs.masterDataIndex == rhs.masterDataIndex &&
        lhs.quantity == rhs.quantity &&
        lhs.storage == rhs.storage &&
        lhs.enhancements == rhs.enhancements
    }
}

extension ItemSnapshot: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(stackKey)
        hasher.combine(masterDataIndex)
        hasher.combine(quantity)
        hasher.combine(storage)
        hasher.combine(enhancements)
    }
}

enum ItemStorage: String, Codable, Sendable {
    case playerItem
    case unknown
}
