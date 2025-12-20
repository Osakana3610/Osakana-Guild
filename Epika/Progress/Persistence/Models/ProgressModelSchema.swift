// ==============================================================================
// ProgressModelSchema.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - SwiftDataモデル型の一括登録
//   - ModelContainerへの全永続化モデル提供
//
// 【データ構造】
//   - ProgressModelSchema (enum): 名前空間
//     - modelTypes: 全永続化モデル型の配列
//       - GameStateRecord
//       - CharacterRecord, CharacterEquipmentRecord
//       - PartyRecord
//       - InventoryItemRecord
//       - StoryNodeProgressRecord
//       - DungeonRecord
//       - ExplorationRunRecord, ExplorationEventRecord
//       - ShopStockRecord
//       - AutoTradeRuleRecord
//
// 【使用箇所】
//   - EpikaApp: ModelContainer初期化
//   - テスト: テスト用コンテナ生成
//
// ==============================================================================

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
