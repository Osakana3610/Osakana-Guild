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

        // Note: personality_primary_effects テーブルは常に空だったため削除済み
        // effects は PersonalityPrimaryDefinition 初期化時に [] が設定される

        var secondary: [UInt8: PersonalitySecondaryDefinition] = [:]
        let secondarySQL = "SELECT id, name, positive_skill_id, negative_skill_id FROM personality_secondary ORDER BY id;"
        let secondaryStatement = try prepare(secondarySQL)
        defer { sqlite3_finalize(secondaryStatement) }
        while sqlite3_step(secondaryStatement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(secondaryStatement, 1) else { continue }
            let id = UInt8(sqlite3_column_int(secondaryStatement, 0))
            let positiveSkillId = UInt8(sqlite3_column_int(secondaryStatement, 2))
            let negativeSkillId = UInt8(sqlite3_column_int(secondaryStatement, 3))
            secondary[id] = PersonalitySecondaryDefinition(
                id: id,
                name: String(cString: nameC),
                positiveSkillId: positiveSkillId,
                negativeSkillId: negativeSkillId,
                statBonuses: []
            )
        }

        let secondaryStatSQL = "SELECT personality_id, stat, value FROM personality_secondary_stat_bonuses;"
        let secondaryStatStatement = try prepare(secondaryStatSQL)
        defer { sqlite3_finalize(secondaryStatStatement) }
        while sqlite3_step(secondaryStatStatement) == SQLITE_ROW {
            let id = UInt8(sqlite3_column_int(secondaryStatStatement, 0))
            guard let definition = secondary[id] else { continue }
            var bonuses = definition.statBonuses
            bonuses.append(.init(stat: UInt8(sqlite3_column_int(secondaryStatStatement, 1)), value: Int(sqlite3_column_int(secondaryStatStatement, 2))))
            secondary[definition.id] = PersonalitySecondaryDefinition(
                id: definition.id,
                name: definition.name,
                positiveSkillId: definition.positiveSkillId,
                negativeSkillId: definition.negativeSkillId,
                statBonuses: bonuses
            )
        }

        var skills: [UInt8: PersonalitySkillDefinition] = [:]
        let skillSQL = "SELECT id, name, description FROM personality_skills;"
        let skillStatement = try prepare(skillSQL)
        defer { sqlite3_finalize(skillStatement) }
        while sqlite3_step(skillStatement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(skillStatement, 1),
                  let descriptionC = sqlite3_column_text(skillStatement, 2) else { continue }
            let id = UInt8(sqlite3_column_int(skillStatement, 0))
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
            let skillId = UInt8(sqlite3_column_int(skillEffectStatement, 0))
            guard let definition = skills[skillId] else { continue }
            let effectId = UInt8(sqlite3_column_int(skillEffectStatement, 1))
            var effects = definition.eventEffects
            effects.append(.init(effectId: effectId))
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
            let positiveId = UInt8(sqlite3_column_int(cancelStatement, 0))
            let negativeId = UInt8(sqlite3_column_int(cancelStatement, 1))
            cancellations.append(.init(positiveSkillId: positiveId, negativeSkillId: negativeId))
        }

        var battleEffects: [PersonalityBattleEffect] = []
        let battleSQL = "SELECT category, payload_json FROM personality_battle_effects;"
        let battleStatement = try prepare(battleSQL)
        defer { sqlite3_finalize(battleStatement) }
        while sqlite3_step(battleStatement) == SQLITE_ROW {
            guard let payloadC = sqlite3_column_text(battleStatement, 1) else { continue }
            let categoryId = String(sqlite3_column_int(battleStatement, 0))
            battleEffects.append(.init(id: categoryId, payloadJSON: String(cString: payloadC)))
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
