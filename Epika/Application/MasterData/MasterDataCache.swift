// ==============================================================================
// MasterDataCache.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 起動時にロードされるマスターデータのメモリキャッシュを提供
//   - 全データを配列とDictionaryインデックスの両方で保持
//   - 事前計算データ（dungeonEnemyMap、enemyLevelMap）の提供
//   - オンデマンドキャッシュ（combatStats）の提供
//
// 【データ構造】
//   - @Observable final classで、UIの自動更新をサポート
//   - letプロパティはnonisolatedコンテキストからもアクセス可能
//   - アイテム、職業、種族、スキル、呪文、敵、ダンジョン、性格など全マスターデータ
//   - IDによる単一取得、複数ID取得、条件フィルタ取得を提供
//
// 【使用箇所】
//   - アプリ全体（AppState等から各サービス・UIへ渡される）
//   - MasterDataLoaderによって起動時に1回だけ構築される
//
// ==============================================================================

import Foundation
import SwiftUI
import os

/// 起動時にロードされるマスターデータのメモリキャッシュ
/// @Observable classで、UIの自動更新をサポート
/// letプロパティ（不変データ）はnonisolatedコンテキストからも読み取りアクセス可能
/// @unchecked Sendable: ミュータブルなキャッシュはNSLockで保護されているため安全
@Observable
final class MasterDataCache: @unchecked Sendable {
    // MARK: - 全件データ（配列）

    nonisolated let allItems: [ItemDefinition]
    nonisolated let allJobs: [JobDefinition]
    nonisolated let allRaces: [RaceDefinition]
    nonisolated let allSkills: [SkillDefinition]
    nonisolated let allSpells: [SpellDefinition]
    nonisolated let allEnemies: [EnemyDefinition]
    nonisolated let allEnemySkills: [EnemySkillDefinition]
    nonisolated let allTitles: [TitleDefinition]
    nonisolated let allSuperRareTitles: [SuperRareTitleDefinition]
    nonisolated let allStatusEffects: [StatusEffectDefinition]
    nonisolated let allDungeons: [DungeonDefinition]
    nonisolated let allEncounterTables: [EncounterTableDefinition]
    nonisolated let allDungeonFloors: [DungeonFloorDefinition]
    nonisolated let allExplorationEvents: [ExplorationEventDefinition]
    nonisolated let allStoryNodes: [StoryNodeDefinition]
    nonisolated let allSynthesisRecipes: [SynthesisRecipeDefinition]
    nonisolated let allShopItems: [MasterShopItem]
    nonisolated let allCharacterNames: [CharacterNameDefinition]

    // MARK: - Personality関連

    nonisolated let allPersonalityPrimary: [PersonalityPrimaryDefinition]
    nonisolated let allPersonalitySecondary: [PersonalitySecondaryDefinition]
    nonisolated let allPersonalitySkills: [PersonalitySkillDefinition]
    nonisolated let allPersonalityCancellations: [PersonalityCancellation]
    nonisolated let allPersonalityBattleEffects: [PersonalityBattleEffect]

    // MARK: - Job/Race拡張データ

    nonisolated let jobSkillUnlocks: [UInt8: [(level: Int, skillId: UInt16)]]
    nonisolated let jobMetadata: [UInt8: (category: UInt8, growthTendency: UInt8?)]
    nonisolated let racePassiveSkills: [UInt8: [UInt16]]
    nonisolated let raceSkillUnlocks: [UInt8: [(level: Int, skillId: UInt16)]]

    // MARK: - インデックス（Dictionary）
    // 戦闘システム等で辞書アクセスが必要な場合はinternalで公開

    nonisolated let itemsById: [UInt16: ItemDefinition]
    nonisolated let jobsById: [UInt8: JobDefinition]
    nonisolated let racesById: [UInt8: RaceDefinition]
    nonisolated let skillsById: [UInt16: SkillDefinition]
    nonisolated let spellsById: [UInt8: SpellDefinition]
    nonisolated let enemiesById: [UInt16: EnemyDefinition]
    nonisolated let enemySkillsById: [UInt16: EnemySkillDefinition]
    nonisolated let titlesById: [UInt8: TitleDefinition]
    nonisolated let superRareTitlesById: [UInt8: SuperRareTitleDefinition]
    nonisolated let statusEffectsById: [UInt8: StatusEffectDefinition]
    nonisolated let dungeonsById: [UInt16: DungeonDefinition]
    nonisolated let explorationEventsById: [UInt8: ExplorationEventDefinition]
    nonisolated let personalityPrimaryById: [UInt8: PersonalityPrimaryDefinition]
    nonisolated let personalitySecondaryById: [UInt8: PersonalitySecondaryDefinition]
    nonisolated let personalitySkillsById: [UInt8: PersonalitySkillDefinition]
    nonisolated let personalityBattleEffectsById: [UInt8: PersonalityBattleEffect]
    nonisolated let characterNamesByGender: [UInt8: [CharacterNameDefinition]]
    nonisolated let storyNodesById: [UInt16: StoryNodeDefinition]

    // MARK: - 事前計算データ（起動時に1回だけ計算）

    /// ダンジョンID → 出現敵IDセット
    nonisolated let dungeonEnemyMap: [UInt16: Set<UInt16>]
    /// 敵ID → 最大出現レベル
    nonisolated let enemyLevelMap: [UInt16: Int]

    // MARK: - 敵種族名辞書

    nonisolated let enemyRaceNames: [UInt8: String]

    // MARK: - オンデマンドキャッシュ（combatStats）

    nonisolated private struct CombatCacheKey: Hashable, Sendable {
        let enemyId: UInt16
        let level: Int
    }

    @ObservationIgnored
    nonisolated private let combatCache = OSAllocatedUnfairLock<[CombatCacheKey: CharacterValues.Combat]>(initialState: [:])

    /// 敵の戦闘ステータスを取得（オンデマンドでキャッシュ）
    nonisolated func combatStats(for enemyId: UInt16, level: Int) throws -> CharacterValues.Combat {
        let key = CombatCacheKey(enemyId: enemyId, level: level)

        if let cached = combatCache.withLock({ $0[key] }) {
            return cached
        }

        // キャッシュミス - 計算する
        guard let enemy = enemiesById[enemyId] else {
            throw RuntimeError.masterDataNotFound(entity: "enemy", identifier: String(enemyId))
        }

        let snapshot = try CombatSnapshotBuilder.makeEnemySnapshot(
            from: enemy,
            levelOverride: level,
            masterData: self
        )

        combatCache.withLock { cache in
            cache[key] = snapshot
        }

        return snapshot
    }

    // MARK: - ヘルパーメソッド（UIでよく使う）

    /// 呪文名を取得
    nonisolated func spellName(for spellId: UInt8) -> String {
        spellsById[spellId]?.name ?? "呪文ID:\(spellId)"
    }

    /// アイテム名を取得
    nonisolated func itemName(for itemId: UInt16) -> String {
        itemsById[itemId]?.name ?? "アイテムID:\(itemId)"
    }

    /// 職業名を取得
    nonisolated func jobName(for jobId: UInt8) -> String {
        jobsById[jobId]?.name ?? "職業ID:\(jobId)"
    }

    /// 敵種族名を取得
    nonisolated func enemyRaceName(for raceId: UInt8) -> String {
        enemyRaceNames[raceId] ?? "種族ID:\(raceId)"
    }

    // MARK: - 単一ID取得

    nonisolated func item(_ id: UInt16) -> ItemDefinition? { itemsById[id] }
    nonisolated func job(_ id: UInt8) -> JobDefinition? { jobsById[id] }
    nonisolated func race(_ id: UInt8) -> RaceDefinition? { racesById[id] }
    nonisolated func skill(_ id: UInt16) -> SkillDefinition? { skillsById[id] }
    nonisolated func spell(_ id: UInt8) -> SpellDefinition? { spellsById[id] }
    nonisolated func enemy(_ id: UInt16) -> EnemyDefinition? { enemiesById[id] }
    nonisolated func enemySkill(_ id: UInt16) -> EnemySkillDefinition? { enemySkillsById[id] }
    nonisolated func title(_ id: UInt8) -> TitleDefinition? { titlesById[id] }
    nonisolated func superRareTitle(_ id: UInt8) -> SuperRareTitleDefinition? { superRareTitlesById[id] }
    nonisolated func statusEffect(_ id: UInt8) -> StatusEffectDefinition? { statusEffectsById[id] }
    nonisolated func dungeon(_ id: UInt16) -> DungeonDefinition? { dungeonsById[id] }
    nonisolated func explorationEvent(_ id: UInt8) -> ExplorationEventDefinition? { explorationEventsById[id] }
    nonisolated func personalityPrimary(_ id: UInt8) -> PersonalityPrimaryDefinition? { personalityPrimaryById[id] }
    nonisolated func personalitySecondary(_ id: UInt8) -> PersonalitySecondaryDefinition? { personalitySecondaryById[id] }
    nonisolated func personalitySkill(_ id: UInt8) -> PersonalitySkillDefinition? { personalitySkillsById[id] }
    nonisolated func personalityBattleEffect(_ id: UInt8) -> PersonalityBattleEffect? { personalityBattleEffectsById[id] }
    nonisolated func storyNode(_ id: UInt16) -> StoryNodeDefinition? { storyNodesById[id] }

    // MARK: - 複数ID取得

    nonisolated func items(_ ids: [UInt16]) -> [ItemDefinition] {
        ids.map { itemsById[$0]! }
    }

    nonisolated func skills(_ ids: [UInt16]) -> [SkillDefinition] {
        ids.map { skillsById[$0]! }
    }

    nonisolated func spells(_ ids: [UInt8]) -> [SpellDefinition] {
        ids.map { spellsById[$0]! }
    }

    // MARK: - フィルタ取得

    nonisolated func characterNames(forGenderCode genderCode: UInt8) -> [CharacterNameDefinition] {
        characterNamesByGender[genderCode]!
    }

    nonisolated func randomCharacterName(forGenderCode genderCode: UInt8) -> String {
        let names = characterNames(forGenderCode: genderCode)
        assert(!names.isEmpty, "Character names for gender code \(genderCode) is empty")
        return names.randomElement()?.name ?? "名無し"
    }

    // MARK: - イニシャライザ

    nonisolated init(
        allItems: [ItemDefinition],
        allJobs: [JobDefinition],
        allRaces: [RaceDefinition],
        allSkills: [SkillDefinition],
        allSpells: [SpellDefinition],
        allEnemies: [EnemyDefinition],
        allEnemySkills: [EnemySkillDefinition],
        allTitles: [TitleDefinition],
        allSuperRareTitles: [SuperRareTitleDefinition],
        allStatusEffects: [StatusEffectDefinition],
        allDungeons: [DungeonDefinition],
        allEncounterTables: [EncounterTableDefinition],
        allDungeonFloors: [DungeonFloorDefinition],
        allExplorationEvents: [ExplorationEventDefinition],
        allStoryNodes: [StoryNodeDefinition],
        allSynthesisRecipes: [SynthesisRecipeDefinition],
        allShopItems: [MasterShopItem],
        allCharacterNames: [CharacterNameDefinition],
        allPersonalityPrimary: [PersonalityPrimaryDefinition],
        allPersonalitySecondary: [PersonalitySecondaryDefinition],
        allPersonalitySkills: [PersonalitySkillDefinition],
        allPersonalityCancellations: [PersonalityCancellation],
        allPersonalityBattleEffects: [PersonalityBattleEffect],
        jobSkillUnlocks: [UInt8: [(level: Int, skillId: UInt16)]],
        jobMetadata: [UInt8: (category: UInt8, growthTendency: UInt8?)],
        racePassiveSkills: [UInt8: [UInt16]],
        raceSkillUnlocks: [UInt8: [(level: Int, skillId: UInt16)]],
        dungeonEnemyMap: [UInt16: Set<UInt16>],
        enemyLevelMap: [UInt16: Int]
    ) {
        // 配列を保持
        self.allItems = allItems
        self.allJobs = allJobs
        self.allRaces = allRaces
        self.allSkills = allSkills
        self.allSpells = allSpells
        self.allEnemies = allEnemies
        self.allEnemySkills = allEnemySkills
        self.allTitles = allTitles
        self.allSuperRareTitles = allSuperRareTitles
        self.allStatusEffects = allStatusEffects
        self.allDungeons = allDungeons
        self.allEncounterTables = allEncounterTables
        self.allDungeonFloors = allDungeonFloors
        self.allExplorationEvents = allExplorationEvents
        self.allStoryNodes = allStoryNodes
        self.allSynthesisRecipes = allSynthesisRecipes
        self.allShopItems = allShopItems
        self.allCharacterNames = allCharacterNames
        self.allPersonalityPrimary = allPersonalityPrimary
        self.allPersonalitySecondary = allPersonalitySecondary
        self.allPersonalitySkills = allPersonalitySkills
        self.allPersonalityCancellations = allPersonalityCancellations
        self.allPersonalityBattleEffects = allPersonalityBattleEffects
        self.jobSkillUnlocks = jobSkillUnlocks
        self.jobMetadata = jobMetadata
        self.racePassiveSkills = racePassiveSkills
        self.raceSkillUnlocks = raceSkillUnlocks

        // 事前計算データ
        self.dungeonEnemyMap = dungeonEnemyMap
        self.enemyLevelMap = enemyLevelMap

        // 敵種族名辞書
        self.enemyRaceNames = [
            1: "人型",
            2: "魔物",
            3: "不死",
            4: "竜族",
            5: "神魔"
        ]

        // Dictionaryインデックスを構築
        self.itemsById = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        self.jobsById = Dictionary(uniqueKeysWithValues: allJobs.map { ($0.id, $0) })
        self.racesById = Dictionary(uniqueKeysWithValues: allRaces.map { ($0.id, $0) })
        self.skillsById = Dictionary(uniqueKeysWithValues: allSkills.map { ($0.id, $0) })
        self.spellsById = Dictionary(uniqueKeysWithValues: allSpells.map { ($0.id, $0) })
        self.enemiesById = Dictionary(uniqueKeysWithValues: allEnemies.map { ($0.id, $0) })
        self.enemySkillsById = Dictionary(uniqueKeysWithValues: allEnemySkills.map { ($0.id, $0) })
        self.titlesById = Dictionary(uniqueKeysWithValues: allTitles.map { ($0.id, $0) })
        self.superRareTitlesById = Dictionary(uniqueKeysWithValues: allSuperRareTitles.map { ($0.id, $0) })
        self.statusEffectsById = Dictionary(uniqueKeysWithValues: allStatusEffects.map { ($0.id, $0) })
        self.dungeonsById = Dictionary(uniqueKeysWithValues: allDungeons.map { ($0.id, $0) })
        self.explorationEventsById = Dictionary(uniqueKeysWithValues: allExplorationEvents.map { ($0.id, $0) })
        self.personalityPrimaryById = Dictionary(uniqueKeysWithValues: allPersonalityPrimary.map { ($0.id, $0) })
        self.personalitySecondaryById = Dictionary(uniqueKeysWithValues: allPersonalitySecondary.map { ($0.id, $0) })
        self.personalitySkillsById = Dictionary(uniqueKeysWithValues: allPersonalitySkills.map { ($0.id, $0) })
        self.personalityBattleEffectsById = Dictionary(uniqueKeysWithValues: allPersonalityBattleEffects.map { ($0.id, $0) })
        self.characterNamesByGender = Dictionary(grouping: allCharacterNames, by: { $0.genderCode })
        self.storyNodesById = Dictionary(uniqueKeysWithValues: allStoryNodes.map { ($0.id, $0) })
    }
}
