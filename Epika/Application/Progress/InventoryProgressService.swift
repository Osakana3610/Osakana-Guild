// ==============================================================================
// InventoryProgressService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - インベントリ（所持アイテム）の管理
//   - アイテムの追加・削除・数量変更
//
// 【公開API】
//   - allItems(storage:) → [ItemSnapshot] - 指定ストレージの全アイテム
//   - addItem(...) → ItemSnapshot - アイテム追加（スタック上限99）
//   - addItems(_:) - 一括追加
//   - decrementItem(stackKey:quantity:) - 数量減算
//   - removeItem(stackKey:) - アイテム削除
//   - allEquipment(storage:) → [RuntimeEquipment] - 装備一覧
//
// 【データ構造】
//   - BatchSeed: 一括追加用のシードデータ
//   - maxStackSize: スタック上限（99）
//
// 【スタックキー】
//   - 称号ID+アイテムID+ソケット情報の組み合わせ
//   - 同一キーは同一スタックとして管理
//
// ==============================================================================

import Foundation
import SwiftData

actor InventoryProgressService {
    private let contextProvider: SwiftDataContextProvider
    private let gameStateService: GameStateService
    private let masterDataCache: MasterDataCache
    private let maxStackSize: UInt16 = 99

    struct BatchSeed: Sendable {
        let itemId: UInt16
        let quantity: Int
        let storage: ItemStorage
        let enhancements: ItemEnhancement

        init(itemId: UInt16,
             quantity: Int,
             storage: ItemStorage,
             enhancements: ItemEnhancement = .init()) {
            self.itemId = itemId
            self.quantity = quantity
            self.storage = storage
            self.enhancements = enhancements
        }
    }

    init(contextProvider: SwiftDataContextProvider,
         gameStateService: GameStateService,
         masterDataCache: MasterDataCache) {
        self.contextProvider = contextProvider
        self.gameStateService = gameStateService
        self.masterDataCache = masterDataCache
    }

    // MARK: - Public API

    func allItems(storage: ItemStorage) async throws -> [ItemSnapshot] {
        let context = contextProvider.makeContext()
        let descriptor = fetchDescriptor(for: storage)
        let records = try context.fetch(descriptor)
        let snapshots = records.map(makeSnapshot(_:))
        return snapshots
    }

    func allEquipment(storage: ItemStorage) async throws -> [RuntimeEquipment] {
        let snapshots = try await allItems(storage: storage)
        if snapshots.isEmpty { return [] }

        let masterIndices = Array(Set(snapshots.map { $0.itemId }))
        var definitionMap: [UInt16: ItemDefinition] = [:]
        var missing: [UInt16] = []
        for id in masterIndices {
            if let definition = masterDataCache.item(id) {
                definitionMap[id] = definition
            } else {
                missing.append(id)
            }
        }
        if !missing.isEmpty {
            let missingIds = missing.map { String($0) }
            throw ProgressError.itemDefinitionUnavailable(ids: missingIds)
        }

        return snapshots.compactMap { snapshot -> RuntimeEquipment? in
            guard let definition = definitionMap[snapshot.itemId] else {
                return nil
            }
            // 称号を含めた表示名を生成
            let displayName = buildDisplayName(
                baseName: definition.name,
                superRareTitleId: snapshot.enhancements.superRareTitleId,
                normalTitleId: snapshot.enhancements.normalTitleId
            )
            return RuntimeEquipment(
                id: snapshot.stackKey,
                itemId: snapshot.itemId,
                masterDataId: String(definition.id),
                displayName: displayName,
                quantity: Int(snapshot.quantity),
                category: ItemSaleCategory(rawValue: definition.category) ?? .other,
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
                 enhancements: ItemEnhancement = .init()) async throws -> ItemSnapshot {
        guard quantity > 0 else {
            throw ProgressError.invalidInput(description: "追加数量は1以上である必要があります")
        }

        let context = contextProvider.makeContext()
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
        postInventoryChange(upserted: [record.stackKey])
        return makeSnapshot(record)
    }

    /// バッチ追加してスナップショットを返す（ドロップ報酬用）
    func addItemsBatchReturningSnapshots(_ seeds: [BatchSeed]) async throws -> [ItemSnapshot] {
        guard !seeds.isEmpty else { return [] }

        let context = contextProvider.makeContext()
        let aggregated = aggregate(seeds)
        var stackKeys: [String] = []
        var snapshots: [ItemSnapshot] = []

        for (storage, entries) in aggregated {
            for entry in entries {
                let record = try fetchOrCreateRecord(
                    superRareTitleId: entry.seed.enhancements.superRareTitleId,
                    normalTitleId: entry.seed.enhancements.normalTitleId,
                    itemId: entry.seed.itemId,
                    socketSuperRareTitleId: entry.seed.enhancements.socketSuperRareTitleId,
                    socketNormalTitleId: entry.seed.enhancements.socketNormalTitleId,
                    socketItemId: entry.seed.enhancements.socketItemId,
                    storage: storage,
                    context: context
                )
                _ = applyIncrement(to: record, amount: entry.totalQuantity)
                stackKeys.append(record.stackKey)
                snapshots.append(makeSnapshot(record))
            }
        }

        try context.save()
        postInventoryChange(upserted: stackKeys)
        return snapshots
    }

    /// stackKey重複レコードを数量が多いものだけ残して除去
    /// TODO(Build 16): ビルド16で重複レコードが自然消滅したらこの処理を削除する
    @discardableResult
    func repairDuplicateStackKeys() async throws -> Int {
        let context = contextProvider.makeContext()
        let descriptor = FetchDescriptor<InventoryItemRecord>()
        let allRecords = try context.fetch(descriptor)
        guard !allRecords.isEmpty else { return 0 }

        var totalRemoved = 0
        let groupedByStorage = Dictionary(grouping: allRecords, by: { $0.storageType })
        for recordsInStorage in groupedByStorage.values {
            let result = deduplicateRecords(recordsInStorage, context: context)
            totalRemoved += result.removedCount
        }

        guard totalRemoved > 0 else { return 0 }
        try context.save()
        return totalRemoved
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
            let context = contextProvider.makeContext()
            let aggregated = aggregate(chunk)
            var chunkStackKeys: [String] = []

            for (storage, entries) in aggregated {
                try Task.checkCancellation()
                for entry in entries {
                    let record = try fetchOrCreateRecord(
                        superRareTitleId: entry.seed.enhancements.superRareTitleId,
                        normalTitleId: entry.seed.enhancements.normalTitleId,
                        itemId: entry.seed.itemId,
                        socketSuperRareTitleId: entry.seed.enhancements.socketSuperRareTitleId,
                        socketNormalTitleId: entry.seed.enhancements.socketNormalTitleId,
                        socketItemId: entry.seed.enhancements.socketItemId,
                        storage: storage,
                        context: context
                    )
                    _ = applyIncrement(to: record, amount: entry.totalQuantity)
                    chunkStackKeys.append(record.stackKey)
                }
            }
#if DEBUG
            print("[Inventory] inserted chunk #\(localIndex) size=\(chunk.count)")
#endif
            try context.save()
            postInventoryChange(upserted: chunkStackKeys)
            index = end
        }
    }

    /// 既存チェックなしで高速INSERT（新規生成専用）
    func addItemsUnchecked(_ seeds: [BatchSeed], chunkSize: Int = 50_000) async throws {
        guard !seeds.isEmpty else { return }
        var index = 0
        #if DEBUG
        var chunkNumber = 0
        #endif
        while index < seeds.count {
            try Task.checkCancellation()
            let end = min(index + chunkSize, seeds.count)
            #if DEBUG
            chunkNumber += 1
            #endif
            let context = contextProvider.makeContext()
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
            #if DEBUG
            print("[Inventory] unchecked insert chunk #\(chunkNumber) size=\(end - index)")
            #endif
            index = end
        }
    }

    private struct SeedKey: Hashable {
        let stackKey: String
        let storageRaw: UInt8
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

    func updateItem(stackKey: String,
                    mutate: (InventoryItemRecord) throws -> Void) async throws -> ItemSnapshot {
        guard let components = StackKeyComponents(stackKey: stackKey) else {
            throw ProgressError.invalidInput(description: "不正なstackKeyです")
        }
        let context = contextProvider.makeContext()
        let superRare = components.superRareTitleId
        let normal = components.normalTitleId
        let master = components.itemId
        let socketSuperRare = components.socketSuperRareTitleId
        let socketNormal = components.socketNormalTitleId
        let socketMaster = components.socketItemId
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
        postInventoryChange(upserted: [record.stackKey])
        return makeSnapshot(record)
    }

    func decrementItem(stackKey: String, quantity: Int) async throws {
        guard quantity > 0 else { return }
        guard let components = StackKeyComponents(stackKey: stackKey) else {
            throw ProgressError.invalidInput(description: "不正なstackKeyです")
        }
        let context = contextProvider.makeContext()
        let superRare = components.superRareTitleId
        let normal = components.normalTitleId
        let master = components.itemId
        let socketSuperRare = components.socketSuperRareTitleId
        let socketNormal = components.socketNormalTitleId
        let socketMaster = components.socketItemId
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
        let wasDeleted = record.quantity <= 0
        if wasDeleted {
            context.delete(record)
        }
        try context.save()
        if wasDeleted {
            postInventoryChange(removed: [stackKey])
        } else {
            postInventoryChange(upserted: [record.stackKey])
        }
    }

    func inheritItem(targetStackKey: String,
                     sourceStackKey: String,
                     newEnhancement: ItemEnhancement) async throws -> RuntimeEquipment {
        guard let targetComponents = StackKeyComponents(stackKey: targetStackKey) else {
            throw ProgressError.invalidInput(description: "不正な対象stackKeyです")
        }
        guard let sourceComponents = StackKeyComponents(stackKey: sourceStackKey) else {
            throw ProgressError.invalidInput(description: "不正な提供stackKeyです")
        }
        let context = contextProvider.makeContext()

        // target fetch with individual field comparison
        let tSuperRare = targetComponents.superRareTitleId
        let tNormal = targetComponents.normalTitleId
        let tMaster = targetComponents.itemId
        let tSocketSuperRare = targetComponents.socketSuperRareTitleId
        let tSocketNormal = targetComponents.socketNormalTitleId
        let tSocketMaster = targetComponents.socketItemId
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
        let sSuperRare = sourceComponents.superRareTitleId
        let sNormal = sourceComponents.normalTitleId
        let sMaster = sourceComponents.itemId
        let sSocketSuperRare = sourceComponents.socketSuperRareTitleId
        let sSocketNormal = sourceComponents.socketNormalTitleId
        let sSocketMaster = sourceComponents.socketItemId
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

        let sourceWasDeleted = sourceRecord.quantity <= 1
        if sourceWasDeleted {
            context.delete(sourceRecord)
        } else {
            sourceRecord.quantity -= 1
        }

        try context.save()

        // 通知: 対象は旧stackKeyが削除され、新stackKeyで追加
        var upsertedStackKeys: [String] = [targetRecord.stackKey]
        var removedKeys: [String] = [targetStackKey]
        // ソースは削除または更新
        if sourceWasDeleted {
            removedKeys.append(sourceStackKey)
        } else {
            upsertedStackKeys.append(sourceRecord.stackKey)
        }
        postInventoryChange(upserted: upsertedStackKeys, removed: removedKeys)

        guard let definition = masterDataCache.item(targetRecord.itemId) else {
            throw ProgressError.itemDefinitionUnavailable(ids: [String(targetRecord.itemId)])
        }
        let snapshot = makeSnapshot(targetRecord)
        // 称号を含めた表示名を生成
        let displayName = buildDisplayName(
            baseName: definition.name,
            superRareTitleId: snapshot.enhancements.superRareTitleId,
            normalTitleId: snapshot.enhancements.normalTitleId
        )
        return RuntimeEquipment(
            id: snapshot.stackKey,
            itemId: snapshot.itemId,
            masterDataId: String(definition.id),
            displayName: displayName,
            quantity: Int(snapshot.quantity),
            category: ItemSaleCategory(rawValue: definition.category) ?? .other,
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

    /// 宝石をアイテムにソケットとして装着
    /// - Parameters:
    ///   - gemStackKey: 宝石のstackKey
    ///   - targetStackKey: 対象アイテムのstackKey
    /// - Returns: ソケット装着後のアイテムスナップショット
    /// - Note: 対象の数量が2以上の場合、1個減らして新しいソケット付きスタックを作成
    func attachSocket(gemStackKey: String, targetStackKey: String) async throws -> ItemSnapshot {
        guard let gemComponents = StackKeyComponents(stackKey: gemStackKey) else {
            throw ProgressError.invalidInput(description: "不正な宝石stackKeyです")
        }
        guard let targetComponents = StackKeyComponents(stackKey: targetStackKey) else {
            throw ProgressError.invalidInput(description: "不正な対象stackKeyです")
        }

        let context = contextProvider.makeContext()

        // 宝石レコードの取得
        let gSuperRare = gemComponents.superRareTitleId
        let gNormal = gemComponents.normalTitleId
        let gItem = gemComponents.itemId
        let gSocketSuperRare = gemComponents.socketSuperRareTitleId
        let gSocketNormal = gemComponents.socketNormalTitleId
        let gSocketItem = gemComponents.socketItemId
        var gemDescriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.superRareTitleId == gSuperRare &&
            $0.normalTitleId == gNormal &&
            $0.itemId == gItem &&
            $0.socketSuperRareTitleId == gSocketSuperRare &&
            $0.socketNormalTitleId == gSocketNormal &&
            $0.socketItemId == gSocketItem
        })
        gemDescriptor.fetchLimit = 1
        guard let gemRecord = try context.fetch(gemDescriptor).first else {
            throw ProgressError.invalidInput(description: "宝石が見つかりません")
        }

        // 対象アイテムレコードの取得
        let tSuperRare = targetComponents.superRareTitleId
        let tNormal = targetComponents.normalTitleId
        let tItem = targetComponents.itemId
        let tSocketSuperRare = targetComponents.socketSuperRareTitleId
        let tSocketNormal = targetComponents.socketNormalTitleId
        let tSocketItem = targetComponents.socketItemId
        var targetDescriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.superRareTitleId == tSuperRare &&
            $0.normalTitleId == tNormal &&
            $0.itemId == tItem &&
            $0.socketSuperRareTitleId == tSocketSuperRare &&
            $0.socketNormalTitleId == tSocketNormal &&
            $0.socketItemId == tSocketItem
        })
        targetDescriptor.fetchLimit = 1
        guard let targetRecord = try context.fetch(targetDescriptor).first else {
            throw ProgressError.invalidInput(description: "対象アイテムが見つかりません")
        }

        // 既にソケットが装着されていないか確認
        guard targetRecord.socketItemId == 0 else {
            throw ProgressError.invalidInput(description: "このアイテムには既に宝石改造が施されています")
        }

        let socketItemId = gemRecord.itemId
        let socketSuperRareId = gemRecord.superRareTitleId
        let socketNormalId = gemRecord.normalTitleId

        // 通知用の追跡
        var upsertedStackKeys: [String] = []
        var removedKeys: [String] = []

        let socketedRecord: InventoryItemRecord
        if targetRecord.quantity > 1 {
            // 数量2以上：1個減らし、新しいソケット付きレコードを作成/追加
            targetRecord.quantity -= 1
            upsertedStackKeys.append(targetRecord.stackKey)

            // 既存のソケット付きレコードを検索
            var socketedDescriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
                $0.superRareTitleId == tSuperRare &&
                $0.normalTitleId == tNormal &&
                $0.itemId == tItem &&
                $0.socketSuperRareTitleId == socketSuperRareId &&
                $0.socketNormalTitleId == socketNormalId &&
                $0.socketItemId == socketItemId
            })
            socketedDescriptor.fetchLimit = 1
            if let existingSocketed = try context.fetch(socketedDescriptor).first {
                existingSocketed.quantity += 1
                socketedRecord = existingSocketed
            } else {
                let newRecord = InventoryItemRecord(
                    superRareTitleId: tSuperRare,
                    normalTitleId: tNormal,
                    itemId: tItem,
                    socketSuperRareTitleId: socketSuperRareId,
                    socketNormalTitleId: socketNormalId,
                    socketItemId: socketItemId,
                    quantity: 1,
                    storage: targetRecord.storage
                )
                context.insert(newRecord)
                socketedRecord = newRecord
            }
        } else {
            // 数量1：ソケット情報を直接更新（stackKeyが変わる）
            removedKeys.append(targetStackKey)
            targetRecord.socketItemId = socketItemId
            targetRecord.socketSuperRareTitleId = socketSuperRareId
            targetRecord.socketNormalTitleId = socketNormalId
            socketedRecord = targetRecord
        }

        // 宝石を1個減算
        let gemWasDeleted = gemRecord.quantity <= 1
        if gemWasDeleted {
            context.delete(gemRecord)
            removedKeys.append(gemStackKey)
        } else {
            gemRecord.quantity -= 1
            upsertedStackKeys.append(gemRecord.stackKey)
        }

        upsertedStackKeys.append(socketedRecord.stackKey)

        try context.save()
        postInventoryChange(upserted: upsertedStackKeys, removed: removedKeys)

        return makeSnapshot(socketedRecord)
    }

    // MARK: - Private Helpers

    private func fetchDescriptor(for storage: ItemStorage) -> FetchDescriptor<InventoryItemRecord> {
        let storageTypeValue = storage.rawValue
        var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.storageType == storageTypeValue
        })
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
        let storageTypeValue = storage.rawValue
        var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.superRareTitleId == superRare &&
            $0.normalTitleId == normal &&
            $0.itemId == master &&
            $0.socketSuperRareTitleId == socketSuperRare &&
            $0.socketNormalTitleId == socketNormal &&
            $0.socketItemId == socketMaster &&
            $0.storageType == storageTypeValue
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

    /// 称号を含めた表示名を生成
    /// - Parameters:
    ///   - baseName: アイテムのベース名
    ///   - superRareTitleId: 超レア称号ID（0=なし）
    ///   - normalTitleId: 通常称号ID（0=最低な, 2=無称号）
    /// - Returns: 「超レア称号名 + 通常称号名 + アイテム名」形式の表示名
    private func buildDisplayName(baseName: String,
                                  superRareTitleId: UInt8,
                                  normalTitleId: UInt8) -> String {
        var result = ""
        // 超レア称号
        if superRareTitleId > 0,
           let superRareTitle = masterDataCache.superRareTitle(superRareTitleId) {
            result += superRareTitle.name
        }
        // 通常称号（無称号=2は空文字列なので影響なし）
        if let normalTitle = masterDataCache.title(normalTitleId) {
            result += normalTitle.name
        }
        result += baseName
        return result
    }

    /// TODO(Build 16): repairDuplicateStackKeys削除時に一緒に破棄予定
    private struct DeduplicationResult {
        let recordsByStackKey: [String: InventoryItemRecord]
        let removedCount: Int
    }

    /// TODO(Build 16): repairDuplicateStackKeys削除時に一緒に破棄予定
    private func deduplicateRecords(_ records: [InventoryItemRecord], context: ModelContext) -> DeduplicationResult {
        guard !records.isEmpty else {
            return DeduplicationResult(recordsByStackKey: [:], removedCount: 0)
        }
        var map: [String: InventoryItemRecord] = [:]
        var removed = 0
        for record in records {
            if let existing = map[record.stackKey] {
                if record.quantity > existing.quantity {
                    context.delete(existing)
                    map[record.stackKey] = record
                } else {
                    context.delete(record)
                }
                removed += 1
            } else {
                map[record.stackKey] = record
            }
        }
        return DeduplicationResult(recordsByStackKey: map, removedCount: removed)
    }

    // MARK: - Inventory Change Notification

    /// インベントリ変更通知を送信
    private func postInventoryChange(upserted: [String] = [], removed: [String] = []) {
        guard !upserted.isEmpty || !removed.isEmpty else { return }
        let change = UserDataLoadService.InventoryChange(upserted: upserted, removed: removed)
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .inventoryDidChange,
                object: nil,
                userInfo: ["change": change]
            )
        }
    }
}
