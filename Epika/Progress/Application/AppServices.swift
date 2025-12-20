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
//   - itemPreload: アイテム表示用キャッシュ
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

    init(container: ModelContainer, masterDataCache: MasterDataCache) {
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
        let runtimeService = GameRuntimeService(masterData: masterDataCache, dropNotifier: dropNotifier)
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

extension Notification.Name {
    static let progressUnlocksDidChange = Notification.Name("ProgressUnlocksDidChange")
    static let characterProgressDidChange = Notification.Name("CharacterProgressDidChange")
}
