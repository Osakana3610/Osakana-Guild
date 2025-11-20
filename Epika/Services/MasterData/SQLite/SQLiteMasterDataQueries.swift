import Foundation
import SQLite3

extension SQLiteMasterDataManager {
    // MARK: - Items

    func fetchAllItems() throws -> [ItemDefinition] {
        struct Builder {
            var id: String
            var name: String
            var description: String
            var category: String
            var basePrice: Int
            var sellValue: Int
            var equipable: Bool?
            var rarity: String?
            var statBonuses: [ItemDefinition.StatBonus] = []
            var combatBonuses: [ItemDefinition.CombatBonus] = []
            var allowedRaces: Set<String> = []
            var allowedJobs: Set<String> = []
            var allowedGenders: Set<String> = []
            var bypassRaceRestrictions: Set<String> = []
            var grantedSkills: [ItemDefinition.GrantedSkill] = []
        }

        var builders: [String: Builder] = [:]
        var orderedIds: [String] = []

        let itemSQL = "SELECT id, name, description, category, base_price, sell_value, equipable, rarity FROM items;"
        let itemStatement = try prepare(itemSQL)
        defer { sqlite3_finalize(itemStatement) }
        while sqlite3_step(itemStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(itemStatement, 0),
                  let nameC = sqlite3_column_text(itemStatement, 1),
                  let descC = sqlite3_column_text(itemStatement, 2),
                  let categoryC = sqlite3_column_text(itemStatement, 3) else { continue }
            let id = String(cString: idC)
            let name = String(cString: nameC)
            let description = String(cString: descC)
            let category = String(cString: categoryC)
            let basePrice = Int(sqlite3_column_int(itemStatement, 4))
            let sellValue = Int(sqlite3_column_int(itemStatement, 5))
            let equipableValue = sqlite3_column_type(itemStatement, 6) == SQLITE_NULL ? nil : sqlite3_column_int(itemStatement, 6) == 1
            let rarityValue = sqlite3_column_text(itemStatement, 7).flatMap { String(cString: $0) }
            builders[id] = Builder(
                id: id,
                name: name,
                description: description,
                category: category,
                basePrice: basePrice,
                sellValue: sellValue,
                equipable: equipableValue,
                rarity: rarityValue
            )
            orderedIds.append(id)
        }

        func applyPairs(sql: String, handler: (inout Builder, OpaquePointer) -> Void) throws {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let idC = sqlite3_column_text(statement, 0) else { continue }
                let id = String(cString: idC)
                guard var builder = builders[id] else { continue }
                handler(&builder, statement)
                builders[id] = builder
            }
        }

        try applyPairs(sql: "SELECT item_id, stat, value FROM item_stat_bonuses;") { builder, statement in
            guard let statC = sqlite3_column_text(statement, 1) else { return }
            let stat = String(cString: statC)
            let value = Int(sqlite3_column_int(statement, 2))
            builder.statBonuses.append(.init(stat: stat, value: value))
        }

        try applyPairs(sql: "SELECT item_id, stat, value FROM item_combat_bonuses;") { builder, statement in
            guard let statC = sqlite3_column_text(statement, 1) else { return }
            let stat = String(cString: statC)
            let value = Int(sqlite3_column_int(statement, 2))
            builder.combatBonuses.append(.init(stat: stat, value: value))
        }

        try applyPairs(sql: "SELECT item_id, race_id FROM item_allowed_races;") { builder, statement in
            guard let raceC = sqlite3_column_text(statement, 1) else { return }
            builder.allowedRaces.insert(String(cString: raceC))
        }

        try applyPairs(sql: "SELECT item_id, job_id FROM item_allowed_jobs;") { builder, statement in
            guard let jobC = sqlite3_column_text(statement, 1) else { return }
            builder.allowedJobs.insert(String(cString: jobC))
        }

        try applyPairs(sql: "SELECT item_id, gender FROM item_allowed_genders;") { builder, statement in
            guard let genderC = sqlite3_column_text(statement, 1) else { return }
            builder.allowedGenders.insert(String(cString: genderC))
        }

        try applyPairs(sql: "SELECT item_id, race_id FROM item_bypass_race_restrictions;") { builder, statement in
            guard let raceC = sqlite3_column_text(statement, 1) else { return }
            builder.bypassRaceRestrictions.insert(String(cString: raceC))
        }

        let skillStatement = try prepare("SELECT item_id, order_index, skill_id FROM item_granted_skills ORDER BY item_id, order_index;")
        defer { sqlite3_finalize(skillStatement) }
        while sqlite3_step(skillStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(skillStatement, 0),
                  var builder = builders[String(cString: idC)] else { continue }
            let order = Int(sqlite3_column_int(skillStatement, 1))
            guard let skillC = sqlite3_column_text(skillStatement, 2) else { continue }
            builder.grantedSkills.append(.init(orderIndex: order, skillId: String(cString: skillC)))
            builders[builder.id] = builder
        }

        return orderedIds.compactMap { builders[$0] }.map { builder in
            ItemDefinition(
                id: builder.id,
                name: builder.name,
                description: builder.description,
                category: builder.category,
                basePrice: builder.basePrice,
                sellValue: builder.sellValue,
                equipable: builder.equipable,
                rarity: builder.rarity,
                statBonuses: builder.statBonuses,
                combatBonuses: builder.combatBonuses,
                allowedRaces: Array(builder.allowedRaces).sorted(),
                allowedJobs: Array(builder.allowedJobs).sorted(),
                allowedGenders: Array(builder.allowedGenders).sorted(),
                bypassRaceRestrictions: Array(builder.bypassRaceRestrictions).sorted(),
                grantedSkills: builder.grantedSkills.sorted { $0.orderIndex < $1.orderIndex }
            )
        }
    }

    // MARK: - Skills

    func fetchAllSkills() throws -> [SkillDefinition] {
        var skills: [String: SkillDefinition] = [:]
        let baseSQL = "SELECT id, name, description, type, category, acquisition_conditions_json FROM skills;"
        let baseStatement = try prepare(baseSQL)
        defer { sqlite3_finalize(baseStatement) }
        while sqlite3_step(baseStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(baseStatement, 0),
                  let nameC = sqlite3_column_text(baseStatement, 1),
                  let descC = sqlite3_column_text(baseStatement, 2),
                  let typeC = sqlite3_column_text(baseStatement, 3),
                  let categoryC = sqlite3_column_text(baseStatement, 4),
                  let conditionsC = sqlite3_column_text(baseStatement, 5) else { continue }
            let skill = SkillDefinition(
                id: String(cString: idC),
                name: String(cString: nameC),
                description: String(cString: descC),
                type: String(cString: typeC),
                category: String(cString: categoryC),
                acquisitionConditionsJSON: String(cString: conditionsC),
                effects: []
            )
            skills[skill.id] = skill
        }

        let effectSQL = "SELECT skill_id, effect_index, kind, value, value_percent, stat_type, damage_type, payload_json FROM skill_effects ORDER BY skill_id, effect_index;"
        let effectStatement = try prepare(effectSQL)
        defer { sqlite3_finalize(effectStatement) }
        while sqlite3_step(effectStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(effectStatement, 0),
                  let skill = skills[String(cString: idC)] else { continue }
            let index = Int(sqlite3_column_int(effectStatement, 1))
            guard let kindC = sqlite3_column_text(effectStatement, 2) else { continue }
            let value = sqlite3_column_type(effectStatement, 3) == SQLITE_NULL ? nil : Double(sqlite3_column_double(effectStatement, 3))
            let valuePercent = sqlite3_column_type(effectStatement, 4) == SQLITE_NULL ? nil : Double(sqlite3_column_double(effectStatement, 4))
            let statType = sqlite3_column_text(effectStatement, 5).flatMap { String(cString: $0) }
            let damageType = sqlite3_column_text(effectStatement, 6).flatMap { String(cString: $0) }
            guard let payloadC = sqlite3_column_text(effectStatement, 7) else { continue }
            var effects = skill.effects
            effects.append(.init(index: index,
                                 kind: String(cString: kindC),
                                 value: value,
                                 valuePercent: valuePercent,
                                 statType: statType,
                                 damageType: damageType,
                                 payloadJSON: String(cString: payloadC)))
            skills[skill.id] = SkillDefinition(
                id: skill.id,
                name: skill.name,
                description: skill.description,
                type: skill.type,
                category: skill.category,
                acquisitionConditionsJSON: skill.acquisitionConditionsJSON,
                effects: effects.sorted { $0.index < $1.index }
            )
        }

        return skills.values.sorted { $0.name < $1.name }
    }

    // MARK: - Enemies

    func fetchAllEnemies() throws -> [EnemyDefinition] {
        struct Builder {
            var id: String
            var name: String
            var race: String
            var category: String
            var job: String?
            var baseExperience: Int
            var isBoss: Bool
            var strength: Int
            var wisdom: Int
            var spirit: Int
            var vitality: Int
            var agility: Int
            var luck: Int
            var resistances: [EnemyDefinition.Resistance] = []
            var skills: [EnemyDefinition.Skill] = []
            var drops: [EnemyDefinition.Drop] = []
            var actionRates: EnemyDefinition.ActionRates = .init(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)
            var groupSizeRange: ClosedRange<Int> = 1...1
        }

        var builders: [String: Builder] = [:]
        let baseSQL = "SELECT e.id, e.name, e.race, e.category, e.job, e.base_experience, e.is_boss, s.strength, s.wisdom, s.spirit, s.vitality, s.agility, s.luck FROM enemies e JOIN enemy_stats s ON e.id = s.enemy_id;"
        let baseStatement = try prepare(baseSQL)
        defer { sqlite3_finalize(baseStatement) }
        while sqlite3_step(baseStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(baseStatement, 0),
                  let nameC = sqlite3_column_text(baseStatement, 1),
                  let raceC = sqlite3_column_text(baseStatement, 2),
                  let categoryC = sqlite3_column_text(baseStatement, 3) else { continue }
            let id = String(cString: idC)
            builders[id] = Builder(
                id: id,
                name: String(cString: nameC),
                race: String(cString: raceC),
                category: String(cString: categoryC),
                job: sqlite3_column_text(baseStatement, 4).flatMap { String(cString: $0) },
                baseExperience: Int(sqlite3_column_int(baseStatement, 5)),
                isBoss: sqlite3_column_int(baseStatement, 6) == 1,
                strength: Int(sqlite3_column_int(baseStatement, 7)),
                wisdom: Int(sqlite3_column_int(baseStatement, 8)),
                spirit: Int(sqlite3_column_int(baseStatement, 9)),
                vitality: Int(sqlite3_column_int(baseStatement, 10)),
                agility: Int(sqlite3_column_int(baseStatement, 11)),
                luck: Int(sqlite3_column_int(baseStatement, 12))
            )
        }

        let resistanceSQL = "SELECT enemy_id, element, value FROM enemy_resistances;"
        let resistanceStatement = try prepare(resistanceSQL)
        defer { sqlite3_finalize(resistanceStatement) }
        while sqlite3_step(resistanceStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(resistanceStatement, 0),
                  var builder = builders[String(cString: idC)],
                  let elementC = sqlite3_column_text(resistanceStatement, 1) else { continue }
            builder.resistances.append(.init(element: String(cString: elementC), value: sqlite3_column_double(resistanceStatement, 2)))
            builders[builder.id] = builder
        }

        let skillSQL = "SELECT enemy_id, order_index, skill_id FROM enemy_skills ORDER BY enemy_id, order_index;"
        let skillStatement = try prepare(skillSQL)
        defer { sqlite3_finalize(skillStatement) }
        while sqlite3_step(skillStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(skillStatement, 0),
                  var builder = builders[String(cString: idC)],
                  let skillC = sqlite3_column_text(skillStatement, 2) else { continue }
            builder.skills.append(.init(orderIndex: Int(sqlite3_column_int(skillStatement, 1)), skillId: String(cString: skillC)))
            builders[builder.id] = builder
        }

        let dropSQL = "SELECT enemy_id, order_index, item_id FROM enemy_drops ORDER BY enemy_id, order_index;"
        let dropStatement = try prepare(dropSQL)
        defer { sqlite3_finalize(dropStatement) }
        while sqlite3_step(dropStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(dropStatement, 0),
                  var builder = builders[String(cString: idC)],
                  let itemC = sqlite3_column_text(dropStatement, 2) else { continue }
            builder.drops.append(.init(orderIndex: Int(sqlite3_column_int(dropStatement, 1)), itemId: String(cString: itemC)))
            builders[builder.id] = builder
        }

        return builders.values.sorted { $0.name < $1.name }.map { builder in
            EnemyDefinition(
                id: builder.id,
                name: builder.name,
                race: builder.race,
                category: builder.category,
                job: builder.job,
                baseExperience: builder.baseExperience,
                isBoss: builder.isBoss,
                strength: builder.strength,
                wisdom: builder.wisdom,
                spirit: builder.spirit,
                vitality: builder.vitality,
                agility: builder.agility,
                luck: builder.luck,
                resistances: builder.resistances.sorted { $0.element < $1.element },
                skills: builder.skills.sorted { $0.orderIndex < $1.orderIndex },
                drops: builder.drops.sorted { $0.orderIndex < $1.orderIndex },
                actionRates: builder.actionRates,
                groupSizeRange: builder.groupSizeRange
            )
        }
    }

    // MARK: - Status Effects

    func fetchAllStatusEffects() throws -> [StatusEffectDefinition] {
        var effects: [String: StatusEffectDefinition] = [:]
        let baseSQL = "SELECT id, name, description, category, duration_turns, tick_damage_percent, action_locked, apply_message, expire_message FROM status_effects;"
        let baseStatement = try prepare(baseSQL)
        defer { sqlite3_finalize(baseStatement) }
        while sqlite3_step(baseStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(baseStatement, 0),
                  let nameC = sqlite3_column_text(baseStatement, 1),
                  let descC = sqlite3_column_text(baseStatement, 2),
                  let categoryC = sqlite3_column_text(baseStatement, 3) else { continue }
            let id = String(cString: idC)
            let definition = StatusEffectDefinition(
                id: id,
                name: String(cString: nameC),
                description: String(cString: descC),
                category: String(cString: categoryC),
                durationTurns: sqlite3_column_type(baseStatement, 4) == SQLITE_NULL ? nil : Int(sqlite3_column_int(baseStatement, 4)),
                tickDamagePercent: sqlite3_column_type(baseStatement, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int(baseStatement, 5)),
                actionLocked: sqlite3_column_type(baseStatement, 6) == SQLITE_NULL ? nil : sqlite3_column_int(baseStatement, 6) == 1,
                applyMessage: sqlite3_column_text(baseStatement, 7).flatMap { String(cString: $0) },
                expireMessage: sqlite3_column_text(baseStatement, 8).flatMap { String(cString: $0) },
                tags: [],
                statModifiers: []
            )
            effects[id] = definition
        }

        let tagSQL = "SELECT effect_id, order_index, tag FROM status_effect_tags ORDER BY effect_id, order_index;"
        let tagStatement = try prepare(tagSQL)
        defer { sqlite3_finalize(tagStatement) }
        while sqlite3_step(tagStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(tagStatement, 0),
                  let effect = effects[String(cString: idC)],
                  let tagC = sqlite3_column_text(tagStatement, 2) else { continue }
            var tags = effect.tags
            tags.append(.init(orderIndex: Int(sqlite3_column_int(tagStatement, 1)), value: String(cString: tagC)))
            effects[effect.id] = StatusEffectDefinition(
                id: effect.id,
                name: effect.name,
                description: effect.description,
                category: effect.category,
                durationTurns: effect.durationTurns,
                tickDamagePercent: effect.tickDamagePercent,
                actionLocked: effect.actionLocked,
                applyMessage: effect.applyMessage,
                expireMessage: effect.expireMessage,
                tags: tags.sorted { $0.orderIndex < $1.orderIndex },
                statModifiers: effect.statModifiers
            )
        }

        let modifierSQL = "SELECT effect_id, stat, value FROM status_effect_stat_modifiers;"
        let modifierStatement = try prepare(modifierSQL)
        defer { sqlite3_finalize(modifierStatement) }
        while sqlite3_step(modifierStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(modifierStatement, 0),
                  let effect = effects[String(cString: idC)],
                  let statC = sqlite3_column_text(modifierStatement, 1) else { continue }
            var modifiers = effect.statModifiers
            modifiers.append(.init(stat: String(cString: statC), value: sqlite3_column_double(modifierStatement, 2)))
            effects[effect.id] = StatusEffectDefinition(
                id: effect.id,
                name: effect.name,
                description: effect.description,
                category: effect.category,
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

    // MARK: - Dungeons & Exploration

    func fetchAllDungeons() throws -> ([DungeonDefinition], [EncounterTableDefinition], [DungeonFloorDefinition]) {
        var dungeons: [String: DungeonDefinition] = [:]
        let dungeonSQL = "SELECT id, name, chapter, stage, description, recommended_level, exploration_time, events_per_floor, floor_count, story_text FROM dungeons;"
        let dungeonStatement = try prepare(dungeonSQL)
        defer { sqlite3_finalize(dungeonStatement) }
        while sqlite3_step(dungeonStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(dungeonStatement, 0),
                  let nameC = sqlite3_column_text(dungeonStatement, 1),
                  let descC = sqlite3_column_text(dungeonStatement, 4) else { continue }
            let id = String(cString: idC)
            dungeons[id] = DungeonDefinition(
                id: id,
                name: String(cString: nameC),
                chapter: Int(sqlite3_column_int(dungeonStatement, 2)),
                stage: Int(sqlite3_column_int(dungeonStatement, 3)),
                description: String(cString: descC),
                recommendedLevel: Int(sqlite3_column_int(dungeonStatement, 5)),
                explorationTime: Int(sqlite3_column_int(dungeonStatement, 6)),
                eventsPerFloor: Int(sqlite3_column_int(dungeonStatement, 7)),
                floorCount: Int(sqlite3_column_int(dungeonStatement, 8)),
                storyText: sqlite3_column_text(dungeonStatement, 9).flatMap { String(cString: $0) },
                unlockConditions: [],
                encounterWeights: [],
                enemyGroupConfig: nil
            )
        }

        let unlockSQL = "SELECT dungeon_id, order_index, condition FROM dungeon_unlock_conditions ORDER BY dungeon_id, order_index;"
        let unlockStatement = try prepare(unlockSQL)
        defer { sqlite3_finalize(unlockStatement) }
        while sqlite3_step(unlockStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(unlockStatement, 0),
                  let dungeon = dungeons[String(cString: idC)],
                  let condC = sqlite3_column_text(unlockStatement, 2) else { continue }
            var conditions = dungeon.unlockConditions
            conditions.append(.init(orderIndex: Int(sqlite3_column_int(unlockStatement, 1)), value: String(cString: condC)))
            dungeons[dungeon.id] = DungeonDefinition(
                id: dungeon.id,
                name: dungeon.name,
                chapter: dungeon.chapter,
                stage: dungeon.stage,
                description: dungeon.description,
                recommendedLevel: dungeon.recommendedLevel,
                explorationTime: dungeon.explorationTime,
                eventsPerFloor: dungeon.eventsPerFloor,
                floorCount: dungeon.floorCount,
                storyText: dungeon.storyText,
                unlockConditions: conditions.sorted { $0.orderIndex < $1.orderIndex },
                encounterWeights: dungeon.encounterWeights,
                enemyGroupConfig: dungeon.enemyGroupConfig
            )
        }

        let weightSQL = "SELECT dungeon_id, order_index, enemy_id, weight FROM dungeon_encounter_weights ORDER BY dungeon_id, order_index;"
        let weightStatement = try prepare(weightSQL)
        defer { sqlite3_finalize(weightStatement) }
        while sqlite3_step(weightStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(weightStatement, 0),
                  let dungeon = dungeons[String(cString: idC)],
                  let enemyC = sqlite3_column_text(weightStatement, 2) else { continue }
            var weights = dungeon.encounterWeights
            weights.append(.init(orderIndex: Int(sqlite3_column_int(weightStatement, 1)), enemyId: String(cString: enemyC), weight: sqlite3_column_double(weightStatement, 3)))
            dungeons[dungeon.id] = DungeonDefinition(
                id: dungeon.id,
                name: dungeon.name,
                chapter: dungeon.chapter,
                stage: dungeon.stage,
                description: dungeon.description,
                recommendedLevel: dungeon.recommendedLevel,
                explorationTime: dungeon.explorationTime,
                eventsPerFloor: dungeon.eventsPerFloor,
                floorCount: dungeon.floorCount,
                storyText: dungeon.storyText,
                unlockConditions: dungeon.unlockConditions,
                encounterWeights: weights.sorted { $0.orderIndex < $1.orderIndex },
                enemyGroupConfig: dungeon.enemyGroupConfig
            )
        }

        var tables: [String: EncounterTableDefinition] = [:]
        let tableSQL = "SELECT id, name FROM encounter_tables;"
        let tableStatement = try prepare(tableSQL)
        defer { sqlite3_finalize(tableStatement) }
        while sqlite3_step(tableStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(tableStatement, 0),
                  let nameC = sqlite3_column_text(tableStatement, 1) else { continue }
            let id = String(cString: idC)
            tables[id] = EncounterTableDefinition(id: id, name: String(cString: nameC), events: [])
        }

        let eventSQL = "SELECT table_id, order_index, event_type, enemy_id, spawn_rate, group_min, group_max, is_boss, enemy_level FROM encounter_events ORDER BY table_id, order_index;"
        let eventStatement = try prepare(eventSQL)
        defer { sqlite3_finalize(eventStatement) }
        while sqlite3_step(eventStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(eventStatement, 0),
                  let table = tables[String(cString: idC)],
                  let typeC = sqlite3_column_text(eventStatement, 2) else { continue }
            var events = table.events
            events.append(.init(orderIndex: Int(sqlite3_column_int(eventStatement, 1)),
                                eventType: String(cString: typeC),
                                enemyId: sqlite3_column_text(eventStatement, 3).flatMap { String(cString: $0) },
                                spawnRate: sqlite3_column_type(eventStatement, 4) == SQLITE_NULL ? nil : sqlite3_column_double(eventStatement, 4),
                                groupMin: sqlite3_column_type(eventStatement, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int(eventStatement, 5)),
                                groupMax: sqlite3_column_type(eventStatement, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int(eventStatement, 6)),
                                isBoss: sqlite3_column_type(eventStatement, 7) == SQLITE_NULL ? nil : sqlite3_column_int(eventStatement, 7) == 1,
                                level: sqlite3_column_type(eventStatement, 8) == SQLITE_NULL ? nil : Int(sqlite3_column_int(eventStatement, 8))))
            tables[table.id] = EncounterTableDefinition(id: table.id, name: table.name, events: events.sorted { $0.orderIndex < $1.orderIndex })
        }

        var floors: [DungeonFloorDefinition] = []
        let floorSQL = "SELECT id, dungeon_id, name, floor_number, encounter_table_id, description FROM dungeon_floors;"
        let floorStatement = try prepare(floorSQL)
        defer { sqlite3_finalize(floorStatement) }
        while sqlite3_step(floorStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(floorStatement, 0),
                  let nameC = sqlite3_column_text(floorStatement, 2),
                  let encounterC = sqlite3_column_text(floorStatement, 4),
                  let descC = sqlite3_column_text(floorStatement, 5) else { continue }
            floors.append(DungeonFloorDefinition(
                id: String(cString: idC),
                dungeonId: sqlite3_column_text(floorStatement, 1).flatMap { String(cString: $0) },
                name: String(cString: nameC),
                floorNumber: Int(sqlite3_column_int(floorStatement, 3)),
                encounterTableId: String(cString: encounterC),
                description: String(cString: descC),
                specialEvents: []
            ))
        }

        let floorEventSQL = "SELECT floor_id, order_index, event_id FROM dungeon_floor_special_events ORDER BY floor_id, order_index;"
        let floorEventStatement = try prepare(floorEventSQL)
        defer { sqlite3_finalize(floorEventStatement) }
        var floorMap = Dictionary(uniqueKeysWithValues: floors.map { ($0.id, $0) })
        while sqlite3_step(floorEventStatement) == SQLITE_ROW {
            guard let floorIdC = sqlite3_column_text(floorEventStatement, 0),
                  let floor = floorMap[String(cString: floorIdC)],
                  let eventC = sqlite3_column_text(floorEventStatement, 2) else { continue }
            var events = floor.specialEvents
            events.append(.init(orderIndex: Int(sqlite3_column_int(floorEventStatement, 1)), eventId: String(cString: eventC)))
            floorMap[floor.id] = DungeonFloorDefinition(
                id: floor.id,
                dungeonId: floor.dungeonId,
                name: floor.name,
                floorNumber: floor.floorNumber,
                encounterTableId: floor.encounterTableId,
                description: floor.description,
                specialEvents: events.sorted { $0.orderIndex < $1.orderIndex }
            )
        }

        floors = Array(floorMap.values)

        return (
            dungeons.values.sorted { $0.name < $1.name },
            tables.values.sorted { $0.name < $1.name },
            floors.sorted { lhs, rhs in
                if let lDungeon = lhs.dungeonId, let rDungeon = rhs.dungeonId, lDungeon != rDungeon {
                    return lDungeon < rDungeon
                }
                return lhs.floorNumber < rhs.floorNumber
            }
        )
    }

    // MARK: - Exploration Events

    func fetchAllExplorationEvents() throws -> [ExplorationEventDefinition] {
        var events: [ExplorationEventDefinition] = []
        let baseSQL = "SELECT id, type, name, description, floor_min, floor_max FROM exploration_events;"
        let baseStatement = try prepare(baseSQL)
        defer { sqlite3_finalize(baseStatement) }
        while sqlite3_step(baseStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(baseStatement, 0),
                  let typeC = sqlite3_column_text(baseStatement, 1),
                  let nameC = sqlite3_column_text(baseStatement, 2),
                  let descC = sqlite3_column_text(baseStatement, 3) else { continue }
            let definition = ExplorationEventDefinition(
                id: String(cString: idC),
                type: String(cString: typeC),
                name: String(cString: nameC),
                description: String(cString: descC),
                floorMin: Int(sqlite3_column_int(baseStatement, 4)),
                floorMax: Int(sqlite3_column_int(baseStatement, 5)),
                tags: [],
                weights: [],
                payloadType: nil,
                payloadJSON: nil
            )
            events.append(definition)
        }

        var eventMap = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })

        let tagSQL = "SELECT event_id, order_index, tag FROM exploration_event_tags ORDER BY event_id, order_index;"
        let tagStatement = try prepare(tagSQL)
        defer { sqlite3_finalize(tagStatement) }
        while sqlite3_step(tagStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(tagStatement, 0),
                  let event = eventMap[String(cString: idC)],
                  let tagC = sqlite3_column_text(tagStatement, 2) else { continue }
            var tags = event.tags
            tags.append(.init(orderIndex: Int(sqlite3_column_int(tagStatement, 1)), value: String(cString: tagC)))
            eventMap[event.id] = ExplorationEventDefinition(
                id: event.id,
                type: event.type,
                name: event.name,
                description: event.description,
                floorMin: event.floorMin,
                floorMax: event.floorMax,
                tags: tags.sorted { $0.orderIndex < $1.orderIndex },
                weights: event.weights,
                payloadType: event.payloadType,
                payloadJSON: event.payloadJSON
            )
        }

        let weightSQL = "SELECT event_id, context, weight FROM exploration_event_weights;"
        let weightStatement = try prepare(weightSQL)
        defer { sqlite3_finalize(weightStatement) }
        while sqlite3_step(weightStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(weightStatement, 0),
                  let event = eventMap[String(cString: idC)],
                  let contextC = sqlite3_column_text(weightStatement, 1) else { continue }
            var weights = event.weights
            weights.append(.init(context: String(cString: contextC), weight: sqlite3_column_double(weightStatement, 2)))
            eventMap[event.id] = ExplorationEventDefinition(
                id: event.id,
                type: event.type,
                name: event.name,
                description: event.description,
                floorMin: event.floorMin,
                floorMax: event.floorMax,
                tags: event.tags,
                weights: weights,
                payloadType: event.payloadType,
                payloadJSON: event.payloadJSON
            )
        }

        let payloadSQL = "SELECT event_id, payload_type, payload_json FROM exploration_event_payloads;"
        let payloadStatement = try prepare(payloadSQL)
        defer { sqlite3_finalize(payloadStatement) }
        while sqlite3_step(payloadStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(payloadStatement, 0),
                  let event = eventMap[String(cString: idC)],
                  let typeC = sqlite3_column_text(payloadStatement, 1),
                  let jsonC = sqlite3_column_text(payloadStatement, 2) else { continue }
            eventMap[event.id] = ExplorationEventDefinition(
                id: event.id,
                type: event.type,
                name: event.name,
                description: event.description,
                floorMin: event.floorMin,
                floorMax: event.floorMax,
                tags: event.tags,
                weights: event.weights,
                payloadType: String(cString: typeC),
                payloadJSON: String(cString: jsonC)
            )
        }

        return eventMap.values.sorted { $0.name < $1.name }
    }

    // MARK: - Jobs

    func fetchAllJobs() throws -> [JobDefinition] {
        struct Builder {
            var id: String
            var name: String
            var category: String
            var growthTendency: String?
            var combatCoefficients: [JobDefinition.CombatCoefficient] = []
            var learnedSkills: [JobDefinition.LearnedSkill] = []
        }

        var builders: [String: Builder] = [:]
        var order: [String] = []
        let baseSQL = "SELECT id, name, category, growth_tendency FROM jobs ORDER BY rowid;"
        let baseStatement = try prepare(baseSQL)
        defer { sqlite3_finalize(baseStatement) }
        while sqlite3_step(baseStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(baseStatement, 0),
                  let nameC = sqlite3_column_text(baseStatement, 1),
                  let categoryC = sqlite3_column_text(baseStatement, 2) else { continue }
            let id = String(cString: idC)
            builders[id] = Builder(
                id: id,
                name: String(cString: nameC),
                category: String(cString: categoryC),
                growthTendency: sqlite3_column_text(baseStatement, 3).flatMap { String(cString: $0) }
            )
            order.append(id)
        }

        let coefficientSQL = "SELECT job_id, stat, value FROM job_combat_coefficients;"
        let coefficientStatement = try prepare(coefficientSQL)
        defer { sqlite3_finalize(coefficientStatement) }
        while sqlite3_step(coefficientStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(coefficientStatement, 0),
                  var builder = builders[String(cString: idC)],
                  let statC = sqlite3_column_text(coefficientStatement, 1) else { continue }
            builder.combatCoefficients.append(.init(stat: String(cString: statC), value: sqlite3_column_double(coefficientStatement, 2)))
            builders[builder.id] = builder
        }

        let skillSQL = "SELECT job_id, order_index, skill_id FROM job_skills ORDER BY job_id, order_index;"
        let skillStatement = try prepare(skillSQL)
        defer { sqlite3_finalize(skillStatement) }
        while sqlite3_step(skillStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(skillStatement, 0),
                  var builder = builders[String(cString: idC)],
                  let skillC = sqlite3_column_text(skillStatement, 2) else { continue }
            builder.learnedSkills.append(.init(orderIndex: Int(sqlite3_column_int(skillStatement, 1)), skillId: String(cString: skillC)))
            builders[builder.id] = builder
        }

        return order.compactMap { builders[$0] }.map { builder in
            JobDefinition(
                id: builder.id,
                name: builder.name,
                category: builder.category,
                growthTendency: builder.growthTendency,
                combatCoefficients: builder.combatCoefficients.sorted { $0.stat < $1.stat },
                learnedSkills: builder.learnedSkills.sorted { $0.orderIndex < $1.orderIndex }
            )
        }
    }

    // MARK: - Shops

    func fetchAllShops() throws -> [ShopDefinition] {
        struct Builder {
            var id: String
            var name: String
            var items: [ShopDefinition.ShopItem] = []
        }

        var builders: [String: Builder] = [:]

        let shopSQL = "SELECT id, name FROM shops;"
        let shopStatement = try prepare(shopSQL)
        defer { sqlite3_finalize(shopStatement) }
        while sqlite3_step(shopStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(shopStatement, 0),
                  let nameC = sqlite3_column_text(shopStatement, 1) else { continue }
            let id = String(cString: idC)
            builders[id] = Builder(id: id, name: String(cString: nameC))
        }

        let itemSQL = "SELECT shop_id, order_index, item_id, quantity FROM shop_items ORDER BY shop_id, order_index;"
        let itemStatement = try prepare(itemSQL)
        defer { sqlite3_finalize(itemStatement) }
        while sqlite3_step(itemStatement) == SQLITE_ROW {
            guard let shopIdC = sqlite3_column_text(itemStatement, 0),
                  let itemIdC = sqlite3_column_text(itemStatement, 2) else { continue }
            let shopId = String(cString: shopIdC)
            guard var builder = builders[shopId] else { continue }
            let orderIndex = Int(sqlite3_column_int(itemStatement, 1))
            let itemId = String(cString: itemIdC)
            let quantityValue = sqlite3_column_type(itemStatement, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(itemStatement, 3))
            builder.items.append(.init(orderIndex: orderIndex, itemId: itemId, quantity: quantityValue))
            builders[shopId] = builder
        }

        return builders.values
            .sorted { $0.name < $1.name }
            .map { builder in
                let sortedItems = builder.items.sorted { $0.orderIndex < $1.orderIndex }
                return ShopDefinition(id: builder.id, name: builder.name, items: sortedItems)
            }
    }

    // MARK: - Races

    func fetchAllRaces() throws -> [RaceDefinition] {
        struct Builder {
            var id: String
            var name: String
            var gender: String
            var category: String
            var description: String
            var baseStats: [RaceDefinition.BaseStat] = []
            var maxLevel: Int?
        }

        var builders: [String: Builder] = [:]
        var order: [String] = []
        let baseSQL = "SELECT id, name, gender, category, description FROM races ORDER BY rowid;"
        let baseStatement = try prepare(baseSQL)
        defer { sqlite3_finalize(baseStatement) }
        while sqlite3_step(baseStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(baseStatement, 0),
                  let nameC = sqlite3_column_text(baseStatement, 1),
                  let genderC = sqlite3_column_text(baseStatement, 2),
                  let categoryC = sqlite3_column_text(baseStatement, 3),
                  let descriptionC = sqlite3_column_text(baseStatement, 4) else { continue }
            let id = String(cString: idC)
            builders[id] = Builder(
                id: id,
                name: String(cString: nameC),
                gender: String(cString: genderC),
                category: String(cString: categoryC),
                description: String(cString: descriptionC),
                maxLevel: nil
            )
            order.append(id)
        }

        let statSQL = "SELECT race_id, stat, value FROM race_base_stats;"
        let statStatement = try prepare(statSQL)
        defer { sqlite3_finalize(statStatement) }
        while sqlite3_step(statStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(statStatement, 0),
                  var builder = builders[String(cString: idC)],
                  let statC = sqlite3_column_text(statStatement, 1) else { continue }
            builder.baseStats.append(.init(stat: String(cString: statC), value: Int(sqlite3_column_int(statStatement, 2))))
            builders[builder.id] = builder
        }

        let capSQL = """
            SELECT memberships.race_id, caps.max_level
            FROM race_category_memberships AS memberships
            JOIN race_category_caps AS caps ON memberships.category = caps.category;
        """
        let capStatement = try prepare(capSQL)
        defer { sqlite3_finalize(capStatement) }
        while sqlite3_step(capStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(capStatement, 0),
                  var builder = builders[String(cString: idC)] else { continue }
            builder.maxLevel = Int(sqlite3_column_int(capStatement, 1))
            builders[builder.id] = builder
        }

        return order.compactMap { builders[$0] }.map { builder in
            RaceDefinition(
                id: builder.id,
                name: builder.name,
                gender: builder.gender,
                category: builder.category,
                description: builder.description,
                baseStats: builder.baseStats.sorted { $0.stat < $1.stat },
                maxLevel: builder.maxLevel ?? 200
            )
        }
    }

    // MARK: - Titles

    func fetchAllTitles() throws -> [TitleDefinition] {
        var titles: [TitleDefinition] = []
        let sql = """
            SELECT id,
                   name,
                   description,
                   stat_multiplier,
                   negative_multiplier,
                   drop_rate,
                   plus_correction,
                   minus_correction,
                   judgment_count,
                   rank,
                   drop_probability,
                   allow_with_title_treasure,
                   super_rare_rate_normal,
                   super_rare_rate_good,
                   super_rare_rate_rare,
                   super_rare_rate_gem
            FROM titles;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(statement, 0),
                  let nameC = sqlite3_column_text(statement, 1) else { continue }
            let rankValue = sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 9))
            let dropProbability = sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 10)
            let allowTreasureValue: Bool
            if sqlite3_column_type(statement, 11) == SQLITE_NULL {
                allowTreasureValue = true
            } else {
                allowTreasureValue = sqlite3_column_int(statement, 11) == 1
            }
            let normalRate = sqlite3_column_type(statement, 12) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 12)
            let goodRate = sqlite3_column_type(statement, 13) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 13)
            let rareRate = sqlite3_column_type(statement, 14) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 14)
            let gemRate = sqlite3_column_type(statement, 15) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 15)
            let superRareRates: TitleSuperRareRates?
            if let normalRate, let goodRate, let rareRate, let gemRate {
                superRareRates = TitleSuperRareRates(normal: normalRate,
                                                    good: goodRate,
                                                    rare: rareRate,
                                                    gem: gemRate)
            } else {
                superRareRates = nil
            }
            let definition = TitleDefinition(
                id: String(cString: idC),
                name: String(cString: nameC),
                description: sqlite3_column_text(statement, 2).flatMap { String(cString: $0) },
                statMultiplier: sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 3),
                negativeMultiplier: sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 4),
                dropRate: sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 5),
                plusCorrection: sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 6)),
                minusCorrection: sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 7)),
                judgmentCount: sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 8)),
                rank: rankValue,
                dropProbability: dropProbability,
                allowWithTitleTreasure: allowTreasureValue,
                superRareRates: superRareRates
            )
            titles.append(definition)
        }
        return titles
    }

    func fetchAllSuperRareTitles() throws -> [SuperRareTitleDefinition] {
        var titles: [String: SuperRareTitleDefinition] = [:]
        var orderedIds: [String] = []
        let baseSQL = "SELECT id, name FROM super_rare_titles;"
        let baseStatement = try prepare(baseSQL)
        defer { sqlite3_finalize(baseStatement) }
        while sqlite3_step(baseStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(baseStatement, 0),
                  let nameC = sqlite3_column_text(baseStatement, 1) else { continue }
            let id = String(cString: idC)
            titles[id] = SuperRareTitleDefinition(id: id, name: String(cString: nameC), skills: [])
            orderedIds.append(id)
        }

        let skillSQL = "SELECT title_id, order_index, skill_id FROM super_rare_title_skills ORDER BY title_id, order_index;"
        let skillStatement = try prepare(skillSQL)
        defer { sqlite3_finalize(skillStatement) }
        while sqlite3_step(skillStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(skillStatement, 0),
                  let title = titles[String(cString: idC)],
                  let skillC = sqlite3_column_text(skillStatement, 2) else { continue }
            var skills = title.skills
            skills.append(.init(orderIndex: Int(sqlite3_column_int(skillStatement, 1)), skillId: String(cString: skillC)))
            titles[title.id] = SuperRareTitleDefinition(id: title.id, name: title.name, skills: skills.sorted { $0.orderIndex < $1.orderIndex })
        }

        return orderedIds.compactMap { titles[$0] }
    }

    // MARK: - Personality

    func fetchPersonalityData() throws -> (
        primary: [PersonalityPrimaryDefinition],
        secondary: [PersonalitySecondaryDefinition],
        skills: [PersonalitySkillDefinition],
        cancellations: [PersonalityCancellation],
        battleEffects: [PersonalityBattleEffect]
    ) {
        var primary: [String: PersonalityPrimaryDefinition] = [:]
        let primarySQL = "SELECT id, name, kind, description FROM personality_primary;"
        let primaryStatement = try prepare(primarySQL)
        defer { sqlite3_finalize(primaryStatement) }
        while sqlite3_step(primaryStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(primaryStatement, 0),
                  let nameC = sqlite3_column_text(primaryStatement, 1),
                  let kindC = sqlite3_column_text(primaryStatement, 2),
                  let descriptionC = sqlite3_column_text(primaryStatement, 3) else { continue }
            let id = String(cString: idC)
            primary[id] = PersonalityPrimaryDefinition(
                id: id,
                name: String(cString: nameC),
                kind: String(cString: kindC),
                description: String(cString: descriptionC),
                effects: []
            )
        }

        let primaryEffectSQL = "SELECT personality_id, order_index, effect_type, value, payload_json FROM personality_primary_effects ORDER BY personality_id, order_index;"
        let primaryEffectStatement = try prepare(primaryEffectSQL)
        defer { sqlite3_finalize(primaryEffectStatement) }
        while sqlite3_step(primaryEffectStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(primaryEffectStatement, 0),
                  let definition = primary[String(cString: idC)],
                  let typeC = sqlite3_column_text(primaryEffectStatement, 2),
                  let payloadC = sqlite3_column_text(primaryEffectStatement, 4) else { continue }
            var effects = definition.effects
            effects.append(.init(orderIndex: Int(sqlite3_column_int(primaryEffectStatement, 1)),
                                 effectType: String(cString: typeC),
                                 value: sqlite3_column_type(primaryEffectStatement, 3) == SQLITE_NULL ? nil : sqlite3_column_double(primaryEffectStatement, 3),
                                 payloadJSON: String(cString: payloadC)))
            primary[definition.id] = PersonalityPrimaryDefinition(
                id: definition.id,
                name: definition.name,
                kind: definition.kind,
                description: definition.description,
                effects: effects.sorted { $0.orderIndex < $1.orderIndex }
            )
        }

        var secondary: [String: PersonalitySecondaryDefinition] = [:]
        let secondarySQL = "SELECT id, name, positive_skill_id, negative_skill_id FROM personality_secondary;"
        let secondaryStatement = try prepare(secondarySQL)
        defer { sqlite3_finalize(secondaryStatement) }
        while sqlite3_step(secondaryStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(secondaryStatement, 0),
                  let nameC = sqlite3_column_text(secondaryStatement, 1),
                  let positiveC = sqlite3_column_text(secondaryStatement, 2),
                  let negativeC = sqlite3_column_text(secondaryStatement, 3) else { continue }
            let id = String(cString: idC)
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
            guard let idC = sqlite3_column_text(secondaryStatStatement, 0),
                  let definition = secondary[String(cString: idC)],
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
        let skillSQL = "SELECT id, name, kind, description FROM personality_skills;"
        let skillStatement = try prepare(skillSQL)
        defer { sqlite3_finalize(skillStatement) }
        while sqlite3_step(skillStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(skillStatement, 0),
                  let nameC = sqlite3_column_text(skillStatement, 1),
                  let kindC = sqlite3_column_text(skillStatement, 2),
                  let descriptionC = sqlite3_column_text(skillStatement, 3) else { continue }
            let id = String(cString: idC)
            skills[id] = PersonalitySkillDefinition(
                id: id,
                name: String(cString: nameC),
                kind: String(cString: kindC),
                description: String(cString: descriptionC),
                eventEffects: []
            )
        }

        let skillEffectSQL = "SELECT skill_id, order_index, effect_id FROM personality_skill_event_effects ORDER BY skill_id, order_index;"
        let skillEffectStatement = try prepare(skillEffectSQL)
        defer { sqlite3_finalize(skillEffectStatement) }
        while sqlite3_step(skillEffectStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(skillEffectStatement, 0),
                  let definition = skills[String(cString: idC)],
                  let effectC = sqlite3_column_text(skillEffectStatement, 2) else { continue }
            var effects = definition.eventEffects
            effects.append(.init(orderIndex: Int(sqlite3_column_int(skillEffectStatement, 1)), effectId: String(cString: effectC)))
            skills[definition.id] = PersonalitySkillDefinition(
                id: definition.id,
                name: definition.name,
                kind: definition.kind,
                description: definition.description,
                eventEffects: effects.sorted { $0.orderIndex < $1.orderIndex }
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
            primary.values.sorted { $0.name < $1.name },
            secondary.values.sorted { $0.name < $1.name },
            skills.values.sorted { $0.name < $1.name },
            cancellations,
            battleEffects
        )
    }
}

extension SQLiteMasterDataManager {

    // MARK: - Stories

    func fetchAllStories() throws -> [StoryNodeDefinition] {
        struct Builder {
            var id: String
            var title: String
            var content: String
            var chapter: Int
            var section: Int
            var unlockRequirements: [StoryNodeDefinition.UnlockRequirement] = []
            var rewards: [StoryNodeDefinition.Reward] = []
            var unlockModules: [StoryNodeDefinition.UnlockModule] = []
        }

        var builders: [String: Builder] = [:]

        let nodeSQL = "SELECT id, title, content, chapter, section FROM story_nodes;"
        let nodeStatement = try prepare(nodeSQL)
        defer { sqlite3_finalize(nodeStatement) }
        while sqlite3_step(nodeStatement) == SQLITE_ROW {
            guard
                let idC = sqlite3_column_text(nodeStatement, 0),
                let titleC = sqlite3_column_text(nodeStatement, 1),
                let contentC = sqlite3_column_text(nodeStatement, 2)
            else { continue }
            let id = String(cString: idC)
            let chapter = Int(sqlite3_column_int(nodeStatement, 3))
            let section = Int(sqlite3_column_int(nodeStatement, 4))
            builders[id] = Builder(
                id: id,
                title: String(cString: titleC),
                content: String(cString: contentC),
                chapter: chapter,
                section: section
            )
        }

        func applyList(sql: String, handler: (inout Builder, OpaquePointer) -> Void) throws {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let storyIDC = sqlite3_column_text(statement, 0) else { continue }
                let storyID = String(cString: storyIDC)
                guard var builder = builders[storyID] else { continue }
                handler(&builder, statement)
                builders[storyID] = builder
            }
        }

        try applyList(sql: "SELECT story_id, order_index, requirement FROM story_unlock_requirements;") { builder, statement in
            let order = Int(sqlite3_column_int(statement, 1))
            guard let valueC = sqlite3_column_text(statement, 2) else { return }
            builder.unlockRequirements.append(.init(orderIndex: order, value: String(cString: valueC)))
        }

        try applyList(sql: "SELECT story_id, order_index, reward FROM story_rewards;") { builder, statement in
            let order = Int(sqlite3_column_int(statement, 1))
            guard let valueC = sqlite3_column_text(statement, 2) else { return }
            builder.rewards.append(.init(orderIndex: order, value: String(cString: valueC)))
        }

        try applyList(sql: "SELECT story_id, order_index, module_id FROM story_unlock_modules;") { builder, statement in
            let order = Int(sqlite3_column_int(statement, 1))
            guard let valueC = sqlite3_column_text(statement, 2) else { return }
            builder.unlockModules.append(.init(orderIndex: order, moduleId: String(cString: valueC)))
        }

        let sorted = builders.values.sorted { lhs, rhs in
            if lhs.chapter != rhs.chapter { return lhs.chapter < rhs.chapter }
            if lhs.section != rhs.section { return lhs.section < rhs.section }
            return lhs.id < rhs.id
        }

        return sorted.map { builder in
            StoryNodeDefinition(
                id: builder.id,
                title: builder.title,
                content: builder.content,
                chapter: builder.chapter,
                section: builder.section,
                unlockRequirements: builder.unlockRequirements.sorted { $0.orderIndex < $1.orderIndex },
                rewards: builder.rewards.sorted { $0.orderIndex < $1.orderIndex },
                unlockModules: builder.unlockModules.sorted { $0.orderIndex < $1.orderIndex }
            )
        }
    }

    // MARK: - Spells

    func fetchAllSpells() throws -> [SpellDefinition] {
        struct Builder {
            let id: String
            let name: String
            let schoolRaw: String
            let tier: Int
            let categoryRaw: String
            let targetingRaw: String
            let maxTargetsBase: Int?
            let extraTargetsPerLevels: Double?
            let hitsPerCast: Int?
            let basePowerMultiplier: Double?
            let statusId: String?
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

        var builders: [String: Builder] = [:]
        var order: [String] = []
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
            guard let idC = sqlite3_column_text(spellStatement, 0),
                  let nameC = sqlite3_column_text(spellStatement, 1),
                  let schoolC = sqlite3_column_text(spellStatement, 2),
                  let categoryC = sqlite3_column_text(spellStatement, 4),
                  let targetingC = sqlite3_column_text(spellStatement, 5),
                  let descriptionC = sqlite3_column_text(spellStatement, 13) else {
                continue
            }
            let id = String(cString: idC)
            let builder = Builder(
                id: id,
                name: String(cString: nameC),
                schoolRaw: String(cString: schoolC),
                tier: Int(sqlite3_column_int(spellStatement, 3)),
                categoryRaw: String(cString: categoryC),
                targetingRaw: String(cString: targetingC),
                maxTargetsBase: optionalInt(spellStatement, 6),
                extraTargetsPerLevels: optionalDouble(spellStatement, 7),
                hitsPerCast: optionalInt(spellStatement, 8),
                basePowerMultiplier: optionalDouble(spellStatement, 9),
                statusId: optionalText(spellStatement, 10),
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
            guard let spellIDC = sqlite3_column_text(buffStatement, 0),
                  let typeC = sqlite3_column_text(buffStatement, 2) else { continue }
            let spellId = String(cString: spellIDC)
            guard var builder = builders[spellId] else { continue }
            let orderIndex = Int(sqlite3_column_int(buffStatement, 1))
            let typeRaw = String(cString: typeC)
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
            guard let school = SpellDefinition.School(rawValue: builder.schoolRaw) else {
                throw SQLiteMasterDataError.executionFailed("未知の Spell school \(builder.schoolRaw) (id=\(builder.id))")
            }
            guard let category = SpellDefinition.Category(rawValue: builder.categoryRaw) else {
                throw SQLiteMasterDataError.executionFailed("未知の Spell category \(builder.categoryRaw) (id=\(builder.id))")
            }
            guard let targeting = SpellDefinition.Targeting(rawValue: builder.targetingRaw) else {
                throw SQLiteMasterDataError.executionFailed("未知の Spell targeting \(builder.targetingRaw) (id=\(builder.id))")
            }
            definitions.append(
                SpellDefinition(
                    id: builder.id,
                    name: builder.name,
                    school: school,
                    tier: builder.tier,
                    category: category,
                    targeting: targeting,
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

    // MARK: - Synthesis

    func fetchAllSynthesisRecipes() throws -> [SynthesisRecipeDefinition] {
        let sql = "SELECT id, parent_item_id, child_item_id, result_item_id FROM synthesis_recipes;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var recipes: [SynthesisRecipeDefinition] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(statement, 0),
                  let parentC = sqlite3_column_text(statement, 1),
                  let childC = sqlite3_column_text(statement, 2),
                  let resultC = sqlite3_column_text(statement, 3) else { continue }
            recipes.append(
                SynthesisRecipeDefinition(
                    id: String(cString: idC),
                    parentItemId: String(cString: parentC),
                    childItemId: String(cString: childC),
                    resultItemId: String(cString: resultC)
                )
            )
        }
        return recipes.sorted { $0.id < $1.id }
    }

}
