import Foundation

/// 敵撃破時の戦利品計算を担当するサービス。
enum DropService {
    static func drops(repository: MasterDataRepository,
                      for enemy: EnemyDefinition,
                      party: RuntimePartyState,
                      dungeonId: UInt16? = nil,
                      floorNumber: Int? = nil,
                      isRabiTicketActive: Bool = false,
                      hasTitleTreasure: Bool = false,
                      enemyTitleId: UInt8? = nil,
                      dailySuperRareState: SuperRareDailyState,
                      random: inout GameRandomSource) async throws -> DropOutcome {
        guard !enemy.drops.isEmpty else { return DropOutcome(results: [], superRareState: dailySuperRareState) }
        let partyBonuses = try party.makeDropBonuses()
        let context = DropContext(enemy: enemy,
                                  partyBonuses: partyBonuses,
                                  isRabiTicketActive: isRabiTicketActive,
                                  hasTitleTreasure: hasTitleTreasure,
                                  dungeonId: dungeonId,
                                  floorNumber: floorNumber)
        var superRareState = dailySuperRareState
        var sessionState = SuperRareSessionState()
        let enemyTitleDefinition: TitleDefinition?
        if let enemyTitleId {
            enemyTitleDefinition = try await repository.title(withId: enemyTitleId)
        } else {
            enemyTitleDefinition = nil
        }
        var results: [ItemDropResult] = []

        for drop in enemy.drops.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            guard let item = try await repository.item(withId: drop.itemId) else {
                throw RuntimeError.masterDataNotFound(entity: "item", identifier: String(drop.itemId))
            }

            let category = categorize(item: item)
            let roll = ItemDropRateCalculator.roll(category: category,
                                                   rareMultiplier: context.partyBonuses.rareDropMultiplier,
                                                   isRabiTicketActive: context.isRabiTicketActive,
                                                   partyLuck: context.partyBonuses.averageLuck,
                                                   random: &random)
            guard roll.willDrop else { continue }

            var normalTitleId: UInt8? = nil
            var superRareTitleId: UInt8? = nil

            if TitleAssignmentEngine.shouldAssignTitle(category: category,
                                                        partyBonuses: context.partyBonuses,
                                                        isRabiTicketActive: context.isRabiTicketActive,
                                                        random: &random) {
                if let normalTitle = try await TitleAssignmentEngine.determineNormalTitle(repository: repository,
                                                                                           enemyTitleId: enemyTitleId,
                                                                                           hasTitleTreasure: context.hasTitleTreasure,
                                                                                           category: category,
                                                                                           random: &random) {
                    normalTitleId = normalTitle.id
                    let evaluation = try await evaluateSuperRare(for: category,
                                                                 title: normalTitle,
                                                                 enemyTitle: enemyTitleDefinition,
                                                                 repository: repository,
                                                                 sessionState: &sessionState,
                                                                 dailyState: &superRareState,
                                                                 random: &random)
                    normalTitleId = evaluation.normalTitleId
                    superRareTitleId = evaluation.superRareTitleId
                }
            }

            let result = ItemDropResult(item: item,
                                        quantity: 1,
                                        sourceEnemyId: enemy.id,
                                        normalTitleId: normalTitleId,
                                        superRareTitleId: superRareTitleId)
            results.append(result)
        }

        return DropOutcome(results: results, superRareState: superRareState)
    }

    private static func categorize(item: ItemDefinition) -> DropItemCategory {
        let itemCategory = item.category.lowercased()
        switch itemCategory {
        case "gem", "mazo_material":
            return .gem
        case "race_specific", "grimoire":
            return .rare
        default:
            break
        }

        let referencePrice = max(item.sellValue, item.basePrice)
        if referencePrice >= 10_000 {
            return .rare
        } else if referencePrice >= 2_000 {
            return .good
        }
        return .normal
    }

    private static func evaluateSuperRare(for category: DropItemCategory,
                                          title: TitleDefinition,
                                          enemyTitle: TitleDefinition?,
                                          repository: MasterDataRepository,
                                          sessionState: inout SuperRareSessionState,
                                          dailyState: inout SuperRareDailyState,
                                          random: inout GameRandomSource) async throws -> (normalTitleId: UInt8?, superRareTitleId: UInt8?) {
        guard let rates = title.superRareRates else {
            return (title.id, nil)
        }

        if category == .normal && sessionState.normalItemTriggered {
            guard random.nextBool(probability: 0.35) else {
                return (title.id, nil)
            }
        }

        let denominator = dailyState.hasTriggered ? 22_727_200 : 2_840_900
        guard denominator > 0 else { return (title.id, nil) }

        let baseRate: Double
        switch category {
        case .normal: baseRate = rates.normal
        case .good: baseRate = rates.good
        case .rare: baseRate = rates.rare
        case .gem: baseRate = rates.gem
        }

        guard baseRate > 0 else { return (title.id, nil) }

        let enemyMultiplier = superRareEnemyMultiplier(for: category, enemyTitle: enemyTitle)
        let threshold = min(Double(denominator), baseRate * enemyMultiplier)
        guard threshold > 0 else { return (title.id, nil) }

        let roll = random.nextInt(in: 1...denominator)
        guard Double(roll) <= threshold else {
            return (title.id, nil)
        }

        let superRareTitleId = try await TitleAssignmentEngine.selectSuperRareTitle(repository: repository,
                                                                                     random: &random)
        guard let superRareTitleId else {
            return (title.id, nil)
        }

        dailyState.hasTriggered = true
        if category == .normal {
            sessionState.normalItemTriggered = true
        }

        var normalTitleId: UInt8? = title.id
        if TitleAssignmentEngine.shouldRemoveNormalTitleAfterSuperRare(random: &random) {
            normalTitleId = nil
        }

        return (normalTitleId, superRareTitleId)
    }

    private static func superRareEnemyMultiplier(for category: DropItemCategory,
                                                 enemyTitle: TitleDefinition?) -> Double {
        guard let titleId = enemyTitle?.id, titleId >= 6 else { return 1.0 }
        switch category {
        case .normal, .good:
            return 50.0
        case .rare:
            return 20.0
        case .gem:
            return 1.0
        }
    }
}
