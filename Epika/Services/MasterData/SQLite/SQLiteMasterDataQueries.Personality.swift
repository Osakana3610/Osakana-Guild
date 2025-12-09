import Foundation
import SQLite3

// MARK: - Personality
extension SQLiteMasterDataManager {
    func fetchPersonalityData() throws -> (
        primary: [PersonalityPrimaryDefinition],
        secondary: [PersonalitySecondaryDefinition],
        skills: [PersonalitySkillDefinition],
        cancellations: [PersonalityCancellation],
        battleEffects: [PersonalityBattleEffect]
    ) {
        var primary: [UInt8: PersonalityPrimaryDefinition] = [:]
        let primarySQL = "SELECT id, name, description FROM personality_primary ORDER BY id;"
        let primaryStatement = try prepare(primarySQL)
        defer { sqlite3_finalize(primaryStatement) }
        while sqlite3_step(primaryStatement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(primaryStatement, 1),
                  let descriptionC = sqlite3_column_text(primaryStatement, 2) else { continue }
            let id = UInt8(sqlite3_column_int(primaryStatement, 0))
            primary[id] = PersonalityPrimaryDefinition(
                id: id,
                name: String(cString: nameC),
                description: String(cString: descriptionC),
                effects: []
            )
        }

        let primaryEffectSQL = "SELECT personality_id, effect_type, value, payload_json FROM personality_primary_effects ORDER BY personality_id, order_index;"
        let primaryEffectStatement = try prepare(primaryEffectSQL)
        defer { sqlite3_finalize(primaryEffectStatement) }
        while sqlite3_step(primaryEffectStatement) == SQLITE_ROW {
            let id = UInt8(sqlite3_column_int(primaryEffectStatement, 0))
            guard let definition = primary[id],
                  let typeC = sqlite3_column_text(primaryEffectStatement, 1),
                  let payloadC = sqlite3_column_text(primaryEffectStatement, 3) else { continue }
            var effects = definition.effects
            effects.append(.init(effectType: String(cString: typeC),
                                 value: sqlite3_column_type(primaryEffectStatement, 2) == SQLITE_NULL ? nil : sqlite3_column_double(primaryEffectStatement, 2),
                                 payloadJSON: String(cString: payloadC)))
            primary[definition.id] = PersonalityPrimaryDefinition(
                id: definition.id,
                name: definition.name,
                description: definition.description,
                effects: effects
            )
        }

        var secondary: [UInt8: PersonalitySecondaryDefinition] = [:]
        let secondarySQL = "SELECT id, name, positive_skill_id, negative_skill_id FROM personality_secondary ORDER BY id;"
        let secondaryStatement = try prepare(secondarySQL)
        defer { sqlite3_finalize(secondaryStatement) }
        while sqlite3_step(secondaryStatement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(secondaryStatement, 1),
                  let positiveC = sqlite3_column_text(secondaryStatement, 2),
                  let negativeC = sqlite3_column_text(secondaryStatement, 3) else { continue }
            let id = UInt8(sqlite3_column_int(secondaryStatement, 0))
            secondary[id] = PersonalitySecondaryDefinition(
                id: id,
                name: String(cString: nameC),
                positiveSkillId: String(cString: positiveC),
                negativeSkillId: String(cString: negativeC),
                statBonuses: []
            )
        }

        let secondaryStatSQL = "SELECT personality_id, stat, value FROM personality_secondary_stat_bonuses;"
        let secondaryStatStatement = try prepare(secondaryStatSQL)
        defer { sqlite3_finalize(secondaryStatStatement) }
        while sqlite3_step(secondaryStatStatement) == SQLITE_ROW {
            let id = UInt8(sqlite3_column_int(secondaryStatStatement, 0))
            guard let definition = secondary[id],
                  let statC = sqlite3_column_text(secondaryStatStatement, 1) else { continue }
            var bonuses = definition.statBonuses
            bonuses.append(.init(stat: String(cString: statC), value: Int(sqlite3_column_int(secondaryStatStatement, 2))))
            secondary[definition.id] = PersonalitySecondaryDefinition(
                id: definition.id,
                name: definition.name,
                positiveSkillId: definition.positiveSkillId,
                negativeSkillId: definition.negativeSkillId,
                statBonuses: bonuses
            )
        }

        var skills: [String: PersonalitySkillDefinition] = [:]
        let skillSQL = "SELECT id, name, description FROM personality_skills;"
        let skillStatement = try prepare(skillSQL)
        defer { sqlite3_finalize(skillStatement) }
        while sqlite3_step(skillStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(skillStatement, 0),
                  let nameC = sqlite3_column_text(skillStatement, 1),
                  let descriptionC = sqlite3_column_text(skillStatement, 2) else { continue }
            let id = String(cString: idC)
            skills[id] = PersonalitySkillDefinition(
                id: id,
                name: String(cString: nameC),
                description: String(cString: descriptionC),
                eventEffects: []
            )
        }

        let skillEffectSQL = "SELECT skill_id, effect_id FROM personality_skill_event_effects ORDER BY skill_id, order_index;"
        let skillEffectStatement = try prepare(skillEffectSQL)
        defer { sqlite3_finalize(skillEffectStatement) }
        while sqlite3_step(skillEffectStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(skillEffectStatement, 0),
                  let definition = skills[String(cString: idC)],
                  let effectC = sqlite3_column_text(skillEffectStatement, 1) else { continue }
            var effects = definition.eventEffects
            effects.append(.init(effectId: String(cString: effectC)))
            skills[definition.id] = PersonalitySkillDefinition(
                id: definition.id,
                name: definition.name,
                description: definition.description,
                eventEffects: effects
            )
        }

        var cancellations: [PersonalityCancellation] = []
        let cancelSQL = "SELECT positive_skill_id, negative_skill_id FROM personality_cancellations;"
        let cancelStatement = try prepare(cancelSQL)
        defer { sqlite3_finalize(cancelStatement) }
        while sqlite3_step(cancelStatement) == SQLITE_ROW {
            guard let positiveC = sqlite3_column_text(cancelStatement, 0),
                  let negativeC = sqlite3_column_text(cancelStatement, 1) else { continue }
            cancellations.append(.init(positiveSkillId: String(cString: positiveC), negativeSkillId: String(cString: negativeC)))
        }

        var battleEffects: [PersonalityBattleEffect] = []
        let battleSQL = "SELECT category, payload_json FROM personality_battle_effects;"
        let battleStatement = try prepare(battleSQL)
        defer { sqlite3_finalize(battleStatement) }
        while sqlite3_step(battleStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(battleStatement, 0),
                  let payloadC = sqlite3_column_text(battleStatement, 1) else { continue }
            battleEffects.append(.init(id: String(cString: idC), payloadJSON: String(cString: payloadC)))
        }

        return (
            primary.values.sorted { $0.id < $1.id },
            secondary.values.sorted { $0.id < $1.id },
            skills.values.sorted { $0.name < $1.name },
            cancellations,
            battleEffects
        )
    }
}
