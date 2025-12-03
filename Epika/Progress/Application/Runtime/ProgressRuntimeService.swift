import Foundation

@MainActor
final class ProgressRuntimeService {
    private let runtimeService: GameRuntimeService
    private let metadataService: ProgressMetadataService

    init(runtimeService: GameRuntimeService,
         metadataService: ProgressMetadataService) {
        self.runtimeService = runtimeService
        self.metadataService = metadataService
    }

    func runtimeCharacter(from snapshot: CharacterSnapshot) async throws -> RuntimeCharacter {
        let progress = makeRuntimeCharacterProgress(from: snapshot)
        return try await runtimeService.runtimeCharacter(from: progress)
    }

    func recalculateCombatSnapshot(for snapshot: CharacterSnapshot,
                                    pandoraBoxItemIds: Set<UUID> = []) async throws -> CombatStatCalculator.Result {
        let progress = makeRuntimeCharacterProgress(from: snapshot)
        return try await runtimeService.recalculateCombatStats(for: progress, pandoraBoxItemIds: pandoraBoxItemIds)
    }

    func raceMaxLevel(for raceId: String) async throws -> Int {
        if let definition = try await runtimeService.raceDefinition(withId: raceId) {
            return definition.maxLevel
        }
        throw ProgressError.invalidInput(description: "種族マスタに存在しないIDです (\(raceId))")
    }

    func cancelExploration(runId: UUID) async {
        await runtimeService.cancelExploration(runId: runId)
    }

    func startExplorationRun(party: PartySnapshot,
                              characters: [CharacterSnapshot],
                              dungeonId: String,
                              targetFloorNumber: Int) async throws -> ExplorationRuntimeSession {
        let partyProgress = makeRuntimePartyProgress(from: party)
        let characterProgresses = characters.map(makeRuntimeCharacterProgress(from:))
        let partyState = try await runtimeService.runtimePartyState(party: partyProgress,
                                                                   characters: characterProgresses)
        let runtimeCharacters = partyState.members.map { $0.character }
        let superRareState = try await metadataService.loadSuperRareDailyState()
        let session = try await runtimeService.startExplorationRun(dungeonId: dungeonId,
                                                                   targetFloorNumber: targetFloorNumber,
                                                                   party: partyState,
                                                                   superRareState: superRareState)

        let waitClosure: @Sendable () async throws -> ExplorationRunArtifact = { [weak self] in
            let artifact = try await session.waitForCompletion()
            if let self {
                try await self.metadataService.updateSuperRareDailyState(artifact.updatedSuperRareState)
            }
            return artifact
        }

        return ExplorationRuntimeSession(runId: session.runId,
                                          preparation: session.preparation,
                                          startedAt: session.startedAt,
                                          explorationInterval: session.explorationInterval,
                                          events: session.events,
                                          runtimePartyState: partyState,
                                          runtimeCharacters: runtimeCharacters,
                                          waitForCompletion: waitClosure,
                                          cancel: session.cancel)
    }

}

struct ExplorationRuntimeSession: Sendable {
    let runId: UUID
    let preparation: ExplorationEngine.Preparation
    let startedAt: Date
    let explorationInterval: TimeInterval
    let events: AsyncStream<ExplorationEngine.StepOutcome>
    let runtimePartyState: RuntimePartyState
    let runtimeCharacters: [RuntimeCharacterState]
    let waitForCompletion: @Sendable () async throws -> ExplorationRunArtifact
    let cancel: @Sendable () async -> Void
}

private extension ProgressRuntimeService {
    func makeRuntimeCharacterProgress(from snapshot: CharacterSnapshot) -> RuntimeCharacterProgress {
        RuntimeCharacterProgress(
            id: snapshot.id,
            displayName: snapshot.displayName,
            raceId: snapshot.raceId,
            gender: snapshot.gender,
            jobId: snapshot.jobId,
            avatarIdentifier: snapshot.avatarIdentifier,
            level: snapshot.level,
            experience: snapshot.experience,
            attributes: .init(strength: snapshot.attributes.strength,
                              wisdom: snapshot.attributes.wisdom,
                              spirit: snapshot.attributes.spirit,
                              vitality: snapshot.attributes.vitality,
                              agility: snapshot.attributes.agility,
                              luck: snapshot.attributes.luck),
            hitPoints: .init(current: snapshot.hitPoints.current,
                              maximum: snapshot.hitPoints.maximum),
            combat: .init(maxHP: snapshot.combat.maxHP,
                          physicalAttack: snapshot.combat.physicalAttack,
                          magicalAttack: snapshot.combat.magicalAttack,
                          physicalDefense: snapshot.combat.physicalDefense,
                          magicalDefense: snapshot.combat.magicalDefense,
                          hitRate: snapshot.combat.hitRate,
                          evasionRate: snapshot.combat.evasionRate,
                          criticalRate: snapshot.combat.criticalRate,
                          attackCount: snapshot.combat.attackCount,
                          magicalHealing: snapshot.combat.magicalHealing,
                          trapRemoval: snapshot.combat.trapRemoval,
                          additionalDamage: snapshot.combat.additionalDamage,
                          breathDamage: snapshot.combat.breathDamage,
                          isMartialEligible: snapshot.combat.isMartialEligible),
            personality: .init(primaryId: snapshot.personality.primaryId,
                               secondaryId: snapshot.personality.secondaryId),
            learnedSkills: snapshot.learnedSkills.map {
                RuntimeCharacterProgress.LearnedSkill(id: $0.id,
                                                      skillId: $0.skillId,
                                                      level: $0.level,
                                                      isEquipped: $0.isEquipped,
                                                      createdAt: $0.createdAt,
                                                      updatedAt: $0.updatedAt)
            },
            equippedItems: snapshot.equippedItems.map {
                RuntimeCharacterProgress.EquippedItem(id: $0.id,
                                                      itemId: $0.itemId,
                                                      quantity: $0.quantity,
                                                      normalTitleId: $0.normalTitleId,
                                                      superRareTitleId: $0.superRareTitleId,
                                                      socketKey: $0.socketKey,
                                                      createdAt: $0.createdAt,
                                                      updatedAt: $0.updatedAt)
            },
            jobHistory: snapshot.jobHistory,
            explorationTags: snapshot.explorationTags,
            achievements: .init(totalBattles: snapshot.achievements.totalBattles,
                                totalVictories: snapshot.achievements.totalVictories,
                                defeatCount: snapshot.achievements.defeatCount),
            actionPreferences: .init(attack: snapshot.actionPreferences.attack,
                                     priestMagic: snapshot.actionPreferences.priestMagic,
                                     mageMagic: snapshot.actionPreferences.mageMagic,
                                     breath: snapshot.actionPreferences.breath),
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt)
    }

    func makeRuntimePartyProgress(from snapshot: PartySnapshot) -> RuntimePartyProgress {
        RuntimePartyProgress(
            id: snapshot.id,
            displayName: snapshot.displayName,
            formationId: snapshot.formationId,
            lastSelectedDungeonId: snapshot.lastSelectedDungeonId,
            lastSelectedDifficulty: snapshot.lastSelectedDifficulty,
            targetFloor: snapshot.targetFloor,
            members: snapshot.members.map {
                RuntimePartyProgress.Member(id: $0.id,
                                             characterId: $0.characterId,
                                             order: $0.order,
                                             isReserve: $0.isReserve,
                                             createdAt: $0.createdAt,
                                             updatedAt: $0.updatedAt)
            })
    }
}
