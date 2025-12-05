import SwiftData

enum ProgressModelSchema {
    static var modelTypes: [any PersistentModel.Type] {
        [
            GameStateRecord.self,
            CharacterRecord.self,
            CharacterEquipmentRecord.self,
            PartyRecord.self,
            InventoryItemRecord.self,
            StoryRecord.self,
            StoryNodeProgressRecord.self,
            DungeonRecord.self,
            DungeonFloorRecord.self,
            DungeonEncounterRecord.self,
            ExplorationRunRecord.self,
            ExplorationEventRecord.self,
            ExplorationEventDropRecord.self,
            ExplorationBattleLogRecord.self,
            ShopRecord.self,
            ShopStockRecord.self,
            AutoTradeRuleRecord.self
        ]
    }
}
