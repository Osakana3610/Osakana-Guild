import Foundation

/// アイテム売却価格を計算する純関数。
/// 通常称号と超レア称号に応じた価格倍率を適用する。
enum ItemPriceCalculator {
    private static let maxPrice = 99_999_999
    private static let superRareBaseAddition = 500_000

    /// 超レア称号の倍率（通常称号id 0〜5に対応、id>=6は即座にカンスト）
    private static let superRareMultipliers: [Double] = [1.0, 4.0, 8.0, 16.0, 32.0, 64.0]

    /// 売却価格を計算する。
    /// - Parameters:
    ///   - baseSellValue: アイテムの基本売却価格
    ///   - normalTitleId: 通常称号のID（0〜8）
    ///   - hasSuperRare: 超レア称号が付与されているか
    ///   - multiplierMap: 通常称号IDごとの価格倍率マップ
    /// - Returns: 計算された売却価格（maxPriceでクリップ）
    /// - Throws: タイトルIDに対応する倍率が見つからない場合
    static func sellPrice(
        baseSellValue: Int,
        normalTitleId: UInt8,
        hasSuperRare: Bool,
        multiplierMap: [UInt8: Double]
    ) throws -> Int {
        // 超レア称号付きでid>=6の場合は即座にカンスト
        if hasSuperRare && normalTitleId >= 6 {
            return maxPrice
        }

        guard let priceMultiplier = multiplierMap[normalTitleId] else {
            throw ItemPriceCalculationError.multiplierNotFound(titleId: normalTitleId)
        }

        let result: Double
        if hasSuperRare {
            let superRareMultiplier = superRareMultipliers[Int(normalTitleId)]
            result = Double(baseSellValue + superRareBaseAddition) * superRareMultiplier
        } else {
            result = Double(baseSellValue) * priceMultiplier
        }

        return Int(min(result, Double(maxPrice)))
    }
}

enum ItemPriceCalculationError: Error, LocalizedError {
    case multiplierNotFound(titleId: UInt8)

    var errorDescription: String? {
        switch self {
        case .multiplierNotFound(let titleId):
            return "価格倍率が見つかりません: titleId=\(titleId)"
        }
    }
}
