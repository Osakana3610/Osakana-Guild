import Foundation

/// SQLiteに格納されたマスターデータを提供するランタイムサービス。
/// すべての読み取りはキャッシュ済み`MasterDataRepository`を介して行う。
actor MasterDataRuntimeService {
    static let shared = MasterDataRuntimeService(repository: MasterDataRepository(),
                                                 manager: .shared)

    private let repository: MasterDataRepository
    private let manager: SQLiteMasterDataManager
    private var isInitialized: Bool = false

    // MARK: - Index Maps (String ID ⇔ Int Index)

    /// アイテム: String ID → Int16 Index (1〜1000)
    private var itemIdToIndex: [String: Int16] = [:]
    private var itemIndexToId: [Int16: String] = [:]

    /// 通常称号: String ID → Int8 Index (rank: 0〜8)
    private var titleIdToIndex: [String: Int8] = [:]
    private var titleIndexToId: [Int8: String] = [:]

    /// 超レア称号: String ID → Int16 Index (order: 1〜100)
    private var superRareTitleIdToIndex: [String: Int16] = [:]
    private var superRareTitleIndexToId: [Int16: String] = [:]

    init(repository: MasterDataRepository,
         manager: SQLiteMasterDataManager) {
        self.repository = repository
        self.manager = manager
    }

    // MARK: - Initialization

    func initializeSQLite(databaseURL: URL? = nil) async throws {
        guard !isInitialized else { return }
        try await manager.initialize(databaseURL: databaseURL)
        try await buildIndexMaps()
        isInitialized = true
    }

    private func ensureInitialized() async throws {
        if !isInitialized {
            try await initializeSQLite()
        }
    }

    private func buildIndexMaps() async throws {
        // アイテムのインデックスマップ
        let items = try await repository.allItems()
        for item in items {
            itemIdToIndex[item.id] = item.index
            itemIndexToId[item.index] = item.id
        }

        // 通常称号のインデックスマップ（rankをindexとして使用）
        let titles = try await repository.allTitles()
        for title in titles {
            if let rank = title.rank {
                let index = Int8(rank)
                titleIdToIndex[title.id] = index
                titleIndexToId[index] = title.id
            }
        }

        // 超レア称号のインデックスマップ（orderをindexとして使用）
        let superRareTitles = try await repository.allSuperRareTitles()
        for title in superRareTitles {
            let index = Int16(title.order)
            superRareTitleIdToIndex[title.id] = index
            superRareTitleIndexToId[index] = title.id
        }
    }

    // MARK: - Index Lookup

    func getItemIndex(for id: String) -> Int16? {
        itemIdToIndex[id]
    }

    func getItemId(for index: Int16) -> String? {
        itemIndexToId[index]
    }

    func getTitleIndex(for id: String) -> Int8? {
        titleIdToIndex[id]
    }

    func getTitleId(for index: Int8) -> String? {
        titleIndexToId[index]
    }

    func getSuperRareTitleIndex(for id: String) -> Int16? {
        superRareTitleIdToIndex[id]
    }

    func getSuperRareTitleId(for index: Int16) -> String? {
        superRareTitleIndexToId[index]
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

    /// Int Index からアイテム定義を取得
    func getItemMasterData(byIndex index: Int16) async throws -> ItemDefinition? {
        guard let id = getItemId(for: index) else { return nil }
        return try await getItemMasterData(id: id)
    }

    /// 複数のInt IndexからアイテムをItem定義を取得
    func getItemMasterData(byIndices indices: [Int16]) async throws -> [ItemDefinition] {
        let ids = indices.compactMap { getItemId(for: $0) }
        return try await getItemMasterData(ids: ids)
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
