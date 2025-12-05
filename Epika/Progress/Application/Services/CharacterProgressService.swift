import Foundation
import SwiftData

actor CharacterProgressService {
    struct CharacterCreationRequest: Sendable {
        var displayName: String
        var raceId: String
        var jobId: String
    }

    struct BattleResultUpdate: Sendable {
        let characterId: UInt8
        let experienceDelta: Int
        let hpDelta: Int32
    }

    private let container: ModelContainer
    private let runtime: ProgressRuntimeService
    private var raceLevelCache: [String: Int] = [:]
    private var raceMaxExperienceCache: [String: Int] = [:]

    init(container: ModelContainer, runtime: ProgressRuntimeService) {
        self.container = container
        self.runtime = runtime
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
        try await runtime.runtimeCharacter(from: snapshot)
    }

    // MARK: - Create

    func createCharacter(_ request: CharacterCreationRequest) async throws -> CharacterSnapshot {
        let trimmedName = request.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ProgressError.invalidInput(description: "キャラクター名を入力してください")
        }

        let masterData = MasterDataRuntimeService.shared
        guard let raceIndex = await masterData.getRaceIndex(for: request.raceId) else {
            throw ProgressError.invalidInput(description: "無効な種族IDです")
        }
        guard let jobIndex = await masterData.getJobIndex(for: request.jobId) else {
            throw ProgressError.invalidInput(description: "無効な職業IDです")
        }

        let context = makeContext()

        // ID採番: 1〜200で最小の未使用IDを割り当てる
        let newId = try allocateCharacterId(context: context)

        // 初期HPは一旦100を設定（最初のmakeSnapshotで再計算される）
        let initialHP: Int32 = 100

        let record = CharacterRecord(
            id: newId,
            displayName: trimmedName,
            raceIndex: raceIndex,
            jobIndex: jobIndex,
            level: 1,
            experience: 0,
            currentHP: initialHP,
            primaryPersonalityIndex: 0,
            secondaryPersonalityIndex: 0,
            actionRateAttack: 100,
            actionRatePriestMagic: 75,
            actionRateMageMagic: 75,
            actionRateBreath: 50
        )
        context.insert(record)
        try context.save()
        notifyCharacterProgressDidChange()
        return try await makeSnapshot(record, context: context)
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

        let masterData = MasterDataRuntimeService.shared

        for update in updates {
            guard let record = map[update.characterId] else {
                throw ProgressError.characterNotFound
            }
            if update.experienceDelta != 0 {
                let previousLevel = record.level
                let addition = Int32(record.experience).addingReportingOverflow(Int32(update.experienceDelta))
                guard !addition.overflow else {
                    throw ProgressError.invalidInput(description: "経験値計算中にオーバーフローが発生しました")
                }
                let updatedExperience = max(0, Int(addition.partialValue))

                // raceIdを取得
                guard let raceId = await masterData.getRaceId(for: record.raceIndex) else {
                    throw ProgressError.invalidInput(description: "種族情報が見つかりません")
                }

                let cappedExperience = try await clampExperience(updatedExperience, raceId: raceId)
                record.experience = Int32(cappedExperience)
                let computedLevel = try await resolveLevel(for: cappedExperience, raceId: raceId)
                if computedLevel != Int(previousLevel) {
                    record.level = UInt8(computedLevel)
                }
            }
            if update.hpDelta != 0 {
                let newHP = Int32(record.currentHP) + update.hpDelta
                record.currentHP = max(0, newHP)
            }
        }
        try context.save()
        notifyCharacterProgressDidChange()
    }

    func updateHP(characterId: UInt8, newHP: Int32) async throws {
        let context = makeContext()
        var descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { $0.id == characterId })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            throw ProgressError.characterNotFound
        }
        record.currentHP = max(0, newHP)
        try context.save()
        notifyCharacterProgressDidChange()
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

        if currentEquipment.count + quantity > EquipmentProgressService.maxEquippedItems {
            throw ProgressError.invalidInput(description: "装備数が上限(\(EquipmentProgressService.maxEquippedItems)個)を超えます")
        }

        // 装備レコード作成（1アイテム1レコード、quantityなし）
        for _ in 0..<quantity {
            let equipmentRecord = CharacterEquipmentRecord(
                characterId: characterId,
                superRareTitleIndex: inventoryRecord.superRareTitleIndex,
                normalTitleIndex: inventoryRecord.normalTitleIndex,
                masterDataIndex: inventoryRecord.masterDataIndex,
                socketSuperRareTitleIndex: inventoryRecord.socketSuperRareTitleIndex,
                socketNormalTitleIndex: inventoryRecord.socketNormalTitleIndex,
                socketMasterDataIndex: inventoryRecord.socketMasterDataIndex
            )
            context.insert(equipmentRecord)
        }

        // インベントリから減算
        inventoryRecord.quantity -= quantity
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
            existingInventory.quantity = min(existingInventory.quantity + quantity, 99)
        } else if let firstEquip = matchingEquipment.first {
            // 新規インベントリレコード作成
            let inventoryRecord = InventoryItemRecord(
                superRareTitleIndex: firstEquip.superRareTitleIndex,
                normalTitleIndex: firstEquip.normalTitleIndex,
                masterDataIndex: firstEquip.masterDataIndex,
                socketSuperRareTitleIndex: firstEquip.socketSuperRareTitleIndex,
                socketNormalTitleIndex: firstEquip.socketNormalTitleIndex,
                socketMasterDataIndex: firstEquip.socketMasterDataIndex,
                quantity: quantity,
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
                superRareTitleIndex: record.superRareTitleIndex,
                normalTitleIndex: record.normalTitleIndex,
                masterDataIndex: record.masterDataIndex,
                socketSuperRareTitleIndex: record.socketSuperRareTitleIndex,
                socketNormalTitleIndex: record.socketNormalTitleIndex,
                socketMasterDataIndex: record.socketMasterDataIndex,
                quantity: count
            )
        }
    }
}

// MARK: - Private Helpers

private extension CharacterProgressService {
    func resolveLevel(for experience: Int, raceId: String) async throws -> Int {
        let maxLevel = try await raceMaxLevel(for: raceId)
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

    func raceMaxLevel(for raceId: String) async throws -> Int {
        if let cached = raceLevelCache[raceId] {
            return cached
        }
        let resolved = try await runtime.raceMaxLevel(for: raceId)
        raceLevelCache[raceId] = resolved
        return resolved
    }

    func clampExperience(_ experience: Int, raceId: String) async throws -> Int {
        guard experience > 0 else { return 0 }
        let maximum = try await raceMaxExperience(for: raceId)
        return min(experience, maximum)
    }

    func raceMaxExperience(for raceId: String) async throws -> Int {
        if let cached = raceMaxExperienceCache[raceId] {
            return cached
        }
        let maxLevel = try await raceMaxLevel(for: raceId)
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
        let characterId = record.id
        let equipmentDescriptor = FetchDescriptor<CharacterEquipmentRecord>(predicate: #Predicate { $0.characterId == characterId })
        let equipment = try context.fetch(equipmentDescriptor)

        let masterData = MasterDataRuntimeService.shared

        // Index → ID 変換
        guard let raceId = await masterData.getRaceId(for: record.raceIndex) else {
            throw ProgressError.invalidInput(description: "種族情報が見つかりません")
        }
        guard let jobId = await masterData.getJobId(for: record.jobIndex) else {
            throw ProgressError.invalidInput(description: "職業情報が見つかりません")
        }

        let primaryPersonalityId: String?
        if record.primaryPersonalityIndex > 0 {
            primaryPersonalityId = await masterData.getPrimaryPersonalityId(for: record.primaryPersonalityIndex)
        } else {
            primaryPersonalityId = nil
        }

        let secondaryPersonalityId: String?
        if record.secondaryPersonalityIndex > 0 {
            secondaryPersonalityId = await masterData.getSecondaryPersonalityId(for: record.secondaryPersonalityIndex)
        } else {
            secondaryPersonalityId = nil
        }

        // 種族から性別を導出
        let gender: String
        let allRaces = try await masterData.getAllRaces()
        if let raceDefinition = allRaces.first(where: { $0.id == raceId }) {
            gender = raceDefinition.gender
        } else {
            gender = "other"
        }

        // アバター識別子を導出
        let avatarIdentifier = try await resolveAvatarIdentifier(jobId: jobId, genderRawValue: gender)

        // 装備をスナップショット形式に変換（グループ化）
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
            CharacterSnapshot.EquippedItem(
                superRareTitleIndex: item.superRareTitleIndex,
                normalTitleIndex: item.normalTitleIndex,
                masterDataIndex: item.masterDataIndex,
                socketSuperRareTitleIndex: item.socketSuperRareTitleIndex,
                socketNormalTitleIndex: item.socketNormalTitleIndex,
                socketMasterDataIndex: item.socketMasterDataIndex,
                quantity: count
            )
        }

        func clamp(_ value: UInt8) -> Int {
            max(0, min(100, Int(value)))
        }
        let actionPreferences = CharacterSnapshot.ActionPreferences(
            attack: clamp(record.actionRateAttack),
            priestMagic: clamp(record.actionRatePriestMagic),
            mageMagic: clamp(record.actionRateMageMagic),
            breath: clamp(record.actionRateBreath)
        )

        let personality = CharacterSnapshot.Personality(
            primaryId: primaryPersonalityId,
            secondaryId: secondaryPersonalityId
        )

        // スキルは種族+職業+装備から導出（learnedSkillsは空配列）
        let learnedSkills: [CharacterSnapshot.LearnedSkill] = []

        // jobHistory, explorationTags, achievementsは廃止（空）
        let jobHistory: [CharacterSnapshot.JobHistoryEntry] = []
        let explorationTags: Set<String> = []
        let achievements = CharacterSnapshot.AchievementCounters(
            totalBattles: 0,
            totalVictories: 0,
            defeatCount: 0
        )

        let now = Date()

        // まずダミーの戦闘ステータスでsnapshotを作成
        let dummyAttributes = CharacterSnapshot.CoreAttributes(
            strength: 10, wisdom: 10, spirit: 10, vitality: 10, agility: 10, luck: 10
        )
        let dummyHitPoints = CharacterSnapshot.HitPoints(current: Int(record.currentHP), maximum: 100)
        let dummyCombat = CharacterSnapshot.Combat(
            maxHP: 100, physicalAttack: 0, magicalAttack: 0,
            physicalDefense: 0, magicalDefense: 0, hitRate: 0, evasionRate: 0,
            criticalRate: 0, attackCount: 1, magicalHealing: 0, trapRemoval: 0,
            additionalDamage: 0, breathDamage: 0, isMartialEligible: false
        )

        var snapshot = CharacterSnapshot(
            persistentIdentifier: record.persistentModelID,
            id: record.id,
            displayName: record.displayName,
            raceId: raceId,
            gender: gender,
            jobId: jobId,
            avatarIdentifier: avatarIdentifier,
            level: Int(record.level),
            experience: Int(record.experience),
            attributes: dummyAttributes,
            hitPoints: dummyHitPoints,
            combat: dummyCombat,
            personality: personality,
            learnedSkills: learnedSkills,
            equippedItems: equippedItems,
            jobHistory: jobHistory,
            explorationTags: explorationTags,
            achievements: achievements,
            actionPreferences: actionPreferences,
            createdAt: now,
            updatedAt: now
        )

        // 戦闘ステータスを再計算
        let pandoraStackKeys = try fetchPandoraBoxStackKeys(context: context)
        let combatResult = try await runtime.recalculateCombatSnapshot(for: snapshot, pandoraBoxStackKeys: pandoraStackKeys)

        // 計算結果を反映
        snapshot.attributes = CharacterSnapshot.CoreAttributes(
            strength: combatResult.attributes.strength,
            wisdom: combatResult.attributes.wisdom,
            spirit: combatResult.attributes.spirit,
            vitality: combatResult.attributes.vitality,
            agility: combatResult.attributes.agility,
            luck: combatResult.attributes.luck
        )
        snapshot.hitPoints = CharacterSnapshot.HitPoints(
            current: min(Int(record.currentHP), combatResult.hitPoints.maximum),
            maximum: combatResult.hitPoints.maximum
        )
        snapshot.combat = CharacterSnapshot.Combat(
            maxHP: combatResult.combat.maxHP,
            physicalAttack: combatResult.combat.physicalAttack,
            magicalAttack: combatResult.combat.magicalAttack,
            physicalDefense: combatResult.combat.physicalDefense,
            magicalDefense: combatResult.combat.magicalDefense,
            hitRate: combatResult.combat.hitRate,
            evasionRate: combatResult.combat.evasionRate,
            criticalRate: combatResult.combat.criticalRate,
            attackCount: combatResult.combat.attackCount,
            magicalHealing: combatResult.combat.magicalHealing,
            trapRemoval: combatResult.combat.trapRemoval,
            additionalDamage: combatResult.combat.additionalDamage,
            breathDamage: combatResult.combat.breathDamage,
            isMartialEligible: combatResult.combat.isMartialEligible
        )

        return snapshot
    }

    func resolveAvatarIdentifier(jobId: String, genderRawValue: String) async throws -> String {
        do {
            return try await MainActor.run {
                try CharacterAvatarIdentifierResolver.defaultAvatarIdentifier(jobId: jobId,
                                                                              genderRawValue: genderRawValue)
            }
        } catch let resolverError as CharacterAvatarIdentifierResolverError {
            let message = resolverError.errorDescription ?? resolverError.localizedDescription
            throw ProgressError.invalidInput(description: message)
        } catch {
            throw error
        }
    }

    func apply(snapshot: CharacterSnapshot, to record: CharacterRecord) {
        record.displayName = snapshot.displayName
        record.level = UInt8(snapshot.level)
        record.experience = Int32(snapshot.experience)
        record.currentHP = Int32(snapshot.hitPoints.current)
        record.actionRateAttack = UInt8(snapshot.actionPreferences.attack)
        record.actionRatePriestMagic = UInt8(snapshot.actionPreferences.priestMagic)
        record.actionRateMageMagic = UInt8(snapshot.actionPreferences.mageMagic)
        record.actionRateBreath = UInt8(snapshot.actionPreferences.breath)
        // raceIndex, jobIndex, personalityIndexは変更しない（種族・職業変更は別APIで）
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
