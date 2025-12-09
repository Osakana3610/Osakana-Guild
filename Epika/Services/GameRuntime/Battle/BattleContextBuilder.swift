import Foundation

struct BattleContextBuilder {
    static func makePlayerActors(from party: RuntimePartyState) throws -> [BattleActor] {
        let members = party.members
            .filter { $0.character.hitPoints.maximum > 0 }
            .sorted { $0.order < $1.order }

        var actors: [BattleActor] = []
        actors.reserveCapacity(members.count)

        for (index, member) in members.enumerated() {
            guard let slot = BattleContextBuilder.slot(for: index) else { continue }
            let character = member.character
            let snapshot = character.combat
            var resources = BattleActionResource.makeDefault(for: snapshot,
                                                            spellLoadout: character.spellLoadout)
            let skillEffects = try SkillRuntimeEffectCompiler.actorEffects(from: character.learnedSkills)
            applySpellChargeModifiers(skillEffects: skillEffects,
                                      loadout: character.spellLoadout,
                                      resources: &resources)
            if skillEffects.spell.breathExtraCharges > 0 {
                let current = resources.charges(for: BattleActionResource.Key.breath)
                resources.setCharges(for: BattleActionResource.Key.breath, value: current + skillEffects.spell.breathExtraCharges)
            }
            let martialEligible = character.isMartialEligible
            let actor = BattleActor(
                identifier: String(member.characterId),
                displayName: character.displayName,
                kind: .player,
                formationSlot: slot,
                strength: character.attributes.strength,
                wisdom: character.attributes.wisdom,
                spirit: character.attributes.spirit,
                vitality: character.attributes.vitality,
                agility: character.attributes.agility,
                luck: character.attributes.luck,
                partyMemberId: member.characterId,
                level: character.level,
                jobName: character.job?.name ?? "職業\(character.jobId)",
                avatarIndex: character.avatarId,
                isMartialEligible: martialEligible,
                raceId: character.race?.id,
                snapshot: snapshot,
                currentHP: character.hitPoints.current,
                actionRates: BattleContextBuilder.playerActionRates(for: character),
                actionResources: resources,
                barrierCharges: skillEffects.combat.barrierCharges,
                skillEffects: skillEffects,
                spellbook: character.spellbook,
                spells: character.spellLoadout,
                baseSkillIds: Set(character.learnedSkills.map { $0.id })
            )
            actors.append(actor)
        }

        return actors
    }

    static func slot(for index: Int) -> BattleFormationSlot? {
        guard index >= 0 && index < BattleFormationSlot.allCases.count else { return nil }
        return BattleFormationSlot.allCases[index]
    }

    private static func playerActionRates(for character: RuntimeCharacter) -> BattleActionRates {
        let preferences = character.actionPreferences
        let breath = character.combat.breathDamage > 0 ? preferences.breath : 0
        return BattleActionRates(attack: preferences.attack,
                                 priestMagic: preferences.priestMagic,
                                 mageMagic: preferences.mageMagic,
                                 breath: breath)
    }

}

private extension BattleContextBuilder {
    static func applySpellChargeModifiers(skillEffects: BattleActor.SkillEffects,
                                          loadout: SkillRuntimeEffects.SpellLoadout,
                                          resources: inout BattleActionResource) {
        let spells = loadout.mage + loadout.priest
        guard !spells.isEmpty else { return }
        for spell in spells {
            guard let modifier = skillEffects.spell.chargeModifier(for: spell.id), !modifier.isEmpty else { continue }
            let baseState = resources.spellChargeState(for: spell.id)
                ?? BattleActionResource.SpellChargeState(current: 1, max: 1)
            let baseInitial = baseState.current
            let baseMax = baseState.max
            let newMax = max(modifier.maxOverride ?? baseMax, 0)
            var newInitial = max(0, modifier.initialOverride ?? baseInitial)
            if modifier.initialBonus != 0 {
                newInitial += modifier.initialBonus
            }
            resources.setSpellCharges(for: spell.id,
                                      current: newInitial,
                                      max: newMax)
        }
    }
}
