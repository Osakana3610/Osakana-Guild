import Foundation

/// アイテムのソート順を計算するサービス
/// マスターデータのインデックスをキャッシュし、sortOrderを計算する
actor ItemSortOrderCalculator {
    private var itemIndexMap: [String: Int]?
    private var titleRankMap: [String: Int]?
    private var superRareTitleOrderMap: [String: Int]?
    private let masterDataService: MasterDataRuntimeService

    init(masterDataService: MasterDataRuntimeService = .shared) {
        self.masterDataService = masterDataService
    }

    /// キャッシュを初期化する
    func ensureInitialized() async throws {
        if itemIndexMap == nil {
            let items = try await masterDataService.getAllItems()
            itemIndexMap = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
        }
        if titleRankMap == nil {
            let titles = try await masterDataService.getAllTitles()
            titleRankMap = Dictionary(uniqueKeysWithValues: titles.compactMap { title -> (String, Int)? in
                guard let rank = title.rank else { return nil }
                return (title.id, rank)
            })
        }
        if superRareTitleOrderMap == nil {
            let superRareTitles = try await masterDataService.getAllSuperRareTitles()
            superRareTitleOrderMap = Dictionary(uniqueKeysWithValues: superRareTitles.map { ($0.id, $0.order) })
        }
    }

    /// アイテムのソート順を計算する
    /// - Parameters:
    ///   - itemId: アイテムID
    ///   - superRareTitleId: 超レア称号ID（nil可）
    ///   - normalTitleId: 通常称号ID（nil可）
    ///   - socketKey: 宝石ID（nil可）
    /// - Returns: ソート順（整数）
    func calculateSortOrder(
        itemId: String,
        superRareTitleId: String?,
        normalTitleId: String?,
        socketKey: String?
    ) async throws -> Int {
        try await ensureInitialized()

        guard let itemIndexMap, let titleRankMap, let superRareTitleOrderMap else {
            throw ProgressError.invalidInput(description: "ソート順計算のキャッシュが初期化されていません")
        }

        // アイテムインデックス（0〜999）
        guard let itemIndex = itemIndexMap[itemId] else {
            throw ProgressError.invalidInput(description: "未知のアイテムID: \(itemId)")
        }

        // 超レア称号order（1〜100、なしの場合は0で先頭に）
        let superRareOrder: Int
        if let superRareTitleId {
            guard let order = superRareTitleOrderMap[superRareTitleId] else {
                throw ProgressError.invalidInput(description: "未知の超レア称号ID: \(superRareTitleId)")
            }
            superRareOrder = order
        } else {
            superRareOrder = 0
        }

        // 通常称号rank（0〜8、なしの場合はnormalのrank=2を使用）
        let normalRank: Int
        if let normalTitleId {
            guard let rank = titleRankMap[normalTitleId] else {
                throw ProgressError.invalidInput(description: "未知の通常称号ID: \(normalTitleId)")
            }
            normalRank = rank
        } else {
            // "normal" のrank（称号なし）を使用
            guard let defaultRank = titleRankMap["normal"] else {
                throw ProgressError.invalidInput(description: "デフォルト称号 'normal' が見つかりません")
            }
            normalRank = defaultRank
        }

        // 宝石インデックス（0〜999、なしの場合は0で先頭に）
        let gemIndex: Int
        if let socketKey {
            guard let socketIndex = itemIndexMap[socketKey] else {
                throw ProgressError.invalidInput(description: "未知の宝石ID: \(socketKey)")
            }
            gemIndex = socketIndex + 1
        } else {
            gemIndex = 0
        }

        // sortOrder = itemIndex * 1億 + superRareOrder * 100万 + normalRank * 1万 + gemIndex
        return itemIndex * 100_000_000
             + superRareOrder * 1_000_000
             + normalRank * 10_000
             + gemIndex
    }

    /// 複数アイテムのソート順を一括計算する
    func calculateSortOrders(
        for items: [(itemId: String, superRareTitleId: String?, normalTitleId: String?, socketKey: String?)]
    ) async throws -> [Int] {
        try await ensureInitialized()
        var results: [Int] = []
        results.reserveCapacity(items.count)
        for item in items {
            let sortOrder = try await calculateSortOrder(
                itemId: item.itemId,
                superRareTitleId: item.superRareTitleId,
                normalTitleId: item.normalTitleId,
                socketKey: item.socketKey
            )
            results.append(sortOrder)
        }
        return results
    }

    /// キャッシュをクリアする
    func clearCache() {
        itemIndexMap = nil
        titleRankMap = nil
        superRareTitleOrderMap = nil
    }
}
