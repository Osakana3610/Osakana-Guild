import Foundation

/// 敵種族・ダンジョン章に基づいてノーマルアイテム（rarity="ノーマル"）の候補を生成する。
enum NormalItemDropGenerator {
    /// 章ごとの売値上限（ランク上限に対応）
    /// 下限は常に0なので、高い章でも低ランクアイテムがドロップする
    static let sellValueThresholds: [Int: Int] = [
        1: 250,      // 章1-2: ランク0-1
        2: 250,
        3: 6_250,    // 章3-4: ランク0-3
        4: 6_250,
        5: 120_000,  // 章5-6: ランク0-5
        6: 120_000,
        7: 360_000,  // 章7-8: ランク0-6
        8: 360_000,
        9: 720_000   // 章9: ランク0-7
    ]

    /// 種族ごとのカテゴリ重み（ノーマルアイテムがある12カテゴリのみ）
    /// 魔道書（grimoire）にはノーマルアイテムがないため除外
    static let raceCategoryWeights: [UInt8: [(category: String, weight: Int)]] = [
        1: [  // 人型
            ("sword", 30),
            ("armor", 25),
            ("shield", 20),
            ("bow", 15),
            ("thin_sword", 10)
        ],
        2: [  // 魔物
            ("gauntlet", 30),
            ("thin_sword", 25),
            ("armor", 20),
            ("katana", 15),
            ("shield", 10)
        ],
        3: [  // 不死
            ("thin_sword", 35),
            ("robe", 30),
            ("wand", 20),
            ("rod", 15)
        ],
        4: [  // 竜族
            ("katana", 30),
            ("heavy_armor", 25),
            ("super_heavy_armor", 20),
            ("sword", 15),
            ("shield", 10)
        ],
        5: [  // 神魔
            ("wand", 35),
            ("rod", 30),
            ("robe", 20),
            ("thin_sword", 15)
        ]
    ]

    /// 敵からノーマルアイテム候補を生成する
    /// - Parameters:
    ///   - enemies: 倒した敵のリスト
    ///   - chapter: ダンジョンの章（1-9）
    ///   - masterData: マスターデータキャッシュ
    ///   - droppedItemIds: 既にドロップ済みのアイテムID
    ///   - random: 乱数生成器
    /// - Returns: ノーマルアイテム候補のリスト（アイテムIDと元の敵ID）
    static func candidates(
        for enemies: [EnemyDefinition],
        chapter: Int,
        masterData: MasterDataCache,
        droppedItemIds: Set<UInt16>,
        random: inout GameRandomSource
    ) throws -> [(itemId: UInt16, sourceEnemyId: UInt16)] {
        guard !enemies.isEmpty else { return [] }

        guard let sellValueLimit = sellValueThresholds[chapter] else {
            throw RuntimeError.invalidConfiguration(reason: "Invalid chapter \(chapter) for normal item drop (expected 1-9)")
        }

        // ノーマルアイテム一覧を取得
        let normalItems = masterData.allItems.filter { $0.rarity == "ノーマル" }

        // カテゴリ→アイテムのマップを構築（売値上限でフィルタ）
        var itemsByCategory: [String: [ItemDefinition]] = [:]
        for item in normalItems {
            guard item.sellValue <= sellValueLimit else { continue }
            itemsByCategory[item.category, default: []].append(item)
        }

        var results: [(itemId: UInt16, sourceEnemyId: UInt16)] = []

        for enemy in enemies {
            // 敵の種族に基づいてカテゴリを選択
            guard let categoryWeights = raceCategoryWeights[enemy.raceId],
                  !categoryWeights.isEmpty else {
                continue
            }

            let selectedCategory = try selectCategory(from: categoryWeights, raceId: enemy.raceId, random: &random)
            guard let candidates = itemsByCategory[selectedCategory],
                  !candidates.isEmpty else {
                continue
            }

            // ドロップ済みを除外した候補から選択
            let available = candidates.filter { !droppedItemIds.contains($0.id) }
            guard !available.isEmpty else {
                continue
            }

            // ランダムに1つ選択
            let index = available.count == 1 ? 0 : random.nextInt(in: 0...(available.count - 1))
            let selected = available[index]
            results.append((itemId: selected.id, sourceEnemyId: enemy.id))
        }

        return results
    }

    enum GeneratorError: Error {
        case zeroCategoryWeight(raceId: UInt8)
    }

    /// 重み付きでカテゴリを選択
    private static func selectCategory(
        from weights: [(category: String, weight: Int)],
        raceId: UInt8,
        random: inout GameRandomSource
    ) throws -> String {
        let totalWeight = weights.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else {
            throw GeneratorError.zeroCategoryWeight(raceId: raceId)
        }

        let pick = totalWeight == 1 ? 0 : random.nextInt(in: 0...(totalWeight - 1))
        var cursor = 0
        for (category, weight) in weights {
            cursor += weight
            if pick < cursor {
                return category
            }
        }
        // ここに到達することは論理的にないが、コンパイラ警告回避のため最後のカテゴリを返す
        guard let last = weights.last else {
            throw GeneratorError.zeroCategoryWeight(raceId: raceId)
        }
        return last.category
    }
}
