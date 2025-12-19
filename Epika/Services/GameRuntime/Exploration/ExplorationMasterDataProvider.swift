import Foundation

struct ExplorationDungeonBundle: Sendable {
    let dungeon: DungeonDefinition
    let floors: [DungeonFloorDefinition]
    let encounterTablesById: [UInt16: EncounterTableDefinition]
}

protocol ExplorationMasterDataProvider: Sendable {
    func dungeonBundle(for dungeonId: UInt16) async throws -> ExplorationDungeonBundle
    func explorationEvents() async throws -> [ExplorationEventDefinition]
}

struct MasterDataCacheExplorationProvider: ExplorationMasterDataProvider, Sendable {
    private let masterData: MasterDataCache

    nonisolated init(masterData: MasterDataCache) {
        self.masterData = masterData
    }

    func dungeonBundle(for dungeonId: UInt16) async throws -> ExplorationDungeonBundle {
        guard let dungeon = masterData.dungeon(dungeonId) else {
            throw RuntimeError.masterDataNotFound(entity: "dungeon", identifier: String(dungeonId))
        }

        let relevantFloors = masterData.allDungeonFloors
            .filter { $0.dungeonId == dungeonId }
            .sorted { $0.floorNumber < $1.floorNumber }

        guard !relevantFloors.isEmpty else {
            throw RuntimeError.invalidConfiguration(reason: "Dungeon \(dungeonId) does not define any floors")
        }

        let tablesById = Dictionary(uniqueKeysWithValues: masterData.allEncounterTables.map { ($0.id, $0) })
        return ExplorationDungeonBundle(dungeon: dungeon,
                                        floors: relevantFloors,
                                        encounterTablesById: tablesById)
    }

    func explorationEvents() async throws -> [ExplorationEventDefinition] {
        masterData.allExplorationEvents
    }
}
