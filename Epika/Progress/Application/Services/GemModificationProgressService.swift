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
        descriptor.sortBy = [SortDescriptor(\InventoryItemRecord.acquiredAt, order: .forward)]
        let records = try context.fetch(descriptor)
        guard !records.isEmpty else { return [] }

        let masterIds = Array(Set(records.map { $0.masterDataId }))
        let definitions = try await masterDataService.getItemMasterData(ids: masterIds)
        let gemIds = Set(definitions.filter { $0.category.lowercased().contains("gem") }.map { $0.id })

        return records
            .filter { gemIds.contains($0.masterDataId) }
            .map(makeSnapshot(_:))
    }

    /// 指定した宝石をソケットとして装着可能なアイテム一覧を取得
    func getSocketableItems(for _: UUID) async throws -> [ItemSnapshot] {
        let context = makeContext()
        let storage = ItemStorage.playerItem
        var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.storageRawValue == storage.rawValue && $0.socketKey == nil
        })
        descriptor.sortBy = [SortDescriptor(\InventoryItemRecord.acquiredAt, order: .forward)]
        let records = try context.fetch(descriptor)
        guard !records.isEmpty else { return [] }

        let masterIds = Array(Set(records.map { $0.masterDataId }))
        let definitions = try await masterDataService.getItemMasterData(ids: masterIds)

        // 宝石・合成用アイテムを除外
        let socketableIds = Set(definitions
            .filter { !$0.category.lowercased().contains("gem") }
            .filter { !Self.nonSocketableCategories.contains($0.category) }
            .map { $0.id })

        return records
            .filter { socketableIds.contains($0.masterDataId) }
            .map(makeSnapshot(_:))
    }

    /// 宝石を装備アイテムに装着
    func attachGem(gemItemId: UUID, targetItemId: UUID) async throws {
        let context = makeContext()

        // 宝石レコードの取得
        var gemDescriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate { $0.id == gemItemId })
        gemDescriptor.fetchLimit = 1
        guard let gemRecord = try context.fetch(gemDescriptor).first else {
            throw ProgressError.invalidInput(description: "宝石が見つかりません")
        }

        // 対象アイテムレコードの取得
        var targetDescriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate { $0.id == targetItemId })
        targetDescriptor.fetchLimit = 1
        guard let targetRecord = try context.fetch(targetDescriptor).first else {
            throw ProgressError.invalidInput(description: "対象アイテムが見つかりません")
        }

        // 対象アイテムに既にソケットが装着されていないか確認
        guard targetRecord.socketKey == nil else {
            throw ProgressError.invalidInput(description: "このアイテムには既に宝石が装着されています")
        }

        // 宝石のカテゴリ確認
        let gemDefinitions = try await masterDataService.getItemMasterData(ids: [gemRecord.masterDataId])
        guard let gemDefinition = gemDefinitions.first,
              gemDefinition.category.lowercased().contains("gem") else {
            throw ProgressError.invalidInput(description: "選択したアイテムは宝石ではありません")
        }

        // 対象アイテムがソケット装着可能か確認
        let targetDefinitions = try await masterDataService.getItemMasterData(ids: [targetRecord.masterDataId])
        guard let targetDefinition = targetDefinitions.first else {
            throw ProgressError.invalidInput(description: "対象アイテムの定義が見つかりません")
        }
        if targetDefinition.category.lowercased().contains("gem") {
            throw ProgressError.invalidInput(description: "宝石に宝石を装着することはできません")
        }
        if Self.nonSocketableCategories.contains(targetDefinition.category) {
            throw ProgressError.invalidInput(description: "このカテゴリのアイテムには宝石を装着できません")
        }

        // 宝石の称号情報を対象アイテムに転送
        targetRecord.socketKey = gemRecord.masterDataId
        targetRecord.socketSuperRareTitleId = gemRecord.superRareTitleId
        targetRecord.socketNormalTitleId = gemRecord.normalTitleId
        updateCompositeKey(for: targetRecord)

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
        ItemSnapshot(persistentIdentifier: record.persistentModelID,
                     id: record.id,
                     compositeKey: record.compositeKey,
                     itemId: record.masterDataId,
                     quantity: record.quantity,
                     storage: record.storage,
                     enhancements: .init(superRareTitleId: record.superRareTitleId,
                                         normalTitleId: record.normalTitleId,
                                         socketSuperRareTitleId: record.socketSuperRareTitleId,
                                         socketNormalTitleId: record.socketNormalTitleId,
                                         socketKey: record.socketKey),
                     acquiredAt: record.acquiredAt)
    }

    private func compositeKey(for itemId: String, enhancements: ItemSnapshot.Enhancement) -> String {
        let parts = [enhancements.superRareTitleId ?? "",
                     enhancements.normalTitleId ?? "",
                     itemId,
                     enhancements.socketSuperRareTitleId ?? "",
                     enhancements.socketNormalTitleId ?? "",
                     enhancements.socketKey ?? ""]
        return parts.joined(separator: "|")
    }

    private func updateCompositeKey(for record: InventoryItemRecord) {
        let enhancements = ItemSnapshot.Enhancement(superRareTitleId: record.superRareTitleId,
                                                    normalTitleId: record.normalTitleId,
                                                    socketSuperRareTitleId: record.socketSuperRareTitleId,
                                                    socketNormalTitleId: record.socketNormalTitleId,
                                                    socketKey: record.socketKey)
        record.compositeKey = compositeKey(for: record.masterDataId, enhancements: enhancements)
    }
}
