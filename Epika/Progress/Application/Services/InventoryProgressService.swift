import Foundation
import SwiftData

actor InventoryProgressService {
    private let container: ModelContainer
    private let playerService: PlayerProgressService
    private let environment: ProgressEnvironment
    private let maxStackSize = 99

    struct BatchSeed: Sendable {
        let itemId: String
        let quantity: Int
        let storage: ItemStorage
        let enhancements: ItemSnapshot.Enhancement
        let acquiredAt: Date

        init(itemId: String,
             quantity: Int,
             storage: ItemStorage,
             enhancements: ItemSnapshot.Enhancement,
             acquiredAt: Date = Date()) {
            self.itemId = itemId
            self.quantity = quantity
            self.storage = storage
            self.enhancements = enhancements
            self.acquiredAt = acquiredAt
        }
    }

    init(container: ModelContainer,
         playerService: PlayerProgressService,
         environment: ProgressEnvironment) {
        self.container = container
        self.playerService = playerService
        self.environment = environment
    }

    // MARK: - Public API

    func allItems(storage: ItemStorage) async throws -> [ItemSnapshot] {
        let context = makeContext()
        let descriptor = fetchDescriptor(for: storage)
        let records = try context.fetch(descriptor)
        return records.map(makeSnapshot(_:))
    }

    func allEquipment(storage: ItemStorage) async throws -> [RuntimeEquipment] {
        let snapshots = try await allItems(storage: storage)
        if snapshots.isEmpty { return [] }

        let masterIds = Array(Set(snapshots.map { $0.itemId }))
        let definitions = try await environment.masterDataService.getItemMasterData(ids: masterIds)
        let definitionMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        let missing = masterIds.filter { definitionMap[$0] == nil }
        if !missing.isEmpty {
            throw ProgressError.itemDefinitionUnavailable(ids: missing.sorted())
        }

        return snapshots.compactMap { snapshot in
            guard let definition = definitionMap[snapshot.itemId] else {
                return nil
            }
            return RuntimeEquipment(id: snapshot.id,
                                    masterDataId: definition.id,
                                    displayName: definition.name,
                                    description: definition.description,
                                    quantity: snapshot.quantity,
                                    category: RuntimeEquipment.Category(from: definition.category),
                                    baseValue: definition.basePrice,
                                    sellValue: definition.sellValue,
                                    enhancement: snapshot.enhancements,
                                    rarity: definition.rarity,
                                    statBonuses: definition.statBonuses,
                                    combatBonuses: definition.combatBonuses,
                                    acquiredAt: snapshot.acquiredAt)
        }
        .sorted { $0.acquiredAt < $1.acquiredAt }
    }

    func addItem(itemId: String,
                 quantity: Int,
                 storage: ItemStorage,
                 enhancements: ItemSnapshot.Enhancement = .init(superRareTitleId: nil,
                                                                normalTitleId: nil,
                                                                socketSuperRareTitleId: nil,
                                                                socketNormalTitleId: nil,
                                                                socketKey: nil)) async throws -> ItemSnapshot {
        guard quantity > 0 else {
            throw ProgressError.invalidInput(description: "追加数量は1以上である必要があります")
        }

        let context = makeContext()
        let key = compositeKey(for: itemId, enhancements: enhancements)
        let record = try fetchOrCreateRecord(with: key,
                                             itemId: itemId,
                                             storage: storage,
                                             enhancements: enhancements,
                                             context: context,
                                             acquiredAt: Date())
        _ = applyIncrement(to: record, amount: quantity)
        try context.save()
        return makeSnapshot(record)
    }

    func addItems(_ seeds: [BatchSeed], chunkSize: Int = 1_000) async throws {
        guard !seeds.isEmpty else { return }
        guard chunkSize > 0 else {
            throw ProgressError.invalidInput(description: "チャンクサイズは1以上である必要があります")
        }
        for seed in seeds {
            guard seed.quantity > 0 else {
                throw ProgressError.invalidInput(description: "追加数量は1以上である必要があります")
            }
            guard seed.storage != .unknown else {
                throw ProgressError.invalidInput(description: "アイテムの保管場所が不正です")
            }
        }

        var index = 0
        var chunkNumber = 0
        while index < seeds.count {
            try Task.checkCancellation()
            let end = min(index + chunkSize, seeds.count)
            let chunk = Array(seeds[index..<end])
            chunkNumber += 1
            let localIndex = chunkNumber
            let context = makeContext()
            let aggregated = try aggregate(chunk)
            for (storage, entries) in aggregated {
                try Task.checkCancellation()
                let keys = entries.map { $0.key.compositeKey }
                var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
                    keys.contains($0.compositeKey) && $0.storageRawValue == storage.rawValue
                })
                descriptor.fetchLimit = keys.count
                let existingRecords = try context.fetch(descriptor)
                let recordMap = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.compositeKey, $0) })

                for entry in entries {
                    if let record = recordMap[entry.key.compositeKey] {
                        _ = applyIncrement(to: record, amount: entry.totalQuantity)
                    } else {
                        let newRecord = InventoryItemRecord(compositeKey: entry.key.compositeKey,
                                                            masterDataId: entry.seed.itemId,
                                                            quantity: 0,
                                                            storage: storage,
                                                            superRareTitleId: entry.seed.enhancements.superRareTitleId,
                                                            normalTitleId: entry.seed.enhancements.normalTitleId,
                                                            socketSuperRareTitleId: entry.seed.enhancements.socketSuperRareTitleId,
                                                            socketNormalTitleId: entry.seed.enhancements.socketNormalTitleId,
                                                            socketKey: entry.seed.enhancements.socketKey,
                                                            acquiredAt: entry.seed.acquiredAt)
                        _ = applyIncrement(to: newRecord, amount: entry.totalQuantity)
                        context.insert(newRecord)
                    }
                }
            }
#if DEBUG
            print("[Inventory] inserted chunk #\(localIndex) size=\(chunk.count)")
#endif
            try context.save()
            index = end
        }
    }

    private struct SeedKey: Hashable {
        let compositeKey: String
        let storageRaw: String
    }

    private struct AggregatedEntry {
        let key: SeedKey
        let seed: BatchSeed
        var totalQuantity: Int
    }

    private func aggregate(_ seeds: [BatchSeed]) throws -> [ItemStorage: [AggregatedEntry]] {
        var grouped: [SeedKey: AggregatedEntry] = [:]
        grouped.reserveCapacity(seeds.count)
        for seed in seeds {
            let key = SeedKey(compositeKey: compositeKey(for: seed.itemId, enhancements: seed.enhancements),
                              storageRaw: seed.storage.rawValue)
            if var existing = grouped[key] {
                let (sum, overflow) = existing.totalQuantity.addingReportingOverflow(seed.quantity)
                existing.totalQuantity = overflow ? Int.max : sum
                grouped[key] = existing
            } else {
                grouped[key] = AggregatedEntry(key: key, seed: seed, totalQuantity: seed.quantity)
            }
        }
        var result: [ItemStorage: [AggregatedEntry]] = [:]
        result.reserveCapacity(grouped.count)
        for entry in grouped.values {
            guard let storage = ItemStorage(rawValue: entry.key.storageRaw) else {
                throw ProgressError.invalidInput(description: "未知の保管場所が指定されました: \(entry.key.storageRaw)")
            }
            result[storage, default: []].append(entry)
        }
        return result
    }

    func sellItems(itemIds: [UUID]) async throws -> PlayerSnapshot {
        guard !itemIds.isEmpty else {
            return try await playerService.currentPlayer()
        }

        let context = makeContext()
        let descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate { itemIds.contains($0.id) })
        let records = try context.fetch(descriptor)
        guard !records.isEmpty else {
            return try await playerService.currentPlayer()
        }
        let masterIds = Set(records.map { $0.masterDataId })
        let definitions = try await environment.masterDataService.getItemMasterData(ids: Array(masterIds))
        let priceMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0.sellValue) })
        let missing = masterIds.filter { priceMap[$0] == nil }
        if !missing.isEmpty {
            throw ProgressError.itemDefinitionUnavailable(ids: missing.sorted())
        }
        let totalGain = records.reduce(into: 0) { total, record in
            guard record.quantity > 0, let value = priceMap[record.masterDataId] else { return }
            total += value * record.quantity
        }
        for record in records {
            context.delete(record)
        }
        try context.save()

        guard totalGain > 0 else {
            return try await playerService.currentPlayer()
        }

        return try await playerService.addGold(totalGain)
    }

    func updateItem(id: UUID,
                    mutate: (InventoryItemRecord) throws -> Void) async throws -> ItemSnapshot {
        let context = makeContext()
        let descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else {
            throw ProgressError.invalidInput(description: "指定したアイテムが見つかりません")
        }
        try mutate(record)
        updateCompositeKey(for: record)
        try context.save()
        return makeSnapshot(record)
    }

    func decrementItem(id: UUID, quantity: Int) async throws {
        guard quantity > 0 else { return }
        let context = makeContext()
        let descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else {
            throw ProgressError.invalidInput(description: "指定したアイテムが見つかりません")
        }
        guard record.quantity >= quantity else {
            throw ProgressError.invalidInput(description: "アイテム数量が不足しています")
        }
        record.quantity -= quantity
        if record.quantity <= 0 {
            context.delete(record)
        }
        try context.save()
    }

    func inheritItem(targetId: UUID,
                     sourceId: UUID,
                     newEnhancement: ItemSnapshot.Enhancement) async throws -> RuntimeEquipment {
        let context = makeContext()

        let targetFetch = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate { $0.id == targetId })
        guard let targetRecord = try context.fetch(targetFetch).first else {
            throw ProgressError.invalidInput(description: "対象アイテムが見つかりません")
        }
        let sourceFetch = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate { $0.id == sourceId })
        guard let sourceRecord = try context.fetch(sourceFetch).first else {
            throw ProgressError.invalidInput(description: "提供アイテムが見つかりません")
        }
        guard targetRecord.storage == .playerItem else {
            throw ProgressError.invalidInput(description: "対象アイテムは所持品から選択してください")
        }
        guard sourceRecord.storage == .playerItem else {
            throw ProgressError.invalidInput(description: "提供アイテムは所持品から選択してください")
        }

        targetRecord.superRareTitleId = newEnhancement.superRareTitleId
        targetRecord.normalTitleId = newEnhancement.normalTitleId
        targetRecord.socketSuperRareTitleId = newEnhancement.socketSuperRareTitleId
        targetRecord.socketNormalTitleId = newEnhancement.socketNormalTitleId
        targetRecord.socketKey = newEnhancement.socketKey
        targetRecord.acquiredAt = Date()
        updateCompositeKey(for: targetRecord)

        if sourceRecord.quantity <= 1 {
            context.delete(sourceRecord)
        } else {
            sourceRecord.quantity -= 1
        }

        try context.save()

        let definitions = try await environment.masterDataService.getItemMasterData(ids: [targetRecord.masterDataId])
        guard let definition = definitions.first else {
            throw ProgressError.itemDefinitionUnavailable(ids: [targetRecord.masterDataId])
        }
        let snapshot = makeSnapshot(targetRecord)
        return RuntimeEquipment(id: snapshot.id,
                                masterDataId: definition.id,
                                displayName: definition.name,
                                description: definition.description,
                                quantity: snapshot.quantity,
                                category: RuntimeEquipment.Category(from: definition.category),
                                baseValue: definition.basePrice,
                                sellValue: definition.sellValue,
                                enhancement: snapshot.enhancements,
                                rarity: definition.rarity,
                                statBonuses: definition.statBonuses,
                                combatBonuses: definition.combatBonuses,
                                acquiredAt: snapshot.acquiredAt)
    }

    // MARK: - Private Helpers

    private func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func fetchDescriptor(for storage: ItemStorage) -> FetchDescriptor<InventoryItemRecord> {
        var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate { $0.storageRawValue == storage.rawValue })
        descriptor.sortBy = [SortDescriptor(\InventoryItemRecord.acquiredAt, order: .forward),
                             SortDescriptor(\InventoryItemRecord.compositeKey, order: .forward)]
        return descriptor
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

    private func fetchOrCreateRecord(with compositeKey: String,
                                     itemId: String,
                                     storage: ItemStorage,
                                     enhancements: ItemSnapshot.Enhancement,
                                     context: ModelContext,
                                     acquiredAt: Date) throws -> InventoryItemRecord {
        var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate { $0.compositeKey == compositeKey && $0.storageRawValue == storage.rawValue })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            if existing.storage != storage {
                existing.storage = storage
            }
            return existing
        }
        let record = InventoryItemRecord(compositeKey: compositeKey,
                                         masterDataId: itemId,
                                         quantity: 0,
                                         storage: storage,
                                         superRareTitleId: enhancements.superRareTitleId,
                                         normalTitleId: enhancements.normalTitleId,
                                         socketSuperRareTitleId: enhancements.socketSuperRareTitleId,
                                         socketNormalTitleId: enhancements.socketNormalTitleId,
                                         socketKey: enhancements.socketKey,
                                         acquiredAt: acquiredAt)
        updateCompositeKey(for: record)
        context.insert(record)
        return record
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

    @discardableResult
    private func applyIncrement(to record: InventoryItemRecord, amount: Int) -> Int {
        guard amount > 0 else { return 0 }

        let clampedCurrent = min(record.quantity, maxStackSize)
        record.quantity = clampedCurrent

        let capacity = max(0, maxStackSize - clampedCurrent)
        let addable = min(capacity, amount)
        record.quantity = clampedCurrent + addable

        return amount - addable
    }
}
