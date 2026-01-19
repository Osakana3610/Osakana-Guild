// ==============================================================================
// ExplorationModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 探索システムで使用するモデル型の定義
//
// 【データ構造】
//   - ExplorationDropReward: 探索で得たドロップ報酬
//   - BattleParticipantSnapshot: 戦闘参加者のスナップショット
//   - BattleLogArchive: 戦闘ログのアーカイブ
//   - CombatSummary: 戦闘結果のサマリ
//   - ScriptedEventSummary: スクリプトイベントのサマリ
//   - ExplorationEventLogEntry: 探索イベントのログエントリ
//   - ExplorationEndState: 探索終了時の状態（完了/全滅）
//   - ExplorationRunArtifact: 探索実行の最終成果物
//
// 【使用箇所】
//   - ExplorationEngine（探索イベント処理）
//   - CombatExecutionService（戦闘結果の構築）
//   - ExplorationService（探索結果の保存）
//
// ==============================================================================

import Foundation

struct ExplorationDropReward: Sendable {
    let item: ItemDefinition
    let quantity: Int
    let trapDifficulty: Int?
    let sourceEnemyId: UInt16?
    let normalTitleId: UInt8?
    let superRareTitleId: UInt8?

    nonisolated init(item: ItemDefinition,
         quantity: Int,
         trapDifficulty: Int? = nil,
         sourceEnemyId: UInt16? = nil,
         normalTitleId: UInt8? = nil,
         superRareTitleId: UInt8? = nil) {
        self.item = item
        self.quantity = max(0, quantity)
        self.trapDifficulty = trapDifficulty
        self.sourceEnemyId = sourceEnemyId
        self.normalTitleId = normalTitleId
        self.superRareTitleId = superRareTitleId
    }
}

struct BattleParticipantSnapshot: Codable, Sendable {
    let actorIndex: UInt16
    let characterId: UInt8?
    let name: String
    let avatarIndex: UInt16?
    let level: Int?
    let maxHP: Int
}

struct BattleLogArchive: Sendable {
    let enemyId: UInt16
    let enemyName: String
    let result: BattleService.BattleResult
    let turns: Int
    let timestamp: Date
    let battleLog: BattleLog
    let playerSnapshots: [BattleParticipantSnapshot]
    let enemySnapshots: [BattleParticipantSnapshot]
}

struct CombatSummary: Sendable {
    let enemy: EnemyDefinition
    let result: BattleService.BattleResult
    let survivingPartyMemberIds: [UInt8]
    let turns: Int
    let experienceByMember: [UInt8: Int]
    let totalExperience: Int
    let goldEarned: Int
    let drops: [ExplorationDropReward]
}

struct ScriptedEventSummary: Sendable {
    let eventId: UInt8
    let name: String
    let description: String
    let statusEffects: [StatusEffectDefinition]
}

struct ExplorationEventLogEntry: Sendable {
    enum Kind: Sendable {
        case nothing
        case scripted(ScriptedEventSummary)
        case combat(CombatSummary)
    }

    let floorNumber: Int
    let eventIndex: Int
    let occurredAt: Date
    let kind: Kind
    let experienceGained: Int
    let experienceByMember: [UInt8: Int]
    let goldGained: Int
    let drops: [ExplorationDropReward]
    let statusEffectsApplied: [StatusEffectDefinition]
}

enum ExplorationEndState: Sendable {
    case completed
    case defeated(floorNumber: Int, eventIndex: Int, enemyId: UInt16)
    case cancelled(floorNumber: Int, eventIndex: Int)
}

struct ExplorationRunArtifact: Sendable {
    let dungeon: DungeonDefinition
    let displayDungeonName: String
    let floorCount: Int
    let eventsPerFloor: Int
    let startedAt: Date
    let endedAt: Date
    let events: [ExplorationEventLogEntry]
    let totalExperience: Int
    let totalGold: Int
    let totalDrops: [ExplorationDropReward]
    let experienceByMember: [UInt8: Int]
    let endState: ExplorationEndState
    let updatedSuperRareState: SuperRareDailyState
    let battleLogs: [BattleLogArchive]
}
