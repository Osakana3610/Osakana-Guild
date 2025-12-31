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

@MainActor
@Observable
final class AppServices {
    let container: ModelContainer
    let masterDataCache: MasterDataCache
    let gameState: GameStateService

    // MARK: - Observable Player State
    var playerGold: UInt32 = 0
    var playerCatTickets: UInt16 = 0
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
    private var explorationPersistenceSessions: [PersistentIdentifier: ExplorationProgressService.EventSession] = [:]

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

    init(container: ModelContainer, masterDataCache: MasterDataCache) {
        self.container = container
        self.masterDataCache = masterDataCache
        let contextProvider = SwiftDataContextProvider(container: container)
        let gameStateService = GameStateService(contextProvider: contextProvider)
        self.gameState = gameStateService
        let dropNotifications = ItemDropNotificationService(masterDataCache: masterDataCache)
        self.dropNotifications = dropNotifications
        self.statChangeNotifications = StatChangeNotificationService()
        let autoTradeService = AutoTradeProgressService(container: container, gameStateService: gameStateService)
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

        self.party = PartyProgressService(container: container)
        self.inventory = InventoryProgressService(contextProvider: contextProvider,
                                                  gameStateService: gameStateService,
                                                  masterDataCache: masterDataCache)
        self.shop = ShopProgressService(container: container,
                                        masterDataCache: masterDataCache,
                                        inventoryService: self.inventory,
                                        gameStateService: gameStateService)
        self.character = CharacterProgressService(contextProvider: contextProvider, masterData: masterDataCache)
        self.exploration = ExplorationProgressService(contextProvider: contextProvider, masterDataCache: masterDataCache)
        self.dungeon = DungeonProgressService(container: container)
        self.story = StoryProgressService(container: container)
        self.titleInheritance = TitleInheritanceProgressService(inventoryService: self.inventory,
                                                                  masterDataCache: masterDataCache)
        self.artifactExchange = ArtifactExchangeProgressService(inventoryService: self.inventory,
                                                                  masterDataCache: masterDataCache)
        self.itemSynthesis = ItemSynthesisProgressService(inventoryService: self.inventory,
                                                          gameStateService: gameStateService,
                                                          masterDataCache: masterDataCache)
        self.userDataLoad = UserDataLoadService(
            masterDataCache: masterDataCache,
            characterService: self.character,
            partyService: self.party,
            inventoryService: self.inventory,
            explorationService: self.exploration
        )
        self.gemModification = GemModificationProgressService(container: container,
                                                               masterDataCache: masterDataCache,
                                                               userDataLoad: self.userDataLoad)
        // 全プロパティ初期化後にAppServicesを設定
        self.userDataLoad.setAppServices(self)
    }

    // MARK: - Player State Updates

    /// PlayerSnapshotからObservable状態を更新
    func applyPlayerSnapshot(_ snapshot: PlayerSnapshot) {
        playerGold = snapshot.gold
        playerCatTickets = snapshot.catTickets
    }

    /// 現在のプレイヤー状態をロードしてObservable状態を更新
    func reloadPlayerState() async {
        do {
            let snapshot = try await gameState.currentPlayer()
            applyPlayerSnapshot(snapshot)
        } catch {
            // プレイヤーが存在しない場合は初期値のまま
        }
    }

    func flushExplorationSessions() {
        for session in explorationPersistenceSessions.values {
            do {
                try session.flushIfNeeded()
            } catch {
                #if DEBUG
                print("[AppServices] flushExplorationSessions failed: \(error)")
                #endif
            }
        }
    }

    func explorationSession(for runId: PersistentIdentifier) throws -> ExplorationProgressService.EventSession {
        if let existing = explorationPersistenceSessions[runId] {
            return existing
        }
        let session = try exploration.makeEventSession(runId: runId)
        explorationPersistenceSessions[runId] = session
        return session
    }

    func removeExplorationSession(runId: PersistentIdentifier) {
        explorationPersistenceSessions.removeValue(forKey: runId)
    }
}

extension Notification.Name {
    static let progressUnlocksDidChange = Notification.Name("ProgressUnlocksDidChange")
    static let characterProgressDidChange = Notification.Name("CharacterProgressDidChange")
}
