import Foundation

struct BattleEnemyGroupBuilder {
    struct EncounteredEnemy {
        let definition: EnemyDefinition
        let level: Int
    }

    static func makeEnemies(baseEnemyId: UInt16?,
                            baseEnemyLevel: Int?,
                            dungeon: DungeonDefinition,
                            floor: DungeonFloorDefinition,
                            enemyDefinitions: [UInt16: EnemyDefinition],
                            skillDefinitions: [UInt16: SkillDefinition],
                            jobDefinitions: [UInt8: JobDefinition],
                            raceDefinitions: [UInt8: RaceDefinition],
                            random: inout GameRandomSource) throws -> ([BattleActor], [EncounteredEnemy]) {
        var skillCache: [UInt16: BattleActor.SkillEffects] = [:]

        if let baseEnemyId, let definition = enemyDefinitions[baseEnemyId] {
            let count = randomGroupSize(for: definition, random: &random)
            let actors = try makeActors(for: definition,
                                        levelOverride: baseEnemyLevel,
                                        count: count,
                                        skillDefinitions: skillDefinitions,
                                        jobDefinitions: jobDefinitions,
                                        raceDefinitions: raceDefinitions,
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
                let baseHP = computeEnemyMaxHP(definition: group.definition, level: baseEnemyLevel ?? 1)
                let levelOverride = baseEnemyLevel ?? 1
                let snapshot = CombatSnapshotBuilder.makeEnemySnapshot(from: group.definition,
                                                                       baseHP: baseHP,
                                                                       levelOverride: levelOverride,
                                                                       jobDefinitions: jobDefinitions,
                                                                       raceDefinitions: raceDefinitions)
                var resources = BattleActionResource.makeDefault(for: snapshot,
                                                                spellLoadout: .empty)
                let skillEffects = try cachedSkillEffects(for: group.definition,
                                                          cache: &skillCache,
                                                          skillDefinitions: skillDefinitions)
                if skillEffects.breathExtraCharges > 0 {
                    let current = resources.charges(for: .breath)
                    resources.setCharges(for: .breath, value: current + skillEffects.breathExtraCharges)
                }
                let identifier = "\(group.definition.id)_\(slotIndex)"
                let raceCategory = raceDefinitions[group.definition.raceId]?.category ?? "enemy"
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
                                        raceCategory: raceCategory,
                                        snapshot: snapshot,
                                        currentHP: snapshot.maxHP,
                                        actionRates: BattleActionRates(attack: group.definition.actionRates.attack,
                                                                       priestMagic: group.definition.actionRates.priestMagic,
                                                                       mageMagic: group.definition.actionRates.mageMagic,
                                                                       breath: group.definition.actionRates.breath),
                                        actionResources: resources,
                                        barrierCharges: skillEffects.barrierCharges,
                                        skillEffects: skillEffects,
                                        spellbook: .empty,
                                        spells: .empty,
                                        baseSkillIds: Set(group.definition.skills.map { $0.skillId }) )
                actors.append(actor)
                encountered.append(EncounteredEnemy(definition: group.definition, level: levelOverride))
                slotIndex += 1
            }
        }

        return (actors, encountered)
    }

    private static func randomGroupSize(for definition: EnemyDefinition,
                                        random: inout GameRandomSource) -> Int {
        let range = definition.groupSizeRange
        if range.lowerBound == range.upperBound { return range.lowerBound }
        return random.nextInt(in: range.lowerBound...range.upperBound)
    }

    private static func makeActors(for definition: EnemyDefinition,
                                    levelOverride: Int?,
                                    count: Int,
                                    skillDefinitions: [UInt16: SkillDefinition],
                                    jobDefinitions: [UInt8: JobDefinition],
                                    raceDefinitions: [UInt8: RaceDefinition],
                                    cache: inout [UInt16: BattleActor.SkillEffects],
                                    random: inout GameRandomSource) throws -> [BattleActor] {
        var actors: [BattleActor] = []
        for index in 0..<count {
            guard let slot = BattleContextBuilder.slot(for: index) else { break }
            let level = levelOverride ?? 1
            let hpBase = computeEnemyMaxHP(definition: definition, level: level)
            let snapshot = CombatSnapshotBuilder.makeEnemySnapshot(from: definition,
                                                                   baseHP: hpBase,
                                                                   levelOverride: level,
                                                                   jobDefinitions: jobDefinitions,
                                                                   raceDefinitions: raceDefinitions)
            var resources = BattleActionResource.makeDefault(for: snapshot,
                                                            spellLoadout: .empty)
            let skillEffects = try cachedSkillEffects(for: definition,
                                                      cache: &cache,
                                                      skillDefinitions: skillDefinitions)
            if skillEffects.breathExtraCharges > 0 {
                let current = resources.charges(for: .breath)
                resources.setCharges(for: .breath, value: current + skillEffects.breathExtraCharges)
            }
            let identifier = index == 0 ? String(definition.id) : "\(definition.id)_\(index)"
            let raceCategory = raceDefinitions[definition.raceId]?.category ?? "enemy"
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
                                        raceCategory: raceCategory,
                                        snapshot: snapshot,
                                        currentHP: snapshot.maxHP,
                                        actionRates: BattleActionRates(attack: definition.actionRates.attack,
                                                                       priestMagic: definition.actionRates.priestMagic,
                                                                       mageMagic: definition.actionRates.mageMagic,
                                                                       breath: definition.actionRates.breath),
                                    actionResources: resources,
                                    barrierCharges: skillEffects.barrierCharges,
                                    skillEffects: skillEffects,
                                    spellbook: .empty,
                                    spells: .empty,
                                    baseSkillIds: Set(definition.skills.map { $0.skillId }) )
            actors.append(actor)
        }
        return actors
    }

    private static func cachedSkillEffects(for definition: EnemyDefinition,
                                           cache: inout [UInt16: BattleActor.SkillEffects],
                                           skillDefinitions: [UInt16: SkillDefinition]) throws -> BattleActor.SkillEffects {
        if let cached = cache[definition.id] {
            return cached
        }
        let skills = try definition.skills.map { entry -> SkillDefinition in
            guard let skill = skillDefinitions[entry.skillId] else {
                throw RuntimeError.masterDataNotFound(entity: "skill", identifier: String(entry.skillId))
            }
            return skill
        }
        let effects = try SkillRuntimeEffectCompiler.actorEffects(from: skills)
        cache[definition.id] = effects
        return effects
    }

    static func computeEnemyMaxHP(definition: EnemyDefinition, level: Int) -> Int {
        let vitality = max(1, definition.vitality)
        let spirit = max(1, definition.spirit)
        let effectiveLevel = max(1, level)
        return vitality * 12 + spirit * 6 + effectiveLevel * 8
    }
}
