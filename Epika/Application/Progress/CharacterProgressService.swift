// ==============================================================================
// CharacterProgressService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクターCRUD操作
//   - 装備管理（装着・解除）
//   - 転職処理
//   - 戦闘結果適用（経験値・HP）
//   - RuntimeCharacter生成
//
// 【公開API - 読み取り】
//   - allCharacters() → [CharacterSnapshot]
//   - character(withId:) → CharacterSnapshot?
//   - characters(withIds:) → [CharacterSnapshot]
//   - runtimeCharacter(from:) → RuntimeCharacter
//
// 【公開API - 書き込み】
//   - createCharacter(request:) → CharacterSnapshot
//   - createCharactersBatch(requests:) - デバッグ用バッチ作成
//   - deleteCharacter(id:)
//   - changeJob(characterId:newJobId:) → CharacterSnapshot
//   - equipItem(characterId:inventoryItemStackKey:) → CharacterSnapshot
//   - unequipItem(characterId:equipmentStackKey:) → CharacterSnapshot
//   - unequipAllItems(characterId:) → CharacterSnapshot
//   - applyBattleResults(_:) - 経験値・HP変更を一括適用
//   - healToFull(characterIds:) - HP全回復
//   - reviveCharacter(id:) → CharacterSnapshot
//
// 【補助型】
//   - CharacterCreationRequest: 作成リクエスト
//   - BattleResultUpdate: 戦闘結果更新
//
// 【キャッシュ】
//   - raceLevelCache: 種族別最大レベル
//   - raceMaxExperienceCache: 種族別最大経験値
//
// ==============================================================================

import Foundation
import SwiftData

@MainActor
final class CharacterProgressService {
    struct CharacterCreationRequest: Sendable {
        var displayName: String
        var raceId: UInt8
        var jobId: UInt8
    }

    /// デバッグ用バッチ作成リクエスト
    struct DebugCharacterCreationRequest: Sendable {
        var displayName: String
        var raceId: UInt8
        var jobId: UInt8
        var previousJobId: UInt8
        var level: Int
    }

    struct BattleResultUpdate: Sendable {
        let characterId: UInt8
        let experienceDelta: Int
        let hpDelta: Int32
    }

    @MainActor
    final class BattleResultSession {
        private unowned let service: CharacterProgressService
        fileprivate let context: ModelContext
        fileprivate let records: [UInt8: CharacterRecord]
        private var pendingLevelUpNotification = false

        fileprivate init(service: CharacterProgressService, characterIds: [UInt8]) throws {
            self.service = service
            self.context = service.makeContext()
            if characterIds.isEmpty {
                self.records = [:]
                return
            }

            let ids = Array(Set(characterIds))
            let descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { ids.contains($0.id) })
            let fetched = try context.fetch(descriptor)
            self.records = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        }

        func applyBattleResults(_ updates: [BattleResultUpdate]) throws {
            guard !updates.isEmpty else { return }
            let levelUp = try service.applyBattleResultsInternal(updates,
                                                                 records: records)
            if levelUp {
                pendingLevelUpNotification = true
            }
        }

        func flushIfNeeded() throws {
            guard context.hasChanges else { return }
            try context.save()
            if pendingLevelUpNotification {
                service.notifyCharacterProgressDidChange()
                pendingLevelUpNotification = false
            }
        }
    }

    private let contextProvider: SwiftDataContextProvider
    private let masterData: MasterDataCache
    private var raceLevelCache: [UInt8: Int] = [:]
    private var raceMaxExperienceCache: [UInt8: Int] = [:]

    init(contextProvider: SwiftDataContextProvider, masterData: MasterDataCache) {
        self.contextProvider = contextProvider
        self.masterData = masterData
    }

    private func notifyCharacterProgressDidChange() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .characterProgressDidChange, object: nil)
        }
    }

    // MARK: - Read Operations

    func allCharacters() throws -> [CharacterSnapshot] {
        let context = makeContext()
        var descriptor = FetchDescriptor<CharacterRecord>()
        descriptor.sortBy = [SortDescriptor(\CharacterRecord.displayOrder, order: .forward)]
        let records = try context.fetch(descriptor)
        return try makeSnapshots(records, context: context)
    }

    func character(withId id: UInt8) throws -> CharacterSnapshot? {
        let context = makeContext()
        var descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            return nil
        }
        return try makeSnapshot(record, context: context)
    }

    func characters(withIds ids: [UInt8]) throws -> [CharacterSnapshot] {
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
        return try makeSnapshots(ordered, context: context)
    }

    func runtimeCharacter(from snapshot: CharacterSnapshot) throws -> RuntimeCharacter {
        let input = makeInput(from: snapshot)
        let pandoraStackKeys = try fetchPandoraBoxStackKeys(context: makeContext())
        return try RuntimeCharacterFactory.make(
            from: input,
            masterData: masterData,
            pandoraBoxStackKeys: pandoraStackKeys
        )
    }

    /// 装備変更時の高速RuntimeCharacter再構築
    /// 既存のRuntimeCharacterからマスターデータを再利用し、装備関連のみを再計算する
    nonisolated func runtimeCharacterWithEquipmentChange(
        current: RuntimeCharacter,
        newEquippedItems: [CharacterInput.EquippedItem]
    ) throws -> RuntimeCharacter {
        try RuntimeCharacterFactory.withEquipmentChange(
            current: current,
            newEquippedItems: newEquippedItems,
            masterData: masterData
        )
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
            displayOrder: snapshot.displayOrder,
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
            displayOrder: record.displayOrder,
            equippedItems: equippedItems
        )
    }

    // MARK: - Create

    func createCharacter(_ request: CharacterCreationRequest) throws -> CharacterSnapshot {
        let trimmedName = request.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ProgressError.invalidInput(description: "キャラクター名が設定されていません")
        }

        let context = makeContext()

        // ID採番: 1〜200で最小の未使用IDを割り当てる
        let newId = try allocateCharacterId(context: context)

        // displayOrder採番: 既存の最大値+1
        let newDisplayOrder = try allocateDisplayOrder(context: context)

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
        record.displayOrder = newDisplayOrder
        context.insert(record)
        try context.save()

        // ステータス計算を行い、maxHPを取得してrecordに書き戻す
        let snapshot = try makeSnapshot(record, context: context)
        record.currentHP = UInt32(snapshot.hitPoints.maximum)
        try context.save()

        notifyCharacterProgressDidChange()
        return snapshot
    }

    /// デバッグ用: 複数キャラクターを一括作成
    /// - Parameter requests: 作成リクエスト配列
    /// - Parameter onProgress: 進捗コールバック (current, total)
    /// - Returns: 作成されたキャラクター数
    func createCharactersBatch(
        _ requests: [DebugCharacterCreationRequest],
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> Int {
        guard !requests.isEmpty else { return 0 }
        let context = makeContext()

        // 使用可能なIDを確保
        let occupied = Set(try context.fetch(FetchDescriptor<CharacterRecord>()).map(\.id))
        let availableCount = (1...200).filter { !occupied.contains(UInt8($0)) }.count
        if availableCount < requests.count {
            throw ProgressError.invalidInput(
                description: "キャラクター数が上限に達しています（空き: \(availableCount), 要求: \(requests.count)）"
            )
        }
        let availableIds = (1...200).lazy.map(UInt8.init).filter { !occupied.contains($0) }
        var idIterator = availableIds.makeIterator()

        // 現在の最大displayOrderを取得（UInt8なので255を超えないようにクランプ）
        let existingRecords = try context.fetch(FetchDescriptor<CharacterRecord>())
        let maxDisplayOrder = existingRecords.map { Int($0.displayOrder) }.max() ?? 0
        var displayOrder = min(maxDisplayOrder + 1, 255)

        var createdIds: [UInt8] = []
        let total = requests.count

        for request in requests {
            guard let newId = idIterator.next() else {
                throw ProgressError.invalidInput(description: "キャラクターIDの割り当てに失敗しました")
            }

            // 種族・職業の存在チェック
            guard let race = masterData.race(request.raceId) else {
                throw ProgressError.invalidInput(description: "種族ID \(request.raceId) のマスターデータが見つかりません")
            }
            guard masterData.job(request.jobId) != nil else {
                throw ProgressError.invalidInput(description: "職業ID \(request.jobId) のマスターデータが見つかりません")
            }

            // 前職の存在チェック（0以外の場合）
            if request.previousJobId > 0 {
                guard masterData.job(request.previousJobId) != nil else {
                    throw ProgressError.invalidInput(description: "前職ID \(request.previousJobId) のマスターデータが見つかりません")
                }
            }

            // レベルの入力検証（1未満はエラー、種族最大超過はクランプ）
            if request.level < 1 {
                throw ProgressError.invalidInput(description: "レベルは1以上である必要があります（入力: \(request.level)）")
            }
            let effectiveLevel = min(request.level, min(race.maxLevel, 255))

            let avatarId = UInt16(race.genderCode) * 100 + UInt16(request.jobId)

            // 指定レベルに必要な経験値を計算
            let experience: UInt64
            if effectiveLevel > 1 {
                let rawExperience = try CharacterExperienceTable.totalExperience(toReach: effectiveLevel)
                experience = UInt64(rawExperience)
            } else {
                experience = 0
            }

            let record = CharacterRecord(
                id: newId,
                displayName: request.displayName,
                raceId: request.raceId,
                jobId: request.jobId,
                previousJobId: request.previousJobId,
                avatarId: avatarId,
                level: UInt8(effectiveLevel),
                experience: experience,
                currentHP: 0,
                primaryPersonalityId: 0,
                secondaryPersonalityId: 0,
                actionRateAttack: 100,
                actionRatePriestMagic: 75,
                actionRateMageMagic: 75,
                actionRateBreath: 50
            )
            record.displayOrder = UInt8(displayOrder)
            if displayOrder < 255 { displayOrder += 1 }
            context.insert(record)

            createdIds.append(newId)
            await onProgress?(createdIds.count, total)
        }

        try context.save()

        // HP設定（新規作成分のみmaxHPで初期化）
        let createdIdSet = Set(createdIds)
        let allRecords = try context.fetch(FetchDescriptor<CharacterRecord>())
        // デバッグ用バッチ作成ではGameStateがない可能性があるため、エラー時は空セットを使用
        let pandoraStackKeys = (try? fetchPandoraBoxStackKeys(context: context)) ?? []
        for record in allRecords where createdIdSet.contains(record.id) {
            let input = try loadInput(record, context: context)
            let runtimeCharacter = try RuntimeCharacterFactory.make(from: input, masterData: masterData, pandoraBoxStackKeys: pandoraStackKeys)
            record.currentHP = UInt32(runtimeCharacter.maxHP)
        }
        try context.save()

        notifyCharacterProgressDidChange()
        return createdIds.count
    }

    // MARK: - Update

    func updateCharacter(id: UInt8,
                         mutate: @Sendable (inout CharacterSnapshot) throws -> Void) throws -> CharacterSnapshot {
        let context = makeContext()
        var descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            throw ProgressError.characterNotFound
        }
        var snapshot = try makeSnapshot(record, context: context)
        try mutate(&snapshot)
        if snapshot.experience < 0 {
            throw ProgressError.invalidInput(description: "経験値は0以上である必要があります")
        }
        let clampedExperience = try clampExperience(snapshot.experience, raceId: snapshot.raceId)
        snapshot.experience = clampedExperience
        let normalizedLevel = try resolveLevel(for: clampedExperience, raceId: snapshot.raceId)
        snapshot.level = normalizedLevel
        apply(snapshot: snapshot, to: record)
        try context.save()
        notifyCharacterProgressDidChange()
        return try makeSnapshot(record, context: context)
    }

    func applyBattleResults(_ updates: [BattleResultUpdate]) throws {
        guard !updates.isEmpty else { return }
        let ids = Array(Set(updates.map { $0.characterId }))
        let session = try makeBattleResultSession(characterIds: ids)
        try session.applyBattleResults(updates)
        try session.flushIfNeeded()
    }

    func makeBattleResultSession(characterIds: [UInt8]) throws -> BattleResultSession {
        try BattleResultSession(service: self, characterIds: characterIds)
    }

    @discardableResult
    fileprivate func applyBattleResultsInternal(
        _ updates: [BattleResultUpdate],
        records: [UInt8: CharacterRecord]
    ) throws -> Bool {
        guard !updates.isEmpty else { return false }
        var anyLevelUp = false
        for update in updates {
            guard let record = records[update.characterId] else {
                throw ProgressError.characterNotFound
            }
            if update.experienceDelta != 0 {
                let previousLevel = record.level
                let addition = Int64(record.experience).addingReportingOverflow(Int64(update.experienceDelta))
                guard !addition.overflow else {
                    throw ProgressError.invalidInput(description: "経験値計算中にオーバーフローが発生しました")
                }
                let updatedExperience = max(0, Int(addition.partialValue))
                let cappedExperience = try clampExperience(updatedExperience, raceId: record.raceId)
                record.experience = UInt64(cappedExperience)
                let computedLevel = try resolveLevel(for: cappedExperience, raceId: record.raceId)
                if computedLevel != Int(previousLevel) {
                    record.level = UInt8(computedLevel)
                    anyLevelUp = true
                }
            }
            if update.hpDelta != 0 {
                let newHP = Int64(record.currentHP) + Int64(update.hpDelta)
                record.currentHP = UInt32(max(0, newHP))
            }
        }
        return anyLevelUp
    }

    func updateHP(characterId: UInt8, newHP: UInt32) throws {
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

    /// HP > 0 のキャラクターを全回復する
    /// - Parameter characterIds: 対象キャラクターID配列
    func healToFull(characterIds: [UInt8]) throws {
        guard !characterIds.isEmpty else { return }
        let context = makeContext()
        let descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { characterIds.contains($0.id) })
        let records = try context.fetch(descriptor)

        // ループの外で1回だけ取得
        let pandoraStackKeys = try fetchPandoraBoxStackKeys(context: context)

        var modified = false
        for record in records {
            // HP > 0 のキャラクターのみ回復（HP 0 は蘇生経路を使う）
            guard record.currentHP > 0 else { continue }

            // maxHPを計算
            let input = try loadInput(record, context: context)
            let runtimeCharacter = try RuntimeCharacterFactory.make(from: input, masterData: masterData, pandoraBoxStackKeys: pandoraStackKeys)
            let maxHP = UInt32(runtimeCharacter.maxHP)

            if record.currentHP < maxHP {
                record.currentHP = maxHP
                modified = true
            }
        }

        if modified {
            try context.save()
            notifyCharacterProgressDidChange()
        }
    }

    // MARK: - Job Change

    /// 転職処理（1回のみ可能、レベル・経験値はリセット）
    /// - Parameters:
    ///   - characterId: キャラクターID
    ///   - newJobId: 新しい職業ID（1〜16: 通常職、101〜116: マスター職）
    /// - Returns: 更新後のスナップショット
    func changeJob(characterId: UInt8, newJobId: UInt8) throws -> CharacterSnapshot {
        let context = makeContext()
        var descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { $0.id == characterId })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            throw ProgressError.characterNotFound
        }

        // 探索中のキャラクターは転職不可
        if try isCharacterExploring(characterId: characterId, context: context) {
            throw ProgressError.invalidInput(description: "探索中のキャラクターは転職できません")
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

        // 装備を全てインベントリに戻す（レベルが1にリセットされるため）
        try unequipAllItems(characterId: characterId, context: context)

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
        return try makeSnapshot(record, context: context)
    }

    // MARK: - Delete

    func deleteCharacter(id: UInt8) throws {
        let context = makeContext()
        var descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return }

        // 探索中のキャラクターは解雇不可
        if try isCharacterExploring(characterId: id, context: context) {
            throw ProgressError.invalidInput(description: "探索中のキャラクターを解雇できません")
        }

        try deleteEquipment(for: id, context: context)
        try removeFromParties(characterId: id, context: context)
        context.delete(record)
        try context.save()
        notifyCharacterProgressDidChange()
    }

    // MARK: - Display Order

    /// キャラクターの表示順序を更新
    /// - Parameter orderedIds: 新しい順序でのキャラクターID配列
    func reorderCharacters(orderedIds: [UInt8]) throws {
        guard !orderedIds.isEmpty else { return }
        let context = makeContext()
        let descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { orderedIds.contains($0.id) })
        let records = try context.fetch(descriptor)
        let recordMap = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })

        // 指定されたIDがすべて存在するか確認
        let missingIds = orderedIds.filter { recordMap[$0] == nil }
        if !missingIds.isEmpty {
            let idList = missingIds.map { String($0) }.joined(separator: ", ")
            throw ProgressError.invalidInput(description: "指定されたキャラクターが見つかりません (ID: \(idList))")
        }

        for (index, id) in orderedIds.enumerated() {
            let record = recordMap[id]!
            record.displayOrder = UInt8(index + 1)
        }

        try context.save()
        notifyCharacterProgressDidChange()
    }

    // MARK: - Equipment Management

    /// キャラクターにアイテムを装備（軽量版）
    /// - Parameters:
    ///   - characterId: キャラクターID
    ///   - inventoryItemStackKey: 装備するアイテムのstackKey
    ///   - quantity: 装備数量（デフォルト1）
    ///   - equipmentCapacity: 装備上限（呼び出し元が既に持っているRuntimeCharacterから取得）
    /// - Returns: 更新後の装備リスト
    func equipItem(characterId: UInt8, inventoryItemStackKey: String, quantity: Int = 1, equipmentCapacity: Int) throws -> [CharacterSnapshot.EquippedItem] {
        guard quantity > 0 else {
            throw ProgressError.invalidInput(description: "装備数量は1以上である必要があります")
        }

        // stackKeyをパースして個別フィールドで検索
        guard let components = StackKeyComponents(stackKey: inventoryItemStackKey) else {
            throw ProgressError.invalidInput(description: "無効なstackKeyです")
        }

        let context = makeContext()

        // 探索中のキャラクターは装備変更不可
        if try isCharacterExploring(characterId: characterId, context: context) {
            throw ProgressError.invalidInput(description: "探索中のキャラクターは装備を変更できません")
        }

        // インベントリアイテムの取得（個別フィールドで検索）
        let storageTypeValue = ItemStorage.playerItem.rawValue
        let superRare = components.superRareTitleId
        let normal = components.normalTitleId
        let itemId = components.itemId
        let socketSuperRare = components.socketSuperRareTitleId
        let socketNormal = components.socketNormalTitleId
        let socketItem = components.socketItemId
        var inventoryDescriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.storageType == storageTypeValue &&
            $0.superRareTitleId == superRare &&
            $0.normalTitleId == normal &&
            $0.itemId == itemId &&
            $0.socketSuperRareTitleId == socketSuperRare &&
            $0.socketNormalTitleId == socketNormal &&
            $0.socketItemId == socketItem
        })
        inventoryDescriptor.fetchLimit = 1
        guard let inventoryRecord = try context.fetch(inventoryDescriptor).first else {
            throw ProgressError.invalidInput(description: "アイテムが見つかりません")
        }

        guard inventoryRecord.quantity >= quantity else {
            throw ProgressError.invalidInput(description: "アイテム数量が不足しています")
        }

        // 現在の装備数をチェック
        let equipmentDescriptor = FetchDescriptor<CharacterEquipmentRecord>(predicate: #Predicate { $0.characterId == characterId })
        let currentEquipment = try context.fetch(equipmentDescriptor)

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

        // 装備変更は呼び出し元が状態を管理するため、通知は送らない
        // （通知すると全キャラクター再構築が発生しUIをブロックする）

        // 更新後の装備リストを返す（軽量版）
        return try fetchEquippedItems(characterId: characterId, context: context)
    }

    /// キャラクターからアイテムを解除（軽量版）
    /// - Returns: 更新後の装備リスト
    func unequipItem(characterId: UInt8, equipmentStackKey: String, quantity: Int = 1) throws -> [CharacterSnapshot.EquippedItem] {
        guard quantity > 0 else {
            throw ProgressError.invalidInput(description: "解除数量は1以上である必要があります")
        }

        // stackKeyをパースして個別フィールドで検索
        guard let components = StackKeyComponents(stackKey: equipmentStackKey) else {
            throw ProgressError.invalidInput(description: "無効なstackKeyです")
        }

        let context = makeContext()

        // 探索中のキャラクターは装備変更不可
        if try isCharacterExploring(characterId: characterId, context: context) {
            throw ProgressError.invalidInput(description: "探索中のキャラクターは装備を変更できません")
        }

        // 装備レコードの取得（個別フィールドで検索）
        let superRare = components.superRareTitleId
        let normal = components.normalTitleId
        let itemId = components.itemId
        let socketSuperRare = components.socketSuperRareTitleId
        let socketNormal = components.socketNormalTitleId
        let socketItem = components.socketItemId
        let equipmentDescriptor = FetchDescriptor<CharacterEquipmentRecord>(predicate: #Predicate {
            $0.characterId == characterId &&
            $0.superRareTitleId == superRare &&
            $0.normalTitleId == normal &&
            $0.itemId == itemId &&
            $0.socketSuperRareTitleId == socketSuperRare &&
            $0.socketNormalTitleId == socketNormal &&
            $0.socketItemId == socketItem
        })
        let matchingEquipment = try context.fetch(equipmentDescriptor)

        guard matchingEquipment.count >= quantity else {
            throw ProgressError.invalidInput(description: "解除数量が装備数を超えています")
        }

        let storage = ItemStorage.playerItem

        // インベントリに戻す（個別フィールドで検索）
        let storageTypeValue = storage.rawValue
        var inventoryDescriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.storageType == storageTypeValue &&
            $0.superRareTitleId == superRare &&
            $0.normalTitleId == normal &&
            $0.itemId == itemId &&
            $0.socketSuperRareTitleId == socketSuperRare &&
            $0.socketNormalTitleId == socketNormal &&
            $0.socketItemId == socketItem
        })
        inventoryDescriptor.fetchLimit = 1

        if let existingInventory = try context.fetch(inventoryDescriptor).first {
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

        // 装備変更は呼び出し元が状態を管理するため、通知は送らない
        // （通知すると全キャラクター再構築が発生しUIをブロックする）

        // 更新後の装備リストを返す（軽量版）
        return try fetchEquippedItems(characterId: characterId, context: context)
    }

    /// 装備リストを取得（内部ヘルパー、既存contextを使用）
    private func fetchEquippedItems(characterId: UInt8, context: ModelContext) throws -> [CharacterSnapshot.EquippedItem] {
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

    /// キャラクターの装備一覧を取得
    func equippedItems(characterId: UInt8) throws -> [CharacterSnapshot.EquippedItem] {
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
    func resolveLevel(for experience: Int, raceId: UInt8) throws -> Int {
        let maxLevel = try raceMaxLevel(for: raceId)
        do {
            return try CharacterExperienceTable.level(forTotalExperience: experience, maximumLevel: maxLevel)
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

    func clampExperience(_ experience: Int, raceId: UInt8) throws -> Int {
        guard experience > 0 else { return 0 }
        let maximum = try raceMaxExperience(for: raceId)
        return min(experience, maximum)
    }

    func raceMaxExperience(for raceId: UInt8) throws -> Int {
        if let cached = raceMaxExperienceCache[raceId] {
            return cached
        }
        let maxLevel = try raceMaxLevel(for: raceId)
        let maximumExperience = try CharacterExperienceTable.totalExperience(toReach: maxLevel)
        raceMaxExperienceCache[raceId] = maximumExperience
        return maximumExperience
    }

    func makeContext() -> ModelContext {
        contextProvider.newBackgroundContext()
    }

    func makeSnapshots(_ records: [CharacterRecord], context: ModelContext) throws -> [CharacterSnapshot] {
        var snapshots: [CharacterSnapshot] = []
        snapshots.reserveCapacity(records.count)
        for record in records {
            let snapshot = try makeSnapshot(record, context: context)
            snapshots.append(snapshot)
        }
        return snapshots
    }

    func makeSnapshot(_ record: CharacterRecord, context: ModelContext) throws -> CharacterSnapshot {
        // CharacterInput を作成
        let input = try loadInput(record, context: context)

        // RuntimeCharacterFactory で計算済み RuntimeCharacter を取得
        let pandoraStackKeys = try fetchPandoraBoxStackKeys(context: context)
        let runtimeCharacter = try RuntimeCharacterFactory.make(
            from: input,
            masterData: masterData,
            pandoraBoxStackKeys: pandoraStackKeys
        )

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
            displayOrder: record.displayOrder,
            createdAt: now,
            updatedAt: now
        )
    }

    func apply(snapshot: CharacterSnapshot, to record: CharacterRecord) {
        record.displayName = snapshot.displayName
        record.avatarId = snapshot.avatarId
        record.level = UInt8(snapshot.level)
        record.experience = UInt64(snapshot.experience)
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

    /// キャラクターが探索中かどうかをチェック
    func isCharacterExploring(characterId: UInt8, context: ModelContext) throws -> Bool {
        // running状態の探索を取得
        let runningStatus = ExplorationResult.running.rawValue
        let runningDescriptor = FetchDescriptor<ExplorationRunRecord>(
            predicate: #Predicate { $0.result == runningStatus }
        )
        let runningExplorations = try context.fetch(runningDescriptor)
        guard !runningExplorations.isEmpty else { return false }

        // 探索中のパーティIDを取得
        let exploringPartyIds = Set(runningExplorations.map(\.partyId))

        // パーティレコードを取得して、キャラクターが所属しているかチェック
        let partyDescriptor = FetchDescriptor<PartyRecord>()
        let parties = try context.fetch(partyDescriptor)
        for party in parties {
            if exploringPartyIds.contains(party.id) && party.memberCharacterIds.contains(characterId) {
                return true
            }
        }
        return false
    }

    /// キャラクターの装備を全てインベントリに戻す
    func unequipAllItems(characterId: UInt8, context: ModelContext) throws {
        let equipmentDescriptor = FetchDescriptor<CharacterEquipmentRecord>(
            predicate: #Predicate { $0.characterId == characterId }
        )
        let allEquipment = try context.fetch(equipmentDescriptor)
        guard !allEquipment.isEmpty else { return }

        let storage = ItemStorage.playerItem

        // インベントリを取得
        let storageTypeValue = storage.rawValue
        let allInventory = try context.fetch(FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.storageType == storageTypeValue
        }))

        // stackKeyでグループ化
        var groupedEquipment: [String: [CharacterEquipmentRecord]] = [:]
        for equip in allEquipment {
            groupedEquipment[equip.stackKey, default: []].append(equip)
        }

        // 各グループをインベントリに戻す
        for (stackKey, equipments) in groupedEquipment {
            let quantity = equipments.count

            if let existingInventory = allInventory.first(where: { $0.stackKey == stackKey }) {
                // 既存スタックに追加
                existingInventory.quantity = min(existingInventory.quantity + UInt16(quantity), 99)
            } else if let firstEquip = equipments.first {
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

            // 装備レコードを削除
            for equip in equipments {
                context.delete(equip)
            }
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

    /// 既存の最大displayOrder+1を割り当てる
    func allocateDisplayOrder(context: ModelContext) throws -> UInt8 {
        let records = try context.fetch(FetchDescriptor<CharacterRecord>())
        let maxOrder = records.map(\.displayOrder).max() ?? 0
        return maxOrder + 1
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
