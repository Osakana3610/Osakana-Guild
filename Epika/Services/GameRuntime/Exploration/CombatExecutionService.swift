// ==============================================================================
// CombatExecutionService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 探索中の戦闘実行と結果の統合
//   - 戦闘後の報酬計算とドロップ処理
//   - 戦闘ログとスナップショットの生成
//
// 【公開API】
//   - runCombat(): 戦闘実行から報酬計算、ドロップ処理までを統合実行
//
// 【使用箇所】
//   - ExplorationEngine（探索イベント処理時の戦闘実行）
//
// ==============================================================================

import Foundation

struct CombatExecutionService {
    private let masterData: MasterDataCache

    init(masterData: MasterDataCache) {
        self.masterData = masterData
    }

    @MainActor
    func runCombat(enemyId: UInt16,
                   enemyLevel: Int?,
                   groupMin: Int?,
                   groupMax: Int?,
                   dungeon: DungeonDefinition,
                   floor: DungeonFloorDefinition,
                   party: RuntimePartyState,
                   droppedItemIds: Set<UInt16>,
                   superRareState: SuperRareDailyState,
                   random: inout GameRandomSource) throws -> CombatExecutionOutcome {
        var battleRandom = random
        let resolution = try BattleService.resolveBattle(masterData: masterData,
                                                         party: party,
                                                         dungeon: dungeon,
                                                         floor: floor,
                                                         encounterEnemyId: enemyId,
                                                         encounterLevel: enemyLevel,
                                                         encounterGroupMin: groupMin,
                                                         encounterGroupMax: groupMax,
                                                         random: &battleRandom)
        random = battleRandom

        let rewards = try BattleRewardCalculator.calculateRewards(party: party,
                                                                  survivingMemberIds: resolution.survivingAllyIds,
                                                                  enemies: resolution.encounteredEnemies,
                                                                  result: resolution.result)

        let dropResults: [ExplorationDropReward]
        var updatedSuperRareState = superRareState
        var newlyDroppedItemIds: Set<UInt16> = []

        if resolution.result == .victory {
            // 勝利時は全敵倒されたとみなす
            var dropRandom = random
            let dropOutcome = try DropService.drops(masterData: masterData,
                                                    for: resolution.enemies,
                                                    party: party,
                                                    dungeonId: dungeon.id,
                                                    chapter: dungeon.chapter,
                                                    floorNumber: floor.floorNumber,
                                                    droppedItemIds: droppedItemIds,
                                                    dailySuperRareState: updatedSuperRareState,
                                                    random: &dropRandom)
            random = dropRandom
            updatedSuperRareState = dropOutcome.superRareState
            newlyDroppedItemIds = dropOutcome.newlyDroppedItemIds
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
            // 敗北（全滅）または撤退時はドロップなし
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

        let enemySnapshots: [BattleParticipantSnapshot] = resolution.enemyActors.enumerated().map { (index, actor) in
            // actorIndex = (arrayIndex + 1) * 1000 + enemyMasterIndex
            // これは BattleContext.actorIndex の計算方法と一致する必要がある
            let actorIndex = UInt16(index + 1) * 1000 + (actor.enemyMasterIndex ?? 0)
            return BattleParticipantSnapshot(actorId: String(actorIndex),
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
                                       updatedSuperRareState: updatedSuperRareState,
                                       newlyDroppedItemIds: newlyDroppedItemIds)
    }
}

struct CombatExecutionOutcome: Sendable {
    let summary: CombatSummary
    let log: BattleLogArchive
    let updatedSuperRareState: SuperRareDailyState
    /// 今回の戦闘で新たにドロップしたアイテムID
    let newlyDroppedItemIds: Set<UInt16>
}
