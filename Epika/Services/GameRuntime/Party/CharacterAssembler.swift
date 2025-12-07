import Foundation

enum CharacterAssembler {
    static func assembleState(repository: MasterDataRepository,
                              from progress: RuntimeCharacterProgress) async throws -> RuntimeCharacterState {
        async let raceDef = repository.race(withId: progress.raceId)
        async let jobDef = repository.job(withId: progress.jobId)
        async let spellDefinitions = repository.allSpells()

        // 装備付与スキルを合成し、先勝ちで重複除去
        let itemIds = Set(progress.equippedItems.map { $0.itemId }).filter { $0 > 0 }
        let equippedItemDefinitions = try await MasterDataRuntimeService.shared.getItemMasterData(ids: Array(itemIds))

        // 装備から付与されるスキルIDを収集
        let grantedSkillIds = equippedItemDefinitions.flatMap { $0.grantedSkills.map { $0.skillId } }
        let grantedSkillDefinitions = try await repository.skills(withIds: grantedSkillIds)
        let validSkillIds = Set(grantedSkillDefinitions.map { $0.id })

        let equipmentSkills: [RuntimeCharacterProgress.LearnedSkill] = equippedItemDefinitions.flatMap { definition in
            definition.grantedSkills.sorted { $0.orderIndex < $1.orderIndex }.compactMap { granted in
                guard validSkillIds.contains(granted.skillId) else { return nil }
                return RuntimeCharacterProgress.LearnedSkill(id: UUID(),
                                                             skillId: granted.skillId,
                                                             level: 1,
                                                             isEquipped: true,
                                                             createdAt: Date(),
                                                             updatedAt: Date())
            }
        }
        let mergedLearnedSkills = deduplicatedSkills(progress.learnedSkills + equipmentSkills)
        let learnedSkillIds = mergedLearnedSkills.map { $0.skillId }
        let learnedSkills = try await repository.skills(withIds: learnedSkillIds)

        let slotModifiers = try SkillRuntimeEffectCompiler.equipmentSlots(from: learnedSkills)
        let allowedSlots = EquipmentSlotCalculator.capacity(forLevel: progress.level,
                                                            modifiers: slotModifiers)
        let usedSlots = EquipmentSlotCalculator.usedSlots(for: progress.equippedItems)
        if usedSlots > allowedSlots {
            throw RuntimeError.invalidConfiguration(reason: "装備枠を超過しています（装備数: \(usedSlots) / 上限: \(allowedSlots)）")
        }

        var revivedProgress = progress
        if revivedProgress.hitPoints.current <= 0 {
            let effects = try SkillRuntimeEffectCompiler.actorEffects(from: learnedSkills)
            if effects.resurrectionPassiveBetweenFloors {
                revivedProgress.hitPoints = .init(current: max(1, revivedProgress.hitPoints.maximum),
                                                  maximum: revivedProgress.hitPoints.maximum)
            }
        }

        let loadout = try await assembleLoadout(repository: repository, from: revivedProgress.equippedItems)
        let primary = try await repository.personalityPrimary(withId: revivedProgress.personality.primaryId)
        let secondary = try await repository.personalitySecondary(withId: revivedProgress.personality.secondaryId)

        let spellbook = try SkillRuntimeEffectCompiler.spellbook(from: learnedSkills)
        let spells = try await spellDefinitions
        let spellLoadout = SkillRuntimeEffectCompiler.spellLoadout(from: spellbook,
                                                                   definitions: spells)

        return RuntimeCharacterState(
            progress: revivedProgress,
            race: try await raceDef,
            job: try await jobDef,
            personalityPrimary: primary,
            personalitySecondary: secondary,
            learnedSkills: learnedSkills,
            loadout: loadout,
            spellbook: spellbook,
            spellLoadout: spellLoadout
        )
    }

    static func assembleRuntimeCharacter(repository: MasterDataRepository,
                                         from progress: RuntimeCharacterProgress) async throws -> RuntimeCharacter {
        let state = try await assembleState(repository: repository, from: progress)
        return RuntimeCharacter(
            progress: state.progress,
            raceData: state.race,
            jobData: state.job,
            masteredSkills: state.learnedSkills,
            statusEffects: [],
            martialEligible: state.isMartialEligible,
            spellbook: state.spellbook,
            spellLoadout: state.spellLoadout,
            loadout: state.loadout
        )
    }

    private static func assembleLoadout(repository: MasterDataRepository,
                                        from equippedItems: [RuntimeCharacterProgress.EquippedItem]) async throws -> RuntimeCharacterState.Loadout {
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

        return RuntimeCharacterState.Loadout(
            items: items,
            titles: titles,
            superRareTitles: superRareTitles
        )
    }
}

private enum EquipmentSlotCalculator {
    static func capacity(forLevel level: Int,
                         modifiers: SkillRuntimeEffects.EquipmentSlots) -> Int {
        let base = baseCapacity(forLevel: level)
        let scaled = Double(base) * max(0.0, modifiers.multiplier)
        let adjusted = Int(scaled.rounded()) + modifiers.additive
        return max(1, adjusted)
    }

    static func usedSlots(for items: [RuntimeCharacterProgress.EquippedItem]) -> Int {
        items.reduce(0) { partial, item in
            let quantity = max(0, item.quantity)
            return partial &+ quantity
        }
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

// MARK: - Helpers

private func deduplicatedSkills(_ skills: [RuntimeCharacterProgress.LearnedSkill]) -> [RuntimeCharacterProgress.LearnedSkill] {
    var seen: Set<UInt16> = []
    var result: [RuntimeCharacterProgress.LearnedSkill] = []
    result.reserveCapacity(skills.count)
    for entry in skills {
        if seen.insert(entry.skillId).inserted {
            result.append(entry)
        }
    }
    return result
}
