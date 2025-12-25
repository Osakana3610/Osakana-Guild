// ==============================================================================
// SQLiteMasterDataQueries.StatusEffects.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 状態異常定義の取得クエリを提供
//   - status_effects, tags, stat_modifiers テーブルを結合して構築
//
// 【公開API】
//   - fetchAllStatusEffects() -> [StatusEffectDefinition]
//
// 【使用箇所】
//   - MasterDataLoader.load(manager:)
//
// ==============================================================================

import Foundation
import SQLite3

// MARK: - Status Effects
extension SQLiteMasterDataManager {
    func fetchAllStatusEffects() throws -> [StatusEffectDefinition] {
        var effects: [UInt8: StatusEffectDefinition] = [:]
        let baseSQL = "SELECT id, name, description, duration_turns, tick_damage_percent, action_locked, apply_message, expire_message FROM status_effects;"
        let baseStatement = try prepare(baseSQL)
        defer { sqlite3_finalize(baseStatement) }
        while sqlite3_step(baseStatement) == SQLITE_ROW {
            let id = UInt8(sqlite3_column_int(baseStatement, 0))
            guard let nameC = sqlite3_column_text(baseStatement, 1),
                  let descC = sqlite3_column_text(baseStatement, 2) else { continue }
            let definition = StatusEffectDefinition(
                id: id,
                name: String(cString: nameC),
                description: String(cString: descC),
                durationTurns: sqlite3_column_type(baseStatement, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(baseStatement, 3)),
                tickDamagePercent: sqlite3_column_type(baseStatement, 4) == SQLITE_NULL ? nil : Int(sqlite3_column_int(baseStatement, 4)),
                actionLocked: sqlite3_column_type(baseStatement, 5) == SQLITE_NULL ? nil : sqlite3_column_int(baseStatement, 5) == 1,
                applyMessage: sqlite3_column_text(baseStatement, 6).flatMap { String(cString: $0) },
                expireMessage: sqlite3_column_text(baseStatement, 7).flatMap { String(cString: $0) },
                tags: [],
                statModifiers: [:]
            )
            effects[id] = definition
        }

        // tagsをUInt8配列として読み込み
        let tagSQL = "SELECT effect_id, tag FROM status_effect_tags ORDER BY effect_id, order_index;"
        let tagStatement = try prepare(tagSQL)
        defer { sqlite3_finalize(tagStatement) }
        while sqlite3_step(tagStatement) == SQLITE_ROW {
            let effectId = UInt8(sqlite3_column_int(tagStatement, 0))
            guard let effect = effects[effectId] else { continue }
            let tag = UInt8(sqlite3_column_int(tagStatement, 1))
            var tags = effect.tags
            tags.append(tag)
            effects[effect.id] = StatusEffectDefinition(
                id: effect.id,
                name: effect.name,
                description: effect.description,
                durationTurns: effect.durationTurns,
                tickDamagePercent: effect.tickDamagePercent,
                actionLocked: effect.actionLocked,
                applyMessage: effect.applyMessage,
                expireMessage: effect.expireMessage,
                tags: tags,
                statModifiers: effect.statModifiers
            )
        }

        // statModifiersを辞書形式で読み込み（キーはCombatStatのrawValue）
        let modifierSQL = "SELECT effect_id, stat, value FROM status_effect_stat_modifiers;"
        let modifierStatement = try prepare(modifierSQL)
        defer { sqlite3_finalize(modifierStatement) }
        while sqlite3_step(modifierStatement) == SQLITE_ROW {
            let effectId = UInt8(sqlite3_column_int(modifierStatement, 0))
            guard let effect = effects[effectId] else { continue }
            let stat = UInt8(sqlite3_column_int(modifierStatement, 1))
            var modifiers = effect.statModifiers
            modifiers[stat] = sqlite3_column_double(modifierStatement, 2)
            effects[effect.id] = StatusEffectDefinition(
                id: effect.id,
                name: effect.name,
                description: effect.description,
                durationTurns: effect.durationTurns,
                tickDamagePercent: effect.tickDamagePercent,
                actionLocked: effect.actionLocked,
                applyMessage: effect.applyMessage,
                expireMessage: effect.expireMessage,
                tags: effect.tags,
                statModifiers: modifiers
            )
        }

        return effects.values.sorted { $0.name < $1.name }
    }
}
