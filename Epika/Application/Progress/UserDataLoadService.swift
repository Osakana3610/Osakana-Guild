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
//   - characters, parties, subcategorizedItems 等を直接参照可能
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
//   - UserDataLoadService+GameState.swift: ゲーム状態キャッシュ（ゴールド、猫チケット等）
//   - UserDataLoadService+AutoTrade.swift: 自動売却ルールキャッシュ
//   - UserDataLoadService+Shop.swift: 商店在庫キャッシュ
//   - UserDataLoadService+Dungeon.swift: ダンジョン進行キャッシュ
//   - UserDataLoadService+Story.swift: ストーリー進行キャッシュ
//
// ==============================================================================

import Foundation
import Observation
import SwiftUI

@Observable
final class UserDataLoadService: Sendable {
    // MARK: - Dependencies

    let masterDataCache: MasterDataCache
    let characterService: CharacterProgressService
    let partyService: PartyProgressService
    let inventoryService: InventoryProgressService
    let explorationService: ExplorationProgressService
    let gameStateService: GameStateService
    let autoTradeService: AutoTradeProgressService
    @MainActor weak var appServices: AppServices?

    // MARK: - Cache（UIから観測されるため@MainActor）

    @MainActor var characters: [CachedCharacter] = []
    @MainActor var parties: [CachedParty] = []
    @MainActor var explorationSummaries: [CachedExploration] = []

    // アイテムキャッシュ（軽量な値型）
    @MainActor var subcategorizedItems: [ItemDisplaySubcategory: [CachedInventoryItem]] = [:]
    @MainActor var stackKeyIndex: [String: ItemDisplaySubcategory] = [:]  // O(1)検索用
    @MainActor var orderedSubcategories: [ItemDisplaySubcategory] = []
    @MainActor var itemCacheVersion: Int = 0

    // 装備中アイテムキャッシュ（キャラクターID → 装備中アイテム配列）
    @MainActor var equippedItemsByCharacter: [UInt8: [CachedInventoryItem]] = [:]

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
    @MainActor var dungeonSnapshots: [CachedDungeonProgress] = []

    // ストーリー進行キャッシュ
    @MainActor var storySnapshot: CachedStoryProgress = CachedStoryProgress(
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
        masterDataCache: MasterDataCache,
        characterService: CharacterProgressService,
        partyService: PartyProgressService,
        inventoryService: InventoryProgressService,
        explorationService: ExplorationProgressService,
        gameStateService: GameStateService,
        autoTradeService: AutoTradeProgressService
    ) {
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
                await AppLogCollector.shared.log(.system, action: "loadAll_start")

                // 1. データロード（直列実行: リリースビルドでのレースコンディション回避）
                try await loadCharacters()
                await AppLogCollector.shared.log(.system, action: "loadCharacters_done")

                try await loadParties()
                await AppLogCollector.shared.log(.system, action: "loadParties_done")

                try await loadExplorationSummaries()
                await AppLogCollector.shared.log(.system, action: "loadExplorationSummaries_done")

                try await loadGameState()
                await AppLogCollector.shared.log(.system, action: "loadGameState_done")

                try await loadAutoTradeRules()
                await AppLogCollector.shared.log(.system, action: "loadAutoTradeRules_done")

                // アイテムロードはMainActorでキャッシュ構築
                try await loadItems()
                await AppLogCollector.shared.log(.system, action: "loadItems_done")

                // 商店在庫ロード（appServicesが必要）
                try await loadShopItems()
                await AppLogCollector.shared.log(.system, action: "loadShopItems_done")

                // ダンジョン進行ロード（appServicesが必要）
                try await loadDungeonSnapshots()
                await AppLogCollector.shared.log(.system, action: "loadDungeonSnapshots_done")

                // 2. 探索再開（データロード完了後に実行）
                await resumeOrphanedExplorations()
                await AppLogCollector.shared.log(.system, action: "resumeOrphanedExplorations_done")

                // 3. 全成功後にフラグ設定
                await MainActor.run { self.isLoaded = true }
                await AppLogCollector.shared.log(.system, action: "loadAll_complete")
            } catch {
                await AppLogCollector.shared.logError(error.localizedDescription, location: "loadAll")
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
