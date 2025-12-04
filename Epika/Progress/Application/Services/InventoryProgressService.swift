import Foundation
import SwiftData

actor InventoryProgressService {
    private let container: ModelContainer
    private let playerService: PlayerProgressService
    private let environment: ProgressEnvironment
    private let maxStackSize = 99

    struct BatchSeed: Sendable {
        let masterDataIndex: Int16
        let quantity: Int
        let storage: ItemStorage
        let enhancements: ItemSnapshot.Enhancement

        init(masterDataIndex: Int16,
             quantity: Int,
             storage: ItemStorage,
             enhancements: ItemSnapshot.Enhancement = .init()) {
            self.masterDataIndex = masterDataIndex
            self.quantity = quantity
            self.storage = storage
            self.enhancements = enhancements
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
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        #endif

        let context = makeContext()
        let descriptor = fetchDescriptor(for: storage)

        #if DEBUG
        let fetchStart = CFAbsoluteTimeGetCurrent()
        #endif

        let records = try context.fetch(descriptor)

        #if DEBUG
        let fetchEnd = CFAbsoluteTimeGetCurrent()
        let mapStart = CFAbsoluteTimeGetCurrent()
        #endif

        let snapshots = records.map(makeSnapshot(_:))

        #if DEBUG
        let mapEnd = CFAbsoluteTimeGetCurrent()
        let totalTime = mapEnd - startTime
        print("[Perf:Inventory] allItems count=\(records.count) fetch=\(String(format: "%.3f", fetchEnd - fetchStart))s map=\(String(format: "%.3f", mapEnd - mapStart))s total=\(String(format: "%.3f", totalTime))s")
        #endif

        return snapshots
    }

    func allEquipment(storage: ItemStorage) async throws -> [RuntimeEquipment] {
        let snapshots = try await allItems(storage: storage)
        if snapshots.isEmpty { return [] }

        let masterIndices = Array(Set(snapshots.map { $0.masterDataIndex }))
        let definitions = try await environment.masterDataService.getItemMasterData(byIndices: masterIndices)
        let definitionMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.index, $0) })
        let missing = masterIndices.filter { definitionMap[$0] == nil }
        if !missing.isEmpty {
            let missingIds = missing.map { String($0) }
            throw ProgressError.itemDefinitionUnavailable(ids: missingIds)
        }

        return snapshots.compactMap { snapshot in
            guard let definition = definitionMap[snapshot.masterDataIndex] else {
                return nil
            }
            return RuntimeEquipment(
                id: snapshot.stackKey,
                masterDataIndex: snapshot.masterDataIndex,
                masterDataId: definition.id,
                displayName: definition.name,
                description: definition.description,
                quantity: snapshot.quantity,
                category: RuntimeEquipment.Category(from: definition.category),
                baseValue: definition.basePrice,
                sellValue: definition.sellValue,
                enhancement: .init(
                    superRareTitleIndex: snapshot.enhancements.superRareTitleIndex,
                    normalTitleIndex: snapshot.enhancements.normalTitleIndex,
                    socketSuperRareTitleIndex: snapshot.enhancements.socketSuperRareTitleIndex,
                    socketNormalTitleIndex: snapshot.enhancements.socketNormalTitleIndex,
                    socketMasterDataIndex: snapshot.enhancements.socketMasterDataIndex
                ),
                rarity: definition.rarity,
                statBonuses: definition.statBonuses,
                combatBonuses: definition.combatBonuses
            )
        }
        .sorted { lhs, rhs in
            // 超レア称号 → 通常称号 → アイテム → ソケット の順でソート
            if lhs.enhancement.superRareTitleIndex != rhs.enhancement.superRareTitleIndex {
                return lhs.enhancement.superRareTitleIndex < rhs.enhancement.superRareTitleIndex
            }
            if lhs.enhancement.normalTitleIndex != rhs.enhancement.normalTitleIndex {
                return lhs.enhancement.normalTitleIndex < rhs.enhancement.normalTitleIndex
            }
            if lhs.masterDataIndex != rhs.masterDataIndex {
                return lhs.masterDataIndex < rhs.masterDataIndex
            }
            return lhs.enhancement.socketMasterDataIndex < rhs.enhancement.socketMasterDataIndex
        }
    }

    func addItem(masterDataIndex: Int16,
                 quantity: Int,
                 storage: ItemStorage,
                 enhancements: ItemSnapshot.Enhancement = .init()) async throws -> ItemSnapshot {
        guard quantity > 0 else {
            throw ProgressError.invalidInput(description: "追加数量は1以上である必要があります")
        }

        let context = makeContext()
        let record = try fetchOrCreateRecord(
            superRareTitleIndex: enhancements.superRareTitleIndex,
            normalTitleIndex: enhancements.normalTitleIndex,
            masterDataIndex: masterDataIndex,
            socketSuperRareTitleIndex: enhancements.socketSuperRareTitleIndex,
            socketNormalTitleIndex: enhancements.socketNormalTitleIndex,
            socketMasterDataIndex: enhancements.socketMasterDataIndex,
            storage: storage,
            context: context
        )
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
            let aggregated = aggregate(chunk)

            for (storage, entries) in aggregated {
                try Task.checkCancellation()
                let stackKeys = entries.map { $0.key.stackKey }
                var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
                    stackKeys.contains($0.stackKey) && $0.storageRawValue == storage.rawValue
                })
                descriptor.fetchLimit = stackKeys.count
                let existingRecords = try context.fetch(descriptor)
                let recordMap = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.stackKey, $0) })

                for entry in entries {
                    if let record = recordMap[entry.key.stackKey] {
                        _ = applyIncrement(to: record, amount: entry.totalQuantity)
                    } else {
                        let newRecord = InventoryItemRecord(
                            superRareTitleIndex: entry.seed.enhancements.superRareTitleIndex,
                            normalTitleIndex: entry.seed.enhancements.normalTitleIndex,
                            masterDataIndex: entry.seed.masterDataIndex,
                            socketSuperRareTitleIndex: entry.seed.enhancements.socketSuperRareTitleIndex,
                            socketNormalTitleIndex: entry.seed.enhancements.socketNormalTitleIndex,
                            socketMasterDataIndex: entry.seed.enhancements.socketMasterDataIndex,
                            quantity: 0,
                            storage: storage
                        )
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
        let stackKey: String
        let storageRaw: String
    }

    private struct AggregatedEntry {
        let key: SeedKey
        let seed: BatchSeed
        var totalQuantity: Int
    }

    private func aggregate(_ seeds: [BatchSeed]) -> [ItemStorage: [AggregatedEntry]] {
        var grouped: [SeedKey: AggregatedEntry] = [:]
        grouped.reserveCapacity(seeds.count)
        for seed in seeds {
            let stackKey = makeStackKey(
                superRareTitleIndex: seed.enhancements.superRareTitleIndex,
                normalTitleIndex: seed.enhancements.normalTitleIndex,
                masterDataIndex: seed.masterDataIndex,
                socketSuperRareTitleIndex: seed.enhancements.socketSuperRareTitleIndex,
                socketNormalTitleIndex: seed.enhancements.socketNormalTitleIndex,
                socketMasterDataIndex: seed.enhancements.socketMasterDataIndex
            )
            let key = SeedKey(stackKey: stackKey, storageRaw: seed.storage.rawValue)
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
                continue
            }
            result[storage, default: []].append(entry)
        }
        return result
    }

    func sellItems(stackKeys: [String]) async throws -> PlayerSnapshot {
        guard !stackKeys.isEmpty else {
            return try await playerService.currentPlayer()
        }

        let context = makeContext()
        let descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate { stackKeys.contains($0.stackKey) })
        let records = try context.fetch(descriptor)
        guard !records.isEmpty else {
            return try await playerService.currentPlayer()
        }
        let masterIndices = Array(Set(records.map { $0.masterDataIndex }))
        let definitions = try await environment.masterDataService.getItemMasterData(byIndices: masterIndices)
        let priceMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.index, $0.sellValue) })
        let missing = masterIndices.filter { priceMap[$0] == nil }
        if !missing.isEmpty {
            throw ProgressError.itemDefinitionUnavailable(ids: missing.map { String($0) })
        }
        let totalGain = records.reduce(into: 0) { total, record in
            guard record.quantity > 0, let value = priceMap[record.masterDataIndex] else { return }
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

    func updateItem(stackKey: String,
                    mutate: (InventoryItemRecord) throws -> Void) async throws -> ItemSnapshot {
        let context = makeContext()
        var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate { $0.stackKey == stackKey })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            throw ProgressError.invalidInput(description: "指定したアイテムが見つかりません")
        }
        try mutate(record)
        try context.save()
        return makeSnapshot(record)
    }

    func decrementItem(stackKey: String, quantity: Int) async throws {
        guard quantity > 0 else { return }
        let context = makeContext()
        var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate { $0.stackKey == stackKey })
        descriptor.fetchLimit = 1
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

    func inheritItem(targetStackKey: String,
                     sourceStackKey: String,
                     newEnhancement: ItemSnapshot.Enhancement) async throws -> RuntimeEquipment {
        let context = makeContext()

        var targetFetch = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate { $0.stackKey == targetStackKey })
        targetFetch.fetchLimit = 1
        guard let targetRecord = try context.fetch(targetFetch).first else {
            throw ProgressError.invalidInput(description: "対象アイテムが見つかりません")
        }
        var sourceFetch = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate { $0.stackKey == sourceStackKey })
        sourceFetch.fetchLimit = 1
        guard let sourceRecord = try context.fetch(sourceFetch).first else {
            throw ProgressError.invalidInput(description: "提供アイテムが見つかりません")
        }
        guard targetRecord.storage == .playerItem else {
            throw ProgressError.invalidInput(description: "対象アイテムは所持品から選択してください")
        }
        guard sourceRecord.storage == .playerItem else {
            throw ProgressError.invalidInput(description: "提供アイテムは所持品から選択してください")
        }

        targetRecord.superRareTitleIndex = newEnhancement.superRareTitleIndex
        targetRecord.normalTitleIndex = newEnhancement.normalTitleIndex
        targetRecord.socketSuperRareTitleIndex = newEnhancement.socketSuperRareTitleIndex
        targetRecord.socketNormalTitleIndex = newEnhancement.socketNormalTitleIndex
        targetRecord.socketMasterDataIndex = newEnhancement.socketMasterDataIndex

        if sourceRecord.quantity <= 1 {
            context.delete(sourceRecord)
        } else {
            sourceRecord.quantity -= 1
        }

        try context.save()

        let definitions = try await environment.masterDataService.getItemMasterData(byIndices: [targetRecord.masterDataIndex])
        guard let definition = definitions.first else {
            throw ProgressError.itemDefinitionUnavailable(ids: [String(targetRecord.masterDataIndex)])
        }
        let snapshot = makeSnapshot(targetRecord)
        return RuntimeEquipment(
            id: snapshot.stackKey,
            masterDataIndex: snapshot.masterDataIndex,
            masterDataId: definition.id,
            displayName: definition.name,
            description: definition.description,
            quantity: snapshot.quantity,
            category: RuntimeEquipment.Category(from: definition.category),
            baseValue: definition.basePrice,
            sellValue: definition.sellValue,
            enhancement: .init(
                superRareTitleIndex: snapshot.enhancements.superRareTitleIndex,
                normalTitleIndex: snapshot.enhancements.normalTitleIndex,
                socketSuperRareTitleIndex: snapshot.enhancements.socketSuperRareTitleIndex,
                socketNormalTitleIndex: snapshot.enhancements.socketNormalTitleIndex,
                socketMasterDataIndex: snapshot.enhancements.socketMasterDataIndex
            ),
            rarity: definition.rarity,
            statBonuses: definition.statBonuses,
            combatBonuses: definition.combatBonuses
        )
    }

    // MARK: - Private Helpers

    private func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func fetchDescriptor(for storage: ItemStorage) -> FetchDescriptor<InventoryItemRecord> {
        var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate { $0.storageRawValue == storage.rawValue })
        // Index順でソート（超レア称号 → 通常称号 → アイテム → ソケット）
        descriptor.sortBy = [
            SortDescriptor(\InventoryItemRecord.superRareTitleIndex, order: .forward),
            SortDescriptor(\InventoryItemRecord.normalTitleIndex, order: .forward),
            SortDescriptor(\InventoryItemRecord.masterDataIndex, order: .forward),
            SortDescriptor(\InventoryItemRecord.socketMasterDataIndex, order: .forward)
        ]
        return descriptor
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

    private func fetchOrCreateRecord(
        superRareTitleIndex: Int16,
        normalTitleIndex: Int8,
        masterDataIndex: Int16,
        socketSuperRareTitleIndex: Int16,
        socketNormalTitleIndex: Int8,
        socketMasterDataIndex: Int16,
        storage: ItemStorage,
        context: ModelContext
    ) throws -> InventoryItemRecord {
        let stackKey = makeStackKey(
            superRareTitleIndex: superRareTitleIndex,
            normalTitleIndex: normalTitleIndex,
            masterDataIndex: masterDataIndex,
            socketSuperRareTitleIndex: socketSuperRareTitleIndex,
            socketNormalTitleIndex: socketNormalTitleIndex,
            socketMasterDataIndex: socketMasterDataIndex
        )
        var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.stackKey == stackKey && $0.storageRawValue == storage.rawValue
        })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            if existing.storage != storage {
                existing.storage = storage
            }
            return existing
        }
        let record = InventoryItemRecord(
            superRareTitleIndex: superRareTitleIndex,
            normalTitleIndex: normalTitleIndex,
            masterDataIndex: masterDataIndex,
            socketSuperRareTitleIndex: socketSuperRareTitleIndex,
            socketNormalTitleIndex: socketNormalTitleIndex,
            socketMasterDataIndex: socketMasterDataIndex,
            quantity: 0,
            storage: storage
        )
        context.insert(record)
        return record
    }

    private func makeStackKey(
        superRareTitleIndex: Int16,
        normalTitleIndex: Int8,
        masterDataIndex: Int16,
        socketSuperRareTitleIndex: Int16,
        socketNormalTitleIndex: Int8,
        socketMasterDataIndex: Int16
    ) -> String {
        "\(superRareTitleIndex)|\(normalTitleIndex)|\(masterDataIndex)|\(socketSuperRareTitleIndex)|\(socketNormalTitleIndex)|\(socketMasterDataIndex)"
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
