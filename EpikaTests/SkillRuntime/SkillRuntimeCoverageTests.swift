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
        var routeCounts: [SkillEffectRouteFlags: Int] = [:]
        var totalEffects = 0

        for skill in skills {
            for effect in skill.effects {
                totalEffects += 1
                do {
                    let payload = try SkillRuntimeEffectCompiler.decodePayload(from: effect, skillId: skill.id)
                    try SkillRuntimeEffectCompiler.validatePayload(payload, skillId: skill.id, effectIndex: effect.index)
                    let routes = SkillEffectRouteMap.routes(for: payload.effectType)
                    guard !routes.isEmpty else {
                        issues.append("skillId=\(skill.id)#\(effect.index): 未解釈のeffectType=\(payload.effectType.identifier)")
                        continue
                    }
                    if routes.contains(.battleEffects),
                       SkillEffectHandlerRegistry.handler(for: payload.effectType) == nil {
                        issues.append("skillId=\(skill.id)#\(effect.index): handler未登録 effectType=\(payload.effectType.identifier)")
                    }
                    if routes.contains(.battleEffects) { routeCounts[.battleEffects, default: 0] += 1 }
                    if routes.contains(.combatStats) { routeCounts[.combatStats, default: 0] += 1 }
                    if routes.contains(.equipmentSlots) { routeCounts[.equipmentSlots, default: 0] += 1 }
                    if routes.contains(.spellbook) { routeCounts[.spellbook, default: 0] += 1 }
                    if routes.contains(.reward) { routeCounts[.reward, default: 0] += 1 }
                    if routes.contains(.exploration) { routeCounts[.exploration, default: 0] += 1 }
                    if routes.contains(.modifierSummary) { routeCounts[.modifierSummary, default: 0] += 1 }
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
                "route.battleEffects": Double(routeCounts[.battleEffects] ?? 0),
                "route.combatStats": Double(routeCounts[.combatStats] ?? 0),
                "route.equipmentSlots": Double(routeCounts[.equipmentSlots] ?? 0),
                "route.spellbook": Double(routeCounts[.spellbook] ?? 0),
                "route.reward": Double(routeCounts[.reward] ?? 0),
                "route.exploration": Double(routeCounts[.exploration] ?? 0),
                "route.modifierSummary": Double(routeCounts[.modifierSummary] ?? 0)
            ]
        )

        if !issues.isEmpty {
            let preview = issues.prefix(20).joined(separator: "\n")
            XCTFail("未解釈のスキル効果が\(issues.count)件あります:\n\(preview)")
        }
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
