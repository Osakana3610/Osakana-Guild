import Foundation

struct CombatExecutionService {
    private let repository: MasterDataRepository

    init(repository: MasterDataRepository) {
        self.repository = repository
    }

    func runCombat(enemyId: UInt16,
                   enemyLevel: Int?,
                   dungeon: DungeonDefinition,
                   floor: DungeonFloorDefinition,
                   party: RuntimePartyState,
                   superRareState: SuperRareDailyState,
                   random: inout GameRandomSource) async throws -> CombatExecutionOutcome {
        var battleRandom = random
        let resolution = try await BattleService.resolveBattle(repository: repository,
                                                               party: party,
                                                               dungeon: dungeon,
                                                               floor: floor,
                                                               encounterEnemyId: enemyId,
                                                               encounterLevel: enemyLevel,
                                                               random: &battleRandom)
        random = battleRandom

        let rewards = try BattleRewardCalculator.calculateRewards(party: party,
                                                                  survivingMemberIds: resolution.survivingAllyIds,
                                                                  enemies: resolution.encounteredEnemies,
                                                                  result: resolution.result)

        let dropResults: [ExplorationDropReward]
        var updatedSuperRareState = superRareState

        if resolution.result == .victory {
            var dropRandom = random
            let dropOutcome = try await DropService.drops(repository: repository,
                                                          for: resolution.enemy,
                                                          party: party,
                                                          dungeonId: dungeon.id,
                                                          floorNumber: floor.floorNumber,
                                                          dailySuperRareState: updatedSuperRareState,
                                                          random: &dropRandom)
            random = dropRandom
            updatedSuperRareState = dropOutcome.superRareState
            dropResults = dropOutcome.results.map { result in
                let difficulty = BattleRewardCalculator.trapDifficulty(for: result.item,
                                                                       dungeon: dungeon,
                                                                       floor: floor)
                return ExplorationDropReward(item: result.item,
                                              quantity: result.quantity,
                                              trapDifficulty: difficulty,
                                              sourceEnemyId: result.sourceEnemyId,
                                              normalTitleId: result.normalTitleId,
                                              superRareTitleId: result.superRareTitleId)
            }
        } else {
            dropResults = []
        }

        let battleLogId = UUID()

        let partyMembersById = Dictionary(uniqueKeysWithValues: party.members.map { ($0.id, $0.character) })

        // survivingAllyIds (partyMemberId) から characterId を取得
        let survivingCharacterIds: [UInt8] = resolution.survivingAllyIds.compactMap { partyMemberId in
            partyMembersById[partyMemberId]?.id
        }

        let playerSnapshots: [BattleParticipantSnapshot] = resolution.playerActors.map { actor in
            let character = actor.partyMemberId.flatMap { partyMembersById[$0] }
            let avatarIndex = character?.resolvedAvatarId
            return BattleParticipantSnapshot(actorId: actor.identifier,
                                             partyMemberId: actor.partyMemberId,
                                             characterId: character?.id,
                                             name: character?.displayName ?? actor.displayName,
                                             avatarIndex: avatarIndex,
                                             level: character?.level ?? actor.level,
                                             maxHP: actor.snapshot.maxHP)
        }

        let enemySnapshots: [BattleParticipantSnapshot] = resolution.enemyActors.map { actor in
            BattleParticipantSnapshot(actorId: actor.identifier,
                                      partyMemberId: nil,
                                      characterId: nil,
                                      name: actor.displayName,
                                      avatarIndex: nil,
                                      level: actor.level,
                                      maxHP: actor.snapshot.maxHP)
        }

        let logArchive = BattleLogArchive(id: battleLogId,
                                          enemyId: resolution.enemy.id,
                                          enemyName: resolution.enemy.name,
                                          result: resolution.result,
                                          turns: resolution.turns,
                                          timestamp: Date(),
                                          battleLog: resolution.battleLog,
                                          playerSnapshots: playerSnapshots,
                                          enemySnapshots: enemySnapshots)

        let summary = CombatSummary(enemy: resolution.enemy,
                                    result: resolution.result,
                                    survivingPartyMemberIds: survivingCharacterIds,
                                    turns: resolution.turns,
                                    experienceByMember: rewards.experienceByMember,
                                    totalExperience: rewards.totalExperience,
                                    goldEarned: rewards.gold,
                                    drops: dropResults,
                                    battleLogId: battleLogId)

        return CombatExecutionOutcome(summary: summary,
                                       log: logArchive,
                                       updatedSuperRareState: updatedSuperRareState)
    }
}

struct CombatExecutionOutcome: Sendable {
    let summary: CombatSummary
    let log: BattleLogArchive
    let updatedSuperRareState: SuperRareDailyState
}
