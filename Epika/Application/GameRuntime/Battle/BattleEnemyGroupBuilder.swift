// ==============================================================================
// BattleEnemyGroupBuilder.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 敵グループの生成と敵BattleActorの構築
//   - ダンジョン設定に基づく敵エンカウントの生成
//   - 敵のスキル効果キャッシュ管理
//
// 【データ構造】
//   - EncounteredEnemy: エンカウントした敵の定義とレベル
//
// 【公開API】
//   - makeEnemies: 敵グループとエンカウント情報を生成
//
// 【使用箇所】
//   - BattleService（戦闘開始時の敵グループ構築）
//
// ==============================================================================

import Foundation

struct BattleEnemyGroupBuilder {
    struct EncounteredEnemy {
        let definition: EnemyDefinition
        let level: Int
    }

    /// 敵グループを生成
    /// nonisolated - 計算処理のためMainActorに縛られない
    nonisolated static func makeEnemies(baseEnemyId: UInt16?,
                            baseEnemyLevel: Int?,
                            groupMin: Int?,
                            groupMax: Int?,
                            dungeon: DungeonDefinition,
                            floor: DungeonFloorDefinition,
                            enemyDefinitions: [UInt16: EnemyDefinition],
                            skillDefinitions: [UInt16: SkillDefinition],
                            jobDefinitions: [UInt8: JobDefinition],
                            raceDefinitions: [UInt8: RaceDefinition],
                            random: inout GameRandomSource) throws -> ([BattleActor], [EncounteredEnemy]) {
        var skillCache: [UInt16: BattleActor.SkillEffects] = [:]

        if let baseEnemyId, let definition = enemyDefinitions[baseEnemyId] {
            let count = randomGroupSize(groupMin: groupMin, groupMax: groupMax, dungeon: dungeon, random: &random)
            let actors = try makeActors(for: definition,
                                        levelOverride: baseEnemyLevel,
                                        count: count,
                                        skillDefinitions: skillDefinitions,
                                        jobDefinitions: jobDefinitions,
                                        cache: &skillCache,
                                        random: &random)
            let encountered = Array(repeating: EncounteredEnemy(definition: definition, level: baseEnemyLevel ?? 1), count: count)
            return (actors, encountered)
        }

        guard let config = dungeon.enemyGroupConfig else { return ([], []) }
        let groups = BattleEnemyGroupConfigService.makeEncounter(using: config,
                                                                floorNumber: floor.floorNumber,
                                                                enemyPool: enemyDefinitions,
                                                                random: &random)
        var actors: [BattleActor] = []
        var encountered: [EncounteredEnemy] = []
        var slotIndex = 0
        for group in groups {
            for _ in 0..<group.count {
                guard let slot = BattleContextBuilder.slot(for: slotIndex) else { break }
                let levelOverride = baseEnemyLevel ?? 1
                let snapshot = try CombatSnapshotBuilder.makeEnemySnapshot(from: group.definition,
                                                                           levelOverride: levelOverride,
                                                                           jobDefinitions: jobDefinitions)
                var resources = BattleActionResource.makeDefault(for: snapshot,
                                                                spellLoadout: .empty)
                let skillEffects = try cachedSkillEffects(for: group.definition,
                                                          cache: &skillCache,
                                                          skillDefinitions: skillDefinitions)
                if skillEffects.spell.breathExtraCharges > 0 {
                    let current = resources.charges(for: .breath)
                    resources.setCharges(for: .breath, value: current + skillEffects.spell.breathExtraCharges)
                }
                let identifier = "\(group.definition.id)_\(slotIndex)"
                let actor = BattleActor(identifier: identifier,
                                        displayName: group.definition.name,
                                        kind: .enemy,
                                        formationSlot: slot,
                                        strength: group.definition.strength,
                                        wisdom: group.definition.wisdom,
                                        spirit: group.definition.spirit,
                                        vitality: group.definition.vitality,
                                        agility: group.definition.agility,
                                        luck: group.definition.luck,
                                        partyMemberId: nil,
                                        level: levelOverride,
                                        jobName: group.definition.jobId.flatMap { jobDefinitions[$0]?.name } ?? "敵",
                                        avatarIndex: nil,
                                        isMartialEligible: false,
                                        raceId: group.definition.raceId,
                                        enemyMasterIndex: group.definition.id,
                                        snapshot: snapshot,
                                        currentHP: snapshot.maxHP,
                                        actionRates: BattleActionRates(attack: group.definition.actionRates.attack,
                                                                       priestMagic: group.definition.actionRates.priestMagic,
                                                                       mageMagic: group.definition.actionRates.mageMagic,
                                                                       breath: group.definition.actionRates.breath),
                                        actionResources: resources,
                                        barrierCharges: skillEffects.combat.barrierCharges,
                                        skillEffects: skillEffects,
                                        spellbook: .empty,
                                        spells: .empty,
                                        baseSkillIds: Set(group.definition.specialSkillIds),
                                        innateResistances: BattleInnateResistances(from: group.definition.resistances))
                actors.append(actor)
                encountered.append(EncounteredEnemy(definition: group.definition, level: levelOverride))
                slotIndex += 1
            }
        }

        return (actors, encountered)
    }

    private static func randomGroupSize(groupMin: Int?,
                                        groupMax: Int?,
                                        dungeon: DungeonDefinition,
                                        random: inout GameRandomSource) -> Int {
        // Use passed-in group size from encounter event, or fallback to dungeon config
        let minSize = groupMin ?? dungeon.enemyGroupConfig?.defaultGroupSize.lowerBound ?? 1
        let maxSize = groupMax ?? dungeon.enemyGroupConfig?.defaultGroupSize.upperBound ?? 1
        let lower = max(1, minSize)
        let upper = max(lower, maxSize)
        if lower == upper { return lower }
        return random.nextInt(in: lower...upper)
    }

    nonisolated private static func makeActors(for definition: EnemyDefinition,
                                    levelOverride: Int?,
                                    count: Int,
                                    skillDefinitions: [UInt16: SkillDefinition],
                                    jobDefinitions: [UInt8: JobDefinition],
                                    cache: inout [UInt16: BattleActor.SkillEffects],
                                    random: inout GameRandomSource) throws -> [BattleActor] {
        var actors: [BattleActor] = []
        for index in 0..<count {
            guard let slot = BattleContextBuilder.slot(for: index) else { break }
            let level = levelOverride ?? 1
            let snapshot = try CombatSnapshotBuilder.makeEnemySnapshot(from: definition,
                                                                       levelOverride: level,
                                                                       jobDefinitions: jobDefinitions)
            var resources = BattleActionResource.makeDefault(for: snapshot,
                                                            spellLoadout: .empty)
            let skillEffects = try cachedSkillEffects(for: definition,
                                                      cache: &cache,
                                                      skillDefinitions: skillDefinitions)
            if skillEffects.spell.breathExtraCharges > 0 {
                let current = resources.charges(for: .breath)
                resources.setCharges(for: .breath, value: current + skillEffects.spell.breathExtraCharges)
            }
            let identifier = index == 0 ? String(definition.id) : "\(definition.id)_\(index)"
            let actor = BattleActor(identifier: identifier,
                                    displayName: definition.name,
                                    kind: .enemy,
                                    formationSlot: slot,
                                    strength: definition.strength,
                                    wisdom: definition.wisdom,
                                    spirit: definition.spirit,
                                    vitality: definition.vitality,
                                    agility: definition.agility,
                                    luck: definition.luck,
                                    partyMemberId: nil,
                                    level: level,
                                    jobName: definition.jobId.flatMap { jobDefinitions[$0]?.name } ?? "敵",
                                    avatarIndex: nil,
                                    isMartialEligible: false,
                                    raceId: definition.raceId,
                                    enemyMasterIndex: definition.id,
                                    snapshot: snapshot,
                                    currentHP: snapshot.maxHP,
                                    actionRates: BattleActionRates(attack: definition.actionRates.attack,
                                                                   priestMagic: definition.actionRates.priestMagic,
                                                                   mageMagic: definition.actionRates.mageMagic,
                                                                   breath: definition.actionRates.breath),
                                    actionResources: resources,
                                    barrierCharges: skillEffects.combat.barrierCharges,
                                    skillEffects: skillEffects,
                                    spellbook: .empty,
                                    spells: .empty,
                                    baseSkillIds: Set(definition.specialSkillIds),
                                    innateResistances: BattleInnateResistances(from: definition.resistances))
            actors.append(actor)
        }
        return actors
    }

    nonisolated private static func cachedSkillEffects(for definition: EnemyDefinition,
                                           cache: inout [UInt16: BattleActor.SkillEffects],
                                           skillDefinitions: [UInt16: SkillDefinition]) throws -> BattleActor.SkillEffects {
        if let cached = cache[definition.id] {
            return cached
        }
        let skills = definition.specialSkillIds.compactMap { skillDefinitions[$0] }
        let skillCompiler = try UnifiedSkillEffectCompiler(skills: skills)
        let effects = skillCompiler.actorEffects
        cache[definition.id] = effects
        return effects
    }
}
