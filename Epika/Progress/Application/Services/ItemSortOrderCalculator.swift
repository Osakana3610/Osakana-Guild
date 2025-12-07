import Foundation

/// アイテムのソート順を計算するサービス
/// マスターデータのインデックスをキャッシュし、sortOrderを計算する
actor ItemSortOrderCalculator {
    private var itemIndexMap: [UInt16: Int]?
    private var titleIdSet: Set<UInt8>?
    private var superRareTitleIdSet: Set<UInt8>?
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
        if titleIdSet == nil {
            let titles = try await masterDataService.getAllTitles()
            titleIdSet = Set(titles.map { $0.id })
        }
        if superRareTitleIdSet == nil {
            let superRareTitles = try await masterDataService.getAllSuperRareTitles()
            superRareTitleIdSet = Set(superRareTitles.map { $0.id })
        }
    }

    /// アイテムのソート順を計算する
    /// - Parameters:
    ///   - itemId: アイテムID
    ///   - superRareTitleId: 超レア称号ID（0 = なし）
    ///   - normalTitleId: 通常称号ID（0〜8、デフォルト2 = 無称号）
    ///   - socketItemId: 宝石アイテムID（0 = なし）
    /// - Returns: ソート順（整数）
    func calculateSortOrder(
        itemId: UInt16,
        superRareTitleId: UInt8,
        normalTitleId: UInt8,
        socketItemId: UInt16
    ) async throws -> Int {
        try await ensureInitialized()

        guard let itemIndexMap else {
            throw ProgressError.invalidInput(description: "ソート順計算のキャッシュが初期化されていません")
        }

        // アイテムインデックス（0〜999）
        guard let itemIndex = itemIndexMap[itemId] else {
            throw ProgressError.invalidInput(description: "未知のアイテムID: \(itemId)")
        }

        // 超レア称号ID（0〜100、0の場合は先頭に）
        let superRareOrder = Int(superRareTitleId)

        // 通常称号ID（0〜8）をそのままrankとして使用
        let normalRank = Int(normalTitleId)

        // 宝石インデックス（0〜999、なしの場合は0で先頭に）
        let gemIndex: Int
        if socketItemId > 0 {
            if let socketIndex = itemIndexMap[socketItemId] {
                gemIndex = socketIndex + 1
            } else {
                gemIndex = Int(socketItemId) + 1
            }
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
        for items: [(itemId: UInt16, superRareTitleId: UInt8, normalTitleId: UInt8, socketItemId: UInt16)]
    ) async throws -> [Int] {
        try await ensureInitialized()
        var results: [Int] = []
        results.reserveCapacity(items.count)
        for item in items {
            let sortOrder = try await calculateSortOrder(
                itemId: item.itemId,
                superRareTitleId: item.superRareTitleId,
                normalTitleId: item.normalTitleId,
                socketItemId: item.socketItemId
            )
            results.append(sortOrder)
        }
        return results
    }

    /// キャッシュをクリアする
    func clearCache() {
        itemIndexMap = nil
        titleIdSet = nil
        superRareTitleIdSet = nil
    }
}
