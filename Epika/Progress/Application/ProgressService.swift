import Foundation
import Combine
import SwiftData

@MainActor
final class ProgressService: ObservableObject {
    let container: ModelContainer
    let gameState: GameStateService
    let environment: ProgressEnvironment
    let character: CharacterProgressService
    let party: PartyProgressService
    let inventory: InventoryProgressService
    let shop: ShopProgressService
    let exploration: ExplorationProgressService
    let dungeon: DungeonProgressService
    let story: StoryProgressService
    let titleInheritance: TitleInheritanceProgressService
    let artifactExchange: ArtifactExchangeProgressService
    let itemSynthesis: ItemSynthesisProgressService
    let autoTrade: AutoTradeProgressService
    let runtime: ProgressRuntimeService
    let dropNotifications: ItemDropNotificationService
    let itemPreload: ItemPreloadService
    let cloudKitCleanup: ProgressCloudKitCleanupService
    let gemModification: GemModificationProgressService
    let masterData: MasterDataRuntimeService

    let maniaDifficultyRank = 2

    struct ExplorationRunTotals: Sendable {
        let totalExperience: Int
        let totalGold: Int
        let drops: [ExplorationDropReward]
    }

    struct ExplorationRunUpdate: Sendable {
        enum Stage: Sendable {
            case step(entry: ExplorationEventLogEntry, totals: ExplorationRunTotals)
            case completed(ExplorationRunArtifact)
        }

        let runId: UUID
        let stage: Stage
    }

    struct ExplorationRunHandle: Sendable {
        let runId: UUID
        let updates: AsyncThrowingStream<ExplorationRunUpdate, Error>
        let cancel: @Sendable () async -> Void
    }

    init(container: ModelContainer,
         environment: ProgressEnvironment = .live,
         cloudKitCleanup: ProgressCloudKitCleanupService = .init()) {
        self.container = container
        self.environment = environment
        let gameStateService = GameStateService(container: container)
        self.gameState = gameStateService
        self.cloudKitCleanup = cloudKitCleanup
        let dropNotifications = ItemDropNotificationService()
        self.dropNotifications = dropNotifications
        let dropNotifier: @Sendable ([ItemDropResult]) async -> Void = { [weak dropNotifications] results in
            guard let dropNotifications, !results.isEmpty else { return }
            let masterData = MasterDataRuntimeService.shared
            // 全称号を事前取得（個別取得だとエラーが発生する場合があるため）
            var normalTitleNames: [UInt8: String] = [:]
            var superRareTitleNames: [UInt8: String] = [:]
            do {
                let allTitles = try await masterData.getAllTitles()
                for title in allTitles {
                    normalTitleNames[title.id] = title.name
                }
                let allSuperRareTitles = try await masterData.getAllSuperRareTitles()
                for title in allSuperRareTitles {
                    superRareTitleNames[title.id] = title.name
                }
            } catch {
                // 称号取得に失敗しても通知自体は行う
            }
            await MainActor.run {
                dropNotifications.publish(results: results,
                                          normalTitleNames: normalTitleNames,
                                          superRareTitleNames: superRareTitleNames)
            }
        }
        let runtimeService = GameRuntimeService(dropNotifier: dropNotifier)
        self.runtime = ProgressRuntimeService(runtimeService: runtimeService,
                                              gameStateService: gameStateService)

        self.party = PartyProgressService(container: container)
        self.inventory = InventoryProgressService(container: container,
                                                  gameStateService: gameStateService,
                                                  environment: environment)
        self.shop = ShopProgressService(container: container,
                                        environment: environment,
                                        inventoryService: self.inventory,
                                        gameStateService: gameStateService)
        self.character = CharacterProgressService(container: container)
        self.exploration = ExplorationProgressService(container: container)
        self.dungeon = DungeonProgressService(container: container)
        self.story = StoryProgressService(container: container)
        self.titleInheritance = TitleInheritanceProgressService(inventoryService: self.inventory)
        self.artifactExchange = ArtifactExchangeProgressService(inventoryService: self.inventory)
        self.itemSynthesis = ItemSynthesisProgressService(inventoryService: self.inventory,
                                                          gameStateService: gameStateService)
        self.autoTrade = AutoTradeProgressService(container: container,
                                                   gameStateService: gameStateService,
                                                   environment: environment)
        self.itemPreload = .shared
        self.masterData = .shared
        self.gemModification = GemModificationProgressService(container: container,
                                                               masterDataService: .shared)
    }
}

extension Notification.Name {
    static let progressUnlocksDidChange = Notification.Name("ProgressUnlocksDidChange")
    static let characterProgressDidChange = Notification.Name("CharacterProgressDidChange")
}
