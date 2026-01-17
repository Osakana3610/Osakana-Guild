// ==============================================================================
// CachedCharacterFactory.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - CharacterInputからCachedCharacterを生成
//   - マスターデータ取得と戦闘ステータス計算の統合
//
// 【公開API】
//   - make(from:masterData:pandoraBoxItems:) → CachedCharacter
//     nonisolated - キャラクター生成（純粋計算）
//   - withEquipmentChange(current:newEquippedItems:masterData:) → CachedCharacter
//     nonisolated - 装備変更時の高速再構築（既存データを再利用）
//
// 【生成フロー】
//   1. マスターデータ取得（種族/職業/性格）
//   2. スキルID収集（職業 + 装備）
//   3. Loadout構築（アイテム/称号定義）
//   4. 装備スロット計算・検証
//   5. スペルブック構築
//   6. CombatStatCalculatorで戦闘ステータス計算
//   7. CachedCharacter生成
//
// 【スキル収集】
//   - パッシブスキル: 前職 + 現職（転職しても引き継ぐ）
//   - パッシブスキル: 種族（種族固有のスキル）
//   - レベル習得スキル: 現職のみ（レベル条件を満たしたもの）
//   - 種族レベル習得スキル（レベル条件を満たしたもの）
//   - 装備アイテム + 超レア称号から付与されるスキル
//
// 【補助機能】
//   - EquipmentSlotCalculator: レベルベースの装備可能数計算
//     - baseCapacity: 基本値（√(1.5×レベル+0.3)-0.5)/0.7
//     - capacity: スキル修正込み
//
// 【使用箇所】
//   - GameRuntimeService: runtimeCharacter API
//   - PartyAssembler: パーティメンバー生成
//
// ==============================================================================

import Foundation

/// CharacterInputからCachedCharacterを生成するファクトリ。
/// マスターデータ取得と戦闘ステータス計算を行う。
enum CachedCharacterFactory {

    nonisolated static func make(
        from input: CharacterInput,
        masterData: MasterDataCache,
        pandoraBoxItems: Set<UInt64> = []
    ) throws -> CachedCharacter {

        // マスターデータ取得
        guard let race = masterData.race(input.raceId) else {
            throw RuntimeError.invalidConfiguration(reason: "種族ID \(input.raceId) のマスターデータが見つかりません")
        }
        guard let job = masterData.job(input.jobId) else {
            throw RuntimeError.invalidConfiguration(reason: "職業ID \(input.jobId) のマスターデータが見つかりません")
        }
        let primaryPersonality = masterData.personalityPrimary(input.primaryPersonalityId)
        let secondaryPersonality = masterData.personalitySecondary(input.secondaryPersonalityId)

        // 装備アイテムの定義を取得（ソケット宝石は含めない）
        let equippedItemIds = Set(input.equippedItems.map { $0.itemId }).filter { $0 > 0 }
        let equippedItemDefinitions = equippedItemIds.compactMap { masterData.item($0) }

        // 装備アイテムの超レア称号を取得（ソケット宝石の超レア称号は含めない）
        let superRareTitleIds = Set(input.equippedItems.map { $0.superRareTitleId }).filter { $0 > 0 }
        let superRareTitles = superRareTitleIds.compactMap { masterData.superRareTitle($0) }

        // 前職のマスターデータ取得（転職済みの場合のみ）
        let previousJob: JobDefinition?
        if input.previousJobId > 0 {
            guard let pJob = masterData.job(input.previousJobId) else {
                throw RuntimeError.invalidConfiguration(reason: "前職ID \(input.previousJobId) のマスターデータが見つかりません")
            }
            previousJob = pJob
        } else {
            previousJob = nil
        }

        // スキルIDを収集
        var allSkillIds: [UInt16] = []

        // パッシブスキル: 前職から引き継ぐ（転職済みの場合のみ）
        if let previousJob {
            allSkillIds.append(contentsOf: previousJob.learnedSkillIds)
        }

        // パッシブスキル: 現職
        allSkillIds.append(contentsOf: job.learnedSkillIds)

        // パッシブスキル: 種族
        if let racePassiveSkills = masterData.racePassiveSkills[input.raceId] {
            allSkillIds.append(contentsOf: racePassiveSkills)
        }

        // レベル習得スキル: 現職のみ（レベル条件を満たしたもの）
        let jobUnlocks = masterData.jobSkillUnlocks[input.jobId] ?? []
        for unlock in jobUnlocks where input.level >= unlock.level {
            allSkillIds.append(unlock.skillId)
        }

        // 種族レベル習得スキル（レベル条件を満たしたもの）
        let raceUnlocks = masterData.raceSkillUnlocks[input.raceId] ?? []
        for unlock in raceUnlocks where input.level >= unlock.level {
            allSkillIds.append(unlock.skillId)
        }

        // 装備から付与されるスキル（装備アイテム + 装備の超レア称号）
        allSkillIds.append(contentsOf: equippedItemDefinitions.flatMap { $0.grantedSkillIds })
        allSkillIds.append(contentsOf: superRareTitles.flatMap { $0.skillIds })

        // 重複除去してからスキル定義に変換
        let uniqueSkillIds = Set(allSkillIds)
        let learnedSkills = uniqueSkillIds.compactMap { masterData.skill($0) }

        // Loadout構築
        let loadout = assembleLoadout(masterData: masterData, from: input.equippedItems)

        // 統合スキルエフェクトコンパイラで一括処理
        let skillCompiler = try UnifiedSkillEffectCompiler(skills: learnedSkills)

        // 装備スロット計算
        let allowedSlots = EquipmentSlotCalculator.capacity(forLevel: input.level, modifiers: skillCompiler.equipmentSlots)
        let usedSlots = input.equippedItems.reduce(0) { $0 + max(0, $1.quantity) }
        if usedSlots > allowedSlots {
            throw RuntimeError.invalidConfiguration(reason: "装備枠を超過しています（装備数: \(usedSlots) / 上限: \(allowedSlots)）")
        }

        // スペルブック
        let spellbook = skillCompiler.spellbook
        let spellLoadout = SkillRuntimeEffectCompiler.spellLoadout(
            from: spellbook,
            definitions: masterData.allSpells,
            characterLevel: Int(input.level)
        )

        // 装備を CharacterValues.EquippedItem に変換
        let equippedItemsValues = input.equippedItems.map { item in
            CharacterValues.EquippedItem(
                superRareTitleId: item.superRareTitleId,
                normalTitleId: item.normalTitleId,
                itemId: item.itemId,
                socketSuperRareTitleId: item.socketSuperRareTitleId,
                socketNormalTitleId: item.socketNormalTitleId,
                socketItemId: item.socketItemId,
                quantity: item.quantity
            )
        }

        // キャッシュ済み装備アイテムを作成（combatBonusesに称号・超レア・宝石改造・パンドラ適用済み）
        let cachedEquippedItems = makeCachedEquippedItems(from: input.equippedItems, masterData: masterData, pandoraBoxItems: pandoraBoxItems)

        // 戦闘ステータス計算
        let calcContext = CombatStatCalculator.Context(
            raceId: input.raceId,
            jobId: input.jobId,
            level: input.level,
            currentHP: input.currentHP,
            equippedItems: equippedItemsValues,
            cachedEquippedItems: cachedEquippedItems,
            race: race,
            job: job,
            personalitySecondary: secondaryPersonality,
            learnedSkills: learnedSkills,
            loadout: CachedCharacter.Loadout(
                items: loadout.items,
                titles: loadout.titles,
                superRareTitles: loadout.superRareTitles
            )
        )

        let calcResult = try CombatStatCalculator.calculate(for: calcContext)
        let actorStats = ActorStats(
            strength: calcResult.attributes.strength,
            wisdom: calcResult.attributes.wisdom,
            spirit: calcResult.attributes.spirit,
            vitality: calcResult.attributes.vitality,
            agility: calcResult.attributes.agility,
            luck: calcResult.attributes.luck
        )
        let actorEffects = try UnifiedSkillEffectCompiler(skills: learnedSkills, stats: actorStats).actorEffects

        // isMartialEligible判定
        let isMartialEligible = calcResult.combat.isMartialEligible ||
            (calcResult.combat.physicalAttackScore > 0 && !hasPositivePhysicalAttackBonus(input: input, loadout: loadout))

        // 蘇生パッシブチェック
        var resolvedCurrentHP = min(input.currentHP, calcResult.hitPoints.maximum)
        if resolvedCurrentHP <= 0 {
            let resurrection = actorEffects.resurrection
            if resurrection.passiveBetweenFloors {
                if let chance = resurrection.passiveBetweenFloorsChancePercent {
                    let cappedChance = max(0, min(100, Int(chance.rounded(.down))))
                    if cappedChance >= 100 {
                        resolvedCurrentHP = max(1, calcResult.hitPoints.maximum)
                    }
                } else {
                resolvedCurrentHP = max(1, calcResult.hitPoints.maximum)
                }
            }
        }

        // combatにisMartialEligibleを設定
        var combat = calcResult.combat
        combat.isMartialEligible = isMartialEligible

        return CachedCharacter(
            id: input.id,
            displayName: input.displayName,
            raceId: input.raceId,
            jobId: input.jobId,
            previousJobId: input.previousJobId,
            avatarId: input.avatarId,
            level: input.level,
            experience: input.experience,
            currentHP: resolvedCurrentHP,
            equippedItems: cachedEquippedItems,
            primaryPersonalityId: input.primaryPersonalityId,
            secondaryPersonalityId: input.secondaryPersonalityId,
            actionRateAttack: input.actionRateAttack,
            actionRatePriestMagic: input.actionRatePriestMagic,
            actionRateMageMagic: input.actionRateMageMagic,
            actionRateBreath: input.actionRateBreath,
            updatedAt: input.updatedAt,
            displayOrder: input.displayOrder,
            attributes: calcResult.attributes,
            maxHP: calcResult.hitPoints.maximum,
            combat: combat,
            equipmentCapacity: allowedSlots,
            race: race,
            job: job,
            previousJob: previousJob,
            personalityPrimary: primaryPersonality,
            personalitySecondary: secondaryPersonality,
            learnedSkills: learnedSkills,
            loadout: loadout,
            spellbook: spellbook,
            spellLoadout: spellLoadout
        )
    }

    // MARK: - Equipment Change (Fast Path)

    /// 装備変更時の高速再構築
    /// 既存のCachedCharacterからマスターデータ（種族/職業/性格）を再利用し、
    /// 装備関連のみを再計算する
    nonisolated static func withEquipmentChange(
        current: CachedCharacter,
        newEquippedItems: [CharacterInput.EquippedItem],
        masterData: MasterDataCache,
        pandoraBoxItems: Set<UInt64>
    ) throws -> CachedCharacter {
        // 既存のマスターデータを再利用（必須データが欠落している場合はエラー）
        guard let race = current.race else {
            throw RuntimeError.invalidConfiguration(reason: "種族データが見つかりません")
        }
        guard let job = current.job else {
            throw RuntimeError.invalidConfiguration(reason: "職業データが見つかりません")
        }
        let previousJob = current.previousJob
        let primaryPersonality = current.personalityPrimary
        let secondaryPersonality = current.personalitySecondary

        // 装備アイテムの定義を取得
        let equippedItemIds = Set(newEquippedItems.map { $0.itemId }).filter { $0 > 0 }
        let equippedItemDefinitions = equippedItemIds.compactMap { masterData.item($0) }

        // 装備アイテムの超レア称号を取得
        let superRareTitleIds = Set(newEquippedItems.map { $0.superRareTitleId }).filter { $0 > 0 }
        let superRareTitles = superRareTitleIds.compactMap { masterData.superRareTitle($0) }

        // スキルIDを収集（職業/種族由来 + 装備由来）
        var allSkillIds: [UInt16] = []

        // パッシブスキル: 前職から引き継ぐ（転職済みの場合のみ）
        if let previousJob {
            allSkillIds.append(contentsOf: previousJob.learnedSkillIds)
        }

        // パッシブスキル: 現職
        allSkillIds.append(contentsOf: job.learnedSkillIds)

        // パッシブスキル: 種族
        if let racePassiveSkills = masterData.racePassiveSkills[current.raceId] {
            allSkillIds.append(contentsOf: racePassiveSkills)
        }

        // レベル習得スキル: 現職のみ（レベル条件を満たしたもの）
        let jobUnlocks = masterData.jobSkillUnlocks[current.jobId] ?? []
        for unlock in jobUnlocks where current.level >= unlock.level {
            allSkillIds.append(unlock.skillId)
        }

        // 種族レベル習得スキル（レベル条件を満たしたもの）
        let raceUnlocks = masterData.raceSkillUnlocks[current.raceId] ?? []
        for unlock in raceUnlocks where current.level >= unlock.level {
            allSkillIds.append(unlock.skillId)
        }

        // 装備から付与されるスキル（装備アイテム + 装備の超レア称号）
        allSkillIds.append(contentsOf: equippedItemDefinitions.flatMap { $0.grantedSkillIds })
        allSkillIds.append(contentsOf: superRareTitles.flatMap { $0.skillIds })

        // 重複除去してからスキル定義に変換
        let uniqueSkillIds = Set(allSkillIds)
        let learnedSkills = uniqueSkillIds.compactMap { masterData.skill($0) }

        // Loadout構築
        let loadout = assembleLoadout(masterData: masterData, from: newEquippedItems)

        // 統合スキルエフェクトコンパイラで一括処理
        let skillCompiler = try UnifiedSkillEffectCompiler(skills: learnedSkills)

        // 装備スロット計算
        let allowedSlots = EquipmentSlotCalculator.capacity(forLevel: current.level, modifiers: skillCompiler.equipmentSlots)
        let usedSlots = newEquippedItems.reduce(0) { $0 + max(0, $1.quantity) }
        if usedSlots > allowedSlots {
            throw RuntimeError.invalidConfiguration(reason: "装備枠を超過しています（装備数: \(usedSlots) / 上限: \(allowedSlots)）")
        }

        // スペルブック
        let spellbook = skillCompiler.spellbook
        let spellLoadout = SkillRuntimeEffectCompiler.spellLoadout(
            from: spellbook,
            definitions: masterData.allSpells,
            characterLevel: current.level
        )

        // 装備を CharacterValues.EquippedItem に変換
        let equippedItemsValues = newEquippedItems.map { item in
            CharacterValues.EquippedItem(
                superRareTitleId: item.superRareTitleId,
                normalTitleId: item.normalTitleId,
                itemId: item.itemId,
                socketSuperRareTitleId: item.socketSuperRareTitleId,
                socketNormalTitleId: item.socketNormalTitleId,
                socketItemId: item.socketItemId,
                quantity: item.quantity
            )
        }

        // キャッシュ済み装備アイテムを作成（combatBonusesに称号・超レア・宝石改造・パンドラ適用済み）
        let cachedEquippedItems = makeCachedEquippedItems(from: newEquippedItems, masterData: masterData, pandoraBoxItems: pandoraBoxItems)

        // 戦闘ステータス計算
        let calcContext = CombatStatCalculator.Context(
            raceId: current.raceId,
            jobId: current.jobId,
            level: current.level,
            currentHP: current.currentHP,
            equippedItems: equippedItemsValues,
            cachedEquippedItems: cachedEquippedItems,
            race: race,
            job: job,
            personalitySecondary: secondaryPersonality,
            learnedSkills: learnedSkills,
            loadout: CachedCharacter.Loadout(
                items: loadout.items,
                titles: loadout.titles,
                superRareTitles: loadout.superRareTitles
            )
        )

        let calcResult = try CombatStatCalculator.calculate(for: calcContext)

        // isMartialEligible判定
        let isMartialEligible = calcResult.combat.isMartialEligible ||
            (calcResult.combat.physicalAttackScore > 0 && !hasPositivePhysicalAttackBonus(equippedItems: newEquippedItems, loadout: loadout))

        // 蘇生パッシブチェックはスキップ（装備変更でHPが0になることはない）
        let resolvedCurrentHP = min(current.currentHP, calcResult.hitPoints.maximum)

        // combatにisMartialEligibleを設定
        var combat = calcResult.combat
        combat.isMartialEligible = isMartialEligible

        return CachedCharacter(
            id: current.id,
            displayName: current.displayName,
            raceId: current.raceId,
            jobId: current.jobId,
            previousJobId: current.previousJobId,
            avatarId: current.avatarId,
            level: current.level,
            experience: current.experience,
            currentHP: resolvedCurrentHP,
            equippedItems: cachedEquippedItems,
            primaryPersonalityId: current.primaryPersonalityId,
            secondaryPersonalityId: current.secondaryPersonalityId,
            actionRateAttack: current.actionRateAttack,
            actionRatePriestMagic: current.actionRatePriestMagic,
            actionRateMageMagic: current.actionRateMageMagic,
            actionRateBreath: current.actionRateBreath,
            updatedAt: current.updatedAt,
            displayOrder: current.displayOrder,
            attributes: calcResult.attributes,
            maxHP: calcResult.hitPoints.maximum,
            combat: combat,
            equipmentCapacity: allowedSlots,
            race: race,
            job: job,
            previousJob: previousJob,
            personalityPrimary: primaryPersonality,
            personalitySecondary: secondaryPersonality,
            learnedSkills: learnedSkills,
            loadout: loadout,
            spellbook: spellbook,
            spellLoadout: spellLoadout
        )
    }

    // MARK: - Private

    /// 装備アイテムからCachedInventoryItemのリストを構築
    private nonisolated static func makeCachedEquippedItems(
        from items: [CharacterInput.EquippedItem],
        masterData: MasterDataCache,
        pandoraBoxItems: Set<UInt64>
    ) -> [CachedInventoryItem] {
        let allTitles = masterData.allTitles
        let priceMultiplierMap = Dictionary(uniqueKeysWithValues: allTitles.map { ($0.id, $0.priceMultiplier) })

        let cachedItems: [CachedInventoryItem] = items.compactMap { item in
            guard let definition = masterData.item(item.itemId) else { return nil }

            let category = ItemSaleCategory(rawValue: definition.category) ?? .other

            // 称号名を構築
            var displayName = ""
            if item.superRareTitleId > 0,
               let superRareTitle = masterData.superRareTitle(item.superRareTitleId) {
                displayName += superRareTitle.name
            }
            if let title = masterData.title(item.normalTitleId),
               !title.name.isEmpty {
                displayName += title.name
            }
            displayName += definition.name

            // ソケット名を追加
            if item.socketItemId > 0,
               let socketDef = masterData.item(item.socketItemId) {
                var socketName = ""
                if item.socketSuperRareTitleId > 0,
                   let socketSuperRare = masterData.superRareTitle(item.socketSuperRareTitleId) {
                    socketName += socketSuperRare.name
                }
                if let socketTitle = masterData.title(item.socketNormalTitleId),
                   !socketTitle.name.isEmpty {
                    socketName += socketTitle.name
                }
                socketName += socketDef.name
                displayName += "[\(socketName)]"
            }

            // 売却価格を計算
            let sellValue = (try? ItemPriceCalculator.sellPrice(
                baseSellValue: definition.sellValue,
                normalTitleId: item.normalTitleId,
                hasSuperRare: item.superRareTitleId != 0,
                multiplierMap: priceMultiplierMap
            )) ?? definition.sellValue

            // スキルIDを収集（ベース + 超レア称号）
            var grantedSkillIds = definition.grantedSkillIds
            if item.superRareTitleId > 0,
               let superRareSkillIds = masterData.superRareTitle(item.superRareTitleId)?.skillIds {
                grantedSkillIds.append(contentsOf: superRareSkillIds)
            }

            // 戦闘ステータスを計算（称号 × 超レア × 宝石改造 × パンドラ）
            let combatBonuses = calculateFinalCombatBonuses(
                definition: definition,
                normalTitleId: item.normalTitleId,
                superRareTitleId: item.superRareTitleId,
                socketItemId: item.socketItemId,
                socketNormalTitleId: item.socketNormalTitleId,
                socketSuperRareTitleId: item.socketSuperRareTitleId,
                isPandora: pandoraBoxItems.contains(item.packedStackKey),
                masterData: masterData
            )

            return CachedInventoryItem(
                stackKey: item.stackKey,
                itemId: item.itemId,
                quantity: UInt16(item.quantity),
                normalTitleId: item.normalTitleId,
                superRareTitleId: item.superRareTitleId,
                socketItemId: item.socketItemId,
                socketNormalTitleId: item.socketNormalTitleId,
                socketSuperRareTitleId: item.socketSuperRareTitleId,
                category: category,
                rarity: definition.rarity,
                displayName: displayName,
                baseValue: definition.basePrice,
                sellValue: sellValue,
                statBonuses: definition.statBonuses,
                combatBonuses: combatBonuses,
                grantedSkillIds: grantedSkillIds
            )
        }

        // インベントリと同じソート順で並べ替え
        return cachedItems.sorted { lhs, rhs in
            // itemId の昇順
            if lhs.itemId != rhs.itemId {
                return lhs.itemId < rhs.itemId
            }
            // 超レア称号あり → 後
            let lhsHasSuperRare = lhs.superRareTitleId > 0
            let rhsHasSuperRare = rhs.superRareTitleId > 0
            if lhsHasSuperRare != rhsHasSuperRare {
                return !lhsHasSuperRare
            }
            // ソケットあり → 後
            let lhsHasSocket = lhs.socketItemId > 0
            let rhsHasSocket = rhs.socketItemId > 0
            if lhsHasSocket != rhsHasSocket {
                return !lhsHasSocket
            }
            // normalTitleId の昇順
            if lhs.normalTitleId != rhs.normalTitleId {
                return lhs.normalTitleId < rhs.normalTitleId
            }
            // superRareTitleId の昇順
            if lhs.superRareTitleId != rhs.superRareTitleId {
                return lhs.superRareTitleId < rhs.superRareTitleId
            }
            // socketItemId の昇順
            return lhs.socketItemId < rhs.socketItemId
        }
    }

    private nonisolated static func assembleLoadout(
        masterData: MasterDataCache,
        from equippedItems: [CharacterInput.EquippedItem]
    ) -> CachedCharacter.Loadout {
        // アイテムIDを収集（装備とソケット宝石）
        var itemIds = Set(equippedItems.map { $0.itemId })
        let socketItemIds = Set(equippedItems.map { $0.socketItemId }).filter { $0 > 0 }
        itemIds.formUnion(socketItemIds)
        let items = itemIds.filter { $0 > 0 }.compactMap { masterData.item($0) }

        // 通常称号IDを収集（装備とソケット宝石）
        var normalTitleIds = Set(equippedItems.map { $0.normalTitleId })
        let socketNormalTitleIds = Set(equippedItems.map { $0.socketNormalTitleId })
        normalTitleIds.formUnion(socketNormalTitleIds)
        let titles = normalTitleIds.filter { $0 > 0 }.compactMap { masterData.title($0) }

        // 超レア称号IDを収集（装備とソケット宝石）
        var superRareTitleIds = Set(equippedItems.map { $0.superRareTitleId })
        let socketSuperRareTitleIds = Set(equippedItems.map { $0.socketSuperRareTitleId })
        superRareTitleIds.formUnion(socketSuperRareTitleIds)
        let superRareTitles = superRareTitleIds.filter { $0 > 0 }.compactMap { masterData.superRareTitle($0) }

        return CachedCharacter.Loadout(
            items: items,
            titles: titles,
            superRareTitles: superRareTitles
        )
    }

    private nonisolated static func hasPositivePhysicalAttackBonus(
        input: CharacterInput,
        loadout: CachedCharacter.Loadout
    ) -> Bool {
        hasPositivePhysicalAttackBonus(equippedItems: input.equippedItems, loadout: loadout)
    }

    private nonisolated static func hasPositivePhysicalAttackBonus(
        equippedItems: [CharacterInput.EquippedItem],
        loadout: CachedCharacter.Loadout
    ) -> Bool {
        guard !equippedItems.isEmpty else { return false }
        let definitionsById = Dictionary(uniqueKeysWithValues: loadout.items.map { ($0.id, $0) })
        for equipment in equippedItems {
            guard let definition = definitionsById[equipment.itemId] else { continue }
            if definition.combatBonuses.physicalAttackScore * equipment.quantity > 0 { return true }
        }
        return false
    }

    /// 最終的なcombatBonusesを計算（称号 × 超レア × 宝石改造 × パンドラ）
    private nonisolated static func calculateFinalCombatBonuses(
        definition: ItemDefinition,
        normalTitleId: UInt8,
        superRareTitleId: UInt8,
        socketItemId: UInt16,
        socketNormalTitleId: UInt8,
        socketSuperRareTitleId: UInt8,
        isPandora: Bool,
        masterData: MasterDataCache
    ) -> ItemDefinition.CombatBonuses {
        // 親装備の称号倍率
        let title = masterData.title(normalTitleId)
        let statMult = title?.statMultiplier ?? 1.0
        let negMult = title?.negativeMultiplier ?? 1.0
        let superRareMult: Double = superRareTitleId > 0 ? 2.0 : 1.0

        // 親装備のcombatBonuses（称号 × 超レア）
        var result = definition.combatBonuses.scaledWithTitle(
            statMult: statMult,
            negMult: negMult,
            superRare: superRareMult
        )

        // ソケット宝石があれば加算
        if socketItemId > 0,
           let gemDefinition = masterData.item(socketItemId) {
            let gemTitle = masterData.title(socketNormalTitleId)
            let gemStatMult = gemTitle?.statMultiplier ?? 1.0
            let gemNegMult = gemTitle?.negativeMultiplier ?? 1.0
            let gemSuperRareMult: Double = socketSuperRareTitleId > 0 ? 2.0 : 1.0

            let gemBonus = gemDefinition.combatBonuses.scaledForGem(
                statMult: gemStatMult,
                negMult: gemNegMult,
                superRare: gemSuperRareMult
            )
            result = result.adding(gemBonus)
        }

        // パンドラ効果
        if isPandora {
            result = result.scaled(by: 1.5)
        }

        return result
    }
}

// MARK: - Equipment Slot Calculator

enum EquipmentSlotCalculator: Sendable {
    /// スキル修正込みの装備可能数を計算
    nonisolated static func capacity(forLevel level: Int, modifiers: SkillRuntimeEffects.EquipmentSlots) -> Int {
        let base = baseCapacity(forLevel: level)
        let scaled = Double(base) * max(0.0, modifiers.multiplier)
        let adjusted = Int(scaled.rounded()) + modifiers.additive
        return max(1, adjusted)
    }

    /// レベルに基づく基本装備可能数（スキル修正なし）
    nonisolated static func baseCapacity(forLevel rawLevel: Int) -> Int {
        let level = max(1, rawLevel)
        // 装備可能数 = (√(1.5 × レベル + 0.3) - 0.5) / 0.7
        let value = (sqrt(1.5 * Double(level) + 0.3) - 0.5) / 0.7
        return max(1, Int(value))
    }
}
