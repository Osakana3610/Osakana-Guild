import Foundation
import SwiftUI

/// 起動時にロードされるマスターデータのメモリキャッシュ
/// Sendableで、どのスレッドからでも安全にアクセス可能
struct MasterDataCache: Sendable {
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
    let jobMetadata: [UInt8: (category: String, growthTendency: String?)]
    let racePassiveSkills: [UInt8: [UInt16]]
    let raceSkillUnlocks: [UInt8: [(level: Int, skillId: UInt16)]]

    // MARK: - インデックス（Dictionary）

    private let itemsById: [UInt16: ItemDefinition]
    private let jobsById: [UInt8: JobDefinition]
    private let racesById: [UInt8: RaceDefinition]
    private let skillsById: [UInt16: SkillDefinition]
    private let spellsById: [UInt8: SpellDefinition]
    private let enemiesById: [UInt16: EnemyDefinition]
    private let enemySkillsById: [UInt16: EnemySkillDefinition]
    private let titlesById: [UInt8: TitleDefinition]
    private let superRareTitlesById: [UInt8: SuperRareTitleDefinition]
    private let statusEffectsById: [UInt8: StatusEffectDefinition]
    private let dungeonsById: [UInt16: DungeonDefinition]
    private let explorationEventsById: [UInt8: ExplorationEventDefinition]
    private let personalityPrimaryById: [UInt8: PersonalityPrimaryDefinition]
    private let personalitySecondaryById: [UInt8: PersonalitySecondaryDefinition]
    private let personalitySkillsById: [String: PersonalitySkillDefinition]
    private let personalityBattleEffectsById: [String: PersonalityBattleEffect]
    private let characterNamesByGender: [UInt8: [CharacterNameDefinition]]
    private let storyNodesById: [UInt16: StoryNodeDefinition]

    // MARK: - 単一ID取得（同期、nonisolated）

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
    nonisolated func personalitySkill(_ id: String) -> PersonalitySkillDefinition? { personalitySkillsById[id] }
    nonisolated func personalityBattleEffect(_ id: String) -> PersonalityBattleEffect? { personalityBattleEffectsById[id] }
    nonisolated func storyNode(_ id: UInt16) -> StoryNodeDefinition? { storyNodesById[id] }

    // MARK: - 複数ID取得（同期、nonisolated）

    nonisolated func items(_ ids: [UInt16]) -> [ItemDefinition] {
        ids.map { itemsById[$0]! }
    }

    nonisolated func skills(_ ids: [UInt16]) -> [SkillDefinition] {
        ids.map { skillsById[$0]! }
    }

    nonisolated func spells(_ ids: [UInt8]) -> [SpellDefinition] {
        ids.map { spellsById[$0]! }
    }

    // MARK: - フィルタ取得（同期、nonisolated）

    nonisolated func characterNames(forGenderCode genderCode: UInt8) -> [CharacterNameDefinition] {
        characterNamesByGender[genderCode]!
    }

    nonisolated func randomCharacterName(forGenderCode genderCode: UInt8) -> String {
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
        jobMetadata: [UInt8: (category: String, growthTendency: String?)],
        racePassiveSkills: [UInt8: [UInt16]],
        raceSkillUnlocks: [UInt8: [(level: Int, skillId: UInt16)]]
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
