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

    // MARK: - 単一ID取得（同期）

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
    func personalitySkill(_ id: String) -> PersonalitySkillDefinition? { personalitySkillsById[id] }
    func personalityBattleEffect(_ id: String) -> PersonalityBattleEffect? { personalityBattleEffectsById[id] }

    // MARK: - 複数ID取得（同期）

    func items(_ ids: [UInt16]) -> [ItemDefinition] {
        ids.map { itemsById[$0]! }
    }

    func skills(_ ids: [UInt16]) -> [SkillDefinition] {
        ids.map { skillsById[$0]! }
    }

    func spells(_ ids: [UInt8]) -> [SpellDefinition] {
        ids.map { spellsById[$0]! }
    }

    // MARK: - フィルタ取得（同期）

    func characterNames(forGenderCode genderCode: UInt8) -> [CharacterNameDefinition] {
        characterNamesByGender[genderCode]!
    }

    func randomCharacterName(forGenderCode genderCode: UInt8) -> String {
        characterNames(forGenderCode: genderCode).randomElement()!.name
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
    }
}

// MARK: - SwiftUI Environment

private struct MasterDataKey: EnvironmentKey {
    static var defaultValue: MasterDataCache {
        fatalError("MasterDataCache not provided in environment. Ensure .environment(\\.masterData, cache) is set in EpikaApp.")
    }
}

extension EnvironmentValues {
    var masterData: MasterDataCache {
        get { self[MasterDataKey.self] }
        set { self[MasterDataKey.self] = newValue }
    }
}
