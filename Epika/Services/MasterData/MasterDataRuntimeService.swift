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

    /// 通常称号: String ID → UInt8 Index (rank: 0〜8)
    private var titleIdToIndex: [String: UInt8] = [:]
    private var titleIndexToId: [UInt8: String] = [:]

    /// 超レア称号: String ID → Int16 Index (order: 1〜100)
    private var superRareTitleIdToIndex: [String: Int16] = [:]
    private var superRareTitleIndexToId: [Int16: String] = [:]

    /// 種族: String ID → UInt8 Index (1〜18)
    private var raceIdToIndex: [String: UInt8] = [:]
    private var raceIndexToId: [UInt8: String] = [:]

    /// 職業: String ID → UInt8 Index (1〜16)
    private var jobIdToIndex: [String: UInt8] = [:]
    private var jobIndexToId: [UInt8: String] = [:]

    /// 主性格: String ID → UInt8 Index (1〜18, 0=なし)
    private var primaryPersonalityIdToIndex: [String: UInt8] = [:]
    private var primaryPersonalityIndexToId: [UInt8: String] = [:]

    /// 副性格: String ID → UInt8 Index (1〜15, 0=なし)
    private var secondaryPersonalityIdToIndex: [String: UInt8] = [:]
    private var secondaryPersonalityIndexToId: [UInt8: String] = [:]

    /// ダンジョン: String ID → UInt16 Index (1〜, 0=未選択)
    private var dungeonIdToIndex: [String: UInt16] = [:]
    private var dungeonIndexToId: [UInt16: String] = [:]

    /// 敵: String ID → UInt16 Index
    private var enemyIdToIndex: [String: UInt16] = [:]
    private var enemyIndexToId: [UInt16: String] = [:]

    /// 探索イベント: String ID → UInt16 Index
    private var explorationEventIdToIndex: [String: UInt16] = [:]
    private var explorationEventIndexToId: [UInt16: String] = [:]

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

        // 通常称号のインデックスマップ（rankをそのままindexとして使用: 0=最低な, 2=無称号, 8=壊れた）
        let titles = try await repository.allTitles()
        for title in titles {
            if let rank = title.rank {
                let index = UInt8(rank)
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

        // 種族のインデックスマップ
        let races = try await repository.allRaces()
        for race in races {
            let index = UInt8(race.index)
            raceIdToIndex[race.id] = index
            raceIndexToId[index] = race.id
        }

        // 職業のインデックスマップ
        let jobs = try await repository.allJobs()
        for job in jobs {
            let index = UInt8(job.index)
            jobIdToIndex[job.id] = index
            jobIndexToId[index] = job.id
        }

        // 性格のインデックスマップ
        let primaryPersonalities = try await repository.allPersonalityPrimary()
        for personality in primaryPersonalities {
            let index = UInt8(personality.index)
            primaryPersonalityIdToIndex[personality.id] = index
            primaryPersonalityIndexToId[index] = personality.id
        }
        let secondaryPersonalities = try await repository.allPersonalitySecondary()
        for personality in secondaryPersonalities {
            let index = UInt8(personality.index)
            secondaryPersonalityIdToIndex[personality.id] = index
            secondaryPersonalityIndexToId[index] = personality.id
        }

        // ダンジョンのインデックスマップ
        let dungeons = try await repository.allDungeons()
        for dungeon in dungeons.0 {
            dungeonIdToIndex[dungeon.id] = dungeon.index
            dungeonIndexToId[dungeon.index] = dungeon.id
        }

        // 敵のインデックスマップ
        let enemies = try await repository.allEnemies()
        for enemy in enemies {
            enemyIdToIndex[enemy.id] = enemy.index
            enemyIndexToId[enemy.index] = enemy.id
        }

        // 探索イベントのインデックスマップ
        let explorationEvents = try await repository.allExplorationEvents()
        for event in explorationEvents {
            explorationEventIdToIndex[event.id] = event.index
            explorationEventIndexToId[event.index] = event.id
        }
    }

    // MARK: - Index Lookup

    func getItemIndex(for id: String) -> Int16? {
        itemIdToIndex[id]
    }

    func getItemId(for index: Int16) -> String? {
        itemIndexToId[index]
    }

    func getTitleIndex(for id: String) -> UInt8? {
        titleIdToIndex[id]
    }

    func getTitleId(for index: UInt8) -> String? {
        titleIndexToId[index]
    }

    func getSuperRareTitleIndex(for id: String) -> Int16? {
        superRareTitleIdToIndex[id]
    }

    func getSuperRareTitleId(for index: Int16) -> String? {
        superRareTitleIndexToId[index]
    }

    func getRaceIndex(for id: String) -> UInt8? {
        raceIdToIndex[id]
    }

    func getRaceId(for index: UInt8) -> String? {
        raceIndexToId[index]
    }

    func getJobIndex(for id: String) -> UInt8? {
        jobIdToIndex[id]
    }

    func getJobId(for index: UInt8) -> String? {
        jobIndexToId[index]
    }

    func getPrimaryPersonalityIndex(for id: String) -> UInt8? {
        primaryPersonalityIdToIndex[id]
    }

    func getPrimaryPersonalityId(for index: UInt8) -> String? {
        primaryPersonalityIndexToId[index]
    }

    func getSecondaryPersonalityIndex(for id: String) -> UInt8? {
        secondaryPersonalityIdToIndex[id]
    }

    func getSecondaryPersonalityId(for index: UInt8) -> String? {
        secondaryPersonalityIndexToId[index]
    }

    func getDungeonIndex(for id: String) -> UInt16? {
        dungeonIdToIndex[id]
    }

    func getDungeonId(for index: UInt16) -> String? {
        dungeonIndexToId[index]
    }

    func getEnemyIndex(for id: String) -> UInt16? {
        enemyIdToIndex[id]
    }

    func getEnemyId(for index: UInt16) -> String? {
        enemyIndexToId[index]
    }

    func getExplorationEventIndex(for id: String) -> UInt16? {
        explorationEventIdToIndex[id]
    }

    func getExplorationEventId(for index: UInt16) -> String? {
        explorationEventIndexToId[index]
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

    func getEnemyDefinition(byIndex index: UInt16) async throws -> EnemyDefinition? {
        guard let id = getEnemyId(for: index) else { return nil }
        return try await getEnemyDefinition(id: id)
    }

    func getAllEnemies() async throws -> [EnemyDefinition] {
        try await ensureInitialized()
        return try await repository.allEnemies()
    }

    // MARK: - Exploration Events

    func getExplorationEventDefinition(id: String) async throws -> ExplorationEventDefinition? {
        try await ensureInitialized()
        return try await repository.explorationEvent(withId: id)
    }

    func getExplorationEventDefinition(byIndex index: UInt16) async throws -> ExplorationEventDefinition? {
        guard let id = getExplorationEventId(for: index) else { return nil }
        return try await getExplorationEventDefinition(id: id)
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
