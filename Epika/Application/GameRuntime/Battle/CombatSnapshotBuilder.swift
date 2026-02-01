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
//   - MasterDataCache（オンデマンドキャッシュ）
//
// ==============================================================================

import Foundation

nonisolated struct CombatSnapshotBuilder {
    /// 敵のCombatスナップショットを生成する。
    /// 味方と同じ `CombatStatCalculator` を使用して計算する。
    nonisolated static func makeEnemySnapshot(from definition: EnemyDefinition,
                                  levelOverride: Int?,
                                  masterData: MasterDataCache) throws -> CharacterValues.Combat {
        let level = max(1, levelOverride ?? 1)

        // 敵独自のbaseStatsからRaceDefinitionを作成
        let raceDefinition = makeRaceDefinition(for: definition)
        let jobDefinition = definition.jobId.flatMap { masterData.jobsById[$0] } ?? makeJobDefinition(for: definition)

        // 敵のパッシブスキルを取得
        let learnedSkills = definition.skillIds.sorted().compactMap { masterData.skillsById[$0] }

        let baseAggregation = try SkillEffectAggregationService.aggregate(
            input: SkillEffectAggregationInput(skills: learnedSkills),
            options: []
        )

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
            skillEffects: baseAggregation.combatStatInputs,
            loadout: CachedCharacter.Loadout(items: [], titles: [], superRareTitles: [])
        )

        let result = try CombatStatCalculator.calculate(for: context)
        return result.combat
    }
}

private extension CombatSnapshotBuilder {
    /// 敵独自のbaseStatsからRaceDefinitionを作成
    nonisolated static func makeRaceDefinition(for definition: EnemyDefinition) -> RaceDefinition {
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
    nonisolated static func makeJobDefinition(for definition: EnemyDefinition) -> JobDefinition {
        let coefficients = JobDefinition.CombatCoefficients(
            maxHP: 0.0,
            physicalAttackScore: 0.0,
            magicalAttackScore: 0.0,
            physicalDefenseScore: 0.0,
            magicalDefenseScore: 0.0,
            hitScore: 0.0,
            evasionScore: 0.0,
            criticalChancePercent: 0.0,
            attackCount: 0.0,
            magicalHealingScore: 0.0,
            trapRemovalScore: 0.0,
            additionalDamageScore: 0.0,
            breathDamageScore: 0.0
        )
        return JobDefinition(id: definition.jobId ?? 0,
                             name: definition.name,
                             combatCoefficients: coefficients,
                             learnedSkillIds: [])
    }
}
