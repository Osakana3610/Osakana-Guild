// ==============================================================================
// SQLiteMasterDataQueries.Items.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アイテム定義の取得クエリを提供
//   - アイテム基本情報、ステータスボーナス、戦闘ボーナス、装備制限等を結合
//
// 【公開API】
//   - fetchAllItems() -> [ItemDefinition]
//
// 【使用箇所】
//   - MasterDataLoader.load(manager:)
//
// ==============================================================================

import Foundation
import SQLite3

// MARK: - Items
extension SQLiteMasterDataManager {
    func fetchAllItems() throws -> [ItemDefinition] {
        struct StatBonusesBuilder {
            var strength: Int = 0
            var wisdom: Int = 0
            var spirit: Int = 0
            var vitality: Int = 0
            var agility: Int = 0
            var luck: Int = 0

            mutating func apply(stat: BaseStat, value: Int) {
                switch stat {
                case .strength: strength = value
                case .wisdom: wisdom = value
                case .spirit: spirit = value
                case .vitality: vitality = value
                case .agility: agility = value
                case .luck: luck = value
                }
            }

            func build() -> ItemDefinition.StatBonuses {
                ItemDefinition.StatBonuses(
                    strength: strength, wisdom: wisdom, spirit: spirit,
                    vitality: vitality, agility: agility, luck: luck
                )
            }
        }

        struct CombatBonusesBuilder {
            var maxHP: Int = 0
            var physicalAttack: Int = 0
            var magicalAttack: Int = 0
            var physicalDefense: Int = 0
            var magicalDefense: Int = 0
            var hitRate: Int = 0
            var evasionRate: Int = 0
            var criticalRate: Int = 0
            var attackCount: Int = 0
            var magicalHealing: Int = 0
            var trapRemoval: Int = 0
            var additionalDamage: Int = 0
            var breathDamage: Int = 0

            mutating func apply(stat: CombatStat, value: Int) {
                switch stat {
                case .maxHP: maxHP = value
                case .physicalAttack: physicalAttack = value
                case .magicalAttack: magicalAttack = value
                case .physicalDefense: physicalDefense = value
                case .magicalDefense: magicalDefense = value
                case .hitRate: hitRate = value
                case .evasionRate: evasionRate = value
                case .criticalRate: criticalRate = value
                case .attackCount: attackCount = value
                case .magicalHealing: magicalHealing = value
                case .trapRemoval: trapRemoval = value
                case .additionalDamage: additionalDamage = value
                case .breathDamage: breathDamage = value
                }
            }

            func build() -> ItemDefinition.CombatBonuses {
                ItemDefinition.CombatBonuses(
                    maxHP: maxHP, physicalAttack: physicalAttack, magicalAttack: magicalAttack,
                    physicalDefense: physicalDefense, magicalDefense: magicalDefense,
                    hitRate: hitRate, evasionRate: evasionRate, criticalRate: criticalRate, attackCount: attackCount,
                    magicalHealing: magicalHealing, trapRemoval: trapRemoval,
                    additionalDamage: additionalDamage, breathDamage: breathDamage
                )
            }
        }

        struct Builder {
            var id: UInt16
            var name: String
            var category: UInt8
            var basePrice: Int
            var sellValue: Int
            var rarity: UInt8?
            var statBonuses = StatBonusesBuilder()
            var combatBonuses = CombatBonusesBuilder()
            var allowedRaceIds: Set<UInt8> = []
            var allowedJobIds: Set<UInt8> = []
            var allowedGenderCodes: Set<UInt8> = []
            var bypassRaceIds: Set<UInt8> = []
            var grantedSkillIds: [UInt16] = []
        }

        var builders: [UInt16: Builder] = [:]
        var orderedIds: [UInt16] = []

        let itemSQL = "SELECT id, name, category, base_price, sell_value, rarity FROM items ORDER BY id;"
        let itemStatement = try prepare(itemSQL)
        defer { sqlite3_finalize(itemStatement) }
        while sqlite3_step(itemStatement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(itemStatement, 1) else { continue }
            let id = UInt16(sqlite3_column_int(itemStatement, 0))
            let name = String(cString: nameC)
            let category = UInt8(sqlite3_column_int(itemStatement, 2))
            let basePrice = Int(sqlite3_column_int(itemStatement, 3))
            let sellValue = Int(sqlite3_column_int(itemStatement, 4))
            // rarityはUInt8としてそのまま取得（NULLの場合はnil）
            let rarityValue: UInt8? = sqlite3_column_type(itemStatement, 5) != SQLITE_NULL
                ? UInt8(sqlite3_column_int(itemStatement, 5))
                : nil
            builders[id] = Builder(
                id: id,
                name: name,
                category: category,
                basePrice: basePrice,
                sellValue: sellValue,
                rarity: rarityValue
            )
            orderedIds.append(id)
        }

        func applyPairs(sql: String, handler: (inout Builder, OpaquePointer) -> Void) throws {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = UInt16(sqlite3_column_int(statement, 0))
                guard var builder = builders[id] else { continue }
                handler(&builder, statement)
                builders[id] = builder
            }
        }

        try applyPairs(sql: "SELECT item_id, stat, value FROM item_stat_bonuses;") { builder, statement in
            let statRaw = UInt8(sqlite3_column_int(statement, 1))
            guard let stat = BaseStat(rawValue: statRaw) else { return }
            let value = Int(sqlite3_column_int(statement, 2))
            builder.statBonuses.apply(stat: stat, value: value)
        }

        try applyPairs(sql: "SELECT item_id, stat, value FROM item_combat_bonuses;") { builder, statement in
            let statRaw = UInt8(sqlite3_column_int(statement, 1))
            guard let stat = CombatStat(rawValue: statRaw) else { return }
            let value = Int(sqlite3_column_int(statement, 2))
            builder.combatBonuses.apply(stat: stat, value: value)
        }

        try applyPairs(sql: "SELECT item_id, race_id FROM item_allowed_races;") { builder, statement in
            let raceId = UInt8(sqlite3_column_int(statement, 1))
            builder.allowedRaceIds.insert(raceId)
        }

        try applyPairs(sql: "SELECT item_id, job_id FROM item_allowed_jobs;") { builder, statement in
            let jobId = UInt8(sqlite3_column_int(statement, 1))
            builder.allowedJobIds.insert(jobId)
        }

        try applyPairs(sql: "SELECT item_id, gender FROM item_allowed_genders;") { builder, statement in
            let genderCode = UInt8(sqlite3_column_int(statement, 1))
            builder.allowedGenderCodes.insert(genderCode)
        }

        try applyPairs(sql: "SELECT item_id, race_id FROM item_bypass_race_restrictions;") { builder, statement in
            let raceId = UInt8(sqlite3_column_int(statement, 1))
            builder.bypassRaceIds.insert(raceId)
        }

        // ORDER BY order_index で取得しているため、配列の順序は保持される
        let skillStatement = try prepare("SELECT item_id, skill_id FROM item_granted_skills ORDER BY item_id, order_index;")
        defer { sqlite3_finalize(skillStatement) }
        while sqlite3_step(skillStatement) == SQLITE_ROW {
            let id = UInt16(sqlite3_column_int(skillStatement, 0))
            guard var builder = builders[id] else { continue }
            let skillId = UInt16(sqlite3_column_int(skillStatement, 1))
            builder.grantedSkillIds.append(skillId)
            builders[builder.id] = builder
        }

        return orderedIds.compactMap { builders[$0] }.map { builder in
            ItemDefinition(
                id: builder.id,
                name: builder.name,
                category: builder.category,
                basePrice: builder.basePrice,
                sellValue: builder.sellValue,
                rarity: builder.rarity,
                statBonuses: builder.statBonuses.build(),
                combatBonuses: builder.combatBonuses.build(),
                allowedRaceIds: Array(builder.allowedRaceIds).sorted(),
                allowedJobIds: Array(builder.allowedJobIds).sorted(),
                allowedGenderCodes: Array(builder.allowedGenderCodes).sorted(),
                bypassRaceIds: Array(builder.bypassRaceIds).sorted(),
                grantedSkillIds: builder.grantedSkillIds  // ORDER BY order_index でソート済み
            )
        }
    }
}
