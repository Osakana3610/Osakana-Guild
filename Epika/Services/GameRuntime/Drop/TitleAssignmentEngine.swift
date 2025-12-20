// ==============================================================================
// TitleAssignmentEngine.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アイテムドロップ時の称号付与判定
//   - 通常称号の抽選とランク選択
//   - 超レア称号の選択と低ランク称号の削除判定
//
// 【公開API】
//   - shouldAssignTitle(): 称号付与の可否を判定
//   - determineNormalTitle(): 通常称号を抽選して決定
//   - selectSuperRareTitle(): 超レア称号をランダム選択
//   - shouldRemoveNormalTitleAfterSuperRare(): 超レア時の通常称号削除判定
//
// 【使用箇所】
//   - DropService（称号付与ロジック）
//
// ==============================================================================

import Foundation

/// 通常称号抽選と超レア称号処理をまとめたエンジン。
struct TitleAssignmentEngine {
    static func shouldAssignTitle(category: DropItemCategory,
                                  partyBonuses: PartyDropBonuses,
                                  isRabiTicketActive: Bool,
                                  random: inout GameRandomSource) -> Bool {
        let titleRate = partyBonuses.titleGrantRateMultiplier * (isRabiTicketActive ? 2.0 : 1.0)
        let threshold: Double
        if category == .normal {
            threshold = max(0.0, 100.0 - (titleRate * 30.0))
        } else {
            threshold = max(0.0, 100.0 - titleRate)
        }
        let luckRandom = random.nextLuckRandom(lowerBound: partyBonuses.averageLuck)
        return threshold < luckRandom
    }

    static func determineNormalTitle(masterData: MasterDataCache,
                                     enemyTitleId: UInt8?,
                                     hasTitleTreasure: Bool,
                                     category: DropItemCategory,
                                     random: inout GameRandomSource) -> TitleDefinition? {
        let candidates = normalTitleCandidates(masterData: masterData,
                                               hasTitleTreasure: hasTitleTreasure)
        guard !candidates.isEmpty else { return nil }

        let judgmentCount = judgmentCountForEnemyTitle(masterData: masterData, titleId: enemyTitleId)
        var bestTitle: TitleDefinition?
        for _ in 0..<max(1, judgmentCount) {
            if let rolled = rollNormalTitle(from: candidates, random: &random) {
                if let current = bestTitle {
                    if titleRank(of: rolled) > titleRank(of: current) {
                        bestTitle = rolled
                    }
                } else {
                    bestTitle = rolled
                }
            }
        }
        guard let title = bestTitle else { return nil }
        if shouldRemoveLowTitle(title: title, category: category) {
            return nil
        }
        return title
    }

    static func shouldRemoveNormalTitleAfterSuperRare(random: inout GameRandomSource) -> Bool {
        random.nextBool(probability: 0.12)
    }

    static func selectSuperRareTitle(masterData: MasterDataCache,
                                     random: inout GameRandomSource) -> UInt8? {
        let titles = masterData.allSuperRareTitles
        guard !titles.isEmpty else { return nil }
        let index = random.nextInt(in: 0...(titles.count - 1))
        return titles[index].id
    }

    private static func normalTitleCandidates(masterData: MasterDataCache,
                                              hasTitleTreasure: Bool) -> [TitleDefinition] {
        masterData.allTitles.filter { definition in
            guard let probability = definition.dropProbability, probability > 0 else { return false }
            if !definition.allowWithTitleTreasure && hasTitleTreasure {
                return false
            }
            return true
        }
    }

    private static func rollNormalTitle(from candidates: [TitleDefinition],
                                        random: inout GameRandomSource) -> TitleDefinition? {
        let weights = candidates.map { $0.dropProbability ?? 0.0 }
        guard let index = random.nextIndex(weights: weights) else {
            return candidates.last
        }
        return candidates[index]
    }

    private static func shouldRemoveLowTitle(title: TitleDefinition,
                                             category: DropItemCategory) -> Bool {
        let rank = titleRank(of: title)
        switch category {
        case .good, .gem:
            return rank <= 2
        case .normal, .rare:
            return false
        }
    }

    private static func titleRank(of title: TitleDefinition) -> Int {
        Int(title.id)
    }

    private static func judgmentCountForEnemyTitle(masterData: MasterDataCache,
                                                    titleId: UInt8?) -> Int {
        guard let titleId else { return 1 }
        if let definition = masterData.title(titleId),
           let multiplier = definition.statMultiplier {
            let squared = multiplier * multiplier
            return max(1, Int(squared.rounded()))
        }
        return 1
    }
}
