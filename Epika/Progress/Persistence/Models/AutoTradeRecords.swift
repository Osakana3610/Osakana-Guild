import Foundation
import SwiftData

@Model
final class AutoTradeRuleRecord {
    var id: UUID = UUID()
    /// アイテム識別子（superRareTitleId|normalTitleId|itemId|socketKey）
    var compositeKey: String = ""
    /// 表示用の名前（称号付きアイテム名）
    var displayName: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(),
         compositeKey: String,
         displayName: String,
         createdAt: Date) {
        self.id = id
        self.compositeKey = compositeKey
        self.displayName = displayName
        self.createdAt = createdAt
    }
}
