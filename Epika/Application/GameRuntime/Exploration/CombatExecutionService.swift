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

/// 戦闘に出現する敵1種類の仕様
struct EncounteredEnemySpec: Sendable {
    let enemyId: UInt16
    let level: Int
    let count: Int
}

struct CombatExecutionService {
    private let masterData: MasterDataCache

    init(masterData: MasterDataCache) {
        self.masterData = masterData
    }

    func runCombat(enemySpecs: [EncounteredEnemySpec],
                   dungeon: DungeonDefinition,
                   floor: DungeonFloorDefinition,
                   party: inout RuntimePartyState,
                   droppedItemIds: Set<UInt16>,
                   superRareState: SuperRareDailyState,
                   random: inout GameRandomSource) throws -> CombatExecutionOutcome {
        var battleRandom = random
        let resolution = try BattleService.resolveBattle(masterData: masterData,
                                                         party: party,
                                                         dungeon: dungeon,
                                                         floor: floor,
                                                         enemySpecs: enemySpecs,
                                                         random: &battleRandom)
        random = battleRandom

        // 戦闘後のHP状態をパーティに反映
        for playerActor in resolution.playerActors {
            guard let partyMemberId = playerActor.partyMemberId else { continue }
            if let memberIndex = party.members.firstIndex(where: { $0.characterId == partyMemberId }) {
                party.members[memberIndex].character.currentHP = playerActor.currentHP
            }
        }

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
                                                    for: resolution.encounteredEnemies,
                                                    party: party,
                                                    dungeonId: dungeon.id,
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

        // identifierからスロット番号を抽出し、同じ敵種内での順番でサフィックスを決定
        // identifier形式: "enemyId_slotIndex" (例: "123_0", "123_1", "456_2")
        func extractSlotIndex(from identifier: String) -> Int {
            guard let underscoreIndex = identifier.lastIndex(of: "_"),
                  let slot = Int(identifier[identifier.index(after: underscoreIndex)...]) else {
                return 0
            }
            return slot
        }

        // 同じenemyMasterIndex内でスロット番号順にソートし、サフィックスマップを構築
        // key: enemyMasterIndex, value: [(slotIndex, suffixIndex)]
        var slotToSuffixMap: [UInt16: [Int: Int]] = [:]  // enemyMasterIndex → [slotIndex → suffixIndex (0=A, 1=B...)]

        // 同じenemyMasterIndexの敵をグループ化し、スロット番号でソート
        var groupedByEnemy: [UInt16: [(actor: BattleActor, arrayIndex: Int, slotIndex: Int)]] = [:]
        for (arrayIndex, actor) in resolution.enemyActors.enumerated() {
            let enemyId = actor.enemyMasterIndex ?? 0
            let slotIndex = extractSlotIndex(from: actor.identifier)
            groupedByEnemy[enemyId, default: []].append((actor, arrayIndex, slotIndex))
        }

        // 各グループ内でスロット番号順にソートし、サフィックスを割り当て
        for (enemyId, group) in groupedByEnemy {
            let sorted = group.sorted { $0.slotIndex < $1.slotIndex }
            var mapping: [Int: Int] = [:]
            for (suffixIndex, item) in sorted.enumerated() {
                mapping[item.slotIndex] = suffixIndex
            }
            slotToSuffixMap[enemyId] = mapping
        }

        // 同じ名前の敵が複数いるかカウント
        let enemyNameCounts = resolution.enemyActors.reduce(into: [String: Int]()) { counts, actor in
            counts[actor.displayName, default: 0] += 1
        }

        // スナップショットとソートキーを一緒に作成
        let snapshotsWithKeys: [(snapshot: BattleParticipantSnapshot, enemyId: UInt16, suffixIndex: Int)] = resolution.enemyActors.enumerated().map { (index, actor) in
            // actorIndex = (arrayIndex + 1) * 1000 + enemyMasterIndex
            // これは BattleContext.actorIndex の計算方法と一致する必要がある
            let actorIndex = UInt16(index + 1) * 1000 + (actor.enemyMasterIndex ?? 0)
            let enemyId = actor.enemyMasterIndex ?? 0
            let slotIndex = extractSlotIndex(from: actor.identifier)
            let suffixIndex = slotToSuffixMap[enemyId]?[slotIndex] ?? 0

            // 名前にサフィックスを追加（同名が2体以上の場合のみ）
            let baseName = actor.displayName
            let displayName: String
            if enemyNameCounts[baseName, default: 0] >= 2 {
                let suffix = String(UnicodeScalar(65 + suffixIndex)!)  // A, B, C...
                displayName = "\(baseName)\(suffix)"
            } else {
                displayName = baseName
            }

            let snapshot = BattleParticipantSnapshot(actorId: String(actorIndex),
                                                     partyMemberId: nil,
                                                     characterId: nil,
                                                     name: displayName,
                                                     avatarIndex: nil,
                                                     level: actor.level,
                                                     maxHP: actor.snapshot.maxHP)
            return (snapshot, enemyId, suffixIndex)
        }

        // enemyId昇順、同じenemyId内はsuffixIndex昇順（A→B→C→D）
        let enemySnapshots = snapshotsWithKeys
            .sorted { lhs, rhs in
                if lhs.enemyId != rhs.enemyId {
                    return lhs.enemyId < rhs.enemyId
                }
                return lhs.suffixIndex < rhs.suffixIndex
            }
            .map { $0.snapshot }

        let logArchive = BattleLogArchive(enemyId: resolution.enemy.id,
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
                                    drops: dropResults)

        // デバッグ用: 戦闘ログをバッファに保存
        BattleLogBuffer.shared.append(dungeonId: Int(dungeon.id),
                                       floor: floor.floorNumber,
                                       battleLog: resolution.battleLog)

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
