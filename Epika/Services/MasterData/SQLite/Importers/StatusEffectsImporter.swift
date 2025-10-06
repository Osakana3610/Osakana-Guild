import Foundation
import SQLite3

private struct StatusEffectMasterFile: Decodable {
    struct StatusEffect: Decodable {
        let id: String
        let name: String
        let description: String
        let category: String
        let durationTurns: Int?
        let tickDamagePercent: Int?
        let actionLocked: Bool?
        let statModifiers: [String: Double]?
        let tags: [String]?
        let applyMessage: String?
        let expireMessage: String?
    }

    let statusEffects: [StatusEffect]
}

extension SQLiteMasterDataManager {
    func importStatusEffectMaster(_ data: Data) async throws -> Int {
        let file = try await MainActor.run { () throws -> StatusEffectMasterFile in
            let decoder = JSONDecoder()
            return try decoder.decode(StatusEffectMasterFile.self, from: data)
        }

        try withTransaction {
            try execute("DELETE FROM status_effects;")

            let insertEffectSQL = """
                INSERT INTO status_effects (id, name, description, category, duration_turns, tick_damage_percent, action_locked, apply_message, expire_message)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let insertTagSQL = "INSERT INTO status_effect_tags (effect_id, order_index, tag) VALUES (?, ?, ?);"
            let insertModifierSQL = "INSERT INTO status_effect_stat_modifiers (effect_id, stat, value) VALUES (?, ?, ?);"

            let effectStatement = try prepare(insertEffectSQL)
            let tagStatement = try prepare(insertTagSQL)
            let modifierStatement = try prepare(insertModifierSQL)
            defer {
                sqlite3_finalize(effectStatement)
                sqlite3_finalize(tagStatement)
                sqlite3_finalize(modifierStatement)
            }

            for effect in file.statusEffects {
                bindText(effectStatement, index: 1, value: effect.id)
                bindText(effectStatement, index: 2, value: effect.name)
                bindText(effectStatement, index: 3, value: effect.description)
                bindText(effectStatement, index: 4, value: effect.category)
                bindInt(effectStatement, index: 5, value: effect.durationTurns)
                bindInt(effectStatement, index: 6, value: effect.tickDamagePercent)
                bindBool(effectStatement, index: 7, value: effect.actionLocked)
                bindText(effectStatement, index: 8, value: effect.applyMessage)
                bindText(effectStatement, index: 9, value: effect.expireMessage)
                try step(effectStatement)
                reset(effectStatement)

                if let tags = effect.tags {
                    for (index, tag) in tags.enumerated() {
                        bindText(tagStatement, index: 1, value: effect.id)
                        bindInt(tagStatement, index: 2, value: index)
                        bindText(tagStatement, index: 3, value: tag)
                        try step(tagStatement)
                        reset(tagStatement)
                    }
                }

                if let modifiers = effect.statModifiers {
                    for (stat, value) in modifiers {
                        bindText(modifierStatement, index: 1, value: effect.id)
                        bindText(modifierStatement, index: 2, value: stat)
                        bindDouble(modifierStatement, index: 3, value: value)
                        try step(modifierStatement)
                        reset(modifierStatement)
                    }
                }
            }
        }

        return file.statusEffects.count
    }
}
