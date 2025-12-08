import Foundation

/// CharacterInputからRuntimeCharacterを生成するファクトリ。
/// マスターデータ取得と戦闘ステータス計算を行う。
enum RuntimeCharacterFactory {

    static func make(
        from input: CharacterInput,
        repository: MasterDataRepository,
        pandoraBoxStackKeys: Set<String> = []
    ) async throws -> RuntimeCharacter {

        // マスターデータ取得
        async let raceDef = repository.race(withId: input.raceId)
        async let jobDef = repository.job(withId: input.jobId)
        async let primaryDef = repository.personalityPrimary(withId: input.primaryPersonalityId)
        async let secondaryDef = repository.personalitySecondary(withId: input.secondaryPersonalityId)
        async let spellDefinitions = repository.allSpells()

        let race = try await raceDef
        let job = try await jobDef
        let primaryPersonality = try await primaryDef
        let secondaryPersonality = try await secondaryDef

        // 装備からアイテム定義を取得
        let itemIds = Set(input.equippedItems.map { $0.itemId }).filter { $0 > 0 }
        let equippedItemDefinitions = try await MasterDataRuntimeService.shared.getItemMasterData(ids: Array(itemIds))

        // 装備から付与されるスキルIDを収集
        let grantedSkillIds = equippedItemDefinitions.flatMap { $0.grantedSkills.map { $0.skillId } }
        let learnedSkills = try await repository.skills(withIds: grantedSkillIds)

        // 装備スロット計算
        let slotModifiers = try SkillRuntimeEffectCompiler.equipmentSlots(from: learnedSkills)
        let allowedSlots = EquipmentSlotCalculator.capacity(forLevel: input.level, modifiers: slotModifiers)
        let usedSlots = input.equippedItems.reduce(0) { $0 + max(0, $1.quantity) }
        if usedSlots > allowedSlots {
            throw RuntimeError.invalidConfiguration(reason: "装備枠を超過しています（装備数: \(usedSlots) / 上限: \(allowedSlots)）")
        }

        // Loadout構築
        let loadout = try await assembleLoadout(repository: repository, from: input.equippedItems)

        // スペルブック
        let spellbook = try SkillRuntimeEffectCompiler.spellbook(from: learnedSkills)
        let spells = try await spellDefinitions
        let spellLoadout = SkillRuntimeEffectCompiler.spellLoadout(from: spellbook, definitions: spells)

        // 戦闘ステータス計算（CombatStatCalculatorは旧形式を使用するため互換形式を構築）
        let tempProgress = makeTemporaryProgress(from: input)
        let tempState = RuntimeCharacterState(
            progress: tempProgress,
            race: race,
            job: job,
            personalityPrimary: primaryPersonality,
            personalitySecondary: secondaryPersonality,
            learnedSkills: learnedSkills,
            loadout: RuntimeCharacterState.Loadout(
                items: loadout.items,
                titles: loadout.titles,
                superRareTitles: loadout.superRareTitles
            ),
            spellbook: spellbook,
            spellLoadout: spellLoadout
        )

        let calcContext = CombatStatCalculator.Context(
            progress: tempProgress,
            state: tempState,
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
            if effects.resurrectionPassiveBetweenFloors {
                resolvedCurrentHP = max(1, calcResult.hitPoints.maximum)
            }
        }

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
            attributes: RuntimeCharacter.CoreAttributes(
                strength: calcResult.attributes.strength,
                wisdom: calcResult.attributes.wisdom,
                spirit: calcResult.attributes.spirit,
                vitality: calcResult.attributes.vitality,
                agility: calcResult.attributes.agility,
                luck: calcResult.attributes.luck
            ),
            maxHP: calcResult.hitPoints.maximum,
            combat: RuntimeCharacter.Combat(
                maxHP: calcResult.combat.maxHP,
                physicalAttack: calcResult.combat.physicalAttack,
                magicalAttack: calcResult.combat.magicalAttack,
                physicalDefense: calcResult.combat.physicalDefense,
                magicalDefense: calcResult.combat.magicalDefense,
                hitRate: calcResult.combat.hitRate,
                evasionRate: calcResult.combat.evasionRate,
                criticalRate: calcResult.combat.criticalRate,
                attackCount: calcResult.combat.attackCount,
                magicalHealing: calcResult.combat.magicalHealing,
                trapRemoval: calcResult.combat.trapRemoval,
                additionalDamage: calcResult.combat.additionalDamage,
                breathDamage: calcResult.combat.breathDamage
            ),
            isMartialEligible: isMartialEligible,
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
        repository: MasterDataRepository,
        from equippedItems: [CharacterInput.EquippedItem]
    ) async throws -> RuntimeCharacter.Loadout {
        // アイテムIDを収集（装備とソケット宝石）
        var itemIds = Set(equippedItems.map { $0.itemId })
        let socketItemIds = Set(equippedItems.map { $0.socketItemId }).filter { $0 > 0 }
        itemIds.formUnion(socketItemIds)
        let items = try await repository.items(withIds: Array(itemIds.filter { $0 > 0 }))

        // 通常称号IDを収集（装備とソケット宝石）
        var normalTitleIds = Set(equippedItems.map { $0.normalTitleId })
        let socketNormalTitleIds = Set(equippedItems.map { $0.socketNormalTitleId })
        normalTitleIds.formUnion(socketNormalTitleIds)
        var titles: [TitleDefinition] = []
        for titleId in normalTitleIds where titleId > 0 {
            if let definition = try await repository.title(withId: titleId) {
                titles.append(definition)
            }
        }

        // 超レア称号IDを収集（装備とソケット宝石）
        var superRareTitleIds = Set(equippedItems.map { $0.superRareTitleId })
        let socketSuperRareTitleIds = Set(equippedItems.map { $0.socketSuperRareTitleId })
        superRareTitleIds.formUnion(socketSuperRareTitleIds)
        var superRareTitles: [SuperRareTitleDefinition] = []
        for titleId in superRareTitleIds where titleId > 0 {
            if let definition = try await repository.superRareTitle(withId: titleId) {
                superRareTitles.append(definition)
            }
        }

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
            for bonus in definition.combatBonuses where bonus.stat == "physicalAttack" {
                if bonus.value * equipment.quantity > 0 { return true }
            }
        }
        return false
    }

    /// CharacterInputからCombatStatCalculator用の一時的なRuntimeCharacterProgressを作成
    private static func makeTemporaryProgress(from input: CharacterInput) -> RuntimeCharacterProgress {
        let equippedItems = input.equippedItems.map { item in
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

        let dummyAttributes = CharacterValues.CoreAttributes(
            strength: 0, wisdom: 0, spirit: 0, vitality: 0, agility: 0, luck: 0
        )
        let dummyHitPoints = CharacterValues.HitPoints(current: input.currentHP, maximum: 100)
        let dummyCombat = CharacterValues.Combat(
            maxHP: 100, physicalAttack: 0, magicalAttack: 0,
            physicalDefense: 0, magicalDefense: 0, hitRate: 0, evasionRate: 0,
            criticalRate: 0, attackCount: 1, magicalHealing: 0, trapRemoval: 0,
            additionalDamage: 0, breathDamage: 0, isMartialEligible: false
        )
        let personality = CharacterValues.Personality(
            primaryId: input.primaryPersonalityId,
            secondaryId: input.secondaryPersonalityId
        )
        let actionPreferences = CharacterValues.ActionPreferences(
            attack: input.actionRateAttack,
            priestMagic: input.actionRatePriestMagic,
            mageMagic: input.actionRateMageMagic,
            breath: input.actionRateBreath
        )

        return RuntimeCharacterProgress(
            id: input.id,
            displayName: input.displayName,
            raceId: input.raceId,
            jobId: input.jobId,
            avatarId: input.avatarId,
            level: input.level,
            experience: input.experience,
            attributes: dummyAttributes,
            hitPoints: dummyHitPoints,
            combat: dummyCombat,
            personality: personality,
            learnedSkills: [],
            equippedItems: equippedItems,
            jobHistory: [],
            explorationTags: [],
            achievements: CharacterValues.AchievementCounters(totalBattles: 0, totalVictories: 0, defeatCount: 0),
            actionPreferences: actionPreferences,
            createdAt: input.updatedAt,
            updatedAt: input.updatedAt
        )
    }
}

// MARK: - Equipment Slot Calculator

private enum EquipmentSlotCalculator {
    static func capacity(forLevel level: Int, modifiers: SkillRuntimeEffects.EquipmentSlots) -> Int {
        let base = baseCapacity(forLevel: level)
        let scaled = Double(base) * max(0.0, modifiers.multiplier)
        let adjusted = Int(scaled.rounded()) + modifiers.additive
        return max(1, adjusted)
    }

    private static func baseCapacity(forLevel rawLevel: Int) -> Int {
        let level = max(1, rawLevel)
        if level <= 18 {
            let value = 0.34 * Double(level * level) + 0.55 * Double(level)
            return max(1, Int(value.rounded()))
        }
        return max(1, 118 + (level - 18) * 16)
    }
}
