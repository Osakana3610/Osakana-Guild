import Foundation

/// ドロップ率計算を担当するユーティリティ。旧 `ItemDropRateService` を非決定論向けに再構築。
struct ItemDropRateCalculator {
    static func roll(category: DropItemCategory,
                     rareMultiplier: Double,
                     isRabiTicketActive: Bool,
                     partyLuck: Double,
                     random: inout GameRandomSource) -> DropRollResult {
        let baseThreshold = Self.baseThreshold(for: category,
                                               rareMultiplier: rareMultiplier,
                                               isRabiTicketActive: isRabiTicketActive)
        let luckRoll = random.nextLuckRandom(lowerBound: partyLuck)
        // 現状はスキルによる加算・乗算補正が未導入のため、閾値はそのまま比較する。
        let finalThreshold = baseThreshold
        let willDrop = finalThreshold < luckRoll
        return DropRollResult(willDrop: willDrop,
                              luckRoll: luckRoll,
                              baseThreshold: baseThreshold,
                              finalThreshold: finalThreshold)
    }

    private static func baseThreshold(for category: DropItemCategory,
                                      rareMultiplier: Double,
                                      isRabiTicketActive: Bool) -> Double {
        switch category {
        case .normal:
            return clamp(100.0 - (rareMultiplier * 10.0))
        case .good, .rare:
            let adjusted = rareMultiplier * (isRabiTicketActive ? 2.0 : 1.0)
            return clamp(100.0 - (adjusted * 0.1))
        case .gem:
            let adjusted = rareMultiplier * (isRabiTicketActive ? 2.0 : 1.0)
            let y = min(adjusted * 0.1, 1.0)
            return clamp(100.0 - y)
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(100.0, max(0.0, value))
    }
}
