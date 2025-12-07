import Foundation

/// マスターデータへの読み取り専用ファサード。
/// SQLite 読み出しはコストが高いため、必要なデータはキャッシュして扱う。
actor MasterDataRepository {
    private let manager: SQLiteMasterDataManager
    private var itemsCache: [ItemDefinition]?
    private var itemsById: [UInt16: ItemDefinition]?
    private var skillsCache: [SkillDefinition]?
    private var skillsById: [UInt16: SkillDefinition]?
    private var spellsCache: [SpellDefinition]?
    private var spellsById: [UInt8: SpellDefinition]?
    private var enemiesCache: [EnemyDefinition]?
    private var enemiesById: [UInt16: EnemyDefinition]?
    private var statusEffectsCache: [StatusEffectDefinition]?
    private var statusEffectsById: [UInt8: StatusEffectDefinition]?
    private var jobsCache: [JobDefinition]?
    private var jobsById: [UInt8: JobDefinition]?
    private var racesCache: [RaceDefinition]?
    private var racesById: [UInt8: RaceDefinition]?
    private var titlesCache: [TitleDefinition]?
    private var titlesById: [UInt8: TitleDefinition]?
    private var superRareTitlesCache: [SuperRareTitleDefinition]?
    private var superRareTitlesById: [UInt8: SuperRareTitleDefinition]?
    private var personalityPrimaryCache: [PersonalityPrimaryDefinition]?
    private var personalityPrimaryById: [UInt8: PersonalityPrimaryDefinition]?
    private var personalitySecondaryCache: [PersonalitySecondaryDefinition]?
    private var personalitySecondaryById: [UInt8: PersonalitySecondaryDefinition]?
    private var dungeonsCache: ([DungeonDefinition], [EncounterTableDefinition], [DungeonFloorDefinition])?
    private var dungeonsById: [UInt16: DungeonDefinition]?
    private var explorationEventsCache: [ExplorationEventDefinition]?
    private var explorationEventsById: [UInt8: ExplorationEventDefinition]?
    private var storiesCache: [StoryNodeDefinition]?
    private var synthesisCache: [SynthesisRecipeDefinition]?
    private var shopsCache: [ShopDefinition]?
    private var shopsById: [String: ShopDefinition]?

    init(manager: SQLiteMasterDataManager = .shared) {
        self.manager = manager
    }

    private func ensureInitialized() async throws {
        try await manager.initialize()
    }

    func allItems() async throws -> [ItemDefinition] {
        if let itemsCache { return itemsCache }
        try await ensureInitialized()
        let items = try await manager.fetchAllItems()
        self.itemsCache = items
        self.itemsById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return items
    }

    func item(withId id: UInt16) async throws -> ItemDefinition? {
        if let itemsById, let definition = itemsById[id] { return definition }
        _ = try await allItems()
        return itemsById?[id]
    }

    func items(withIds ids: [UInt16]) async throws -> [ItemDefinition] {
        guard !ids.isEmpty else { return [] }
        _ = try await allItems()
        guard let itemsById else {
            throw RuntimeError.invalidConfiguration(reason: "Item cache is unavailable")
        }
        var definitions: [ItemDefinition] = []
        definitions.reserveCapacity(ids.count)
        for id in ids {
            guard let definition = itemsById[id] else {
                throw RuntimeError.masterDataNotFound(entity: "item", identifier: "\(id)")
            }
            definitions.append(definition)
        }
        return definitions
    }

    func allSkills() async throws -> [SkillDefinition] {
        if let skillsCache { return skillsCache }
        try await ensureInitialized()
        let skills = try await manager.fetchAllSkills()
        self.skillsCache = skills
        self.skillsById = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0) })
        return skills
    }

    func skills(withIds ids: [UInt16]) async throws -> [SkillDefinition] {
        guard !ids.isEmpty else { return [] }
        _ = try await allSkills()
        guard let skillsById else {
            throw RuntimeError.invalidConfiguration(reason: "Skill cache is unavailable")
        }
        var definitions: [SkillDefinition] = []
        definitions.reserveCapacity(ids.count)
        for id in ids {
            guard let definition = skillsById[id] else {
                throw RuntimeError.masterDataNotFound(entity: "skill", identifier: "\(id)")
            }
            definitions.append(definition)
        }
        return definitions
    }

    func skills(withIndices indices: [UInt16]) async throws -> [SkillDefinition] {
        guard !indices.isEmpty else { return [] }
        _ = try await allSkills()
        guard let skillsById else {
            throw RuntimeError.invalidConfiguration(reason: "Skill cache is unavailable")
        }
        var definitions: [SkillDefinition] = []
        definitions.reserveCapacity(indices.count)
        for index in indices {
            guard let definition = skillsById[index] else {
                throw RuntimeError.masterDataNotFound(entity: "skill", identifier: "\(index)")
            }
            definitions.append(definition)
        }
        return definitions
    }

    func allSpells() async throws -> [SpellDefinition] {
        if let spellsCache { return spellsCache }
        try await ensureInitialized()
        let spells = try await manager.fetchAllSpells()
        self.spellsCache = spells
        self.spellsById = Dictionary(uniqueKeysWithValues: spells.map { ($0.id, $0) })
        return spells
    }

    func spell(withId id: UInt8) async throws -> SpellDefinition? {
        if let spellsById, let definition = spellsById[id] { return definition }
        _ = try await allSpells()
        return spellsById?[id]
    }

    func spells(withIds ids: [UInt8]) async throws -> [SpellDefinition] {
        guard !ids.isEmpty else { return [] }
        _ = try await allSpells()
        guard let spellsById else {
            throw RuntimeError.invalidConfiguration(reason: "Spell cache is unavailable")
        }
        var definitions: [SpellDefinition] = []
        definitions.reserveCapacity(ids.count)
        for id in ids {
            guard let definition = spellsById[id] else {
                throw RuntimeError.masterDataNotFound(entity: "spell", identifier: "\(id)")
            }
            definitions.append(definition)
        }
        return definitions
    }

    func allEnemies() async throws -> [EnemyDefinition] {
        if let enemiesCache { return enemiesCache }
        try await ensureInitialized()
        let enemies = try await manager.fetchAllEnemies()
        self.enemiesCache = enemies
        self.enemiesById = Dictionary(uniqueKeysWithValues: enemies.map { ($0.id, $0) })
        return enemies
    }

    func enemy(withId id: UInt16) async throws -> EnemyDefinition? {
        if let enemiesById, let definition = enemiesById[id] { return definition }
        _ = try await allEnemies()
        return enemiesById?[id]
    }

    func allStatusEffects() async throws -> [StatusEffectDefinition] {
        if let statusEffectsCache { return statusEffectsCache }
        try await ensureInitialized()
        let effects = try await manager.fetchAllStatusEffects()
        self.statusEffectsCache = effects
        self.statusEffectsById = Dictionary(uniqueKeysWithValues: effects.map { ($0.id, $0) })
        return effects
    }

    func statusEffect(withId id: UInt8) async throws -> StatusEffectDefinition? {
        if let statusEffectsById, let definition = statusEffectsById[id] { return definition }
        _ = try await allStatusEffects()
        return statusEffectsById?[id]
    }

    func allJobs() async throws -> [JobDefinition] {
        if let jobsCache { return jobsCache }
        try await ensureInitialized()
        let jobs = try await manager.fetchAllJobs()
        self.jobsCache = jobs
        self.jobsById = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) })
        return jobs
    }

    func job(withId id: UInt8) async throws -> JobDefinition? {
        if let jobsById, let definition = jobsById[id] { return definition }
        _ = try await allJobs()
        return jobsById?[id]
    }

    func allRaces() async throws -> [RaceDefinition] {
        if let racesCache { return racesCache }
        try await ensureInitialized()
        let races = try await manager.fetchAllRaces()
        self.racesCache = races
        self.racesById = Dictionary(uniqueKeysWithValues: races.map { ($0.id, $0) })
        return races
    }

    func race(withId id: UInt8) async throws -> RaceDefinition? {
        if let racesById, let definition = racesById[id] { return definition }
        _ = try await allRaces()
        return racesById?[id]
    }

    func allShops() async throws -> [ShopDefinition] {
        if let shopsCache { return shopsCache }
        try await ensureInitialized()
        let shops = try await manager.fetchAllShops()
        self.shopsCache = shops
        self.shopsById = Dictionary(uniqueKeysWithValues: shops.map { ($0.id, $0) })
        return shops
    }

    func shop(withId id: String) async throws -> ShopDefinition? {
        if let shopsById, let definition = shopsById[id] { return definition }
        _ = try await allShops()
        return shopsById?[id]
    }

    func allTitles() async throws -> [TitleDefinition] {
        if let titlesCache { return titlesCache }
        try await ensureInitialized()
        let titles = try await manager.fetchAllTitles()
        self.titlesCache = titles
        self.titlesById = Dictionary(uniqueKeysWithValues: titles.map { ($0.id, $0) })
        return titles
    }

    func title(withId id: UInt8) async throws -> TitleDefinition? {
        if let titlesById, let definition = titlesById[id] { return definition }
        _ = try await allTitles()
        return titlesById?[id]
    }

    func allSuperRareTitles() async throws -> [SuperRareTitleDefinition] {
        if let superRareTitlesCache { return superRareTitlesCache }
        try await ensureInitialized()
        let titles = try await manager.fetchAllSuperRareTitles()
        self.superRareTitlesCache = titles
        self.superRareTitlesById = Dictionary(uniqueKeysWithValues: titles.map { ($0.id, $0) })
        return titles
    }

    func superRareTitle(withId id: UInt8) async throws -> SuperRareTitleDefinition? {
        if let superRareTitlesById, let definition = superRareTitlesById[id] { return definition }
        _ = try await allSuperRareTitles()
        return superRareTitlesById?[id]
    }

    func allPersonalityPrimary() async throws -> [PersonalityPrimaryDefinition] {
        if let personalityPrimaryCache { return personalityPrimaryCache }
        try await ensureInitialized()
        let bundle = try await manager.fetchPersonalityData()
        self.personalityPrimaryCache = bundle.primary
        self.personalityPrimaryById = Dictionary(uniqueKeysWithValues: bundle.primary.map { ($0.id, $0) })
        self.personalitySecondaryCache = bundle.secondary
        self.personalitySecondaryById = Dictionary(uniqueKeysWithValues: bundle.secondary.map { ($0.id, $0) })
        return bundle.primary
    }

    func personalityPrimary(withId id: UInt8) async throws -> PersonalityPrimaryDefinition? {
        if let personalityPrimaryById, let definition = personalityPrimaryById[id] { return definition }
        _ = try await allPersonalityPrimary()
        return personalityPrimaryById?[id]
    }

    func allPersonalitySecondary() async throws -> [PersonalitySecondaryDefinition] {
        if let personalitySecondaryCache { return personalitySecondaryCache }
        _ = try await allPersonalityPrimary()
        return personalitySecondaryCache ?? []
    }

    func personalitySecondary(withId id: UInt8) async throws -> PersonalitySecondaryDefinition? {
        if let personalitySecondaryById, let definition = personalitySecondaryById[id] { return definition }
        _ = try await allPersonalitySecondary()
        return personalitySecondaryById?[id]
    }

    func allDungeons() async throws -> ([DungeonDefinition], [EncounterTableDefinition], [DungeonFloorDefinition]) {
        if let dungeonsCache {
            if dungeonsById == nil {
                let (dungeons, _, _) = dungeonsCache
                dungeonsById = Dictionary(uniqueKeysWithValues: dungeons.map { ($0.id, $0) })
            }
            return dungeonsCache
        }
        try await ensureInitialized()
        let data = try await manager.fetchAllDungeons()
        self.dungeonsCache = data
        let (dungeons, _, _) = data
        self.dungeonsById = Dictionary(uniqueKeysWithValues: dungeons.map { ($0.id, $0) })
        return data
    }

    func dungeon(withId id: UInt16) async throws -> DungeonDefinition? {
        if let dungeonsById, let definition = dungeonsById[id] { return definition }
        let data = try await allDungeons()
        if let dungeonsById, let definition = dungeonsById[id] { return definition }
        return data.0.first { $0.id == id }
    }

    func allExplorationEvents() async throws -> [ExplorationEventDefinition] {
        if let explorationEventsCache { return explorationEventsCache }
        try await ensureInitialized()
        let events = try await manager.fetchAllExplorationEvents()
        self.explorationEventsCache = events
        self.explorationEventsById = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        return events
    }

    func explorationEvent(withId id: UInt8) async throws -> ExplorationEventDefinition? {
        if let explorationEventsById, let definition = explorationEventsById[id] { return definition }
        _ = try await allExplorationEvents()
        return explorationEventsById?[id]
    }

    func allStories() async throws -> [StoryNodeDefinition] {
        if let storiesCache { return storiesCache }
        try await ensureInitialized()
        let stories = try await manager.fetchAllStories()
        self.storiesCache = stories
        return stories
    }

    func allSynthesisRecipes() async throws -> [SynthesisRecipeDefinition] {
        if let synthesisCache { return synthesisCache }
        try await ensureInitialized()
        let recipes = try await manager.fetchAllSynthesisRecipes()
        self.synthesisCache = recipes
        return recipes
    }


}
