import Foundation

/// SQLiteに格納されたマスターデータを提供するランタイムサービス。
/// すべての読み取りはキャッシュ済み`MasterDataRepository`を介して行う。
actor MasterDataRuntimeService {
    static let shared = MasterDataRuntimeService(repository: MasterDataRepository(),
                                                 manager: .shared)

    private let repository: MasterDataRepository
    private let manager: SQLiteMasterDataManager
    private var isInitialized: Bool = false

    init(repository: MasterDataRepository,
         manager: SQLiteMasterDataManager) {
        self.repository = repository
        self.manager = manager
    }

    // MARK: - Initialization

    func initializeSQLite(databaseURL: URL? = nil,
                          resourceLocator: MasterDataResourceLocator? = nil) async throws {
        guard !isInitialized else { return }
        let locator = try await resolveLocator(resourceLocator)
        try await manager.initialize(databaseURL: databaseURL, resourceLocator: locator)
        isInitialized = true
    }

    private func ensureInitialized() async throws {
        if !isInitialized {
            try await initializeSQLite()
        }
    }

    private func resolveLocator(_ locator: MasterDataResourceLocator?) async throws -> MasterDataResourceLocator {
        if let locator { return locator }
        return await MainActor.run { MasterDataResourceLocator.makeDefault() }
    }

    // MARK: - Item Master Data

    func getAllItems() async throws -> [ItemDefinition] {
        try await ensureInitialized()
        return try await repository.allItems()
    }

    func getItemMasterData(id: String) async throws -> ItemDefinition? {
        try await ensureInitialized()
        return try await repository.item(withId: id)
    }

    func getItemMasterData(ids: [String]) async throws -> [ItemDefinition] {
        try await ensureInitialized()
        return try await repository.items(withIds: ids)
    }

    // MARK: - Jobs

    func getAllJobs() async throws -> [JobDefinition] {
        try await ensureInitialized()
        return try await repository.allJobs()
    }

    func getEnemyDefinition(id: String) async throws -> EnemyDefinition? {
        try await ensureInitialized()
        return try await repository.enemy(withId: id)
    }

    // MARK: - Spells

    func getAllSpells() async throws -> [SpellDefinition] {
        try await ensureInitialized()
        return try await repository.allSpells()
    }

    func getSpellDefinition(id: String) async throws -> SpellDefinition? {
        try await ensureInitialized()
        return try await repository.spell(withId: id)
    }

    // MARK: - Races

    func getAllRaces() async throws -> [RaceDefinition] {
        try await ensureInitialized()
        return try await repository.allRaces()
    }

    // MARK: - Shops

    func getShopDefinition(id: String) async throws -> ShopDefinition? {
        try await ensureInitialized()
        return try await repository.shop(withId: id)
    }

    // MARK: - Titles

    func getAllTitles() async throws -> [TitleDefinition] {
        try await ensureInitialized()
        return try await repository.allTitles()
    }

    func getTitleMasterData(id: String) async throws -> TitleDefinition? {
        try await ensureInitialized()
        return try await repository.title(withId: id)
    }

    func getAllSuperRareTitles() async throws -> [SuperRareTitleDefinition] {
        try await ensureInitialized()
        return try await repository.allSuperRareTitles()
    }

    func getSuperRareTitle(id: String) async throws -> SuperRareTitleDefinition? {
        try await ensureInitialized()
        return try await repository.superRareTitle(withId: id)
    }

    func getStatusEffectDefinition(id: String) async throws -> StatusEffectDefinition? {
        try await ensureInitialized()
        return try await repository.statusEffect(withId: id)
    }

    // MARK: - Personality

    // MARK: - Dungeons & Exploration

    func getAllDungeons() async throws -> [DungeonDefinition] {
        try await ensureInitialized()
        let (dungeons, _, _) = try await repository.allDungeons()
        return dungeons
    }

    func getDungeonDefinition(id: String) async throws -> DungeonDefinition? {
        try await ensureInitialized()
        return try await repository.dungeon(withId: id)
    }

    // MARK: - Story

    func getAllStoryNodes() async throws -> [StoryNodeDefinition] {
        try await ensureInitialized()
        return try await repository.allStories()
    }

    // MARK: - Synthesis
    func getAllSynthesisRecipes() async throws -> [SynthesisRecipeDefinition] {
        try await ensureInitialized()
        return try await repository.allSynthesisRecipes()
    }
}
