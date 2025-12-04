import Foundation
import SwiftData

/// 宝石改造サービス
/// 宝石を装備アイテムにソケットとして装着する機能を提供
actor GemModificationProgressService {
    private let container: ModelContainer
    private let masterDataService: MasterDataRuntimeService

    /// ソケット装着不可カテゴリ
    private static let nonSocketableCategories: Set<String> = ["mazo_material", "for_synthesis"]

    init(container: ModelContainer, masterDataService: MasterDataRuntimeService) {
        self.container = container
        self.masterDataService = masterDataService
    }

    // MARK: - Public API

    /// 宝石一覧を取得
    func getGems() async throws -> [ItemSnapshot] {
        let context = makeContext()
        let storage = ItemStorage.playerItem
        var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.storageRawValue == storage.rawValue
        })
        descriptor.sortBy = [
            SortDescriptor(\InventoryItemRecord.superRareTitleIndex, order: .forward),
            SortDescriptor(\InventoryItemRecord.normalTitleIndex, order: .forward),
            SortDescriptor(\InventoryItemRecord.masterDataIndex, order: .forward)
        ]
        let records = try context.fetch(descriptor)
        guard !records.isEmpty else { return [] }

        let masterIndices = Array(Set(records.map { $0.masterDataIndex }))
        let definitions = try await masterDataService.getItemMasterData(byIndices: masterIndices)
        let gemIndices = Set(definitions.filter { $0.category.lowercased().contains("gem") }.map { $0.index })

        return records
            .filter { gemIndices.contains($0.masterDataIndex) }
            .map(makeSnapshot(_:))
    }

    /// 指定した宝石をソケットとして装着可能なアイテム一覧を取得
    func getSocketableItems(for _: String) async throws -> [ItemSnapshot] {
        let context = makeContext()
        let storage = ItemStorage.playerItem
        var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.storageRawValue == storage.rawValue && $0.socketMasterDataIndex == 0
        })
        descriptor.sortBy = [
            SortDescriptor(\InventoryItemRecord.superRareTitleIndex, order: .forward),
            SortDescriptor(\InventoryItemRecord.normalTitleIndex, order: .forward),
            SortDescriptor(\InventoryItemRecord.masterDataIndex, order: .forward)
        ]
        let records = try context.fetch(descriptor)
        guard !records.isEmpty else { return [] }

        let masterIndices = Array(Set(records.map { $0.masterDataIndex }))
        let definitions = try await masterDataService.getItemMasterData(byIndices: masterIndices)

        // 宝石・合成用アイテムを除外
        let socketableIndices = Set(definitions
            .filter { !$0.category.lowercased().contains("gem") }
            .filter { !Self.nonSocketableCategories.contains($0.category) }
            .map { $0.index })

        return records
            .filter { socketableIndices.contains($0.masterDataIndex) }
            .map(makeSnapshot(_:))
    }

    /// 宝石を装備アイテムに装着
    func attachGem(gemItemStackKey: String, targetItemStackKey: String) async throws {
        let context = makeContext()

        // 宝石レコードの取得
        var gemDescriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate { $0.stackKey == gemItemStackKey })
        gemDescriptor.fetchLimit = 1
        guard let gemRecord = try context.fetch(gemDescriptor).first else {
            throw ProgressError.invalidInput(description: "宝石が見つかりません")
        }

        // 対象アイテムレコードの取得
        var targetDescriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate { $0.stackKey == targetItemStackKey })
        targetDescriptor.fetchLimit = 1
        guard let targetRecord = try context.fetch(targetDescriptor).first else {
            throw ProgressError.invalidInput(description: "対象アイテムが見つかりません")
        }

        // 対象アイテムに既に宝石改造が施されていないか確認
        guard targetRecord.socketMasterDataIndex == 0 else {
            throw ProgressError.invalidInput(description: "このアイテムには既に宝石改造が施されています")
        }

        // 宝石のカテゴリ確認
        let gemDefinitions = try await masterDataService.getItemMasterData(byIndices: [gemRecord.masterDataIndex])
        guard let gemDefinition = gemDefinitions.first,
              gemDefinition.category.lowercased().contains("gem") else {
            throw ProgressError.invalidInput(description: "選択したアイテムは宝石ではありません")
        }

        // 対象アイテムがソケット装着可能か確認
        let targetDefinitions = try await masterDataService.getItemMasterData(byIndices: [targetRecord.masterDataIndex])
        guard let targetDefinition = targetDefinitions.first else {
            throw ProgressError.invalidInput(description: "対象アイテムの定義が見つかりません")
        }
        if targetDefinition.category.lowercased().contains("gem") {
            throw ProgressError.invalidInput(description: "宝石に宝石改造を施すことはできません")
        }
        if Self.nonSocketableCategories.contains(targetDefinition.category) {
            throw ProgressError.invalidInput(description: "このカテゴリのアイテムには宝石改造を施すことができません")
        }

        // 宝石の称号情報を対象アイテムに転送
        targetRecord.socketMasterDataIndex = gemRecord.masterDataIndex
        targetRecord.socketSuperRareTitleIndex = gemRecord.superRareTitleIndex
        targetRecord.socketNormalTitleIndex = gemRecord.normalTitleIndex

        // 宝石をインベントリから削除（1個減算）
        if gemRecord.quantity <= 1 {
            context.delete(gemRecord)
        } else {
            gemRecord.quantity -= 1
        }

        // アトミックに保存
        try context.save()
    }

    // MARK: - Private Helpers

    private func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func makeSnapshot(_ record: InventoryItemRecord) -> ItemSnapshot {
        ItemSnapshot(
            persistentIdentifier: record.persistentModelID,
            stackKey: record.stackKey,
            masterDataIndex: record.masterDataIndex,
            quantity: record.quantity,
            storage: record.storage,
            enhancements: .init(
                superRareTitleIndex: record.superRareTitleIndex,
                normalTitleIndex: record.normalTitleIndex,
                socketSuperRareTitleIndex: record.socketSuperRareTitleIndex,
                socketNormalTitleIndex: record.socketNormalTitleIndex,
                socketMasterDataIndex: record.socketMasterDataIndex
            )
        )
    }
}
