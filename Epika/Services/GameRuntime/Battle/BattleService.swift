import Foundation

enum BattleService {
    enum BattleResult: String, Sendable, Codable {
        case victory
        case defeat
        case retreat
    }

    struct Resolution: Sendable {
        let result: BattleResult
        let survivingAllyIds: [UUID]
        let turns: Int
        let log: [BattleLogEntry]
        let enemy: EnemyDefinition
        let enemies: [EnemyDefinition]
        let encounteredEnemies: [BattleEnemyGroupBuilder.EncounteredEnemy]
        let playerActors: [BattleActor]
        let enemyActors: [BattleActor]
    }

    static func resolveBattle(repository: MasterDataRepository,
                              party: RuntimePartyState,
                              dungeon: DungeonDefinition,
                              floor: DungeonFloorDefinition,
                              encounterEnemyId: String?,
                              encounterLevel: Int?,
                              random: inout GameRandomSource) async throws -> Resolution {
        let skillDefinitions = try await repository.allSkills()
        let skillDictionary = Dictionary(uniqueKeysWithValues: skillDefinitions.map { ($0.id, $0) })

        let players = try BattleContextBuilder.makePlayerActors(from: party)
        guard !players.isEmpty else {
            guard let enemyDefinition = try await repository.enemy(withId: encounterEnemyId ?? "") else {
                throw RuntimeError.masterDataNotFound(entity: "enemy", identifier: encounterEnemyId ?? "unknown")
            }
            return Resolution(result: .defeat,
                              survivingAllyIds: [],
                              turns: 0,
                              log: [],
                              enemy: enemyDefinition,
                              enemies: [enemyDefinition],
                              encounteredEnemies: [BattleEnemyGroupBuilder.EncounteredEnemy(definition: enemyDefinition,
                                                                                              level: encounterLevel ?? 1)],
                              playerActors: [],
                              enemyActors: [])
        }

        let enemyDefinitions = try await repository.allEnemies()
        let enemyDictionary = Dictionary(uniqueKeysWithValues: enemyDefinitions.map { ($0.id, $0) })
        let statusEffects = try await repository.allStatusEffects()
        let statusDefinitions = Dictionary(uniqueKeysWithValues: statusEffects.map { ($0.id, $0) })
        let jobDefinitions = try await repository.allJobs()
        let jobDictionary = Dictionary(uniqueKeysWithValues: jobDefinitions.map { ($0.id, $0) })
        let raceDefinitions = try await repository.allRaces()
        let raceDictionary = Dictionary(uniqueKeysWithValues: raceDefinitions.map { ($0.id, $0) })

        var localRandom = random
        let enemyResult = try BattleEnemyGroupBuilder.makeEnemies(baseEnemyId: encounterEnemyId,
                                                                 baseEnemyLevel: encounterLevel,
                                                                 dungeon: dungeon,
                                                                 floor: floor,
                                                                 enemyDefinitions: enemyDictionary,
                                                                 skillDefinitions: skillDictionary,
                                                                 jobDefinitions: jobDictionary,
                                                                 raceDefinitions: raceDictionary,
                                                                 random: &localRandom)
        var enemies = enemyResult.0
        var encounteredEnemies = enemyResult.1

        if enemies.isEmpty {
            guard let enemyId = encounterEnemyId,
                  let fallbackDefinition = enemyDictionary[enemyId] else {
                throw RuntimeError.masterDataNotFound(entity: "enemy", identifier: encounterEnemyId ?? "unknown")
            }
            let slot = BattleFormationSlot.frontLeft
            let fallbackLevel = encounterLevel ?? 1
            let baseHP = BattleEnemyGroupBuilder.computeEnemyMaxHP(definition: fallbackDefinition, level: fallbackLevel)
            let snapshot = CombatSnapshotBuilder.makeEnemySnapshot(from: fallbackDefinition,
                                                                   baseHP: baseHP,
                                                                   levelOverride: fallbackLevel,
                                                                   jobDefinitions: jobDictionary,
                                                                   raceDefinitions: raceDictionary)
            let resources = BattleActionResource.makeDefault(for: snapshot)
            let fallbackSkillEffects = try SkillRuntimeEffectCompiler.actorEffects(from: fallbackDefinition.skills.map { entry in
                guard let definition = skillDictionary[entry.skillId] else {
                    throw RuntimeError.masterDataNotFound(entity: "skill", identifier: entry.skillId)
                }
                return definition
            })
            enemies = [BattleActor(identifier: fallbackDefinition.id,
                                   displayName: fallbackDefinition.name,
                                   kind: .enemy,
                                   formationSlot: slot,
                                   strength: fallbackDefinition.strength,
                                   wisdom: fallbackDefinition.wisdom,
                                   spirit: fallbackDefinition.spirit,
                                   vitality: fallbackDefinition.vitality,
                                   agility: fallbackDefinition.agility,
                                   luck: fallbackDefinition.luck,
                                   partyMemberId: nil,
                                   level: fallbackLevel,
                                   jobName: fallbackDefinition.job,
                                   avatarIdentifier: nil,
                                   isMartialEligible: false,
                                   raceId: fallbackDefinition.race,
                                   raceCategory: raceDictionary[fallbackDefinition.race]?.category ?? fallbackDefinition.race,
                                   snapshot: snapshot,
                                   currentHP: snapshot.maxHP,
                                   actionRates: BattleActionRates(attack: fallbackDefinition.actionRates.attack,
                                                                  priestMagic: fallbackDefinition.actionRates.priestMagic,
                                                                  mageMagic: fallbackDefinition.actionRates.mageMagic,
                                                                  breath: fallbackDefinition.actionRates.breath),
                                   actionResources: resources,
                                   skillEffects: fallbackSkillEffects,
                                   spellbook: .empty,
                                   spells: .empty,
                                   baseSkillIds: Set(fallbackDefinition.skills.map { $0.skillId }) )]
            encounteredEnemies = [BattleEnemyGroupBuilder.EncounteredEnemy(definition: fallbackDefinition,
                                                                          level: encounterLevel ?? 1)]
            random = localRandom
        }
        random = localRandom

        guard !enemies.isEmpty else {
            throw RuntimeError.invalidConfiguration(reason: "敵編成を生成できませんでした")
        }

        var mutablePlayers = players
        var mutableEnemies = enemies
        var mutableRandom = random
        let battleResult = BattleTurnEngine.runBattle(players: &mutablePlayers,
                                                      enemies: &mutableEnemies,
                                                      statusEffects: statusDefinitions,
                                                      skillDefinitions: skillDictionary,
                                                      random: &mutableRandom)
        random = mutableRandom

        let revivedPlayers = applyBetweenFloorsResurrection(to: battleResult.players)
        let revivedEnemies = applyBetweenFloorsResurrection(to: battleResult.enemies)

        let survivingPartyIds = revivedPlayers
            .filter { $0.isAlive }
            .compactMap { $0.partyMemberId }

        let enemyDefinition = encounteredEnemies.first?.definition ?? enemyDictionary[encounterEnemyId ?? ""] ?? enemyDefinitions.first!

        return Resolution(result: battleResult.result,
                          survivingAllyIds: survivingPartyIds,
                          turns: battleResult.turns,
                          log: battleResult.log,
                          enemy: enemyDefinition,
                          enemies: encounteredEnemies.map { $0.definition },
                          encounteredEnemies: encounteredEnemies,
                          playerActors: revivedPlayers,
                          enemyActors: revivedEnemies)
    }
}

private extension BattleService {
    static func applyBetweenFloorsResurrection(to actors: [BattleActor]) -> [BattleActor] {
        actors.map { actor in
            guard !actor.isAlive,
                  actor.skillEffects.resurrectionPassiveBetweenFloors else {
                return actor
            }

            var revived = actor
            revived.currentHP = max(1, actor.currentHP)
            revived.statusEffects = []
            revived.guardActive = false
            return revived
        }
    }
}

