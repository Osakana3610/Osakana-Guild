import Foundation

struct BattleEnemyGroupConfigService {
    struct GroupEnemy {
        let definition: EnemyDefinition
        let count: Int
    }

    static func makeEncounter(using configuration: DungeonDefinition.EnemyGroupConfig?,
                              floorNumber: Int,
                              enemyPool: [UInt16: EnemyDefinition],
                              random: inout GameRandomSource) -> [GroupEnemy] {
        guard let configuration else { return [] }

        var groups: [GroupEnemy] = []
        let pool = collectPool(configuration: configuration, floorNumber: floorNumber)
        guard !pool.isEmpty else { return groups }

        let minEnemies = max(1, configuration.minEnemies)
        let maxEnemies = max(minEnemies, configuration.maxEnemies)
        let maxGroups = max(1, configuration.maxGroups)
        let defaultRange = configuration.defaultGroupSize

        var totalEnemies = 0
        while groups.count < maxGroups && totalEnemies < minEnemies {
            guard let enemyDefinition = randomEnemy(from: pool, enemyPool: enemyPool, random: &random) else { break }
            let groupSize = random.nextInt(in: defaultRange)
            groups.append(GroupEnemy(definition: enemyDefinition, count: groupSize))
            totalEnemies += groupSize
        }

        if totalEnemies < minEnemies {
            if let last = groups.last {
                let needed = minEnemies - totalEnemies
                let adjusted = GroupEnemy(definition: last.definition, count: last.count + needed)
                groups[groups.count - 1] = adjusted
            }
        }

        if totalEnemies > maxEnemies {
            var over = totalEnemies - maxEnemies
            for index in groups.indices.reversed() where over > 0 {
                var group = groups[index]
                let reduce = min(over, group.count - 1)
                group = GroupEnemy(definition: group.definition, count: group.count - reduce)
                groups[index] = group
                over -= reduce
            }
        }

        return groups
    }

    private static func collectPool(configuration: DungeonDefinition.EnemyGroupConfig,
                                     floorNumber: Int) -> [UInt16] {
        var pool = configuration.normalPool
        if let floorPool = configuration.floorPools[floorNumber] {
            let ratio = configuration.mixRatio
            if ratio >= 1.0 {
                pool = floorPool
            } else if ratio > 0 {
                let normalCount = max(0, Int(Double(floorPool.count) * (1.0 - ratio)))
                pool = Array(floorPool.prefix(floorPool.count - normalCount)) + Array(pool.prefix(normalCount))
            }
        }
        return pool
    }

    private static func randomEnemy(from pool: [UInt16],
                                    enemyPool: [UInt16: EnemyDefinition],
                                    random: inout GameRandomSource) -> EnemyDefinition? {
        guard !pool.isEmpty else { return nil }
        let pick = random.nextInt(in: 0...(pool.count - 1))
        let enemyId = pool[pick]
        return enemyPool[enemyId]
    }
}
