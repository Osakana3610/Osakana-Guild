import Foundation

@MainActor
final class ProgressRuntimeService {
    private let runtimeService: GameRuntimeService
    private let gameStateService: GameStateService

    init(runtimeService: GameRuntimeService,
         gameStateService: GameStateService) {
        self.runtimeService = runtimeService
        self.gameStateService = gameStateService
    }

    func runtimeCharacter(from snapshot: CharacterSnapshot) async throws -> RuntimeCharacter {
        let progress = makeRuntimeCharacterProgress(from: snapshot)
        return try await runtimeService.runtimeCharacter(from: progress)
    }

    func recalculateCombatSnapshot(for snapshot: CharacterSnapshot,
                                    pandoraBoxStackKeys: Set<String> = []) async throws -> CombatStatCalculator.Result {
        let progress = makeRuntimeCharacterProgress(from: snapshot)
        return try await runtimeService.recalculateCombatStats(for: progress, pandoraBoxStackKeys: pandoraBoxStackKeys)
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
        let superRareState = try await gameStateService.loadSuperRareDailyState()
        let session = try await runtimeService.startExplorationRun(dungeonId: dungeonId,
                                                                   targetFloorNumber: targetFloorNumber,
                                                                   party: partyState,
                                                                   superRareState: superRareState)

        let waitClosure: @Sendable () async throws -> ExplorationRunArtifact = { [weak self] in
            let artifact = try await session.waitForCompletion()
            if let self {
                try await self.gameStateService.updateSuperRareDailyState(artifact.updatedSuperRareState)
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
                RuntimeCharacterProgress.EquippedItem(superRareTitleIndex: $0.superRareTitleIndex,
                                                      normalTitleIndex: $0.normalTitleIndex,
                                                      masterDataIndex: $0.masterDataIndex,
                                                      socketSuperRareTitleIndex: $0.socketSuperRareTitleIndex,
                                                      socketNormalTitleIndex: $0.socketNormalTitleIndex,
                                                      socketMasterDataIndex: $0.socketMasterDataIndex,
                                                      quantity: $0.quantity)
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
            lastSelectedDungeonIndex: snapshot.lastSelectedDungeonIndex,
            lastSelectedDifficulty: snapshot.lastSelectedDifficulty,
            targetFloor: snapshot.targetFloor,
            memberIds: snapshot.memberCharacterIds)
    }
}
