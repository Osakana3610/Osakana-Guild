import Foundation

/// SQLiteに格納されたマスターデータを提供するランタイムサービス。
/// すべての読み取りはキャッシュ済み`MasterDataRepository`を介して行う。
actor MasterDataRuntimeService {
    static let shared = MasterDataRuntimeService(repository: MasterDataRepository(),
                                                 manager: .shared)

    let repository: MasterDataRepository
    private let manager: SQLiteMasterDataManager
    private var isInitialized: Bool = false

    init(repository: MasterDataRepository,
         manager: SQLiteMasterDataManager) {
        self.repository = repository
        self.manager = manager
    }

    // MARK: - Initialization

    func initializeSQLite(databaseURL: URL? = nil) async throws {
        guard !isInitialized else { return }
        try await manager.initialize(databaseURL: databaseURL)
        isInitialized = true
    }

    private func ensureInitialized() async throws {
        if !isInitialized {
            try await initializeSQLite()
        }
    }

    // MARK: - Item Master Data

    func getAllItems() async throws -> [ItemDefinition] {
        try await ensureInitialized()
        return try await repository.allItems()
    }

    func getItemMasterData(id: UInt16) async throws -> ItemDefinition? {
        try await ensureInitialized()
        return try await repository.item(withId: id)
    }

    func getItemMasterData(ids: [UInt16]) async throws -> [ItemDefinition] {
        try await ensureInitialized()
        return try await repository.items(withIds: ids)
    }

    // MARK: - Jobs

    func getAllJobs() async throws -> [JobDefinition] {
        try await ensureInitialized()
        return try await repository.allJobs()
    }

    func getJobDefinition(id: UInt8) async throws -> JobDefinition? {
        try await ensureInitialized()
        return try await repository.job(withId: id)
    }

    // MARK: - Enemies

    func getEnemyDefinition(id: UInt16) async throws -> EnemyDefinition? {
        try await ensureInitialized()
        return try await repository.enemy(withId: id)
    }

    func getAllEnemies() async throws -> [EnemyDefinition] {
        try await ensureInitialized()
        return try await repository.allEnemies()
    }

    func getAllEnemySkills() async throws -> [EnemySkillDefinition] {
        try await ensureInitialized()
        return try await repository.allEnemySkills()
    }

    // MARK: - Exploration Events

    func getExplorationEventDefinition(id: UInt8) async throws -> ExplorationEventDefinition? {
        try await ensureInitialized()
        return try await repository.explorationEvent(withId: id)
    }

    func getAllExplorationEvents() async throws -> [ExplorationEventDefinition] {
        try await ensureInitialized()
        return try await repository.allExplorationEvents()
    }

    // MARK: - Spells

    func getAllSpells() async throws -> [SpellDefinition] {
        try await ensureInitialized()
        return try await repository.allSpells()
    }

    func getSpellDefinition(id: UInt8) async throws -> SpellDefinition? {
        try await ensureInitialized()
        return try await repository.spell(withId: id)
    }

    // MARK: - Races

    func getAllRaces() async throws -> [RaceDefinition] {
        try await ensureInitialized()
        return try await repository.allRaces()
    }

    func getRaceDefinition(id: UInt8) async throws -> RaceDefinition? {
        try await ensureInitialized()
        return try await repository.race(withId: id)
    }

    // MARK: - Shops

    func getShopItems() async throws -> [MasterShopItem] {
        try await ensureInitialized()
        return try await repository.shopItems()
    }

    // MARK: - Titles

    func getAllTitles() async throws -> [TitleDefinition] {
        try await ensureInitialized()
        return try await repository.allTitles()
    }

    func getTitleMasterData(id: UInt8) async throws -> TitleDefinition? {
        try await ensureInitialized()
        return try await repository.title(withId: id)
    }

    func getAllSuperRareTitles() async throws -> [SuperRareTitleDefinition] {
        try await ensureInitialized()
        return try await repository.allSuperRareTitles()
    }

    func getSuperRareTitle(id: UInt8) async throws -> SuperRareTitleDefinition? {
        try await ensureInitialized()
        return try await repository.superRareTitle(withId: id)
    }

    func getStatusEffectDefinition(id: UInt8) async throws -> StatusEffectDefinition? {
        try await ensureInitialized()
        return try await repository.statusEffect(withId: id)
    }

    // MARK: - Personality

    func getPersonalityPrimaryDefinition(id: UInt8) async throws -> PersonalityPrimaryDefinition? {
        try await ensureInitialized()
        return try await repository.personalityPrimary(withId: id)
    }

    func getPersonalitySecondaryDefinition(id: UInt8) async throws -> PersonalitySecondaryDefinition? {
        try await ensureInitialized()
        return try await repository.personalitySecondary(withId: id)
    }

    // MARK: - Dungeons & Exploration

    func getAllDungeons() async throws -> [DungeonDefinition] {
        try await ensureInitialized()
        let (dungeons, _, _) = try await repository.allDungeons()
        return dungeons
    }

    func getAllDungeonsWithEncounters() async throws -> ([DungeonDefinition], [EncounterTableDefinition], [DungeonFloorDefinition]) {
        try await ensureInitialized()
        return try await repository.allDungeons()
    }

    func getDungeonDefinition(id: UInt16) async throws -> DungeonDefinition? {
        try await ensureInitialized()
        return try await repository.dungeon(withId: id)
    }

    // MARK: - Story

    func getAllStoryNodes() async throws -> [StoryNodeDefinition] {
        try await ensureInitialized()
        return try await repository.allStories()
    }

    // MARK: - Skills

    func getAllSkills() async throws -> [SkillDefinition] {
        try await ensureInitialized()
        return try await repository.allSkills()
    }

    // MARK: - Synthesis
    func getAllSynthesisRecipes() async throws -> [SynthesisRecipeDefinition] {
        try await ensureInitialized()
        return try await repository.allSynthesisRecipes()
    }
}
