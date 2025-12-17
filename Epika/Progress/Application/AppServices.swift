import Foundation
import Combine
import SwiftData
import SwiftUI

@MainActor
final class AppServices: ObservableObject {
    let container: ModelContainer
    let masterDataCache: MasterDataCache
    let gameState: GameStateService
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
    let gemModification: GemModificationProgressService

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

    init(container: ModelContainer, masterDataCache: MasterDataCache, masterDataManager: SQLiteMasterDataManager) {
        self.container = container
        self.masterDataCache = masterDataCache
        let gameStateService = GameStateService(container: container)
        self.gameState = gameStateService
        let dropNotifications = ItemDropNotificationService(masterDataCache: masterDataCache)
        self.dropNotifications = dropNotifications
        let dropNotifier: @Sendable ([ItemDropResult]) async -> Void = { [weak dropNotifications] results in
            guard let dropNotifications, !results.isEmpty else { return }
            await MainActor.run {
                dropNotifications.publish(results: results)
            }
        }
        let repository = MasterDataRepository(manager: masterDataManager)
        let runtimeService = GameRuntimeService(masterData: masterDataCache, repository: repository, dropNotifier: dropNotifier)
        self.runtime = ProgressRuntimeService(runtimeService: runtimeService,
                                              gameStateService: gameStateService)

        self.party = PartyProgressService(container: container)
        self.inventory = InventoryProgressService(container: container,
                                                  gameStateService: gameStateService,
                                                  masterDataCache: masterDataCache)
        self.shop = ShopProgressService(container: container,
                                        masterDataCache: masterDataCache,
                                        inventoryService: self.inventory,
                                        gameStateService: gameStateService)
        self.character = CharacterProgressService(container: container, masterData: masterDataCache)
        self.exploration = ExplorationProgressService(container: container, masterDataCache: masterDataCache)
        self.dungeon = DungeonProgressService(container: container)
        self.story = StoryProgressService(container: container)
        self.titleInheritance = TitleInheritanceProgressService(inventoryService: self.inventory,
                                                                  masterDataCache: masterDataCache)
        self.artifactExchange = ArtifactExchangeProgressService(inventoryService: self.inventory,
                                                                  masterDataCache: masterDataCache)
        self.itemSynthesis = ItemSynthesisProgressService(inventoryService: self.inventory,
                                                          gameStateService: gameStateService,
                                                          masterDataCache: masterDataCache)
        self.autoTrade = AutoTradeProgressService(container: container, gameStateService: gameStateService)
        self.itemPreload = ItemPreloadService(masterDataCache: masterDataCache)
        self.gemModification = GemModificationProgressService(container: container,
                                                               masterDataCache: masterDataCache)
    }
}

// MARK: - SwiftUI Environment

private struct AppServicesKey: EnvironmentKey {
    @MainActor static var defaultValue: AppServices {
        fatalError("AppServices not provided in environment. Ensure .environment(\\.appServices, services) is set in EpikaApp.")
    }
}

extension EnvironmentValues {
    var appServices: AppServices {
        get { self[AppServicesKey.self] }
        set { self[AppServicesKey.self] = newValue }
    }
}

extension Notification.Name {
    static let progressUnlocksDidChange = Notification.Name("ProgressUnlocksDidChange")
    static let characterProgressDidChange = Notification.Name("CharacterProgressDidChange")
}
