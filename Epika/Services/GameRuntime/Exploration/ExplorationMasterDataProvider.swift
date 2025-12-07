import Foundation

struct ExplorationDungeonBundle: Sendable {
    let dungeon: DungeonDefinition
    let floors: [DungeonFloorDefinition]
    let encounterTablesById: [String: EncounterTableDefinition]
}

protocol ExplorationMasterDataProvider: Sendable {
    func dungeonBundle(for dungeonId: UInt8) async throws -> ExplorationDungeonBundle
    func explorationEvents() async throws -> [ExplorationEventDefinition]
}

struct MasterDataRepositoryExplorationProvider: ExplorationMasterDataProvider {
    private let repository: MasterDataRepository

    init(repository: MasterDataRepository) {
        self.repository = repository
    }

    func dungeonBundle(for dungeonId: UInt8) async throws -> ExplorationDungeonBundle {
        let (dungeons, encounterTables, floors) = try await repository.allDungeons()
        guard let dungeon = dungeons.first(where: { $0.id == dungeonId }) else {
            throw RuntimeError.masterDataNotFound(entity: "dungeon", identifier: String(dungeonId))
        }

        let relevantFloors = floors
            .filter { $0.dungeonId == dungeonId }
            .sorted { $0.floorNumber < $1.floorNumber }

        guard !relevantFloors.isEmpty else {
            throw RuntimeError.invalidConfiguration(reason: "Dungeon \(dungeonId) does not define any floors")
        }

        let tablesById = Dictionary(uniqueKeysWithValues: encounterTables.map { ($0.id, $0) })
        return ExplorationDungeonBundle(dungeon: dungeon,
                                        floors: relevantFloors,
                                        encounterTablesById: tablesById)
    }

    func explorationEvents() async throws -> [ExplorationEventDefinition] {
        try await repository.allExplorationEvents()
    }
}
