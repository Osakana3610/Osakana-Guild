import Foundation

/// 敵撃破時の戦利品計算を担当するサービス。
enum DropService {
    static func drops(repository: MasterDataRepository,
                      for enemies: [EnemyDefinition],
                      party: RuntimePartyState,
                      dungeonId: UInt16? = nil,
                      chapter: Int,
                      floorNumber: Int? = nil,
                      droppedItemIds: Set<UInt16> = [],
                      isRabiTicketActive: Bool = false,
                      hasTitleTreasure: Bool = false,
                      enemyTitleId: UInt8? = nil,
                      dailySuperRareState: SuperRareDailyState,
                      random: inout GameRandomSource) async throws -> DropOutcome {
        guard !enemies.isEmpty else {
            return DropOutcome(results: [], superRareState: dailySuperRareState, newlyDroppedItemIds: [])
        }
        let partyBonuses = try party.makeDropBonuses()
        var superRareState = dailySuperRareState
        var sessionState = SuperRareSessionState()
        let enemyTitleDefinition: TitleDefinition?
        if let enemyTitleId {
            enemyTitleDefinition = try await repository.title(withId: enemyTitleId)
        } else {
            enemyTitleDefinition = nil
        }
        var results: [ItemDropResult] = []
        var newlyDroppedItemIds: Set<UInt16> = []

        // 1. レアアイテム（敵マスタのdrops配列）を処理
        for enemy in enemies {
            for itemId in enemy.drops {
                // ドロップ済みセットに含まれるアイテムは候補から除外
                guard !droppedItemIds.contains(itemId) else { continue }

                guard let item = try await repository.item(withId: itemId) else {
                    throw RuntimeError.masterDataNotFound(entity: "item", identifier: String(itemId))
                }

                let category = categorize(item: item)
                let roll = ItemDropRateCalculator.roll(category: category,
                                                       rareMultiplier: partyBonuses.rareDropMultiplier,
                                                       isRabiTicketActive: isRabiTicketActive,
                                                       partyLuck: partyBonuses.averageLuck,
                                                       random: &random)
                guard roll.willDrop else { continue }

                let (normalTitleId, superRareTitleId) = try await assignTitles(
                    category: category,
                    partyBonuses: partyBonuses,
                    isRabiTicketActive: isRabiTicketActive,
                    enemyTitleId: enemyTitleId,
                    hasTitleTreasure: hasTitleTreasure,
                    enemyTitleDefinition: enemyTitleDefinition,
                    repository: repository,
                    sessionState: &sessionState,
                    superRareState: &superRareState,
                    random: &random
                )

                let result = ItemDropResult(item: item,
                                            quantity: 1,
                                            sourceEnemyId: enemy.id,
                                            normalTitleId: normalTitleId,
                                            superRareTitleId: superRareTitleId)
                results.append(result)
                newlyDroppedItemIds.insert(itemId)
            }
        }

        // 2. ノーマルアイテム（敵種族・ダンジョン章から動的生成）を処理
        let combinedDroppedIds = droppedItemIds.union(newlyDroppedItemIds)
        let normalCandidates = try await NormalItemDropGenerator.candidates(
            for: enemies,
            chapter: chapter,
            repository: repository,
            droppedItemIds: combinedDroppedIds,
            random: &random
        )

        for candidate in normalCandidates {
            // 同一戦闘内で既にドロップした場合はスキップ
            guard !newlyDroppedItemIds.contains(candidate.itemId) else { continue }

            guard let item = try await repository.item(withId: candidate.itemId) else {
                throw RuntimeError.masterDataNotFound(entity: "item", identifier: String(candidate.itemId))
            }

            // ノーマルアイテムは.normalカテゴリで抽選
            let roll = ItemDropRateCalculator.roll(category: .normal,
                                                   rareMultiplier: partyBonuses.rareDropMultiplier,
                                                   isRabiTicketActive: isRabiTicketActive,
                                                   partyLuck: partyBonuses.averageLuck,
                                                   random: &random)
            guard roll.willDrop else { continue }

            let (normalTitleId, superRareTitleId) = try await assignTitles(
                category: .normal,
                partyBonuses: partyBonuses,
                isRabiTicketActive: isRabiTicketActive,
                enemyTitleId: enemyTitleId,
                hasTitleTreasure: hasTitleTreasure,
                enemyTitleDefinition: enemyTitleDefinition,
                repository: repository,
                sessionState: &sessionState,
                superRareState: &superRareState,
                random: &random
            )

            let result = ItemDropResult(item: item,
                                        quantity: 1,
                                        sourceEnemyId: candidate.sourceEnemyId,
                                        normalTitleId: normalTitleId,
                                        superRareTitleId: superRareTitleId)
            results.append(result)
            newlyDroppedItemIds.insert(candidate.itemId)
        }

        return DropOutcome(results: results, superRareState: superRareState, newlyDroppedItemIds: newlyDroppedItemIds)
    }

    /// 称号付与ロジック（レアアイテム・ノーマルアイテム共通）
    private static func assignTitles(
        category: DropItemCategory,
        partyBonuses: PartyDropBonuses,
        isRabiTicketActive: Bool,
        enemyTitleId: UInt8?,
        hasTitleTreasure: Bool,
        enemyTitleDefinition: TitleDefinition?,
        repository: MasterDataRepository,
        sessionState: inout SuperRareSessionState,
        superRareState: inout SuperRareDailyState,
        random: inout GameRandomSource
    ) async throws -> (normalTitleId: UInt8?, superRareTitleId: UInt8?) {
        var normalTitleId: UInt8? = nil
        var superRareTitleId: UInt8? = nil

        if TitleAssignmentEngine.shouldAssignTitle(category: category,
                                                    partyBonuses: partyBonuses,
                                                    isRabiTicketActive: isRabiTicketActive,
                                                    random: &random) {
            if let normalTitle = try await TitleAssignmentEngine.determineNormalTitle(repository: repository,
                                                                                       enemyTitleId: enemyTitleId,
                                                                                       hasTitleTreasure: hasTitleTreasure,
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

        return (normalTitleId, superRareTitleId)
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
