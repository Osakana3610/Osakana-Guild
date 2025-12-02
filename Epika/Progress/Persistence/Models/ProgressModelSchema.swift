import SwiftData

enum ProgressModelSchema {
    static var modelTypes: [any PersistentModel.Type] {
        [
            ProgressMetadataRecord.self,
            PlayerProfileRecord.self,
            CharacterRecord.self,
            CharacterSkillRecord.self,
            CharacterEquipmentRecord.self,
            CharacterJobHistoryRecord.self,
            CharacterExplorationTagRecord.self,
            PartyRecord.self,
            PartyMemberRecord.self,
            InventoryItemRecord.self,
            StoryRecord.self,
            StoryNodeProgressRecord.self,
            DungeonRecord.self,
            DungeonFloorRecord.self,
            DungeonEncounterRecord.self,
            ExplorationRunRecord.self,
            ExplorationRunMemberRecord.self,
            ExplorationEventRecord.self,
            ExplorationEventExperienceRecord.self,
            ExplorationEventDropRecord.self,
            ExplorationBattleLogRecord.self,
            ShopRecord.self,
            ShopStockRecord.self,
            AutoTradeRuleRecord.self
        ]
    }
}
