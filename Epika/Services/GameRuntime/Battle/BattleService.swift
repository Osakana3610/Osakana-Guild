import Foundation

enum BattleService {
    enum BattleResult: String, Sendable, Codable {
        case victory
        case defeat
        case retreat
    }

    struct Resolution: Sendable {
        let result: BattleResult
        let survivingAllyIds: [UInt8]
        let turns: Int
        let battleLog: BattleLog
        let enemy: EnemyDefinition
        let enemies: [EnemyDefinition]
        let encounteredEnemies: [BattleEnemyGroupBuilder.EncounteredEnemy]
        let playerActors: [BattleActor]
        let enemyActors: [BattleActor]
    }

    static func resolveBattle(masterData: MasterDataCache,
                              party: RuntimePartyState,
                              dungeon: DungeonDefinition,
                              floor: DungeonFloorDefinition,
                              encounterEnemyId: UInt16?,
                              encounterLevel: Int?,
                              encounterGroupMin: Int?,
                              encounterGroupMax: Int?,
                              random: inout GameRandomSource) throws -> Resolution {
        let skillDictionary = Dictionary(uniqueKeysWithValues: masterData.allSkills.map { ($0.id, $0) })

        let players = try BattleContextBuilder.makePlayerActors(from: party)
        guard !players.isEmpty else {
            guard let enemyId = encounterEnemyId,
                  let enemyDefinition = masterData.enemy(enemyId) else {
                throw RuntimeError.masterDataNotFound(entity: "enemy", identifier: String(encounterEnemyId ?? 0))
            }
            return Resolution(result: .defeat,
                              survivingAllyIds: [],
                              turns: 0,
                              battleLog: .empty,
                              enemy: enemyDefinition,
                              enemies: [enemyDefinition],
                              encounteredEnemies: [BattleEnemyGroupBuilder.EncounteredEnemy(definition: enemyDefinition,
                                                                                              level: encounterLevel ?? 1)],
                              playerActors: [],
                              enemyActors: [])
        }

        let enemyDictionary = Dictionary(uniqueKeysWithValues: masterData.allEnemies.map { ($0.id, $0) })
        let statusDefinitions = Dictionary(uniqueKeysWithValues: masterData.allStatusEffects.map { ($0.id, $0) })
        let jobDictionary = Dictionary(uniqueKeysWithValues: masterData.allJobs.map { ($0.id, $0) })
        let raceDictionary = Dictionary(uniqueKeysWithValues: masterData.allRaces.map { ($0.id, $0) })
        let enemySkillDictionary = Dictionary(uniqueKeysWithValues: masterData.allEnemySkills.map { ($0.id, $0) })

        var localRandom = random
        let enemyResult = try BattleEnemyGroupBuilder.makeEnemies(baseEnemyId: encounterEnemyId,
                                                                 baseEnemyLevel: encounterLevel,
                                                                 groupMin: encounterGroupMin,
                                                                 groupMax: encounterGroupMax,
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
                throw RuntimeError.masterDataNotFound(entity: "enemy", identifier: String(encounterEnemyId ?? 0))
            }
            let slot = BattleFormationSlot.frontLeft
            let fallbackLevel = encounterLevel ?? 1
            let snapshot = try CombatSnapshotBuilder.makeEnemySnapshot(from: fallbackDefinition,
                                                                       levelOverride: fallbackLevel,
                                                                       jobDefinitions: jobDictionary)
            let resources = BattleActionResource.makeDefault(for: snapshot)
            let fallbackSkillEffects = try SkillRuntimeEffectCompiler.actorEffects(from: fallbackDefinition.specialSkillIds.compactMap { skillDictionary[$0] })
            let jobName: String? = fallbackDefinition.jobId.flatMap { jobDictionary[$0]?.name }
            enemies = [BattleActor(identifier: String(fallbackDefinition.id),
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
                                   jobName: jobName,
                                   avatarIndex: nil,
                                   isMartialEligible: false,
                                   raceId: fallbackDefinition.raceId,
                                   enemyMasterIndex: fallbackDefinition.id,
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
                                   baseSkillIds: Set(fallbackDefinition.specialSkillIds) )]
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
                                                      enemySkillDefinitions: enemySkillDictionary,
                                                      random: &mutableRandom)
        random = mutableRandom

        let revivedPlayers = applyBetweenFloorsResurrection(to: battleResult.players)
        let revivedEnemies = applyBetweenFloorsResurrection(to: battleResult.enemies)

        let survivingPartyIds = revivedPlayers
            .filter { $0.isAlive }
            .compactMap { $0.partyMemberId }

        let enemyDefinition = encounteredEnemies.first!.definition

        let result: BattleResult
        switch battleResult.outcome {
        case BattleLog.outcomeVictory: result = .victory
        case BattleLog.outcomeDefeat: result = .defeat
        case BattleLog.outcomeRetreat: result = .retreat
        default: result = .defeat
        }

        return Resolution(result: result,
                          survivingAllyIds: survivingPartyIds,
                          turns: Int(battleResult.battleLog.turns),
                          battleLog: battleResult.battleLog,
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
                  actor.skillEffects.resurrection.passiveBetweenFloors else {
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
