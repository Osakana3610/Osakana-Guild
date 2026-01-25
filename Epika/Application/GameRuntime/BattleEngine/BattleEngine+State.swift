// ==============================================================================
// BattleEngine+State.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - BattleStateのヘルパー（アクター参照/更新など）
//
// ==============================================================================

import Foundation

extension BattleEngine.BattleState {
    // MARK: - Actor Access

    nonisolated func actor(for side: BattleEngine.ActorSide, index: Int) -> BattleActor? {
        switch side {
        case .player:
            guard players.indices.contains(index) else { return nil }
            return players[index]
        case .enemy:
            guard enemies.indices.contains(index) else { return nil }
            return enemies[index]
        }
    }

    nonisolated mutating func updateActor(_ actor: BattleActor, side: BattleEngine.ActorSide, index: Int) {
        switch side {
        case .player:
            guard players.indices.contains(index) else { return }
            players[index] = actor
        case .enemy:
            guard enemies.indices.contains(index) else { return }
            enemies[index] = actor
        }
    }

    nonisolated func opponents(for side: BattleEngine.ActorSide) -> [BattleActor] {
        switch side {
        case .player: return enemies
        case .enemy: return players
        }
    }

    nonisolated func allies(for side: BattleEngine.ActorSide) -> [BattleActor] {
        switch side {
        case .player: return players
        case .enemy: return enemies
        }
    }

    // MARK: - Status Definition

    nonisolated func statusDefinition(for effect: AppliedStatusEffect) -> StatusEffectDefinition? {
        statusDefinitions[effect.id]
    }

    nonisolated func skillDefinition(for skillId: UInt16) -> SkillDefinition? {
        skillDefinitions[skillId]
    }

    nonisolated func enemySkillDefinition(for skillId: UInt16) -> EnemySkillDefinition? {
        enemySkillDefinitions[skillId]
    }

    nonisolated mutating func incrementEnemySkillUsage(actorIdentifier: String, skillId: UInt16) {
        enemySkillUsage[actorIdentifier, default: [:]][skillId, default: 0] += 1
    }

    nonisolated func enemySkillUsageCount(actorIdentifier: String, skillId: UInt16) -> Int {
        enemySkillUsage[actorIdentifier]?[skillId] ?? 0
    }
}
