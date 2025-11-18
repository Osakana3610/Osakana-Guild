import Foundation

struct BattleEnemyGroupBuilder {
    struct EncounteredEnemy {
        let definition: EnemyDefinition
        let level: Int
    }

    static func makeEnemies(baseEnemyId: String?,
                            baseEnemyLevel: Int?,
                            dungeon: DungeonDefinition,
                            floor: DungeonFloorDefinition,
                            enemyDefinitions: [String: EnemyDefinition],
                            skillDefinitions: [String: SkillDefinition],
                            jobDefinitions: [String: JobDefinition],
                            raceDefinitions: [String: RaceDefinition],
                            random: inout GameRandomSource) throws -> ([BattleActor], [EncounteredEnemy]) {
        var skillCache: [String: BattleActor.SkillEffects] = [:]

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
                let resources = BattleActionResource.makeDefault(for: snapshot)
                let skillEffects = try cachedSkillEffects(for: group.definition,
                                                          cache: &skillCache,
                                                          skillDefinitions: skillDefinitions)
                let identifier = "\(group.definition.id)_\(slotIndex)"
                let raceCategory = raceDefinitions[group.definition.race]?.category ?? group.definition.race
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
                                        jobName: group.definition.job,
                                        avatarIdentifier: nil,
                                        isMartialEligible: false,
                                        raceId: group.definition.race,
                                        raceCategory: raceCategory,
                                        snapshot: snapshot,
                                        currentHP: snapshot.maxHP,
                                        actionRates: BattleActionRates(attack: group.definition.actionRates.attack,
                                                                       clericMagic: group.definition.actionRates.clericMagic,
                                                                       arcaneMagic: group.definition.actionRates.arcaneMagic,
                                                                       breath: group.definition.actionRates.breath),
                                        actionResources: resources,
                                        barrierCharges: skillEffects.barrierCharges,
                                        skillEffects: skillEffects,
                                        spellbook: .empty,
                                        spells: .empty)
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
                                    skillDefinitions: [String: SkillDefinition],
                                    jobDefinitions: [String: JobDefinition],
                                    raceDefinitions: [String: RaceDefinition],
                                    cache: inout [String: BattleActor.SkillEffects],
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
            let resources = BattleActionResource.makeDefault(for: snapshot)
            let skillEffects = try cachedSkillEffects(for: definition,
                                                      cache: &cache,
                                                      skillDefinitions: skillDefinitions)
            let identifier = index == 0 ? definition.id : "\(definition.id)_\(index)"
            let raceCategory = raceDefinitions[definition.race]?.category ?? definition.race
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
                                    jobName: definition.job,
                                    avatarIdentifier: nil,
                                    isMartialEligible: false,
                                    raceId: definition.race,
                                        raceCategory: raceCategory,
                                        snapshot: snapshot,
                                        currentHP: snapshot.maxHP,
                                        actionRates: BattleActionRates(attack: definition.actionRates.attack,
                                                                       clericMagic: definition.actionRates.clericMagic,
                                                                       arcaneMagic: definition.actionRates.arcaneMagic,
                                                                       breath: definition.actionRates.breath),
                                        actionResources: resources,
                                        barrierCharges: skillEffects.barrierCharges,
                                        skillEffects: skillEffects,
                                        spellbook: .empty,
                                        spells: .empty)
                actors.append(actor)
        }
        return actors
    }

    private static func cachedSkillEffects(for definition: EnemyDefinition,
                                           cache: inout [String: BattleActor.SkillEffects],
                                           skillDefinitions: [String: SkillDefinition]) throws -> BattleActor.SkillEffects {
        if let cached = cache[definition.id] {
            return cached
        }
        let skills = try definition.skills.map { entry -> SkillDefinition in
            guard let definition = skillDefinitions[entry.skillId] else {
                throw RuntimeError.masterDataNotFound(entity: "skill", identifier: entry.skillId)
            }
            return definition
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
