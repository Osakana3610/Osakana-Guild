// ==============================================================================
// BattleRewardCalculator.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 戦闘報酬（経験値、ゴールド）の計算
//   - レベル差による倍率調整
//   - スキルによる報酬倍率の適用
//   - 罠難易度の計算
//
// 【データ構造】
//   - BattleRewards: 報酬情報（メンバー別経験値、合計経験値、ゴールド）
//
// 【公開API】
//   - calculateRewards: 戦闘報酬を計算
//   - trapDifficulty: アイテム罠の難易度を計算
//
// 【使用箇所】
//   - BattleService（戦闘終了時の報酬付与）
//
// ==============================================================================

import Foundation

struct BattleRewards: Sendable {
    let experienceByMember: [UInt8: Int]
    let totalExperience: Int
    let gold: Int
}

enum BattleRewardCalculator {
    nonisolated static func calculateRewards(party: RuntimePartyState,
                                 survivingMemberIds: [UInt8],
                                 enemies: [BattleEnemyGroupBuilder.EncounteredEnemy],
                                 result: BattleService.BattleResult) throws -> BattleRewards {
        guard result == .victory, !enemies.isEmpty else {
            let zeroMap = Dictionary(uniqueKeysWithValues: party.members.map { ($0.characterId, 0) })
            return BattleRewards(experienceByMember: zeroMap, totalExperience: 0, gold: 0)
        }

        let survivors = Set(survivingMemberIds)
        let aliveCount = max(1, survivors.count)
        let survivorLevels = party.members
            .filter { survivors.contains($0.id) }
            .map { max(1, $0.character.level) }
        var experiencePerMember: [UInt8: Int] = [:]
        var totalExperience = 0

        var rewardComponentsByMember: [UInt8: SkillRuntimeEffects.RewardComponents] = [:]
        for member in party.members {
            rewardComponentsByMember[member.id] = member.character.rewardComponents
        }

        for member in party.members {
            let components = rewardComponentsByMember[member.id] ?? .neutral
            let reward = computeExperience(for: member,
                                           survivors: survivors,
                                           aliveCount: aliveCount,
                                           enemies: enemies,
                                           rewardComponents: components)
            experiencePerMember[member.characterId] = reward
            totalExperience += reward
        }

        var partyRewardAggregation = SkillRuntimeEffects.RewardComponents.neutral
        for member in party.members {
            if let components = rewardComponentsByMember[member.id] {
                partyRewardAggregation.merge(components)
            }
        }

        let goldBase = computeGold(enemies: enemies,
                                   survivorLevels: survivorLevels,
                                   aliveCount: aliveCount,
                                   result: result)
        let goldScale = partyRewardAggregation.goldScale()
        let gold = max(0, Int((Double(goldBase) * goldScale).rounded()))

        return BattleRewards(experienceByMember: experiencePerMember,
                             totalExperience: totalExperience,
                             gold: gold)
    }

    nonisolated static func trapDifficulty(for item: ItemDefinition,
                               dungeon: DungeonDefinition,
                               floor: DungeonFloorDefinition) -> Int {
        let base = baseItemDifficulty(price: item.basePrice)
        let modifier = max(0, dungeon.recommendedLevel * 5 + floor.floorNumber * 2)
        return max(0, base + modifier)
    }

    private nonisolated static func computeExperience(for member: RuntimePartyState.Member,
                                          survivors: Set<UInt8>,
                                          aliveCount: Int,
                                          enemies: [BattleEnemyGroupBuilder.EncounteredEnemy],
                                          rewardComponents: SkillRuntimeEffects.RewardComponents) -> Int {
        guard survivors.contains(member.id) else { return 0 }
        let character = member.character
        let characterLevel = max(1, character.level)
        var accumulated: Double = 0
        for enemy in enemies {
            let baseExp = Double(enemy.definition.baseExperience) / Double(aliveCount)
            let diffMultiplier = levelDifferenceMultiplier(enemyLevel: enemy.level, characterLevel: characterLevel)
            let ratioMultiplier = levelRatioMultiplier(enemyLevel: enemy.level, characterLevel: characterLevel)
            let multiplier = min(10.0, diffMultiplier * ratioMultiplier)
            accumulated += baseExp * multiplier
        }
        let scale = rewardComponents.experienceScale()
        let adjusted = accumulated * scale
        return max(0, Int(adjusted.rounded()))
    }

    private nonisolated static func computeGold(enemies: [BattleEnemyGroupBuilder.EncounteredEnemy],
                                    survivorLevels: [Int],
                                    aliveCount: Int,
                                    result: BattleService.BattleResult) -> Int {
        guard result == .victory, !survivorLevels.isEmpty else { return 0 }
        var total: Double = 0
        for enemy in enemies {
            let baseGold = Double(enemy.definition.baseExperience) * 0.5
            for level in survivorLevels {
                let diffMultiplier = levelDifferenceMultiplier(enemyLevel: enemy.level, characterLevel: level)
                let ratioMultiplier = levelRatioMultiplier(enemyLevel: enemy.level, characterLevel: level)
                let multiplier = min(10.0, diffMultiplier * ratioMultiplier)
                total += (baseGold / Double(aliveCount)) * multiplier
            }
        }
        return max(0, Int(total.rounded()))
    }

    private nonisolated static func levelDifferenceMultiplier(enemyLevel: Int, characterLevel: Int) -> Double {
        let diff = enemyLevel - characterLevel
        if diff <= -50 {
            return 0.5
        } else if diff <= 0 {
            return 50.0 / Double(50 - diff)
        } else if diff <= 50 {
            return Double(50 + diff) / 50.0
        } else {
            return 2.0
        }
    }

    private nonisolated static func levelRatioMultiplier(enemyLevel: Int, characterLevel: Int) -> Double {
        guard characterLevel > 0 else { return 1.0 }
        let ratio = Double(enemyLevel) / Double(characterLevel)
        if ratio <= 2.0 {
            return ratio
        } else if ratio < 17.0 {
            return 1.0 + sqrt(max(0, ratio - 1.0))
        } else {
            return 5.0
        }
    }

    private nonisolated static func baseItemDifficulty(price: Int) -> Int {
        guard price > 0 else { return 0 }
        if price <= 1_000 {
            let value = 0.033 * Double(price) + 32.6
            return Int(value.rounded())
        } else {
            let value = 99.2 + 0.172 * sqrt(Double(price))
            return Int(value.rounded())
        }
    }
}
