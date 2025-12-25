// ==============================================================================
// DungeonMasterModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ダンジョン・フロア・エンカウントテーブルのマスタデータ型定義
//
// 【データ構造】
//   - EncounterEventType: エンカウント種別（通常/ボス/スクリプト/確定）
//   - UnlockCondition: 解放条件（ストーリー読了/ダンジョンクリア）
//   - DungeonDefinition: ダンジョン定義
//     - 基本情報: id, name, chapter, stage, description
//     - 探索設定: recommendedLevel, explorationTime, eventsPerFloor, floorCount
//     - 敵出現設定: encounterWeights, enemyGroupConfig
//     - 解放条件: unlockConditions
//   - DungeonDefinition.EnemyGroupConfig: 敵グループ構成設定
//     - 出現数範囲, グループ数上限, 混在比率
//     - normalPool, floorPools, midBossPool, bossPool
//   - EncounterTableDefinition: エンカウントテーブル
//     - 各イベントの出現率・敵構成を定義
//   - DungeonFloorDefinition: フロア定義
//     - floorNumber, encounterTableId, specialEventIds
//
// 【使用箇所】
//   - ExplorationEngine: 探索処理でのエンカウント決定
//   - BattleEnemyGroupBuilder: 敵グループ生成
//   - DungeonProgressService: ダンジョン進行状態管理
//
// ==============================================================================

import Foundation

// MARK: - EncounterEventType

enum EncounterEventType: UInt8, Sendable, Hashable {
    case enemyEncounter = 1
    case bossEncounter = 2
    case scripted = 3
    case guaranteed = 4

    var identifier: String {
        switch self {
        case .enemyEncounter: return "enemy_encounter"
        case .bossEncounter: return "boss_encounter"
        case .scripted: return "scripted"
        case .guaranteed: return "guaranteed"
        }
    }
}

// MARK: - UnlockCondition

struct UnlockCondition: Sendable, Hashable {
    /// 0 = storyRead, 1 = dungeonClear
    let type: UInt8
    let value: UInt16
}

// MARK: - DungeonDefinition

struct DungeonDefinition: Identifiable, Sendable, Hashable {
    struct EncounterWeight: Sendable, Hashable {
        let enemyId: UInt16
        let weight: Double
    }

    struct EnemyGroupConfig: Sendable, Hashable {
        struct BossGroup: Sendable, Hashable {
            let enemyId: UInt16
            let groupSize: Int?
        }

        let minEnemies: Int
        let maxEnemies: Int
        let maxGroups: Int
        let defaultGroupSize: ClosedRange<Int>
        let mixRatio: Double // 0.0〜1.0, floorPoolの混在比率
        let normalPool: [UInt16]
        let floorPools: [Int: [UInt16]]
        let midBossPool: [BossGroup]
        let bossPool: [BossGroup]
    }

    let id: UInt16
    let name: String
    let chapter: Int
    let stage: Int
    let description: String
    let recommendedLevel: Int
    let explorationTime: Int
    let eventsPerFloor: Int
    let floorCount: Int
    let storyText: String?
    let unlockConditions: [UnlockCondition]
    let encounterWeights: [EncounterWeight]
    let enemyGroupConfig: EnemyGroupConfig?
}

struct EncounterTableDefinition: Identifiable, Sendable, Hashable {
    struct Event: Sendable, Hashable {
        let eventType: UInt8
        let enemyId: UInt16?
        let spawnRate: Double?
        let groupMin: Int?
        let groupMax: Int?
        let level: Int?
    }

    let id: UInt16
    let name: String
    let events: [Event]
    let isBoss: Bool
    let totalMin: Int?
    let totalMax: Int?
}

struct DungeonFloorDefinition: Identifiable, Sendable, Hashable {
    let id: UInt16
    let dungeonId: UInt16?
    let name: String
    let floorNumber: Int
    let encounterTableId: UInt16
    let description: String
    let specialEventIds: [String]
}
