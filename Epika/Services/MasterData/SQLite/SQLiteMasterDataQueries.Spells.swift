import Foundation
import SQLite3

// MARK: - Spells
extension SQLiteMasterDataManager {
    func fetchAllSpells() throws -> [SpellDefinition] {
        struct Builder {
            let id: UInt8
            let name: String
            let school: SpellDefinition.School
            let tier: Int
            let category: SpellDefinition.Category
            let targeting: SpellDefinition.Targeting
            let maxTargetsBase: Int?
            let extraTargetsPerLevels: Double?
            let hitsPerCast: Int?
            let basePowerMultiplier: Double?
            let statusId: UInt8?
            let healMultiplier: Double?
            let castCondition: String?
            let description: String
            var buffs: [SpellDefinition.Buff] = []
        }

        func optionalInt(_ statement: OpaquePointer, _ index: Int32) -> Int? {
            sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, index))
        }

        func optionalDouble(_ statement: OpaquePointer, _ index: Int32) -> Double? {
            sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_double(statement, index)
        }

        func optionalText(_ statement: OpaquePointer, _ index: Int32) -> String? {
            guard let text = sqlite3_column_text(statement, index) else { return nil }
            return String(cString: text)
        }

        var builders: [UInt8: Builder] = [:]
        var order: [UInt8] = []
        let spellSQL = """
            SELECT id, name, school, tier, category, targeting,
                   max_targets_base, extra_targets_per_levels,
                   hits_per_cast, base_power_multiplier,
                   status_id, heal_multiplier, cast_condition,
                   description
            FROM spells;
        """
        let spellStatement = try prepare(spellSQL)
        defer { sqlite3_finalize(spellStatement) }
        while sqlite3_step(spellStatement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(spellStatement, 1),
                  let descriptionC = sqlite3_column_text(spellStatement, 13) else {
                continue
            }
            let id = UInt8(sqlite3_column_int(spellStatement, 0))
            let schoolRaw = UInt8(sqlite3_column_int(spellStatement, 2))
            let categoryRaw = UInt8(sqlite3_column_int(spellStatement, 4))
            let targetingRaw = UInt8(sqlite3_column_int(spellStatement, 5))

            guard let school = SpellDefinition.School(rawValue: schoolRaw) else {
                throw SQLiteMasterDataError.executionFailed("未知の Spell school \(schoolRaw) (id=\(id))")
            }
            guard let category = SpellDefinition.Category(rawValue: categoryRaw) else {
                throw SQLiteMasterDataError.executionFailed("未知の Spell category \(categoryRaw) (id=\(id))")
            }
            guard let targeting = SpellDefinition.Targeting(rawValue: targetingRaw) else {
                throw SQLiteMasterDataError.executionFailed("未知の Spell targeting \(targetingRaw) (id=\(id))")
            }

            let builder = Builder(
                id: id,
                name: String(cString: nameC),
                school: school,
                tier: Int(sqlite3_column_int(spellStatement, 3)),
                category: category,
                targeting: targeting,
                maxTargetsBase: optionalInt(spellStatement, 6),
                extraTargetsPerLevels: optionalDouble(spellStatement, 7),
                hitsPerCast: optionalInt(spellStatement, 8),
                basePowerMultiplier: optionalDouble(spellStatement, 9),
                statusId: sqlite3_column_type(spellStatement, 10) == SQLITE_NULL ? nil : UInt8(sqlite3_column_int(spellStatement, 10)),
                healMultiplier: optionalDouble(spellStatement, 11),
                castCondition: optionalText(spellStatement, 12),
                description: String(cString: descriptionC)
            )
            builders[id] = builder
            order.append(id)
        }

        let buffSQL = "SELECT spell_id, order_index, type, multiplier FROM spell_buffs ORDER BY spell_id, order_index;"
        let buffStatement = try prepare(buffSQL)
        defer { sqlite3_finalize(buffStatement) }
        while sqlite3_step(buffStatement) == SQLITE_ROW {
            let spellId = UInt8(sqlite3_column_int(buffStatement, 0))
            guard var builder = builders[spellId] else { continue }
            let orderIndex = Int(sqlite3_column_int(buffStatement, 1))
            let typeRaw = UInt8(sqlite3_column_int(buffStatement, 2))
            let multiplier = sqlite3_column_double(buffStatement, 3)
            guard let buffType = SpellDefinition.Buff.BuffType(rawValue: typeRaw) else {
                throw SQLiteMasterDataError.executionFailed("未知の Spell buff type \(typeRaw) (spell_id=\(spellId))")
            }
            let buff = SpellDefinition.Buff(type: buffType, multiplier: multiplier)
            if builder.buffs.count <= orderIndex {
                builder.buffs.append(buff)
            } else {
                builder.buffs.insert(buff, at: min(orderIndex, builder.buffs.count))
            }
            builders[spellId] = builder
        }

        var definitions: [SpellDefinition] = []
        definitions.reserveCapacity(order.count)
        for id in order {
            guard let builder = builders[id] else { continue }
            definitions.append(
                SpellDefinition(
                    id: builder.id,
                    name: builder.name,
                    school: builder.school,
                    tier: builder.tier,
                    category: builder.category,
                    targeting: builder.targeting,
                    maxTargetsBase: builder.maxTargetsBase,
                    extraTargetsPerLevels: builder.extraTargetsPerLevels,
                    hitsPerCast: builder.hitsPerCast,
                    basePowerMultiplier: builder.basePowerMultiplier,
                    statusId: builder.statusId,
                    buffs: builder.buffs,
                    healMultiplier: builder.healMultiplier,
                    castCondition: builder.castCondition,
                    description: builder.description
                )
            )
        }

        return definitions
    }
}
