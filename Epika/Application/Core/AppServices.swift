// ==============================================================================
// AppServices.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 全サービスへのアクセスを提供するファサード
//   - サービス間の依存関係を管理・注入
//   - @Observable によるUI更新トリガー
//
// 【保持するサービス】
//   - gameState: ゴールド・ゲーム状態管理
//   - character: キャラクターCRUD・装備・転職
//   - party: パーティ編成
//   - inventory: インベントリ管理
//   - shop: 商店機能
//   - exploration: 探索進行永続化
//   - dungeon: ダンジョン進行状態
//   - story: ストーリー進行
//   - titleInheritance: 称号継承
//   - artifactExchange: 遺物交換
//   - itemSynthesis: アイテム合成
//   - autoTrade: 自動売却
//   - runtime: ゲームランタイムへのブリッジ
//   - dropNotifications: ドロップ通知
//   - statChangeNotifications: ステータス変動通知
//   - userDataLoad: ユーザーデータ一括ロード＆キャッシュ
//   - gemModification: 宝石改造
//
// 【補助型】
//   - ExplorationRunTotals: 探索累計（経験値/ゴールド/ドロップ）
//   - ExplorationRunUpdate: 探索更新イベント
//   - ExplorationRunHandle: 探索セッションハンドル
//
// 【通知】
//   - .progressUnlocksDidChange: 解放状態変更通知
//   - .characterProgressDidChange: キャラクター変更通知
//
// ==============================================================================

import Foundation
import SwiftData
import Observation

@Observable
final class AppServices: Sendable {
    let container: ModelContainer
    let contextProvider: SwiftDataContextProvider
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
    let statChangeNotifications: StatChangeNotificationService
    let userDataLoad: UserDataLoadService
    let gemModification: GemModificationProgressService

    struct ExplorationRunTotals: Sendable {
        let totalExperience: Int
        let totalGold: Int
        let drops: [ExplorationDropReward]
    }

    struct ExplorationRunUpdate: Sendable {
        enum Stage: Sendable {
            case step(entry: ExplorationEventLogEntry, totals: ExplorationRunTotals, battleLogId: PersistentIdentifier?)
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

    @MainActor
    init(container: ModelContainer, masterDataCache: MasterDataCache) {
        self.container = container
        let contextProvider = SwiftDataContextProvider(container: container)
        self.contextProvider = contextProvider
        self.masterDataCache = masterDataCache
        let gameStateService = GameStateService(contextProvider: contextProvider)
        self.gameState = gameStateService
        let dropNotifications = ItemDropNotificationService(masterDataCache: masterDataCache)
        self.dropNotifications = dropNotifications
        self.statChangeNotifications = StatChangeNotificationService()
        let autoTradeService = AutoTradeProgressService(contextProvider: contextProvider, gameStateService: gameStateService)
        self.autoTrade = autoTradeService
        let dropNotifier: @Sendable ([ItemDropResult]) async -> Void = { [weak dropNotifications, autoTradeService] results in
            guard let dropNotifications, !results.isEmpty else { return }
            let filteredResults: [ItemDropResult]
            do {
                let autoTradeKeys = try await autoTradeService.registeredStackKeys()
                if autoTradeKeys.isEmpty {
                    filteredResults = results
                } else {
                    filteredResults = results.filter { !autoTradeKeys.contains($0.autoTradeStackKey) }
                }
            } catch {
                #if DEBUG
                print("[AppServices] Failed to load auto-trade keys for drop notifications: \(error)")
                #endif
                filteredResults = results
            }
            guard !filteredResults.isEmpty else { return }
            await MainActor.run {
                dropNotifications.publish(results: filteredResults)
            }
        }
        let runtimeService = GameRuntimeService(masterData: masterDataCache, dropNotifier: dropNotifier)
        self.runtime = ProgressRuntimeService(runtimeService: runtimeService,
                                              gameStateService: gameStateService)

        self.party = PartyProgressService(contextProvider: contextProvider)
        self.inventory = InventoryProgressService(contextProvider: contextProvider,
                                                  gameStateService: gameStateService)
        self.shop = ShopProgressService(contextProvider: contextProvider,
                                        masterDataCache: masterDataCache,
                                        inventoryService: self.inventory,
                                        gameStateService: gameStateService)
        self.character = CharacterProgressService(contextProvider: contextProvider, masterData: masterDataCache)
        self.exploration = ExplorationProgressService(contextProvider: contextProvider, masterDataCache: masterDataCache)
        self.dungeon = DungeonProgressService(contextProvider: contextProvider)
        self.story = StoryProgressService(contextProvider: contextProvider)
        self.titleInheritance = TitleInheritanceProgressService(inventoryService: self.inventory)
        self.artifactExchange = ArtifactExchangeProgressService(inventoryService: self.inventory)
        self.itemSynthesis = ItemSynthesisProgressService(inventoryService: self.inventory,
                                                          gameStateService: gameStateService)
        self.userDataLoad = UserDataLoadService(
            contextProvider: contextProvider,
            masterDataCache: masterDataCache,
            characterService: self.character,
            partyService: self.party,
            inventoryService: self.inventory,
            explorationService: self.exploration,
            gameStateService: gameStateService,
            autoTradeService: autoTradeService
        )
        self.gemModification = GemModificationProgressService(contextProvider: contextProvider,
                                                               masterDataCache: masterDataCache,
                                                               inventoryService: self.inventory)
        // 全プロパティ初期化後にAppServicesを設定
        self.userDataLoad.setAppServices(self)
    }
}

extension Notification.Name {
    static let progressUnlocksDidChange = Notification.Name("ProgressUnlocksDidChange")
    static let characterProgressDidChange = Notification.Name("CharacterProgressDidChange")
    static let partyProgressDidChange = Notification.Name("PartyProgressDidChange")
    static let inventoryDidChange = Notification.Name("InventoryDidChange")
    static let gameStateDidChange = Notification.Name("GameStateDidChange")
    static let autoTradeRulesDidChange = Notification.Name("AutoTradeRulesDidChange")
    static let shopStockDidChange = Notification.Name("ShopStockDidChange")
    static let dungeonProgressDidChange = Notification.Name("DungeonProgressDidChange")
    static let storyProgressDidChange = Notification.Name("StoryProgressDidChange")
}
