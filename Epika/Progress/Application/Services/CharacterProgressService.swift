import Foundation
import SwiftData

actor CharacterProgressService {
    struct CharacterCreationRequest: Sendable {
        var displayName: String
        var raceId: UInt8
        var jobId: UInt8
    }

    struct BattleResultUpdate: Sendable {
        let characterId: UInt8
        let experienceDelta: Int
        let hpDelta: Int32
    }

    private let container: ModelContainer
    private let masterData: MasterDataCache
    private var raceLevelCache: [UInt8: Int] = [:]
    private var raceMaxExperienceCache: [UInt8: Int] = [:]

    init(container: ModelContainer, masterData: MasterDataCache) {
        self.container = container
        self.masterData = masterData
    }

    private func notifyCharacterProgressDidChange() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .characterProgressDidChange, object: nil)
        }
    }

    // MARK: - Read Operations

    func allCharacters() async throws -> [CharacterSnapshot] {
        let context = makeContext()
        var descriptor = FetchDescriptor<CharacterRecord>()
        descriptor.sortBy = [SortDescriptor(\CharacterRecord.id, order: .forward)]
        let records = try context.fetch(descriptor)
        return try await makeSnapshots(records, context: context)
    }

    func character(withId id: UInt8) async throws -> CharacterSnapshot? {
        let context = makeContext()
        var descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            return nil
        }
        return try await makeSnapshot(record, context: context)
    }

    func characters(withIds ids: [UInt8]) async throws -> [CharacterSnapshot] {
        guard !ids.isEmpty else { return [] }
        let context = makeContext()
        let descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { ids.contains($0.id) })
        let records = try context.fetch(descriptor)
        let map = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        var ordered: [CharacterRecord] = []
        var missing: [UInt8] = []
        var seen: Set<UInt8> = []
        for id in ids {
            guard let record = map[id] else {
                missing.append(id)
                continue
            }
            if seen.insert(id).inserted {
                ordered.append(record)
            }
        }
        if !missing.isEmpty {
            let identifierList = missing.map { String($0) }.joined(separator: ", ")
            throw ProgressError.invalidInput(description: "キャラクターが見つかりません (ID: \(identifierList))")
        }
        return try await makeSnapshots(ordered, context: context)
    }

    func runtimeCharacter(from snapshot: CharacterSnapshot) async throws -> RuntimeCharacter {
        let input = makeInput(from: snapshot)
        let pandoraStackKeys = try fetchPandoraBoxStackKeys(context: makeContext())
        return try await MainActor.run {
            try RuntimeCharacterFactory.make(
                from: input,
                masterData: masterData,
                pandoraBoxStackKeys: pandoraStackKeys
            )
        }
    }

    /// CharacterSnapshotからCharacterInputへ変換
    private func makeInput(from snapshot: CharacterSnapshot) -> CharacterInput {
        CharacterInput(
            id: snapshot.id,
            displayName: snapshot.displayName,
            raceId: snapshot.raceId,
            jobId: snapshot.jobId,
            previousJobId: snapshot.previousJobId,
            avatarId: snapshot.avatarId,
            level: snapshot.level,
            experience: snapshot.experience,
            currentHP: snapshot.hitPoints.current,
            primaryPersonalityId: snapshot.personality.primaryId,
            secondaryPersonalityId: snapshot.personality.secondaryId,
            actionRateAttack: snapshot.actionPreferences.attack,
            actionRatePriestMagic: snapshot.actionPreferences.priestMagic,
            actionRateMageMagic: snapshot.actionPreferences.mageMagic,
            actionRateBreath: snapshot.actionPreferences.breath,
            updatedAt: snapshot.updatedAt,
            equippedItems: snapshot.equippedItems.map { item in
                CharacterInput.EquippedItem(
                    superRareTitleId: item.superRareTitleId,
                    normalTitleId: item.normalTitleId,
                    itemId: item.itemId,
                    socketSuperRareTitleId: item.socketSuperRareTitleId,
                    socketNormalTitleId: item.socketNormalTitleId,
                    socketItemId: item.socketItemId,
                    quantity: item.quantity
                )
            }
        )
    }

    /// CharacterRecordからCharacterInputを生成（計算なし）。
    /// Progress層からRuntime層へデータを渡すために使用。
    func loadInput(_ record: CharacterRecord, context: ModelContext) throws -> CharacterInput {
        let characterId = record.id
        let equipmentDescriptor = FetchDescriptor<CharacterEquipmentRecord>(
            predicate: #Predicate { $0.characterId == characterId }
        )
        let equipment = try context.fetch(equipmentDescriptor)

        // 装備をグループ化
        var groupedEquipment: [String: (record: CharacterEquipmentRecord, count: Int)] = [:]
        for item in equipment {
            let key = item.stackKey
            if let existing = groupedEquipment[key] {
                groupedEquipment[key] = (existing.record, existing.count + 1)
            } else {
                groupedEquipment[key] = (item, 1)
            }
        }

        let equippedItems = groupedEquipment.values.map { (item, count) in
            CharacterInput.EquippedItem(
                superRareTitleId: item.superRareTitleId,
                normalTitleId: item.normalTitleId,
                itemId: item.itemId,
                socketSuperRareTitleId: item.socketSuperRareTitleId,
                socketNormalTitleId: item.socketNormalTitleId,
                socketItemId: item.socketItemId,
                quantity: count
            )
        }

        return CharacterInput(
            id: record.id,
            displayName: record.displayName,
            raceId: record.raceId,
            jobId: record.jobId,
            previousJobId: record.previousJobId,
            avatarId: record.avatarId,
            level: Int(record.level),
            experience: Int(record.experience),
            currentHP: Int(record.currentHP),
            primaryPersonalityId: record.primaryPersonalityId,
            secondaryPersonalityId: record.secondaryPersonalityId,
            actionRateAttack: Int(record.actionRateAttack),
            actionRatePriestMagic: Int(record.actionRatePriestMagic),
            actionRateMageMagic: Int(record.actionRateMageMagic),
            actionRateBreath: Int(record.actionRateBreath),
            updatedAt: record.updatedAt,
            equippedItems: equippedItems
        )
    }

    // MARK: - Create

    func createCharacter(_ request: CharacterCreationRequest) async throws -> CharacterSnapshot {
        let trimmedName = request.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ProgressError.invalidInput(description: "キャラクター名が設定されていません")
        }

        let context = makeContext()

        // ID採番: 1〜200で最小の未使用IDを割り当てる
        let newId = try allocateCharacterId(context: context)

        // 種族のgenderCodeを取得してavatarIdを計算（職業画像: genderCode * 100 + jobId）
        let race = masterData.race(request.raceId)
        let avatarId: UInt16 = if let race {
            UInt16(race.genderCode) * 100 + UInt16(request.jobId)
        } else {
            0
        }

        let record = CharacterRecord(
            id: newId,
            displayName: trimmedName,
            raceId: request.raceId,
            jobId: request.jobId,
            avatarId: avatarId,
            level: 1,
            experience: 0,
            currentHP: 0,  // makeSnapshot後に正しい値を設定
            primaryPersonalityId: 0,
            secondaryPersonalityId: 0,
            actionRateAttack: 100,
            actionRatePriestMagic: 75,
            actionRateMageMagic: 75,
            actionRateBreath: 50
        )
        context.insert(record)
        try context.save()

        // ステータス計算を行い、maxHPを取得してrecordに書き戻す
        let snapshot = try await makeSnapshot(record, context: context)
        record.currentHP = UInt32(snapshot.hitPoints.maximum)
        try context.save()

        notifyCharacterProgressDidChange()
        return snapshot
    }

    // MARK: - Update

    func updateCharacter(id: UInt8,
                         mutate: @Sendable (inout CharacterSnapshot) throws -> Void) async throws -> CharacterSnapshot {
        let context = makeContext()
        var descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            throw ProgressError.characterNotFound
        }
        var snapshot = try await makeSnapshot(record, context: context)
        try mutate(&snapshot)
        if snapshot.experience < 0 {
            throw ProgressError.invalidInput(description: "経験値は0以上である必要があります")
        }
        let clampedExperience = try await clampExperience(snapshot.experience, raceId: snapshot.raceId)
        snapshot.experience = clampedExperience
        let normalizedLevel = try await resolveLevel(for: clampedExperience, raceId: snapshot.raceId)
        snapshot.level = normalizedLevel
        apply(snapshot: snapshot, to: record)
        try context.save()
        notifyCharacterProgressDidChange()
        return try await makeSnapshot(record, context: context)
    }

    func applyBattleResults(_ updates: [BattleResultUpdate]) async throws {
        guard !updates.isEmpty else { return }
        let context = makeContext()
        let ids = updates.map { $0.characterId }
        let descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { ids.contains($0.id) })
        let records = try context.fetch(descriptor)
        let map = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })

        for update in updates {
            guard let record = map[update.characterId] else {
                throw ProgressError.characterNotFound
            }
            if update.experienceDelta != 0 {
                let previousLevel = record.level
                let addition = Int64(record.experience).addingReportingOverflow(Int64(update.experienceDelta))
                guard !addition.overflow else {
                    throw ProgressError.invalidInput(description: "経験値計算中にオーバーフローが発生しました")
                }
                let updatedExperience = max(0, Int(addition.partialValue))

                let cappedExperience = try await clampExperience(updatedExperience, raceId: record.raceId)
                record.experience = UInt32(cappedExperience)
                let computedLevel = try await resolveLevel(for: cappedExperience, raceId: record.raceId)
                if computedLevel != Int(previousLevel) {
                    record.level = UInt8(computedLevel)
                }
            }
            if update.hpDelta != 0 {
                let newHP = Int64(record.currentHP) + Int64(update.hpDelta)
                record.currentHP = UInt32(max(0, newHP))
            }
        }
        try context.save()
        notifyCharacterProgressDidChange()
    }

    func updateHP(characterId: UInt8, newHP: UInt32) async throws {
        let context = makeContext()
        var descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { $0.id == characterId })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            throw ProgressError.characterNotFound
        }
        record.currentHP = newHP
        try context.save()
        notifyCharacterProgressDidChange()
    }

    // MARK: - Job Change

    /// 転職処理（1回のみ可能、レベル・経験値はリセット）
    /// - Parameters:
    ///   - characterId: キャラクターID
    ///   - newJobId: 新しい職業ID（1〜16: 通常職、101〜116: マスター職）
    /// - Returns: 更新後のスナップショット
    func changeJob(characterId: UInt8, newJobId: UInt8) async throws -> CharacterSnapshot {
        let context = makeContext()
        var descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { $0.id == characterId })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            throw ProgressError.characterNotFound
        }

        // 転職は1回のみ
        if record.previousJobId != 0 {
            throw ProgressError.invalidInput(description: "このキャラクターは既に転職済みです")
        }

        // マスター職（id 101〜116）への転職条件チェック
        if newJobId >= 101 && newJobId <= 116 {
            let baseJobId = newJobId - 100  // 101→1, 102→2, ...
            // 現在の職業が対応する基本職で、かつLv50以上であること
            if record.jobId != baseJobId {
                throw ProgressError.invalidInput(description: "マスター職への転職は元の職業から行う必要があります")
            }
            if record.level < 50 {
                throw ProgressError.invalidInput(description: "マスター職への転職にはLv50以上が必要です")
            }
        }

        // 同じ職業への転職は不可
        if record.jobId == newJobId {
            throw ProgressError.invalidInput(description: "現在と同じ職業には転職できません")
        }

        // 転職実行
        record.previousJobId = record.jobId
        record.jobId = newJobId
        record.level = 1
        record.experience = 0

        // avatarIdを再計算（職業画像: genderCode * 100 + jobId）
        let race = masterData.race(record.raceId)
        if let race {
            record.avatarId = UInt16(race.genderCode) * 100 + UInt16(newJobId)
        }

        try context.save()
        notifyCharacterProgressDidChange()
        return try await makeSnapshot(record, context: context)
    }

    // MARK: - Delete

    func deleteCharacter(id: UInt8) async throws {
        let context = makeContext()
        var descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return }
        try deleteEquipment(for: id, context: context)
        try removeFromParties(characterId: id, context: context)
        context.delete(record)
        try context.save()
        notifyCharacterProgressDidChange()
    }

    // MARK: - Equipment Management

    /// キャラクターにアイテムを装備
    func equipItem(characterId: UInt8, inventoryItemStackKey: String, quantity: Int = 1) async throws -> CharacterSnapshot {
        guard quantity > 0 else {
            throw ProgressError.invalidInput(description: "装備数量は1以上である必要があります")
        }

        let context = makeContext()

        // キャラクターの取得
        var characterDescriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { $0.id == characterId })
        characterDescriptor.fetchLimit = 1
        guard let characterRecord = try context.fetch(characterDescriptor).first else {
            throw ProgressError.invalidInput(description: "キャラクターが見つかりません")
        }

        // インベントリアイテムの取得（stackKeyでマッチング）
        let storage = ItemStorage.playerItem
        let allInventory = try context.fetch(FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.storageRawValue == storage.rawValue
        }))
        guard let inventoryRecord = allInventory.first(where: { $0.stackKey == inventoryItemStackKey }) else {
            throw ProgressError.invalidInput(description: "アイテムが見つかりません")
        }

        guard inventoryRecord.quantity >= quantity else {
            throw ProgressError.invalidInput(description: "アイテム数量が不足しています")
        }

        // 現在の装備数をチェック
        let equipmentDescriptor = FetchDescriptor<CharacterEquipmentRecord>(predicate: #Predicate { $0.characterId == characterId })
        let currentEquipment = try context.fetch(equipmentDescriptor)

        // 装備可能数はレベルベースで計算（スキル修正は後で適用可能）
        let equipmentCapacity = EquipmentSlotCalculator.baseCapacity(forLevel: Int(characterRecord.level))
        if currentEquipment.count + quantity > equipmentCapacity {
            throw ProgressError.invalidInput(description: "装備数が上限(\(equipmentCapacity)個)を超えます")
        }

        // 装備レコード作成（1アイテム1レコード、quantityなし）
        for _ in 0..<quantity {
            let equipmentRecord = CharacterEquipmentRecord(
                characterId: characterId,
                superRareTitleId: inventoryRecord.superRareTitleId,
                normalTitleId: inventoryRecord.normalTitleId,
                itemId: inventoryRecord.itemId,
                socketSuperRareTitleId: inventoryRecord.socketSuperRareTitleId,
                socketNormalTitleId: inventoryRecord.socketNormalTitleId,
                socketItemId: inventoryRecord.socketItemId
            )
            context.insert(equipmentRecord)
        }

        // インベントリから減算
        inventoryRecord.quantity -= UInt16(quantity)
        if inventoryRecord.quantity <= 0 {
            context.delete(inventoryRecord)
        }

        try context.save()

        notifyCharacterProgressDidChange()
        return try await makeSnapshot(characterRecord, context: context)
    }

    /// キャラクターからアイテムを解除（stackKeyで指定、quantity個）
    func unequipItem(characterId: UInt8, equipmentStackKey: String, quantity: Int = 1) async throws -> CharacterSnapshot {
        guard quantity > 0 else {
            throw ProgressError.invalidInput(description: "解除数量は1以上である必要があります")
        }

        let context = makeContext()

        // キャラクターの取得
        var characterDescriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { $0.id == characterId })
        characterDescriptor.fetchLimit = 1
        guard let characterRecord = try context.fetch(characterDescriptor).first else {
            throw ProgressError.invalidInput(description: "キャラクターが見つかりません")
        }

        // 装備レコードの取得（同じstackKeyのものを探す）
        let equipmentDescriptor = FetchDescriptor<CharacterEquipmentRecord>(predicate: #Predicate { $0.characterId == characterId })
        let allEquipment = try context.fetch(equipmentDescriptor)
        let matchingEquipment = allEquipment.filter { $0.stackKey == equipmentStackKey }

        guard matchingEquipment.count >= quantity else {
            throw ProgressError.invalidInput(description: "解除数量が装備数を超えています")
        }

        let storage = ItemStorage.playerItem

        // インベントリに戻す（同じstackKeyのアイテムを探す）
        let allInventory = try context.fetch(FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.storageRawValue == storage.rawValue
        }))

        if let existingInventory = allInventory.first(where: { $0.stackKey == equipmentStackKey }) {
            // 既存スタックに追加
            existingInventory.quantity = min(existingInventory.quantity + UInt16(quantity), 99)
        } else if let firstEquip = matchingEquipment.first {
            // 新規インベントリレコード作成
            let inventoryRecord = InventoryItemRecord(
                superRareTitleId: firstEquip.superRareTitleId,
                normalTitleId: firstEquip.normalTitleId,
                itemId: firstEquip.itemId,
                socketSuperRareTitleId: firstEquip.socketSuperRareTitleId,
                socketNormalTitleId: firstEquip.socketNormalTitleId,
                socketItemId: firstEquip.socketItemId,
                quantity: UInt16(quantity),
                storage: storage
            )
            context.insert(inventoryRecord)
        }

        // 装備レコードを削除（quantity個）
        for i in 0..<quantity {
            context.delete(matchingEquipment[i])
        }

        try context.save()

        notifyCharacterProgressDidChange()
        return try await makeSnapshot(characterRecord, context: context)
    }

    /// キャラクターの装備一覧を取得
    func equippedItems(characterId: UInt8) async throws -> [CharacterSnapshot.EquippedItem] {
        let context = makeContext()
        let descriptor = FetchDescriptor<CharacterEquipmentRecord>(predicate: #Predicate { $0.characterId == characterId })
        let records = try context.fetch(descriptor)

        // stackKeyでグループ化してquantityを計算
        var grouped: [String: (record: CharacterEquipmentRecord, count: Int)] = [:]
        for record in records {
            let key = record.stackKey
            if let existing = grouped[key] {
                grouped[key] = (existing.record, existing.count + 1)
            } else {
                grouped[key] = (record, 1)
            }
        }

        return grouped.values.map { (record, count) in
            CharacterSnapshot.EquippedItem(
                superRareTitleId: record.superRareTitleId,
                normalTitleId: record.normalTitleId,
                itemId: record.itemId,
                socketSuperRareTitleId: record.socketSuperRareTitleId,
                socketNormalTitleId: record.socketNormalTitleId,
                socketItemId: record.socketItemId,
                quantity: count
            )
        }
    }
}

// MARK: - Private Helpers

private extension CharacterProgressService {
    func resolveLevel(for experience: Int, raceId: UInt8) async throws -> Int {
        let maxLevel = try raceMaxLevel(for: raceId)
        do {
            return try await MainActor.run {
                try CharacterExperienceTable.level(forTotalExperience: experience, maximumLevel: maxLevel)
            }
        } catch CharacterExperienceError.invalidLevel {
            throw ProgressError.invalidInput(description: "経験値テーブルに無効なレベル要求が行われました")
        } catch CharacterExperienceError.invalidExperience {
            throw ProgressError.invalidInput(description: "経験値が負の値になる操作は許可されていません")
        } catch CharacterExperienceError.overflowedComputation {
            throw ProgressError.invalidInput(description: "経験値計算中にオーバーフローが発生しました")
        }
    }

    func raceMaxLevel(for raceId: UInt8) throws -> Int {
        if let cached = raceLevelCache[raceId] {
            return cached
        }
        guard let definition = masterData.race(raceId) else {
            throw ProgressError.invalidInput(description: "種族マスタに存在しないIDです (\(raceId))")
        }
        let resolved = definition.maxLevel
        raceLevelCache[raceId] = resolved
        return resolved
    }

    func clampExperience(_ experience: Int, raceId: UInt8) async throws -> Int {
        guard experience > 0 else { return 0 }
        let maximum = try await raceMaxExperience(for: raceId)
        return min(experience, maximum)
    }

    func raceMaxExperience(for raceId: UInt8) async throws -> Int {
        if let cached = raceMaxExperienceCache[raceId] {
            return cached
        }
        let maxLevel = try raceMaxLevel(for: raceId)
        let maximumExperience = try await MainActor.run {
            try CharacterExperienceTable.totalExperience(toReach: maxLevel)
        }
        raceMaxExperienceCache[raceId] = maximumExperience
        return maximumExperience
    }

    func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    func makeSnapshots(_ records: [CharacterRecord], context: ModelContext) async throws -> [CharacterSnapshot] {
        var snapshots: [CharacterSnapshot] = []
        snapshots.reserveCapacity(records.count)
        for record in records {
            let snapshot = try await makeSnapshot(record, context: context)
            snapshots.append(snapshot)
        }
        return snapshots
    }

    func makeSnapshot(_ record: CharacterRecord, context: ModelContext) async throws -> CharacterSnapshot {
        // CharacterInput を作成
        let input = try loadInput(record, context: context)

        // RuntimeCharacterFactory で計算済み RuntimeCharacter を取得
        let pandoraStackKeys = try fetchPandoraBoxStackKeys(context: context)
        let runtimeCharacter = try await MainActor.run {
            try RuntimeCharacterFactory.make(
                from: input,
                masterData: masterData,
                pandoraBoxStackKeys: pandoraStackKeys
            )
        }

        // RuntimeCharacter から CharacterSnapshot を構築
        let now = Date()

        func clamp(_ value: Int) -> Int {
            max(0, min(100, value))
        }
        let actionPreferences = CharacterSnapshot.ActionPreferences(
            attack: clamp(runtimeCharacter.actionRateAttack),
            priestMagic: clamp(runtimeCharacter.actionRatePriestMagic),
            mageMagic: clamp(runtimeCharacter.actionRateMageMagic),
            breath: clamp(runtimeCharacter.actionRateBreath)
        )

        let personality = CharacterSnapshot.Personality(
            primaryId: runtimeCharacter.primaryPersonalityId,
            secondaryId: runtimeCharacter.secondaryPersonalityId
        )

        let equippedItems = runtimeCharacter.equippedItems.map { item in
            CharacterSnapshot.EquippedItem(
                superRareTitleId: item.superRareTitleId,
                normalTitleId: item.normalTitleId,
                itemId: item.itemId,
                socketSuperRareTitleId: item.socketSuperRareTitleId,
                socketNormalTitleId: item.socketNormalTitleId,
                socketItemId: item.socketItemId,
                quantity: item.quantity
            )
        }

        let attributes = CharacterSnapshot.CoreAttributes(
            strength: runtimeCharacter.attributes.strength,
            wisdom: runtimeCharacter.attributes.wisdom,
            spirit: runtimeCharacter.attributes.spirit,
            vitality: runtimeCharacter.attributes.vitality,
            agility: runtimeCharacter.attributes.agility,
            luck: runtimeCharacter.attributes.luck
        )

        let hitPoints = CharacterSnapshot.HitPoints(
            current: runtimeCharacter.currentHP,
            maximum: runtimeCharacter.maxHP
        )

        let combat = CharacterSnapshot.Combat(
            maxHP: runtimeCharacter.combat.maxHP,
            physicalAttack: runtimeCharacter.combat.physicalAttack,
            magicalAttack: runtimeCharacter.combat.magicalAttack,
            physicalDefense: runtimeCharacter.combat.physicalDefense,
            magicalDefense: runtimeCharacter.combat.magicalDefense,
            hitRate: runtimeCharacter.combat.hitRate,
            evasionRate: runtimeCharacter.combat.evasionRate,
            criticalRate: runtimeCharacter.combat.criticalRate,
            attackCount: runtimeCharacter.combat.attackCount,
            magicalHealing: runtimeCharacter.combat.magicalHealing,
            trapRemoval: runtimeCharacter.combat.trapRemoval,
            additionalDamage: runtimeCharacter.combat.additionalDamage,
            breathDamage: runtimeCharacter.combat.breathDamage,
            isMartialEligible: runtimeCharacter.combat.isMartialEligible
        )

        return CharacterSnapshot(
            id: runtimeCharacter.id,
            displayName: runtimeCharacter.displayName,
            raceId: runtimeCharacter.raceId,
            jobId: runtimeCharacter.jobId,
            previousJobId: runtimeCharacter.previousJobId,
            avatarId: runtimeCharacter.avatarId,
            level: runtimeCharacter.level,
            experience: runtimeCharacter.experience,
            attributes: attributes,
            hitPoints: hitPoints,
            combat: combat,
            personality: personality,
            equippedItems: equippedItems,
            actionPreferences: actionPreferences,
            createdAt: now,
            updatedAt: now
        )
    }

    func apply(snapshot: CharacterSnapshot, to record: CharacterRecord) {
        record.displayName = snapshot.displayName
        record.avatarId = snapshot.avatarId
        record.level = UInt8(snapshot.level)
        record.experience = UInt32(snapshot.experience)
        record.currentHP = UInt32(snapshot.hitPoints.current)
        record.actionRateAttack = UInt8(snapshot.actionPreferences.attack)
        record.actionRatePriestMagic = UInt8(snapshot.actionPreferences.priestMagic)
        record.actionRateMageMagic = UInt8(snapshot.actionPreferences.mageMagic)
        record.actionRateBreath = UInt8(snapshot.actionPreferences.breath)
        // raceId, jobId, personalityIdは変更しない（種族・職業変更は別APIで）
    }

    func deleteEquipment(for characterId: UInt8, context: ModelContext) throws {
        let equipmentDescriptor = FetchDescriptor<CharacterEquipmentRecord>(predicate: #Predicate { $0.characterId == characterId })
        for record in try context.fetch(equipmentDescriptor) {
            context.delete(record)
        }
    }

    /// 1〜200の範囲で最小の未使用IDを割り当てる
    func allocateCharacterId(context: ModelContext) throws -> UInt8 {
        let occupied = Set(try context.fetch(FetchDescriptor<CharacterRecord>()).map(\.id))
        guard let id = (1...200).lazy.map(UInt8.init).first(where: { !occupied.contains($0) }) else {
            throw ProgressError.invalidInput(description: "キャラクター数が上限（200体）に達しています")
        }
        return id
    }

    func removeFromParties(characterId: UInt8, context: ModelContext) throws {
        let descriptor = FetchDescriptor<PartyRecord>()
        let parties = try context.fetch(descriptor)
        let now = Date()
        for party in parties {
            if party.memberCharacterIds.contains(characterId) {
                party.memberCharacterIds.removeAll { $0 == characterId }
                party.updatedAt = now
            }
        }
    }

    func fetchPandoraBoxStackKeys(context: ModelContext) throws -> Set<String> {
        var descriptor = FetchDescriptor<GameStateRecord>()
        descriptor.fetchLimit = 1
        guard let gameState = try context.fetch(descriptor).first else {
            throw ProgressError.playerNotFound
        }
        return Set(gameState.pandoraBoxStackKeys)
    }
}
