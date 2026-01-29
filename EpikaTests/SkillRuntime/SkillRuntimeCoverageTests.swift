import XCTest
@testable import Epika

nonisolated final class SkillRuntimeCoverageTests: XCTestCase {
    override class func tearDown() {
        let expectation = XCTestExpectation(description: "Export observations")
        Task { @MainActor in
            do {
                let url = try ObservationRecorder.shared.export()
                print("Observations exported to: \(url.path)")
            } catch {
                print("Failed to export observations: \(error)")
            }
            expectation.fulfill()
        }
        _ = XCTWaiter().wait(for: [expectation], timeout: 5.0)
        super.tearDown()
    }

    @MainActor func testAllSkillEffectsAreInterpreted() async throws {
        let cache = try await loadMasterData()
        let skills = cache.allSkills
        var issues: [String] = []
        var routeCounts: [String: Int] = [:]
        var totalEffects = 0

        for skill in skills {
            for effect in skill.effects {
                totalEffects += 1
                do {
                    let payload = try SkillRuntimeEffectCompiler.decodePayload(from: effect, skillId: skill.id)
                    try SkillRuntimeEffectCompiler.validatePayload(payload, skillId: skill.id, effectIndex: effect.index)
                    guard let route = interpretationRoute(for: payload.effectType) else {
                        issues.append("skillId=\(skill.id)#\(effect.index): 未解釈のeffectType=\(payload.effectType.identifier)")
                        continue
                    }
                    routeCounts[route, default: 0] += 1
                } catch {
                    issues.append("skillId=\(skill.id)#\(effect.index): \(error)")
                }
            }
        }

        ObservationRecorder.shared.record(
            id: "SKILL-COVERAGE-001",
            expected: (min: 0, max: 0),
            measured: Double(issues.count),
            rawData: [
                "skillCount": Double(skills.count),
                "effectCount": Double(totalEffects),
                "issueCount": Double(issues.count),
                "route.actor": Double(routeCounts["actor"] ?? 0),
                "route.combatStats": Double(routeCounts["combatStats"] ?? 0),
                "route.equipmentSlots": Double(routeCounts["equipmentSlots"] ?? 0),
                "route.spellbook": Double(routeCounts["spellbook"] ?? 0),
                "route.reward": Double(routeCounts["reward"] ?? 0),
                "route.exploration": Double(routeCounts["exploration"] ?? 0)
            ]
        )

        if !issues.isEmpty {
            let preview = issues.prefix(20).joined(separator: "\n")
            XCTFail("未解釈のスキル効果が\(issues.count)件あります:\n\(preview)")
        }
    }
}

// MARK: - Coverage Routing

private extension SkillRuntimeCoverageTests {
    static let passthroughTypes: Set<SkillEffectType> = [
        .criticalChancePercentAdditive,
        .criticalChancePercentCap,
        .criticalChancePercentMaxDelta,
        .equipmentSlotAdditive,
        .equipmentSlotMultiplier,
        .explorationTimeMultiplier,
        .growthMultiplier,
        .incompetenceStat,
        .itemStatMultiplier,
        .rewardExperienceMultiplier,
        .rewardExperiencePercent,
        .rewardGoldMultiplier,
        .rewardGoldPercent,
        .rewardItemMultiplier,
        .rewardItemPercent,
        .rewardTitleMultiplier,
        .rewardTitlePercent,
        .statAdditive,
        .statConversionLinear,
        .statConversionPercent,
        .statFixedToOne,
        .statMultiplier,
        .talentStat
    ]

    static let nonActorTypes: Set<SkillEffectType> = {
        passthroughTypes.union([.spellAccess, .spellTierUnlock])
    }()

    static let actorTypes: Set<SkillEffectType> = {
        let allHandlerTypes = Set(SkillEffectHandlerRegistry.handlers.keys)
        return allHandlerTypes.subtracting(nonActorTypes)
    }()

    static let equipmentSlotTypes: Set<SkillEffectType> = [
        .equipmentSlotAdditive,
        .equipmentSlotMultiplier
    ]

    static let spellbookTypes: Set<SkillEffectType> = [
        .spellAccess,
        .spellTierUnlock
    ]

    static let rewardTypes: Set<SkillEffectType> = [
        .rewardExperiencePercent,
        .rewardExperienceMultiplier,
        .rewardGoldPercent,
        .rewardGoldMultiplier,
        .rewardItemPercent,
        .rewardItemMultiplier,
        .rewardTitlePercent,
        .rewardTitleMultiplier
    ]

    static let explorationTypes: Set<SkillEffectType> = [
        .explorationTimeMultiplier
    ]

    static let combatStatTypes: Set<SkillEffectType> = [
        .additionalDamageScoreAdditive,
        .additionalDamageScoreMultiplier,
        .statAdditive,
        .statMultiplier,
        .attackCountAdditive,
        .attackCountMultiplier,
        .growthMultiplier,
        .equipmentStatMultiplier,
        .itemStatMultiplier,
        .statConversionPercent,
        .statConversionLinear,
        .criticalChancePercentAdditive,
        .criticalChancePercentCap,
        .criticalChancePercentMaxDelta,
        .criticalDamagePercent,
        .criticalDamageMultiplier,
        .martialBonusPercent,
        .martialBonusMultiplier,
        .talentStat,
        .incompetenceStat,
        .statFixedToOne
    ]

    func interpretationRoute(for effectType: SkillEffectType) -> String? {
        if Self.actorTypes.contains(effectType) { return "actor" }
        if Self.combatStatTypes.contains(effectType) { return "combatStats" }
        if Self.equipmentSlotTypes.contains(effectType) { return "equipmentSlots" }
        if Self.spellbookTypes.contains(effectType) { return "spellbook" }
        if Self.rewardTypes.contains(effectType) { return "reward" }
        if Self.explorationTypes.contains(effectType) { return "exploration" }
        return nil
    }
}

// MARK: - Master Data

private extension SkillRuntimeCoverageTests {
    @MainActor func loadMasterData() async throws -> MasterDataCache {
        let databaseURL = try resolveMasterDataURL()
        let manager = SQLiteMasterDataManager()
        try await manager.initialize(databaseURL: databaseURL)
        return try await MasterDataLoader.load(manager: manager)
    }

    func resolveMasterDataURL() throws -> URL {
        if let url = Bundle.main.url(forResource: "master_data", withExtension: "db") {
            return url
        }
        let bundle = Bundle(for: SkillRuntimeCoverageTests.self)
        if let url = bundle.url(forResource: "master_data", withExtension: "db") {
            return url
        }
        XCTFail("master_data.db not found")
        throw SQLiteMasterDataError.bundledDatabaseNotFound
    }
}
