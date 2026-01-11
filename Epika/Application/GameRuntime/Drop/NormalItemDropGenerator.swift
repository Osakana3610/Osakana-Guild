// ==============================================================================
// NormalItemDropGenerator.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 敵種族とレベルに基づいてノーマルアイテムの候補を動的生成
//   - レベルごとの売値上限とドロップ済み制限の適用
//   - 種族別カテゴリ重み付けによるアイテム選択
//
// 【公開API】
//   - candidates(): 敵リストからノーマルアイテム候補を生成
//
// 【使用箇所】
//   - DropService（ノーマルアイテムのドロップ処理）
//
// ==============================================================================

import Foundation

/// 敵種族・レベルに基づいてノーマルアイテム（rarity=1）の候補を生成する。
enum NormalItemDropGenerator {
    /// 敵レベルから売値上限を計算
    nonisolated static func sellValueLimit(forLevel level: Int) -> Int {
        switch level {
        case ...20: return 250
        case 21...50: return 6_250
        case 51...100: return 120_000
        case 101...150: return 360_000
        default: return 720_000
        }
    }

    /// 種族ごとのカテゴリ重み（ノーマルアイテムがある12カテゴリのみ）
    /// 魔道書（grimoire）にはノーマルアイテムがないため除外
    nonisolated static let raceCategoryWeights: [UInt8: [(category: UInt8, weight: Int)]] = [
        1: [  // 人型
            (ItemSaleCategory.sword.rawValue, 30),
            (ItemSaleCategory.armor.rawValue, 25),
            (ItemSaleCategory.shield.rawValue, 20),
            (ItemSaleCategory.bow.rawValue, 15),
            (ItemSaleCategory.thinSword.rawValue, 10)
        ],
        2: [  // 魔物
            (ItemSaleCategory.gauntlet.rawValue, 30),
            (ItemSaleCategory.thinSword.rawValue, 25),
            (ItemSaleCategory.armor.rawValue, 20),
            (ItemSaleCategory.katana.rawValue, 15),
            (ItemSaleCategory.shield.rawValue, 10)
        ],
        3: [  // 不死
            (ItemSaleCategory.thinSword.rawValue, 35),
            (ItemSaleCategory.robe.rawValue, 30),
            (ItemSaleCategory.wand.rawValue, 20),
            (ItemSaleCategory.rod.rawValue, 15)
        ],
        4: [  // 竜族
            (ItemSaleCategory.katana.rawValue, 30),
            (ItemSaleCategory.heavyArmor.rawValue, 25),
            (ItemSaleCategory.superHeavyArmor.rawValue, 20),
            (ItemSaleCategory.sword.rawValue, 15),
            (ItemSaleCategory.shield.rawValue, 10)
        ],
        5: [  // 神魔
            (ItemSaleCategory.wand.rawValue, 35),
            (ItemSaleCategory.rod.rawValue, 30),
            (ItemSaleCategory.robe.rawValue, 20),
            (ItemSaleCategory.thinSword.rawValue, 15)
        ]
    ]

    /// 敵からノーマルアイテム候補を生成する
    /// - Parameters:
    ///   - enemies: 倒した敵のリスト（定義とレベル）
    ///   - masterData: マスターデータキャッシュ
    ///   - droppedItemIds: 既にドロップ済みのアイテムID
    ///   - random: 乱数生成器
    /// - Returns: ノーマルアイテム候補のリスト（アイテムIDと元の敵ID）
    nonisolated static func candidates(
        for enemies: [BattleEnemyGroupBuilder.EncounteredEnemy],
        masterData: MasterDataCache,
        droppedItemIds: Set<UInt16>,
        random: inout GameRandomSource
    ) throws -> [(itemId: UInt16, sourceEnemyId: UInt16)] {
        guard !enemies.isEmpty else { return [] }

        // ノーマルアイテム一覧を取得
        let normalItems = masterData.allItems.filter { $0.rarity == ItemRarity.normal.rawValue }

        var results: [(itemId: UInt16, sourceEnemyId: UInt16)] = []

        for enemy in enemies {
            let limit = sellValueLimit(forLevel: enemy.level)

            // この敵のレベルに応じた売値上限でフィルタしたアイテムをカテゴリ別に構築
            var itemsByCategory: [UInt8: [ItemDefinition]] = [:]
            for item in normalItems {
                guard item.sellValue <= limit else { continue }
                itemsByCategory[item.category, default: []].append(item)
            }

            // 敵の種族に基づいてカテゴリを選択
            guard let categoryWeights = raceCategoryWeights[enemy.definition.raceId],
                  !categoryWeights.isEmpty else {
                continue
            }

            let selectedCategory = try selectCategory(from: categoryWeights, raceId: enemy.definition.raceId, random: &random)
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
            results.append((itemId: selected.id, sourceEnemyId: enemy.definition.id))
        }

        return results
    }

    enum GeneratorError: Error {
        case zeroCategoryWeight(raceId: UInt8)
    }

    /// 重み付きでカテゴリを選択
    private nonisolated static func selectCategory(
        from weights: [(category: UInt8, weight: Int)],
        raceId: UInt8,
        random: inout GameRandomSource
    ) throws -> UInt8 {
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
