import Foundation

// MARK: - Schema Creation

extension Generator {
    func createSchema() throws {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS md_manifest (
                file TEXT PRIMARY KEY,
                sha256 TEXT NOT NULL,
                row_count INTEGER,
                size_bytes INTEGER,
                imported_at TEXT NOT NULL
            );
            """,
            // Items
            """
            CREATE TABLE IF NOT EXISTS items (
                id TEXT PRIMARY KEY,
                item_index INTEGER NOT NULL,
                name TEXT NOT NULL,
                description TEXT NOT NULL,
                category TEXT NOT NULL,
                base_price INTEGER NOT NULL,
                sell_value INTEGER NOT NULL,
                rarity TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS item_stat_bonuses (
                item_id TEXT NOT NULL,
                stat TEXT NOT NULL,
                value INTEGER NOT NULL,
                PRIMARY KEY (item_id, stat),
                FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS item_combat_bonuses (
                item_id TEXT NOT NULL,
                stat TEXT NOT NULL,
                value INTEGER NOT NULL,
                PRIMARY KEY (item_id, stat),
                FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS item_allowed_races (
                item_id TEXT NOT NULL,
                race_id TEXT NOT NULL,
                PRIMARY KEY (item_id, race_id),
                FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS item_allowed_jobs (
                item_id TEXT NOT NULL,
                job_id TEXT NOT NULL,
                PRIMARY KEY (item_id, job_id),
                FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS item_allowed_genders (
                item_id TEXT NOT NULL,
                gender TEXT NOT NULL,
                PRIMARY KEY (item_id, gender),
                FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS item_bypass_race_restrictions (
                item_id TEXT NOT NULL,
                race_id TEXT NOT NULL,
                PRIMARY KEY (item_id, race_id),
                FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS item_granted_skills (
                item_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                skill_id TEXT NOT NULL,
                PRIMARY KEY (item_id, order_index),
                FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
            );
            """,
            // Skills
            """
            CREATE TABLE IF NOT EXISTS skills (
                id TEXT PRIMARY KEY,
                skill_index INTEGER NOT NULL,
                name TEXT NOT NULL,
                description TEXT NOT NULL,
                type TEXT NOT NULL,
                category TEXT NOT NULL,
                acquisition_conditions_json TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS skill_effects (
                skill_id TEXT NOT NULL,
                effect_index INTEGER NOT NULL,
                kind TEXT NOT NULL,
                value REAL,
                value_percent REAL,
                stat_type TEXT,
                damage_type TEXT,
                payload_json TEXT,
                PRIMARY KEY (skill_id, effect_index),
                FOREIGN KEY (skill_id) REFERENCES skills(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS spells (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                school TEXT NOT NULL,
                tier INTEGER NOT NULL,
                category TEXT NOT NULL,
                targeting TEXT NOT NULL,
                max_targets_base INTEGER,
                extra_targets_per_levels REAL,
                hits_per_cast INTEGER,
                base_power_multiplier REAL,
                status_id TEXT,
                heal_multiplier REAL,
                cast_condition TEXT,
                description TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS spell_buffs (
                spell_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                type TEXT NOT NULL,
                multiplier REAL NOT NULL,
                PRIMARY KEY (spell_id, order_index),
                FOREIGN KEY (spell_id) REFERENCES spells(id) ON DELETE CASCADE
            );
            """,
            // Jobs
            """
            CREATE TABLE IF NOT EXISTS jobs (
                id TEXT PRIMARY KEY,
                job_index INTEGER NOT NULL,
                name TEXT NOT NULL,
                category TEXT NOT NULL,
                growth_tendency TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS job_combat_coefficients (
                job_id TEXT NOT NULL,
                stat TEXT NOT NULL,
                value REAL NOT NULL,
                PRIMARY KEY (job_id, stat),
                FOREIGN KEY (job_id) REFERENCES jobs(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS job_skills (
                job_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                skill_id TEXT NOT NULL,
                PRIMARY KEY (job_id, order_index),
                FOREIGN KEY (job_id) REFERENCES jobs(id) ON DELETE CASCADE
            );
            """,
            // Races
            """
            CREATE TABLE IF NOT EXISTS races (
                id TEXT PRIMARY KEY,
                race_index INTEGER NOT NULL,
                name TEXT NOT NULL,
                gender TEXT NOT NULL,
                gender_code INTEGER NOT NULL,
                category TEXT NOT NULL,
                description TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS race_base_stats (
                race_id TEXT NOT NULL,
                stat TEXT NOT NULL,
                value INTEGER NOT NULL,
                PRIMARY KEY (race_id, stat),
                FOREIGN KEY (race_id) REFERENCES races(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS race_passive_skills (
                race_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                skill_id TEXT NOT NULL,
                name TEXT NOT NULL,
                effect TEXT NOT NULL,
                description TEXT NOT NULL,
                PRIMARY KEY (race_id, order_index),
                FOREIGN KEY (race_id) REFERENCES races(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS race_skill_unlocks (
                race_id TEXT NOT NULL,
                level_requirement INTEGER NOT NULL,
                skill_id TEXT NOT NULL,
                name TEXT NOT NULL,
                effect TEXT NOT NULL,
                description TEXT NOT NULL,
                PRIMARY KEY (race_id, level_requirement),
                FOREIGN KEY (race_id) REFERENCES races(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS race_category_caps (
                category TEXT PRIMARY KEY,
                max_level INTEGER NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS race_category_memberships (
                category TEXT NOT NULL,
                race_id TEXT NOT NULL,
                PRIMARY KEY (category, race_id),
                FOREIGN KEY (category) REFERENCES race_category_caps(category) ON DELETE CASCADE,
                FOREIGN KEY (race_id) REFERENCES races(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS race_gender_restrictions (
                rule TEXT NOT NULL,
                race_id TEXT NOT NULL,
                PRIMARY KEY (rule, race_id),
                FOREIGN KEY (race_id) REFERENCES races(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS race_hiring_cost_categories (
                category TEXT PRIMARY KEY,
                cost INTEGER NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS race_hiring_cost_memberships (
                category TEXT NOT NULL,
                race_id TEXT NOT NULL,
                PRIMARY KEY (category, race_id),
                FOREIGN KEY (category) REFERENCES race_hiring_cost_categories(category) ON DELETE CASCADE,
                FOREIGN KEY (race_id) REFERENCES races(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS race_hiring_level_limits (
                category TEXT PRIMARY KEY,
                max_level INTEGER NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS race_hiring_level_memberships (
                category TEXT NOT NULL,
                race_id TEXT NOT NULL,
                PRIMARY KEY (category, race_id),
                FOREIGN KEY (category) REFERENCES race_hiring_level_limits(category) ON DELETE CASCADE,
                FOREIGN KEY (race_id) REFERENCES races(id) ON DELETE CASCADE
            );
            """,
            // Titles
            """
            CREATE TABLE IF NOT EXISTS titles (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                description TEXT,
                stat_multiplier REAL,
                negative_multiplier REAL,
                drop_rate REAL,
                plus_correction INTEGER,
                minus_correction INTEGER,
                judgment_count INTEGER,
                rank INTEGER,
                drop_probability REAL,
                allow_with_title_treasure INTEGER,
                super_rare_rate_normal REAL,
                super_rare_rate_good REAL,
                super_rare_rate_rare REAL,
                super_rare_rate_gem REAL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS super_rare_titles (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                sort_order INTEGER NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS super_rare_title_skills (
                title_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                skill_id TEXT NOT NULL,
                PRIMARY KEY (title_id, order_index),
                FOREIGN KEY (title_id) REFERENCES super_rare_titles(id) ON DELETE CASCADE
            );
            """,
            // Status effects
            """
            CREATE TABLE IF NOT EXISTS status_effects (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                description TEXT NOT NULL,
                category TEXT NOT NULL,
                duration_turns INTEGER,
                tick_damage_percent INTEGER,
                action_locked INTEGER,
                apply_message TEXT,
                expire_message TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS status_effect_tags (
                effect_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                tag TEXT NOT NULL,
                PRIMARY KEY (effect_id, order_index),
                FOREIGN KEY (effect_id) REFERENCES status_effects(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS status_effect_stat_modifiers (
                effect_id TEXT NOT NULL,
                stat TEXT NOT NULL,
                value REAL NOT NULL,
                PRIMARY KEY (effect_id, stat),
                FOREIGN KEY (effect_id) REFERENCES status_effects(id) ON DELETE CASCADE
            );
            """,
            // Enemies
            """
            CREATE TABLE IF NOT EXISTS enemies (
                id TEXT PRIMARY KEY,
                enemy_index INTEGER NOT NULL,
                name TEXT NOT NULL,
                race TEXT NOT NULL,
                category TEXT NOT NULL,
                job TEXT,
                base_experience INTEGER NOT NULL,
                is_boss INTEGER NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS enemy_stats (
                enemy_id TEXT PRIMARY KEY,
                strength INTEGER NOT NULL,
                wisdom INTEGER NOT NULL,
                spirit INTEGER NOT NULL,
                vitality INTEGER NOT NULL,
                agility INTEGER NOT NULL,
                luck INTEGER NOT NULL,
                FOREIGN KEY (enemy_id) REFERENCES enemies(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS enemy_resistances (
                enemy_id TEXT NOT NULL,
                element TEXT NOT NULL,
                value REAL NOT NULL,
                PRIMARY KEY (enemy_id, element),
                FOREIGN KEY (enemy_id) REFERENCES enemies(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS enemy_skills (
                enemy_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                skill_id TEXT NOT NULL,
                PRIMARY KEY (enemy_id, order_index),
                FOREIGN KEY (enemy_id) REFERENCES enemies(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS enemy_drops (
                enemy_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                item_id TEXT NOT NULL,
                PRIMARY KEY (enemy_id, order_index),
                FOREIGN KEY (enemy_id) REFERENCES enemies(id) ON DELETE CASCADE
            );
            """,
            // Dungeons
            """
            CREATE TABLE IF NOT EXISTS dungeons (
                id TEXT PRIMARY KEY,
                dungeon_index INTEGER NOT NULL,
                name TEXT NOT NULL,
                chapter INTEGER NOT NULL,
                stage INTEGER NOT NULL,
                description TEXT NOT NULL,
                recommended_level INTEGER NOT NULL,
                exploration_time INTEGER NOT NULL,
                events_per_floor INTEGER NOT NULL,
                floor_count INTEGER NOT NULL,
                story_text TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS dungeon_unlock_conditions (
                dungeon_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                condition TEXT NOT NULL,
                PRIMARY KEY (dungeon_id, order_index),
                FOREIGN KEY (dungeon_id) REFERENCES dungeons(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS dungeon_encounter_weights (
                dungeon_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                enemy_id TEXT NOT NULL,
                weight REAL NOT NULL,
                PRIMARY KEY (dungeon_id, order_index),
                FOREIGN KEY (dungeon_id) REFERENCES dungeons(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS encounter_tables (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS encounter_events (
                table_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                event_type TEXT NOT NULL,
                enemy_id TEXT,
                spawn_rate REAL,
                group_min INTEGER,
                group_max INTEGER,
                is_boss INTEGER,
                enemy_level INTEGER,
                PRIMARY KEY (table_id, order_index),
                FOREIGN KEY (table_id) REFERENCES encounter_tables(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS dungeon_floors (
                id TEXT PRIMARY KEY,
                dungeon_id TEXT,
                name TEXT NOT NULL,
                floor_number INTEGER NOT NULL,
                encounter_table_id TEXT NOT NULL,
                description TEXT NOT NULL,
                FOREIGN KEY (dungeon_id) REFERENCES dungeons(id) ON DELETE CASCADE,
                FOREIGN KEY (encounter_table_id) REFERENCES encounter_tables(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS dungeon_floor_special_events (
                floor_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                event_id TEXT NOT NULL,
                PRIMARY KEY (floor_id, order_index),
                FOREIGN KEY (floor_id) REFERENCES dungeon_floors(id) ON DELETE CASCADE
            );
            """,
            // Shops
            """
            CREATE TABLE IF NOT EXISTS shops (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS shop_items (
                shop_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                item_id TEXT NOT NULL,
                quantity INTEGER,
                PRIMARY KEY (shop_id, order_index),
                FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE,
                FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
            );
            """,
            // Synthesis
            """
            CREATE TABLE IF NOT EXISTS synthesis_metadata (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                version TEXT NOT NULL,
                last_updated TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS synthesis_recipes (
                id TEXT PRIMARY KEY,
                parent_item_id TEXT NOT NULL,
                child_item_id TEXT NOT NULL,
                result_item_id TEXT NOT NULL
            );
            """,
            // Stories
            """
            CREATE TABLE IF NOT EXISTS story_nodes (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                chapter INTEGER NOT NULL,
                section INTEGER NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS story_unlock_requirements (
                story_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                requirement TEXT NOT NULL,
                PRIMARY KEY (story_id, order_index),
                FOREIGN KEY (story_id) REFERENCES story_nodes(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS story_rewards (
                story_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                reward TEXT NOT NULL,
                PRIMARY KEY (story_id, order_index),
                FOREIGN KEY (story_id) REFERENCES story_nodes(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS story_unlock_modules (
                story_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                module_id TEXT NOT NULL,
                PRIMARY KEY (story_id, order_index),
                FOREIGN KEY (story_id) REFERENCES story_nodes(id) ON DELETE CASCADE
            );
            """,
            // Personality
            """
            CREATE TABLE IF NOT EXISTS personality_primary (
                id TEXT PRIMARY KEY,
                personality_index INTEGER NOT NULL,
                name TEXT NOT NULL,
                kind TEXT NOT NULL,
                description TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS personality_primary_effects (
                personality_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                effect_type TEXT NOT NULL,
                value REAL,
                payload_json TEXT,
                PRIMARY KEY (personality_id, order_index),
                FOREIGN KEY (personality_id) REFERENCES personality_primary(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS personality_secondary (
                id TEXT PRIMARY KEY,
                personality_index INTEGER NOT NULL,
                name TEXT NOT NULL,
                positive_skill_id TEXT NOT NULL,
                negative_skill_id TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS personality_secondary_stat_bonuses (
                personality_id TEXT NOT NULL,
                stat TEXT NOT NULL,
                value INTEGER NOT NULL,
                PRIMARY KEY (personality_id, stat),
                FOREIGN KEY (personality_id) REFERENCES personality_secondary(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS personality_skills (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                kind TEXT NOT NULL,
                description TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS personality_skill_event_effects (
                skill_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                effect_id TEXT NOT NULL,
                PRIMARY KEY (skill_id, order_index),
                FOREIGN KEY (skill_id) REFERENCES personality_skills(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS personality_cancellations (
                positive_skill_id TEXT NOT NULL,
                negative_skill_id TEXT NOT NULL,
                PRIMARY KEY (positive_skill_id, negative_skill_id)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS personality_battle_effects (
                category TEXT PRIMARY KEY,
                payload_json TEXT NOT NULL
            );
            """,
            // Exploration events
            """
            CREATE TABLE IF NOT EXISTS exploration_events (
                id TEXT PRIMARY KEY,
                event_index INTEGER NOT NULL,
                type TEXT NOT NULL,
                name TEXT NOT NULL,
                description TEXT NOT NULL,
                floor_min INTEGER NOT NULL,
                floor_max INTEGER NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS exploration_event_tags (
                event_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                tag TEXT NOT NULL,
                PRIMARY KEY (event_id, order_index),
                FOREIGN KEY (event_id) REFERENCES exploration_events(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS exploration_event_weights (
                event_id TEXT NOT NULL,
                context TEXT NOT NULL,
                weight REAL NOT NULL,
                PRIMARY KEY (event_id, context),
                FOREIGN KEY (event_id) REFERENCES exploration_events(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS exploration_event_payloads (
                event_id TEXT PRIMARY KEY,
                payload_type TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                FOREIGN KEY (event_id) REFERENCES exploration_events(id) ON DELETE CASCADE
            );
            """
        ]

        for sql in statements {
            try execute(sql)
        }
    }
}
