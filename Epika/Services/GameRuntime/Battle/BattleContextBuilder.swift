import Foundation

struct BattleContextBuilder {
    static func makePlayerActors(from party: RuntimePartyState) throws -> [BattleActor] {
        let members = party.members
            .filter { !$0.isReserve && $0.character.progress.hitPoints.maximum > 0 }
            .sorted { $0.order < $1.order }

        var actors: [BattleActor] = []
        actors.reserveCapacity(members.count)

        for (index, member) in members.enumerated() {
            guard let slot = BattleContextBuilder.slot(for: index) else { continue }
            let snapshot = member.character.combatSnapshot
            let state = member.character
            let resources = BattleActionResource.makeDefault(for: snapshot)
            let skillEffects = try SkillRuntimeEffectCompiler.actorEffects(from: state.learnedSkills)
            let martialEligible = state.isMartialEligible
            let actor = BattleActor(
                identifier: member.id.uuidString,
                displayName: state.progress.displayName,
                kind: .player,
                formationSlot: slot,
                strength: state.progress.attributes.strength,
                wisdom: state.progress.attributes.wisdom,
                spirit: state.progress.attributes.spirit,
                vitality: state.progress.attributes.vitality,
                agility: state.progress.attributes.agility,
                luck: state.progress.attributes.luck,
                partyMemberId: member.id,
                level: state.progress.level,
                jobName: state.job?.name ?? state.progress.jobId,
                avatarIdentifier: state.progress.avatarIdentifier,
                isMartialEligible: martialEligible,
                raceId: state.progress.raceId,
                raceCategory: state.race?.category,
                snapshot: snapshot,
                currentHP: state.progress.hitPoints.current,
                actionRates: BattleContextBuilder.playerActionRates(for: state),
                actionResources: resources,
                barrierCharges: skillEffects.barrierCharges,
                skillEffects: skillEffects,
                spellbook: state.spellbook,
                spells: state.spellLoadout
            )
            actors.append(actor)
        }

        return actors
    }

    static func slot(for index: Int) -> BattleFormationSlot? {
        guard index >= 0 && index < BattleFormationSlot.allCases.count else { return nil }
        return BattleFormationSlot.allCases[index]
    }

    private static func playerActionRates(for character: RuntimeCharacterState) -> BattleActionRates {
        let preferences = character.progress.actionPreferences
        let breath = character.combatSnapshot.breathDamage > 0 ? preferences.breath : 0
        return BattleActionRates(attack: preferences.attack,
                                 clericMagic: preferences.clericMagic,
                                 arcaneMagic: preferences.arcaneMagic,
                                 breath: breath)
    }

}
