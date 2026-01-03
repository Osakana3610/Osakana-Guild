// ==============================================================================
// CombatSnapshotBuilder.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 敵のCombatスナップショット生成
//   - 敵定義から戦闘用ステータスへの変換
//   - CombatStatCalculatorを使用した統一的な計算
//
// 【公開API】
//   - makeEnemySnapshot: 敵のCombatスナップショットを生成
//
// 【使用箇所】
//   - BattleEnemyGroupBuilder（敵Actor構築時）
//
// ==============================================================================

import Foundation

struct CombatSnapshotBuilder {
    /// 敵のCombatスナップショットを生成する。
    /// 味方と同じ `CombatStatCalculator` を使用して計算する。
    static func makeEnemySnapshot(from definition: EnemyDefinition,
                                  levelOverride: Int?,
                                  jobDefinitions: [UInt8: JobDefinition],
                                  skillDefinitions: [UInt16: SkillDefinition]) throws -> CharacterValues.Combat {
        let level = max(1, levelOverride ?? 1)

        // 敵独自のbaseStatsからRaceDefinitionを作成
        let raceDefinition = makeRaceDefinition(for: definition)
        let jobDefinition = definition.jobId.flatMap { jobDefinitions[$0] } ?? makeJobDefinition(for: definition)

        // 敵のパッシブスキルを取得
        let learnedSkills = definition.skillIds.compactMap { skillDefinitions[$0] }

        let context = CombatStatCalculator.Context(
            raceId: definition.raceId,
            jobId: definition.jobId ?? 0,
            level: level,
            currentHP: 1,  // 計算後に maxHP で上書きされる
            equippedItems: [],
            cachedEquippedItems: [],
            race: raceDefinition,
            job: jobDefinition,
            personalitySecondary: nil,
            learnedSkills: learnedSkills,
            loadout: CachedCharacter.Loadout(items: [], titles: [], superRareTitles: [])
        )

        let result = try CombatStatCalculator.calculate(for: context)
        return result.combat
    }
}

private extension CombatSnapshotBuilder {
    /// 敵独自のbaseStatsからRaceDefinitionを作成
    static func makeRaceDefinition(for definition: EnemyDefinition) -> RaceDefinition {
        let baseStats = RaceDefinition.BaseStats(
            strength: definition.strength,
            wisdom: definition.wisdom,
            spirit: definition.spirit,
            vitality: definition.vitality,
            agility: definition.agility,
            luck: definition.luck
        )
        return RaceDefinition(id: definition.raceId,
                              name: definition.name,
                              genderCode: 0,
                              description: "",
                              baseStats: baseStats,
                              maxLevel: 200)
    }

    /// 敵のjobIdに対応するJobDefinitionがない場合のデフォルト（係数0）
    static func makeJobDefinition(for definition: EnemyDefinition) -> JobDefinition {
        let coefficients = JobDefinition.CombatCoefficients(
            maxHP: 0.0,
            physicalAttack: 0.0,
            magicalAttack: 0.0,
            physicalDefense: 0.0,
            magicalDefense: 0.0,
            hitRate: 0.0,
            evasionRate: 0.0,
            criticalRate: 0.0,
            attackCount: 0.0,
            magicalHealing: 0.0,
            trapRemoval: 0.0,
            additionalDamage: 0.0,
            breathDamage: 0.0
        )
        return JobDefinition(id: definition.jobId ?? 0,
                             name: definition.name,
                             combatCoefficients: coefficients,
                             learnedSkillIds: [])
    }
}
