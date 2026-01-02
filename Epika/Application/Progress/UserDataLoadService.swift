// ==============================================================================
// UserDataLoadService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 起動時に全ユーザーデータを一括ロード
//   - キャラクター・パーティ・アイテム・探索サマリーのキャッシュ管理
//   - 孤立した探索の再開（データロード完了後に実行）
//   - キャッシュの差分更新・無効化
//
// 【UIからの参照】
//   - UI層はSwiftDataを直接参照せず、このサービスのキャッシュを使用すること
//   - characters, parties, categorizedItems 等を直接参照可能
//
// 【内部処理からの参照】
//   - 自動売却判定等、内部処理もキャッシュを参照すること
//   - 変更はProgress層に依頼
//
// 【ファイル構成】
//   - UserDataLoadService.swift: コア（Dependencies, Cache, State, Init, loadAll）
//   - UserDataLoadService+Character.swift: キャラクターキャッシュ
//   - UserDataLoadService+Party.swift: パーティキャッシュ
//   - UserDataLoadService+Inventory.swift: インベントリキャッシュ
//   - UserDataLoadService+Exploration.swift: 探索キャッシュ
//
// ==============================================================================

import Foundation
import Observation
import SwiftData
import SwiftUI

@Observable
final class UserDataLoadService: Sendable {
    // MARK: - Dependencies

    let contextProvider: SwiftDataContextProvider
    let masterDataCache: MasterDataCache
    let characterService: CharacterProgressService
    let partyService: PartyProgressService
    let inventoryService: InventoryProgressService
    let explorationService: ExplorationProgressService
    let gameStateService: GameStateService
    let autoTradeService: AutoTradeProgressService
    @MainActor weak var appServices: AppServices?

    // MARK: - Cache（UIから観測されるため@MainActor）

    @MainActor var characters: [RuntimeCharacter] = []
    @MainActor var parties: [PartySnapshot] = []
    @MainActor var explorationSummaries: [ExplorationSnapshot] = []

    // アイテムキャッシュ（軽量な値型）
    @MainActor var categorizedItems: [ItemSaleCategory: [CachedInventoryItem]] = [:]
    @MainActor var subcategorizedItems: [ItemDisplaySubcategory: [CachedInventoryItem]] = [:]
    @MainActor var stackKeyIndex: [String: ItemSaleCategory] = [:]  // O(1)検索用
    @MainActor var orderedCategories: [ItemSaleCategory] = []
    @MainActor var orderedSubcategories: [ItemDisplaySubcategory] = []
    @MainActor var itemCacheVersion: Int = 0

    // ゲーム状態キャッシュ
    @MainActor var playerGold: UInt32 = 0
    @MainActor var playerCatTickets: UInt16 = 0
    @MainActor var playerPartySlots: UInt8 = 0
    @MainActor var pandoraBoxItems: [UInt64] = []

    // 自動売却ルールキャッシュ
    @MainActor var autoTradeStackKeys: Set<String> = []

    // 商店在庫キャッシュ
    @MainActor var shopItems: [ShopProgressService.ShopItem] = []

    // ダンジョン進行キャッシュ
    @MainActor var dungeonSnapshots: [DungeonSnapshot] = []

    // ストーリー進行キャッシュ
    @MainActor var storySnapshot: StorySnapshot = StorySnapshot(
        unlockedNodeIds: [],
        readNodeIds: [],
        rewardedNodeIds: [],
        updatedAt: Date()
    )

    // MARK: - State

    @MainActor private(set) var isLoaded = false
    @MainActor var isCharactersLoaded = false
    @MainActor var isPartiesLoaded = false
    @MainActor var isItemsLoaded = false
    @MainActor var isExplorationSummariesLoaded = false
    @MainActor var isShopItemsLoaded = false
    @MainActor var isDungeonSnapshotsLoaded = false
    @MainActor var isStorySnapshotLoaded = false

    @MainActor private var loadTask: Task<Void, Error>?

    // MARK: - Exploration Resume State

    @MainActor var activeExplorationHandles: [UInt8: AppServices.ExplorationRunHandle] = [:]
    @MainActor var activeExplorationTasks: [UInt8: Task<Void, Never>] = [:]

    // MARK: - Init

    @MainActor
    init(
        contextProvider: SwiftDataContextProvider,
        masterDataCache: MasterDataCache,
        characterService: CharacterProgressService,
        partyService: PartyProgressService,
        inventoryService: InventoryProgressService,
        explorationService: ExplorationProgressService,
        gameStateService: GameStateService,
        autoTradeService: AutoTradeProgressService
    ) {
        self.contextProvider = contextProvider
        self.masterDataCache = masterDataCache
        self.characterService = characterService
        self.partyService = partyService
        self.inventoryService = inventoryService
        self.explorationService = explorationService
        self.gameStateService = gameStateService
        self.autoTradeService = autoTradeService
        subscribeInventoryChanges()
        subscribeCharacterChanges()
        subscribePartyChanges()
        subscribeGameStateChanges()
        subscribeAutoTradeChanges()
    }

    /// AppServicesへの参照を設定（探索再開に必要）
    @MainActor
    func setAppServices(_ appServices: AppServices) {
        self.appServices = appServices
        subscribeShopStockChanges()
        subscribeDungeonChanges()
        subscribeStoryChanges()
    }

    // MARK: - Load All

    /// 全データロード（起動時に1回呼ぶ）
    /// - 探索再開もここで実行（データロード完了後に実行されることを保証）
    @MainActor
    func loadAll() async throws {
        // 既に完了済み or 進行中なら待機
        if let task = loadTask {
            try await task.value
            return
        }

        loadTask = Task {
            do {
                // 1. データロード（並列実行可能なもの）
                async let charactersTask: () = loadCharacters()
                async let partiesTask: () = loadParties()
                async let explorationTask: () = loadExplorationSummaries()
                async let gameStateTask: () = loadGameState()
                async let autoTradeTask: () = loadAutoTradeRules()

                try await charactersTask
                try await partiesTask
                try await explorationTask
                try await gameStateTask
                try await autoTradeTask

                // アイテムロードはMainActorで実行
                try await MainActor.run { try self.loadItems() }

                // 商店在庫ロード（appServicesが必要）
                try await loadShopItems()

                // ダンジョン進行ロード（appServicesが必要）
                try await loadDungeonSnapshots()

                // ストーリー進行ロード（appServicesが必要）
                try await loadStorySnapshot()

                // 2. 探索再開（データロード完了後に実行）
                await resumeOrphanedExplorations()

                // 3. 全成功後にフラグ設定
                await MainActor.run { self.isLoaded = true }
            } catch {
                // 失敗時はloadTaskをクリアしてリトライ可能に
                await MainActor.run { self.loadTask = nil }
                throw error
            }
        }
        try await loadTask!.value
    }
}

// MARK: - Error Types

enum UserDataLoadError: Error, LocalizedError {
    case itemNotFoundInCache(stackKey: String)

    var errorDescription: String? {
        switch self {
        case .itemNotFoundInCache(let stackKey):
            return "アイテムがキャッシュに見つかりません: \(stackKey)"
        }
    }
}
