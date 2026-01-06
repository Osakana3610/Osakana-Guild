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

/// 起動時にロードされるマスターデータのメモリキャッシュ
/// @Observable classで、UIの自動更新をサポート
/// letプロパティ（不変データ）はnonisolatedコンテキストからも読み取りアクセス可能
/// @unchecked Sendable: ミュータブルなキャッシュはNSLockで保護されているため安全
@Observable
final class MasterDataCache: @unchecked Sendable {
    // MARK: - 全件データ（配列）

    let allItems: [ItemDefinition]
    let allJobs: [JobDefinition]
    let allRaces: [RaceDefinition]
    let allSkills: [SkillDefinition]
    let allSpells: [SpellDefinition]
    let allEnemies: [EnemyDefinition]
    let allEnemySkills: [EnemySkillDefinition]
    let allTitles: [TitleDefinition]
    let allSuperRareTitles: [SuperRareTitleDefinition]
    let allStatusEffects: [StatusEffectDefinition]
    let allDungeons: [DungeonDefinition]
    let allEncounterTables: [EncounterTableDefinition]
    let allDungeonFloors: [DungeonFloorDefinition]
    let allExplorationEvents: [ExplorationEventDefinition]
    let allStoryNodes: [StoryNodeDefinition]
    let allSynthesisRecipes: [SynthesisRecipeDefinition]
    let allShopItems: [MasterShopItem]
    let allCharacterNames: [CharacterNameDefinition]

    // MARK: - Personality関連

    let allPersonalityPrimary: [PersonalityPrimaryDefinition]
    let allPersonalitySecondary: [PersonalitySecondaryDefinition]
    let allPersonalitySkills: [PersonalitySkillDefinition]
    let allPersonalityCancellations: [PersonalityCancellation]
    let allPersonalityBattleEffects: [PersonalityBattleEffect]

    // MARK: - Job/Race拡張データ

    let jobSkillUnlocks: [UInt8: [(level: Int, skillId: UInt16)]]
    let jobMetadata: [UInt8: (category: UInt8, growthTendency: UInt8?)]
    let racePassiveSkills: [UInt8: [UInt16]]
    let raceSkillUnlocks: [UInt8: [(level: Int, skillId: UInt16)]]

    // MARK: - インデックス（Dictionary）
    // 戦闘システム等で辞書アクセスが必要な場合はinternalで公開

    let itemsById: [UInt16: ItemDefinition]
    let jobsById: [UInt8: JobDefinition]
    let racesById: [UInt8: RaceDefinition]
    let skillsById: [UInt16: SkillDefinition]
    let spellsById: [UInt8: SpellDefinition]
    let enemiesById: [UInt16: EnemyDefinition]
    let enemySkillsById: [UInt16: EnemySkillDefinition]
    let titlesById: [UInt8: TitleDefinition]
    let superRareTitlesById: [UInt8: SuperRareTitleDefinition]
    let statusEffectsById: [UInt8: StatusEffectDefinition]
    let dungeonsById: [UInt16: DungeonDefinition]
    let explorationEventsById: [UInt8: ExplorationEventDefinition]
    let personalityPrimaryById: [UInt8: PersonalityPrimaryDefinition]
    let personalitySecondaryById: [UInt8: PersonalitySecondaryDefinition]
    let personalitySkillsById: [UInt8: PersonalitySkillDefinition]
    let personalityBattleEffectsById: [UInt8: PersonalityBattleEffect]
    let characterNamesByGender: [UInt8: [CharacterNameDefinition]]
    let storyNodesById: [UInt16: StoryNodeDefinition]

    // MARK: - 事前計算データ（起動時に1回だけ計算）

    /// ダンジョンID → 出現敵IDセット
    let dungeonEnemyMap: [UInt16: Set<UInt16>]
    /// 敵ID → 最大出現レベル
    let enemyLevelMap: [UInt16: Int]

    // MARK: - 敵種族名辞書

    let enemyRaceNames: [UInt8: String]

    // MARK: - オンデマンドキャッシュ（combatStats）

    private struct CombatCacheKey: Hashable, Sendable {
        let enemyId: UInt16
        let level: Int
    }

    @ObservationIgnored
    private let combatCacheLock = NSLock()
    @ObservationIgnored
    private var combatCache: [CombatCacheKey: CharacterValues.Combat] = [:]

    /// 敵の戦闘ステータスを取得（オンデマンドでキャッシュ）
    func combatStats(for enemyId: UInt16, level: Int) throws -> CharacterValues.Combat {
        let key = CombatCacheKey(enemyId: enemyId, level: level)

        combatCacheLock.lock()
        if let cached = combatCache[key] {
            combatCacheLock.unlock()
            return cached
        }
        combatCacheLock.unlock()

        // キャッシュミス - 計算する
        guard let enemy = enemiesById[enemyId] else {
            throw RuntimeError.masterDataNotFound(entity: "enemy", identifier: String(enemyId))
        }

        let snapshot = try CombatSnapshotBuilder.makeEnemySnapshot(
            from: enemy,
            levelOverride: level,
            masterData: self
        )

        combatCacheLock.lock()
        combatCache[key] = snapshot
        combatCacheLock.unlock()

        return snapshot
    }

    // MARK: - ヘルパーメソッド（UIでよく使う）

    /// 呪文名を取得
    func spellName(for spellId: UInt8) -> String {
        spellsById[spellId]?.name ?? "呪文ID:\(spellId)"
    }

    /// アイテム名を取得
    func itemName(for itemId: UInt16) -> String {
        itemsById[itemId]?.name ?? "アイテムID:\(itemId)"
    }

    /// 職業名を取得
    func jobName(for jobId: UInt8) -> String {
        jobsById[jobId]?.name ?? "職業ID:\(jobId)"
    }

    /// 敵種族名を取得
    func enemyRaceName(for raceId: UInt8) -> String {
        enemyRaceNames[raceId] ?? "種族ID:\(raceId)"
    }

    // MARK: - 単一ID取得

    func item(_ id: UInt16) -> ItemDefinition? { itemsById[id] }
    func job(_ id: UInt8) -> JobDefinition? { jobsById[id] }
    func race(_ id: UInt8) -> RaceDefinition? { racesById[id] }
    func skill(_ id: UInt16) -> SkillDefinition? { skillsById[id] }
    func spell(_ id: UInt8) -> SpellDefinition? { spellsById[id] }
    func enemy(_ id: UInt16) -> EnemyDefinition? { enemiesById[id] }
    func enemySkill(_ id: UInt16) -> EnemySkillDefinition? { enemySkillsById[id] }
    func title(_ id: UInt8) -> TitleDefinition? { titlesById[id] }
    func superRareTitle(_ id: UInt8) -> SuperRareTitleDefinition? { superRareTitlesById[id] }
    func statusEffect(_ id: UInt8) -> StatusEffectDefinition? { statusEffectsById[id] }
    func dungeon(_ id: UInt16) -> DungeonDefinition? { dungeonsById[id] }
    func explorationEvent(_ id: UInt8) -> ExplorationEventDefinition? { explorationEventsById[id] }
    func personalityPrimary(_ id: UInt8) -> PersonalityPrimaryDefinition? { personalityPrimaryById[id] }
    func personalitySecondary(_ id: UInt8) -> PersonalitySecondaryDefinition? { personalitySecondaryById[id] }
    func personalitySkill(_ id: UInt8) -> PersonalitySkillDefinition? { personalitySkillsById[id] }
    func personalityBattleEffect(_ id: UInt8) -> PersonalityBattleEffect? { personalityBattleEffectsById[id] }
    func storyNode(_ id: UInt16) -> StoryNodeDefinition? { storyNodesById[id] }

    // MARK: - 複数ID取得

    func items(_ ids: [UInt16]) -> [ItemDefinition] {
        ids.map { itemsById[$0]! }
    }

    func skills(_ ids: [UInt16]) -> [SkillDefinition] {
        ids.map { skillsById[$0]! }
    }

    func spells(_ ids: [UInt8]) -> [SpellDefinition] {
        ids.map { spellsById[$0]! }
    }

    // MARK: - フィルタ取得

    func characterNames(forGenderCode genderCode: UInt8) -> [CharacterNameDefinition] {
        characterNamesByGender[genderCode]!
    }

    func randomCharacterName(forGenderCode genderCode: UInt8) -> String {
        let names = characterNames(forGenderCode: genderCode)
        assert(!names.isEmpty, "Character names for gender code \(genderCode) is empty")
        return names.randomElement()?.name ?? "名無し"
    }

    // MARK: - イニシャライザ

    init(
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
