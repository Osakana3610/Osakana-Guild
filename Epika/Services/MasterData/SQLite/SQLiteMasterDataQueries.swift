// ==============================================================================
// SQLiteMasterDataQueries.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - SQLiteMasterDataManagerのクエリメソッド群の索引ファイル
//   - 実装は各機能ごとに拡張ファイルに分割
//
// 【拡張ファイル一覧】
//   - SQLiteMasterDataQueries.Items.swift: fetchAllItems
//   - SQLiteMasterDataQueries.Skills.swift: fetchAllSkills
//   - SQLiteMasterDataQueries.Enemies.swift: fetchAllEnemies, fetchAllEnemySkills
//   - SQLiteMasterDataQueries.StatusEffects.swift: fetchAllStatusEffects
//   - SQLiteMasterDataQueries.Dungeons.swift: fetchAllDungeons
//   - SQLiteMasterDataQueries.ExplorationEvents.swift: fetchAllExplorationEvents
//   - SQLiteMasterDataQueries.Jobs.swift: fetchAllJobs, fetchAllJobSkillUnlocks, fetchAllJobMetadata
//   - SQLiteMasterDataQueries.Shops.swift: fetchShopItems
//   - SQLiteMasterDataQueries.Races.swift: fetchAllRaces, fetchAllRacePassiveSkills, fetchAllRaceSkillUnlocks
//   - SQLiteMasterDataQueries.Titles.swift: fetchAllTitles, fetchAllSuperRareTitles
//   - SQLiteMasterDataQueries.Personality.swift: fetchPersonalityData
//   - SQLiteMasterDataQueries.Stories.swift: fetchAllStories
//   - SQLiteMasterDataQueries.Spells.swift: fetchAllSpells
//   - SQLiteMasterDataQueries.Synthesis.swift: fetchAllSynthesisRecipes
//   - SQLiteMasterDataQueries.CharacterNames.swift: fetchAllCharacterNames
//
// ==============================================================================

import Foundation
import SQLite3

/// SQLiteMasterDataManager のクエリメソッド群
/// 実際の実装は各extension fileに分割:
/// - SQLiteMasterDataQueries.Items.swift: fetchAllItems
/// - SQLiteMasterDataQueries.Skills.swift: fetchAllSkills
/// - SQLiteMasterDataQueries.Enemies.swift: fetchAllEnemies
/// - SQLiteMasterDataQueries.StatusEffects.swift: fetchAllStatusEffects
/// - SQLiteMasterDataQueries.Dungeons.swift: fetchAllDungeons
/// - SQLiteMasterDataQueries.ExplorationEvents.swift: fetchAllExplorationEvents
/// - SQLiteMasterDataQueries.Jobs.swift: fetchAllJobs
/// - SQLiteMasterDataQueries.Shops.swift: fetchAllShops
/// - SQLiteMasterDataQueries.Races.swift: fetchAllRaces
/// - SQLiteMasterDataQueries.Titles.swift: fetchAllTitles, fetchAllSuperRareTitles
/// - SQLiteMasterDataQueries.Personality.swift: fetchPersonalityData
/// - SQLiteMasterDataQueries.Stories.swift: fetchAllStories
/// - SQLiteMasterDataQueries.Spells.swift: fetchAllSpells
/// - SQLiteMasterDataQueries.Synthesis.swift: fetchAllSynthesisRecipes
