import Foundation
import SwiftData

actor InventoryProgressService {
    private let container: ModelContainer
    private let gameStateService: GameStateService
    private let environment: ProgressEnvironment
    private let maxStackSize: UInt16 = 99

    struct BatchSeed: Sendable {
        let itemId: UInt16
        let quantity: Int
        let storage: ItemStorage
        let enhancements: ItemSnapshot.Enhancement

        init(itemId: UInt16,
             quantity: Int,
             storage: ItemStorage,
             enhancements: ItemSnapshot.Enhancement = .init()) {
            self.itemId = itemId
            self.quantity = quantity
            self.storage = storage
            self.enhancements = enhancements
        }
    }

    init(container: ModelContainer,
         gameStateService: GameStateService,
         environment: ProgressEnvironment) {
        self.container = container
        self.gameStateService = gameStateService
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

        let masterIndices = Array(Set(snapshots.map { $0.itemId }))
        let definitions = try await environment.masterDataService.getItemMasterData(ids: masterIndices)
        let definitionMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        let missing = masterIndices.filter { definitionMap[$0] == nil }
        if !missing.isEmpty {
            let missingIds = missing.map { String($0) }
            throw ProgressError.itemDefinitionUnavailable(ids: missingIds)
        }

        return snapshots.compactMap { snapshot -> RuntimeEquipment? in
            guard let definition = definitionMap[snapshot.itemId] else {
                return nil
            }
            return RuntimeEquipment(
                id: snapshot.stackKey,
                itemId: snapshot.itemId,
                masterDataId: String(definition.id),
                displayName: definition.name,
                quantity: Int(snapshot.quantity),
                category: ItemSaleCategory(masterCategory: definition.category),
                baseValue: definition.basePrice,
                sellValue: definition.sellValue,
                enhancement: .init(
                    superRareTitleId: snapshot.enhancements.superRareTitleId,
                    normalTitleId: snapshot.enhancements.normalTitleId,
                    socketSuperRareTitleId: snapshot.enhancements.socketSuperRareTitleId,
                    socketNormalTitleId: snapshot.enhancements.socketNormalTitleId,
                    socketItemId: snapshot.enhancements.socketItemId
                ),
                rarity: definition.rarity,
                statBonuses: definition.statBonuses,
                combatBonuses: definition.combatBonuses
            )
        }
        .sorted { lhs, rhs in
            // ソート順: アイテムごとに 通常称号のみ → 通常称号+ソケット → 超レア → 超レア+ソケット
            // 1. アイテム (ベースアイテムでグループ化)
            if lhs.itemId != rhs.itemId {
                return lhs.itemId < rhs.itemId
            }
            // 2. 超レアの有無 (なしが先)
            let lhsHasSuperRare = lhs.enhancement.superRareTitleId > 0
            let rhsHasSuperRare = rhs.enhancement.superRareTitleId > 0
            if lhsHasSuperRare != rhsHasSuperRare {
                return !lhsHasSuperRare
            }
            // 3. ソケットの有無 (なしが先)
            let lhsHasSocket = lhs.enhancement.socketItemId > 0
            let rhsHasSocket = rhs.enhancement.socketItemId > 0
            if lhsHasSocket != rhsHasSocket {
                return !lhsHasSocket
            }
            // 4. 通常称号
            if lhs.enhancement.normalTitleId != rhs.enhancement.normalTitleId {
                return lhs.enhancement.normalTitleId < rhs.enhancement.normalTitleId
            }
            // 5. 超レア称号の詳細
            if lhs.enhancement.superRareTitleId != rhs.enhancement.superRareTitleId {
                return lhs.enhancement.superRareTitleId < rhs.enhancement.superRareTitleId
            }
            // 6. ソケットの詳細
            return lhs.enhancement.socketItemId < rhs.enhancement.socketItemId
        }
    }

    func addItem(itemId: UInt16,
                 quantity: Int,
                 storage: ItemStorage,
                 enhancements: ItemSnapshot.Enhancement = .init()) async throws -> ItemSnapshot {
        guard quantity > 0 else {
            throw ProgressError.invalidInput(description: "追加数量は1以上である必要があります")
        }

        let context = makeContext()
        let record = try fetchOrCreateRecord(
            superRareTitleId: enhancements.superRareTitleId,
            normalTitleId: enhancements.normalTitleId,
            itemId: itemId,
            socketSuperRareTitleId: enhancements.socketSuperRareTitleId,
            socketNormalTitleId: enhancements.socketNormalTitleId,
            socketItemId: enhancements.socketItemId,
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
                let stackKeySet = Set(entries.map { $0.key.stackKey })
                // Fetch all records for this storage, then filter in memory
                // (SwiftData #Predicate cannot use computed properties like stackKey)
                let storageRaw = storage.rawValue
                let descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
                    $0.storageRawValue == storageRaw
                })
                let allRecords = try context.fetch(descriptor)
                let existingRecords = allRecords.filter { stackKeySet.contains($0.stackKey) }
                let recordMap = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.stackKey, $0) })

                for entry in entries {
                    if let record = recordMap[entry.key.stackKey] {
                        _ = applyIncrement(to: record, amount: entry.totalQuantity)
                    } else {
                        let newRecord = InventoryItemRecord(
                            superRareTitleId: entry.seed.enhancements.superRareTitleId,
                            normalTitleId: entry.seed.enhancements.normalTitleId,
                            itemId: entry.seed.itemId,
                            socketSuperRareTitleId: entry.seed.enhancements.socketSuperRareTitleId,
                            socketNormalTitleId: entry.seed.enhancements.socketNormalTitleId,
                            socketItemId: entry.seed.enhancements.socketItemId,
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

    #if DEBUG
    /// デバッグ用: 既存チェックなしで高速INSERT（新規生成専用）
    func addItemsUnchecked(_ seeds: [BatchSeed], chunkSize: Int = 50_000) async throws {
        guard !seeds.isEmpty else { return }
        var index = 0
        var chunkNumber = 0
        while index < seeds.count {
            try Task.checkCancellation()
            let end = min(index + chunkSize, seeds.count)
            chunkNumber += 1
            let context = makeContext()
            for i in index..<end {
                let seed = seeds[i]
                let record = InventoryItemRecord(
                    superRareTitleId: seed.enhancements.superRareTitleId,
                    normalTitleId: seed.enhancements.normalTitleId,
                    itemId: seed.itemId,
                    socketSuperRareTitleId: seed.enhancements.socketSuperRareTitleId,
                    socketNormalTitleId: seed.enhancements.socketNormalTitleId,
                    socketItemId: seed.enhancements.socketItemId,
                    quantity: UInt16(clamping: seed.quantity),
                    storage: seed.storage
                )
                context.insert(record)
            }
            try context.save()
            print("[Inventory] unchecked insert chunk #\(chunkNumber) size=\(end - index)")
            index = end
        }
    }
    #endif

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
                superRareTitleId: seed.enhancements.superRareTitleId,
                normalTitleId: seed.enhancements.normalTitleId,
                itemId: seed.itemId,
                socketSuperRareTitleId: seed.enhancements.socketSuperRareTitleId,
                socketNormalTitleId: seed.enhancements.socketNormalTitleId,
                socketItemId: seed.enhancements.socketItemId
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
            return try await gameStateService.currentPlayer()
        }

        let context = makeContext()
        // Fetch all records, then filter in memory by stackKey
        // (SwiftData #Predicate cannot use computed properties like stackKey)
        let stackKeySet = Set(stackKeys)
        let descriptor = FetchDescriptor<InventoryItemRecord>()
        let allRecords = try context.fetch(descriptor)
        let records = allRecords.filter { stackKeySet.contains($0.stackKey) }
        guard !records.isEmpty else {
            return try await gameStateService.currentPlayer()
        }
        let masterIndices = Array(Set(records.map { $0.itemId }))
        let definitions = try await environment.masterDataService.getItemMasterData(ids: masterIndices)
        let priceMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0.sellValue) })
        let missing = masterIndices.filter { priceMap[$0] == nil }
        if !missing.isEmpty {
            throw ProgressError.itemDefinitionUnavailable(ids: missing.map { String($0) })
        }
        let totalGain = records.reduce(into: 0) { total, record in
            guard record.quantity > 0, let value = priceMap[record.itemId] else { return }
            total += value * Int(record.quantity)
        }
        for record in records {
            context.delete(record)
        }
        try context.save()

        guard totalGain > 0 else {
            return try await gameStateService.currentPlayer()
        }

        return try await gameStateService.addGold(UInt32(totalGain))
    }

    func updateItem(stackKey: String,
                    mutate: (InventoryItemRecord) throws -> Void) async throws -> ItemSnapshot {
        guard let c = StackKeyComponents(stackKey: stackKey) else {
            throw ProgressError.invalidInput(description: "不正なstackKeyです")
        }
        let context = makeContext()
        let superRare = c.superRareTitleId
        let normal = c.normalTitleId
        let master = c.itemId
        let socketSuperRare = c.socketSuperRareTitleId
        let socketNormal = c.socketNormalTitleId
        let socketMaster = c.socketItemId
        var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.superRareTitleId == superRare &&
            $0.normalTitleId == normal &&
            $0.itemId == master &&
            $0.socketSuperRareTitleId == socketSuperRare &&
            $0.socketNormalTitleId == socketNormal &&
            $0.socketItemId == socketMaster
        })
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
        guard let c = StackKeyComponents(stackKey: stackKey) else {
            throw ProgressError.invalidInput(description: "不正なstackKeyです")
        }
        let context = makeContext()
        let superRare = c.superRareTitleId
        let normal = c.normalTitleId
        let master = c.itemId
        let socketSuperRare = c.socketSuperRareTitleId
        let socketNormal = c.socketNormalTitleId
        let socketMaster = c.socketItemId
        var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.superRareTitleId == superRare &&
            $0.normalTitleId == normal &&
            $0.itemId == master &&
            $0.socketSuperRareTitleId == socketSuperRare &&
            $0.socketNormalTitleId == socketNormal &&
            $0.socketItemId == socketMaster
        })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            throw ProgressError.invalidInput(description: "指定したアイテムが見つかりません")
        }
        guard Int(record.quantity) >= quantity else {
            throw ProgressError.invalidInput(description: "アイテム数量が不足しています")
        }
        record.quantity -= UInt16(quantity)
        if record.quantity <= 0 {
            context.delete(record)
        }
        try context.save()
    }

    func inheritItem(targetStackKey: String,
                     sourceStackKey: String,
                     newEnhancement: ItemSnapshot.Enhancement) async throws -> RuntimeEquipment {
        guard let tc = StackKeyComponents(stackKey: targetStackKey) else {
            throw ProgressError.invalidInput(description: "不正な対象stackKeyです")
        }
        guard let sc = StackKeyComponents(stackKey: sourceStackKey) else {
            throw ProgressError.invalidInput(description: "不正な提供stackKeyです")
        }
        let context = makeContext()

        // target fetch with individual field comparison
        let tSuperRare = tc.superRareTitleId
        let tNormal = tc.normalTitleId
        let tMaster = tc.itemId
        let tSocketSuperRare = tc.socketSuperRareTitleId
        let tSocketNormal = tc.socketNormalTitleId
        let tSocketMaster = tc.socketItemId
        var targetFetch = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.superRareTitleId == tSuperRare &&
            $0.normalTitleId == tNormal &&
            $0.itemId == tMaster &&
            $0.socketSuperRareTitleId == tSocketSuperRare &&
            $0.socketNormalTitleId == tSocketNormal &&
            $0.socketItemId == tSocketMaster
        })
        targetFetch.fetchLimit = 1
        guard let targetRecord = try context.fetch(targetFetch).first else {
            throw ProgressError.invalidInput(description: "対象アイテムが見つかりません")
        }

        // source fetch with individual field comparison
        let sSuperRare = sc.superRareTitleId
        let sNormal = sc.normalTitleId
        let sMaster = sc.itemId
        let sSocketSuperRare = sc.socketSuperRareTitleId
        let sSocketNormal = sc.socketNormalTitleId
        let sSocketMaster = sc.socketItemId
        var sourceFetch = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.superRareTitleId == sSuperRare &&
            $0.normalTitleId == sNormal &&
            $0.itemId == sMaster &&
            $0.socketSuperRareTitleId == sSocketSuperRare &&
            $0.socketNormalTitleId == sSocketNormal &&
            $0.socketItemId == sSocketMaster
        })
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

        targetRecord.superRareTitleId = newEnhancement.superRareTitleId
        targetRecord.normalTitleId = newEnhancement.normalTitleId
        targetRecord.socketSuperRareTitleId = newEnhancement.socketSuperRareTitleId
        targetRecord.socketNormalTitleId = newEnhancement.socketNormalTitleId
        targetRecord.socketItemId = newEnhancement.socketItemId

        if sourceRecord.quantity <= 1 {
            context.delete(sourceRecord)
        } else {
            sourceRecord.quantity -= 1
        }

        try context.save()

        let definitions = try await environment.masterDataService.getItemMasterData(ids: [targetRecord.itemId])
        guard let definition = definitions.first else {
            throw ProgressError.itemDefinitionUnavailable(ids: [String(targetRecord.itemId)])
        }
        let snapshot = makeSnapshot(targetRecord)
        return RuntimeEquipment(
            id: snapshot.stackKey,
            itemId: snapshot.itemId,
            masterDataId: String(definition.id),
            displayName: definition.name,
            quantity: Int(snapshot.quantity),
            category: ItemSaleCategory(masterCategory: definition.category),
            baseValue: definition.basePrice,
            sellValue: definition.sellValue,
            enhancement: .init(
                superRareTitleId: snapshot.enhancements.superRareTitleId,
                normalTitleId: snapshot.enhancements.normalTitleId,
                socketSuperRareTitleId: snapshot.enhancements.socketSuperRareTitleId,
                socketNormalTitleId: snapshot.enhancements.socketNormalTitleId,
                socketItemId: snapshot.enhancements.socketItemId
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
            SortDescriptor(\InventoryItemRecord.superRareTitleId, order: .forward),
            SortDescriptor(\InventoryItemRecord.normalTitleId, order: .forward),
            SortDescriptor(\InventoryItemRecord.itemId, order: .forward),
            SortDescriptor(\InventoryItemRecord.socketItemId, order: .forward)
        ]
        return descriptor
    }

    private func makeSnapshot(_ record: InventoryItemRecord) -> ItemSnapshot {
        ItemSnapshot(
            stackKey: record.stackKey,
            itemId: record.itemId,
            quantity: record.quantity,
            storage: record.storage,
            enhancements: .init(
                superRareTitleId: record.superRareTitleId,
                normalTitleId: record.normalTitleId,
                socketSuperRareTitleId: record.socketSuperRareTitleId,
                socketNormalTitleId: record.socketNormalTitleId,
                socketItemId: record.socketItemId
            )
        )
    }

    private func fetchOrCreateRecord(
        superRareTitleId: UInt8,
        normalTitleId: UInt8,
        itemId: UInt16,
        socketSuperRareTitleId: UInt8,
        socketNormalTitleId: UInt8,
        socketItemId: UInt16,
        storage: ItemStorage,
        context: ModelContext
    ) throws -> InventoryItemRecord {
        // Capture values for #Predicate
        let superRare = superRareTitleId
        let normal = normalTitleId
        let master = itemId
        let socketSuperRare = socketSuperRareTitleId
        let socketNormal = socketNormalTitleId
        let socketMaster = socketItemId
        let storageRaw = storage.rawValue
        var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.superRareTitleId == superRare &&
            $0.normalTitleId == normal &&
            $0.itemId == master &&
            $0.socketSuperRareTitleId == socketSuperRare &&
            $0.socketNormalTitleId == socketNormal &&
            $0.socketItemId == socketMaster &&
            $0.storageRawValue == storageRaw
        })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            if existing.storage != storage {
                existing.storage = storage
            }
            return existing
        }
        let record = InventoryItemRecord(
            superRareTitleId: superRareTitleId,
            normalTitleId: normalTitleId,
            itemId: itemId,
            socketSuperRareTitleId: socketSuperRareTitleId,
            socketNormalTitleId: socketNormalTitleId,
            socketItemId: socketItemId,
            quantity: 0,
            storage: storage
        )
        context.insert(record)
        return record
    }

    private func makeStackKey(
        superRareTitleId: UInt8,
        normalTitleId: UInt8,
        itemId: UInt16,
        socketSuperRareTitleId: UInt8,
        socketNormalTitleId: UInt8,
        socketItemId: UInt16
    ) -> String {
        "\(superRareTitleId)|\(normalTitleId)|\(itemId)|\(socketSuperRareTitleId)|\(socketNormalTitleId)|\(socketItemId)"
    }

    @discardableResult
    private func applyIncrement(to record: InventoryItemRecord, amount: Int) -> Int {
        guard amount > 0 else { return 0 }

        let clampedCurrent = min(record.quantity, maxStackSize)
        record.quantity = clampedCurrent

        let capacity = Int(max(0, maxStackSize - clampedCurrent))
        let addable = min(capacity, amount)
        record.quantity = clampedCurrent + UInt16(addable)

        return amount - addable
    }
}
