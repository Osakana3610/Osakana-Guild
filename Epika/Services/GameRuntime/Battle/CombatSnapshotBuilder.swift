import Foundation

struct CombatSnapshotBuilder {
    static func makeEnemySnapshot(from definition: EnemyDefinition,
                                  baseHP: Int,
                                  levelOverride: Int?,
                                  jobDefinitions: [String: JobDefinition],
                                  raceDefinitions: [String: RaceDefinition]) -> RuntimeCharacterProgress.Combat {
        let level = max(1, levelOverride ?? 1)
        let baseAttributes = RuntimeCharacterProgress.CoreAttributes(strength: definition.strength,
                                                                     wisdom: definition.wisdom,
                                                                     spirit: definition.spirit,
                                                                     vitality: definition.vitality,
                                                                     agility: definition.agility,
                                                                     luck: definition.luck)
        let initialCombat = RuntimeCharacterProgress.Combat(maxHP: baseHP,
                                                            physicalAttack: definition.strength,
                                                            magicalAttack: definition.wisdom,
                                                            physicalDefense: definition.vitality,
                                                            magicalDefense: definition.spirit,
                                                            hitRate: definition.agility * 2 + definition.luck,
                                                            evasionRate: definition.agility * 2,
                                                            criticalRate: max(5, definition.luck / 2),
                                                            attackCount: max(1, definition.agility / 60 + 1),
                                                            magicalHealing: definition.spirit,
                                                            trapRemoval: 0,
                                                            additionalDamage: 0,
                                                            breathDamage: 0,
                                                            isMartialEligible: false)

        let progress = RuntimeCharacterProgress(id: UUID(),
                                                displayName: definition.name,
                                                raceId: definition.race,
                                                gender: "enemy",
                                                jobId: definition.job ?? "enemy.default",
                                                avatarIdentifier: definition.id,
                                                level: level,
                                                experience: 0,
                                                attributes: baseAttributes,
                                                hitPoints: .init(current: baseHP, maximum: baseHP),
                                                combat: initialCombat,
                                                personality: .init(primaryId: nil, secondaryId: nil),
                                                learnedSkills: [],
                                                equippedItems: [],
                                                jobHistory: [],
                                                explorationTags: Set<String>(),
                                                achievements: .init(totalBattles: 0, totalVictories: 0, defeatCount: 0),
                                                actionPreferences: .init(attack: 100,
                                                                         clericMagic: 0,
                                                                         arcaneMagic: 0,
                                                                         breath: 50),
                                                createdAt: Date(),
                                                updatedAt: Date())

        let raceDefinition = raceDefinitions[definition.race] ?? makeFallbackRaceDefinition(for: definition)
        let jobDefinition = jobDefinitions[definition.job ?? ""] ?? makeFallbackJobDefinition(for: definition)

        let state = RuntimeCharacterState(progress: progress,
                                          race: raceDefinition,
                                          job: jobDefinition,
                                          personalityPrimary: nil,
                                          personalitySecondary: nil,
                                          learnedSkills: [],
                                          loadout: .init(items: [], titles: [], superRareTitles: []),
                                          spellbook: .empty,
                                          spellLoadout: .empty)

        do {
            let context = CombatStatCalculator.Context(progress: progress, state: state)
            let result = try CombatStatCalculator.calculate(for: context)
            return normalized(combat: result.combat, fallback: initialCombat)
        } catch {
            return initialCombat
        }
    }
}

private extension CombatSnapshotBuilder {
    static func makeFallbackRaceDefinition(for definition: EnemyDefinition) -> RaceDefinition {
        let baseStats: [RaceDefinition.BaseStat] = [
            .init(stat: "strength", value: definition.strength),
            .init(stat: "wisdom", value: definition.wisdom),
            .init(stat: "spirit", value: definition.spirit),
            .init(stat: "vitality", value: definition.vitality),
            .init(stat: "agility", value: definition.agility),
            .init(stat: "luck", value: definition.luck)
        ]
        return RaceDefinition(id: definition.race,
                              name: definition.race.capitalized,
                              gender: "enemy",
                              category: definition.category,
                              description: "Auto-generated enemy race",
                              baseStats: baseStats,
                              maxLevel: 200)
    }

    static func makeFallbackJobDefinition(for definition: EnemyDefinition) -> JobDefinition {
        let jobId = definition.job ?? "enemy.default"
        let metricKeys = ["maxHP",
                          "physicalAttack",
                          "magicalAttack",
                          "physicalDefense",
                          "magicalDefense",
                          "hitRate",
                          "evasionRate",
                          "criticalRate",
                          "attackCount",
                          "magicalHealing",
                          "trapRemoval",
                          "additionalDamage",
                          "breathDamage"]
        let coefficients: [JobDefinition.CombatCoefficient] = metricKeys.map {
            JobDefinition.CombatCoefficient(stat: $0, value: 0.0)
        }
        return JobDefinition(id: jobId,
                             name: jobId.capitalized,
                             category: "enemy",
                             growthTendency: nil,
                             combatCoefficients: coefficients,
                             learnedSkills: [])
    }

    static func normalized(combat: RuntimeCharacterProgress.Combat,
                           fallback: RuntimeCharacterProgress.Combat) -> RuntimeCharacterProgress.Combat {
        RuntimeCharacterProgress.Combat(maxHP: max(1, combat.maxHP, fallback.maxHP),
                                        physicalAttack: max(1, combat.physicalAttack, fallback.physicalAttack),
                                        magicalAttack: max(1, combat.magicalAttack, fallback.magicalAttack),
                                        physicalDefense: max(1, combat.physicalDefense, fallback.physicalDefense),
                                        magicalDefense: max(1, combat.magicalDefense, fallback.magicalDefense),
                                        hitRate: max(1, combat.hitRate, fallback.hitRate),
                                        evasionRate: max(0, combat.evasionRate, fallback.evasionRate),
                                        criticalRate: max(0, combat.criticalRate, fallback.criticalRate),
                                        attackCount: max(1, combat.attackCount, fallback.attackCount),
                                        magicalHealing: max(0, combat.magicalHealing, fallback.magicalHealing),
                                        trapRemoval: max(0, combat.trapRemoval, fallback.trapRemoval),
                                        additionalDamage: max(0, combat.additionalDamage, fallback.additionalDamage),
                                        breathDamage: max(0, combat.breathDamage, fallback.breathDamage),
                                        isMartialEligible: combat.isMartialEligible || fallback.isMartialEligible)
    }
}
