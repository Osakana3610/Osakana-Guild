import Foundation
import SQLite3

extension SQLiteMasterDataManager {
    func importSpellMaster(_ data: Data) async throws -> Int {
        let root = try await MainActor.run { () throws -> SpellMasterRoot in
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(SpellMasterRoot.self, from: data)
        }

        try withTransaction {
            try execute("DELETE FROM spell_buffs;")
            try execute("DELETE FROM spells;")

            let insertSpellSQL = """
                INSERT INTO spells (
                    id, name, school, tier, category, targeting,
                    max_targets_base, extra_targets_per_levels,
                    hits_per_cast, base_power_multiplier,
                    status_id, heal_multiplier, cast_condition,
                    description
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let insertBuffSQL = """
                INSERT INTO spell_buffs (spell_id, order_index, type, multiplier)
                VALUES (?, ?, ?, ?);
            """

            let spellStatement = try prepare(insertSpellSQL)
            let buffStatement = try prepare(insertBuffSQL)
            defer {
                sqlite3_finalize(spellStatement)
                sqlite3_finalize(buffStatement)
            }

            for spell in root.spells {
                bindText(spellStatement, index: 1, value: spell.id)
                bindText(spellStatement, index: 2, value: spell.name)
                bindText(spellStatement, index: 3, value: spell.school)
                bindInt(spellStatement, index: 4, value: spell.tier)
                bindText(spellStatement, index: 5, value: spell.category)
                bindText(spellStatement, index: 6, value: spell.targeting)
                bindInt(spellStatement, index: 7, value: spell.maxTargetsBase)
                bindDouble(spellStatement, index: 8, value: spell.extraTargetsPerLevels)
                bindInt(spellStatement, index: 9, value: spell.hitsPerCast)
                bindDouble(spellStatement, index: 10, value: spell.basePowerMultiplier)
                bindText(spellStatement, index: 11, value: spell.statusId)
                bindDouble(spellStatement, index: 12, value: spell.healMultiplier)
                bindText(spellStatement, index: 13, value: spell.castCondition)
                bindText(spellStatement, index: 14, value: spell.description)
                try step(spellStatement)
                reset(spellStatement)

                let buffs = spell.buffs ?? []
                if !buffs.isEmpty {
                    for (index, buff) in buffs.enumerated() {
                        bindText(buffStatement, index: 1, value: spell.id)
                        bindInt(buffStatement, index: 2, value: index)
                        bindText(buffStatement, index: 3, value: buff.type)
                        bindDouble(buffStatement, index: 4, value: buff.multiplier)
                        try step(buffStatement)
                        reset(buffStatement)
                    }
                }
            }
        }

        return root.spells.count
    }
}

private struct SpellMasterRoot: Decodable {
    let version: String?
    let lastUpdated: String?
    let spells: [SpellEntry]
}

private struct SpellEntry: Decodable {
    struct Buff: Decodable {
        let type: String
        let multiplier: Double
    }

    let id: String
    let name: String
    let school: String
    let tier: Int
    let category: String
    let targeting: String
    let maxTargetsBase: Int?
    let extraTargetsPerLevels: Double?
    let hitsPerCast: Int?
    let basePowerMultiplier: Double?
    let statusId: String?
    let healMultiplier: Double?
    let castCondition: String?
    let description: String
    let buffs: [Buff]?
}
