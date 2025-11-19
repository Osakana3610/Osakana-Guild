import Foundation

enum CharacterAssembler {
    static func assembleState(repository: MasterDataRepository,
                              from progress: RuntimeCharacterProgress) async throws -> RuntimeCharacterState {
        async let raceDef = repository.race(withId: progress.raceId)
        async let jobDef = repository.job(withId: progress.jobId)
        async let spellDefinitions = repository.allSpells()

        let learnedSkillIds = progress.learnedSkills.map { $0.skillId }
        let learnedSkills = try await repository.skills(withIds: learnedSkillIds)

        var revivedProgress = progress
        if revivedProgress.hitPoints.current <= 0 {
            let effects = try SkillRuntimeEffectCompiler.actorEffects(from: learnedSkills)
            if effects.resurrectionPassiveBetweenFloors {
                revivedProgress.hitPoints = .init(current: max(1, revivedProgress.hitPoints.maximum),
                                                  maximum: revivedProgress.hitPoints.maximum)
            }
        }

        let loadout = try await assembleLoadout(repository: repository, from: revivedProgress.equippedItems)
        var primary: PersonalityPrimaryDefinition? = nil
        if let primaryId = revivedProgress.personality.primaryId {
            primary = try await repository.personalityPrimary(withId: primaryId)
        }
        var secondary: PersonalitySecondaryDefinition? = nil
        if let secondaryId = revivedProgress.personality.secondaryId {
            secondary = try await repository.personalitySecondary(withId: secondaryId)
        }

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
            spellLoadout: state.spellLoadout
        )
    }

    private static func assembleLoadout(repository: MasterDataRepository,
                                        from equippedItems: [RuntimeCharacterProgress.EquippedItem]) async throws -> RuntimeCharacterState.Loadout {
        let itemIds = Set(equippedItems.map { $0.itemId })
        let normalTitleIds = Set(equippedItems.compactMap { $0.normalTitleId })
        let superRareTitleIds = Set(equippedItems.compactMap { $0.superRareTitleId })

        let items = try await repository.items(withIds: Array(itemIds))
        var titles: [TitleDefinition] = []
        for id in normalTitleIds {
            if let definition = try await repository.title(withId: id) {
                titles.append(definition)
            }
        }
        var superRareTitles: [SuperRareTitleDefinition] = []
        for id in superRareTitleIds {
            if let definition = try await repository.superRareTitle(withId: id) {
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
