// ==============================================================================
// RuntimeCharacterFactory.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - CharacterInputからRuntimeCharacterを生成
//   - マスターデータ取得と戦闘ステータス計算の統合
//
// 【公開API】
//   - make(from:masterData:pandoraBoxStackKeys:) → RuntimeCharacter
//     @MainActor - キャラクター生成
//
// 【生成フロー】
//   1. マスターデータ取得（種族/職業/性格）
//   2. スキルID収集（職業 + 装備）
//   3. Loadout構築（アイテム/称号定義）
//   4. 装備スロット計算・検証
//   5. スペルブック構築
//   6. CombatStatCalculatorで戦闘ステータス計算
//   7. RuntimeCharacter生成
//
// 【スキル収集】
//   - 前職のスキル（転職済みの場合）
//   - 現職のスキル
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

/// CharacterInputからRuntimeCharacterを生成するファクトリ。
/// マスターデータ取得と戦闘ステータス計算を行う。
enum RuntimeCharacterFactory {

    @MainActor
    static func make(
        from input: CharacterInput,
        masterData: MasterDataCache,
        pandoraBoxStackKeys: Set<String> = []
    ) throws -> RuntimeCharacter {

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

        // スキルIDを収集（職業 + 装備）
        var allSkillIds: [UInt16] = []

        // 前職のスキル（previousJobId > 0 の場合のみ）
        if input.previousJobId > 0 {
            guard let previousJob = masterData.job(input.previousJobId) else {
                throw RuntimeError.invalidConfiguration(reason: "前職ID \(input.previousJobId) のマスターデータが見つかりません")
            }
            allSkillIds.append(contentsOf: previousJob.learnedSkillIds)
        }

        // 現職のスキル
        allSkillIds.append(contentsOf: job.learnedSkillIds)

        // 装備から付与されるスキル（装備アイテム + 装備の超レア称号）
        allSkillIds.append(contentsOf: equippedItemDefinitions.flatMap { $0.grantedSkillIds })
        allSkillIds.append(contentsOf: superRareTitles.flatMap { $0.skillIds })

        let learnedSkills = allSkillIds.compactMap { masterData.skill($0) }

        // Loadout構築
        let loadout = assembleLoadout(masterData: masterData, from: input.equippedItems)

        // 装備スロット計算
        let slotModifiers = try SkillRuntimeEffectCompiler.equipmentSlots(from: learnedSkills)
        let allowedSlots = EquipmentSlotCalculator.capacity(forLevel: input.level, modifiers: slotModifiers)
        let usedSlots = input.equippedItems.reduce(0) { $0 + max(0, $1.quantity) }
        if usedSlots > allowedSlots {
            throw RuntimeError.invalidConfiguration(reason: "装備枠を超過しています（装備数: \(usedSlots) / 上限: \(allowedSlots)）")
        }

        // スペルブック
        let spellbook = try SkillRuntimeEffectCompiler.spellbook(from: learnedSkills)
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

        // 戦闘ステータス計算
        let calcContext = CombatStatCalculator.Context(
            raceId: input.raceId,
            jobId: input.jobId,
            level: input.level,
            currentHP: input.currentHP,
            equippedItems: equippedItemsValues,
            race: race,
            job: job,
            personalitySecondary: secondaryPersonality,
            learnedSkills: learnedSkills,
            loadout: RuntimeCharacter.Loadout(
                items: loadout.items,
                titles: loadout.titles,
                superRareTitles: loadout.superRareTitles
            ),
            pandoraBoxStackKeys: pandoraBoxStackKeys
        )

        let calcResult = try CombatStatCalculator.calculate(for: calcContext)

        // isMartialEligible判定
        let isMartialEligible = calcResult.combat.isMartialEligible ||
            (calcResult.combat.physicalAttack > 0 && !hasPositivePhysicalAttackBonus(input: input, loadout: loadout))

        // 蘇生パッシブチェック
        var resolvedCurrentHP = min(input.currentHP, calcResult.hitPoints.maximum)
        if resolvedCurrentHP <= 0 {
            let effects = try SkillRuntimeEffectCompiler.actorEffects(from: learnedSkills)
            if effects.resurrection.passiveBetweenFloors {
                resolvedCurrentHP = max(1, calcResult.hitPoints.maximum)
            }
        }

        // combatにisMartialEligibleを設定
        var combat = calcResult.combat
        combat.isMartialEligible = isMartialEligible

        return RuntimeCharacter(
            id: input.id,
            displayName: input.displayName,
            raceId: input.raceId,
            jobId: input.jobId,
            previousJobId: input.previousJobId,
            avatarId: input.avatarId,
            level: input.level,
            experience: input.experience,
            currentHP: resolvedCurrentHP,
            equippedItems: input.equippedItems,
            primaryPersonalityId: input.primaryPersonalityId,
            secondaryPersonalityId: input.secondaryPersonalityId,
            actionRateAttack: input.actionRateAttack,
            actionRatePriestMagic: input.actionRatePriestMagic,
            actionRateMageMagic: input.actionRateMageMagic,
            actionRateBreath: input.actionRateBreath,
            updatedAt: input.updatedAt,
            attributes: calcResult.attributes,
            maxHP: calcResult.hitPoints.maximum,
            combat: combat,
            equipmentCapacity: allowedSlots,
            race: race,
            job: job,
            personalityPrimary: primaryPersonality,
            personalitySecondary: secondaryPersonality,
            learnedSkills: learnedSkills,
            loadout: loadout,
            spellbook: spellbook,
            spellLoadout: spellLoadout
        )
    }

    // MARK: - Private

    private static func assembleLoadout(
        masterData: MasterDataCache,
        from equippedItems: [CharacterInput.EquippedItem]
    ) -> RuntimeCharacter.Loadout {
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

        return RuntimeCharacter.Loadout(
            items: items,
            titles: titles,
            superRareTitles: superRareTitles
        )
    }

    private static func hasPositivePhysicalAttackBonus(
        input: CharacterInput,
        loadout: RuntimeCharacter.Loadout
    ) -> Bool {
        guard !input.equippedItems.isEmpty else { return false }
        let definitionsById = Dictionary(uniqueKeysWithValues: loadout.items.map { ($0.id, $0) })
        for equipment in input.equippedItems {
            guard let definition = definitionsById[equipment.itemId] else { continue }
            if definition.combatBonuses.physicalAttack * equipment.quantity > 0 { return true }
        }
        return false
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
