import SwiftData

enum ProgressModelSchema {
    static var modelTypes: [any PersistentModel.Type] {
        [
            GameStateRecord.self,
            CharacterRecord.self,
            CharacterEquipmentRecord.self,
            PartyRecord.self,
            InventoryItemRecord.self,
            StoryNodeProgressRecord.self,
            DungeonRecord.self,
            ExplorationRunRecord.self,
            ExplorationEventRecord.self,
            ShopStockRecord.self,
            AutoTradeRuleRecord.self
        ]
    }
}
