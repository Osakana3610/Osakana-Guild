import Foundation
import SQLite3

// MARK: - Item Rarity Int→String逆変換（EnumMappings.itemRarityと同期）
private enum ItemRarityMapping: Sendable {
    nonisolated static func string(from value: Int) -> String? {
        switch value {
        case 1: return "ノーマル"
        case 2: return "Tier1"
        case 3: return "Tier2"
        case 4: return "Tier3"
        case 5: return "Tier4"
        case 6: return "Tier4・斧系"
        case 7: return "エクストラ"
        case 8: return "HP1"
        case 9: return "HP2"
        case 10: return "ブレスレット"
        case 11: return "ブレス系"
        case 12: return "一章"
        case 13: return "二章"
        case 14: return "三章"
        case 15: return "四章"
        case 16: return "五章"
        case 17: return "六章"
        case 18: return "七章"
        case 19: return "格闘"
        case 20: return "格闘系"
        case 21: return "獲得系"
        case 22: return "基礎"
        case 23: return "強化系"
        case 24: return "高級"
        case 25: return "最下級"
        case 26: return "最高級"
        case 27: return "指輪1"
        case 28: return "指輪2"
        case 29: return "指輪3"
        case 30: return "呪文書"
        case 31: return "銃器"
        case 32: return "杖"
        case 33: return "神聖教典"
        case 34: return "僧侶系"
        case 35: return "中級"
        case 36: return "長弓"
        case 37: return "低級"
        case 38: return "投刃"
        case 39: return "特効"
        case 40: return "特殊"
        case 41: return "補助1"
        case 42: return "補助2"
        case 43: return "忘却書"
        case 44: return "魔道教典"
        case 45: return "魔法使い系"
        case 46: return "連射弓"
        case 47: return "罠解除"
        default: return nil
        }
    }
}

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

            mutating func apply(stat: String, value: Int) {
                switch stat {
                case "strength": strength = value
                case "wisdom": wisdom = value
                case "spirit": spirit = value
                case "vitality": vitality = value
                case "agility": agility = value
                case "luck": luck = value
                default: break
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

            mutating func apply(stat: String, value: Int) {
                switch stat {
                case "maxHP": maxHP = value
                case "physicalAttack": physicalAttack = value
                case "magicalAttack": magicalAttack = value
                case "physicalDefense": physicalDefense = value
                case "magicalDefense": magicalDefense = value
                case "hitRate": hitRate = value
                case "evasionRate": evasionRate = value
                case "criticalRate": criticalRate = value
                case "attackCount": attackCount = value
                case "magicalHealing": magicalHealing = value
                case "trapRemoval": trapRemoval = value
                case "additionalDamage": additionalDamage = value
                case "breathDamage": breathDamage = value
                default: break
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
            var category: String
            var basePrice: Int
            var sellValue: Int
            var rarity: String?
            var statBonuses = StatBonusesBuilder()
            var combatBonuses = CombatBonusesBuilder()
            var allowedRaceIds: Set<UInt8> = []
            var allowedJobs: Set<String> = []
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
            // categoryはInt→ItemSaleCategory→identifierに変換（正規化後はInt）
            let categoryInt = UInt8(sqlite3_column_int(itemStatement, 2))
            let category = ItemSaleCategory(rawValue: categoryInt)?.identifier ?? "other"
            let basePrice = Int(sqlite3_column_int(itemStatement, 3))
            let sellValue = Int(sqlite3_column_int(itemStatement, 4))
            // rarityはInt→文字列に変換（NULLの場合はnil）
            let rarityValue: String? = {
                guard sqlite3_column_type(itemStatement, 5) != SQLITE_NULL else { return nil }
                let rarityInt = Int(sqlite3_column_int(itemStatement, 5))
                return ItemRarityMapping.string(from: rarityInt)
            }()
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
            guard let statC = sqlite3_column_text(statement, 1) else { return }
            let stat = String(cString: statC)
            let value = Int(sqlite3_column_int(statement, 2))
            builder.statBonuses.apply(stat: stat, value: value)
        }

        try applyPairs(sql: "SELECT item_id, stat, value FROM item_combat_bonuses;") { builder, statement in
            guard let statC = sqlite3_column_text(statement, 1) else { return }
            let stat = String(cString: statC)
            let value = Int(sqlite3_column_int(statement, 2))
            builder.combatBonuses.apply(stat: stat, value: value)
        }

        try applyPairs(sql: "SELECT item_id, race_id FROM item_allowed_races;") { builder, statement in
            let raceId = UInt8(sqlite3_column_int(statement, 1))
            builder.allowedRaceIds.insert(raceId)
        }

        try applyPairs(sql: "SELECT item_id, job_id FROM item_allowed_jobs;") { builder, statement in
            guard let jobC = sqlite3_column_text(statement, 1) else { return }
            builder.allowedJobs.insert(String(cString: jobC))
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
                allowedJobs: Array(builder.allowedJobs).sorted(),
                allowedGenderCodes: Array(builder.allowedGenderCodes).sorted(),
                bypassRaceIds: Array(builder.bypassRaceIds).sorted(),
                grantedSkillIds: builder.grantedSkillIds  // ORDER BY order_index でソート済み
            )
        }
    }
}
