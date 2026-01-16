// ============================================================================== 
// MasterDataLoadRegressionTests.swift
// EpikaTests
// ==============================================================================

import XCTest
import Foundation
@testable import Epika

nonisolated final class MasterDataLoadRegressionTests: XCTestCase {
    func testMasterDataLoad() async throws {
        let databaseURL = try resolveMasterDataURL()
        let manager = SQLiteMasterDataManager()
        try await manager.initialize(databaseURL: databaseURL)
        let cache = try await MasterDataLoader.load(manager: manager)

        XCTAssertFalse(cache.allItems.isEmpty, "items が空です")
        XCTAssertFalse(cache.allJobs.isEmpty, "jobs が空です")
        XCTAssertFalse(cache.allRaces.isEmpty, "races が空です")
        XCTAssertFalse(cache.allSkills.isEmpty, "skills が空です")
        XCTAssertFalse(cache.allSpells.isEmpty, "spells が空です")
        XCTAssertFalse(cache.allEnemies.isEmpty, "enemies が空です")
        XCTAssertFalse(cache.allDungeons.isEmpty, "dungeons が空です")
        XCTAssertFalse(cache.allTitles.isEmpty, "titles が空です")
        XCTAssertFalse(cache.allStoryNodes.isEmpty, "stories が空です")
        XCTAssertFalse(cache.allShopItems.isEmpty, "shop items が空です")
    }

    private func resolveMasterDataURL() throws -> URL {
        if let url = Bundle.main.url(forResource: "master_data", withExtension: "db") {
            return url
        }
        let bundle = Bundle(for: MasterDataLoadRegressionTests.self)
        if let url = bundle.url(forResource: "master_data", withExtension: "db") {
            return url
        }
        XCTFail("master_data.db が見つかりません")
        throw SQLiteMasterDataError.bundledDatabaseNotFound
    }
}

nonisolated final class SkillFamilyExpectationAlignmentTests: XCTestCase {
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

    func testSkillFamilyExpectationsMatchSkillMasterJSON() async throws {
        let rows = try loadExpectationRows()
        let variantsById = try loadSkillMasterIndex()

        var mismatches: [String] = []

        for row in rows {
            guard let variant = variantsById[row.sampleId] else {
                mismatches.append("id=\(row.sampleId): JSONに存在しません")
                continue
            }

            if variant.label != row.sampleLabel {
                mismatches.append("id=\(row.sampleId): label不一致 json='\(variant.label)' tsv='\(row.sampleLabel)'")
            }
            if variant.description != row.sampleDescription {
                mismatches.append("id=\(row.sampleId): description不一致 json='\(variant.description)' tsv='\(row.sampleDescription)'")
            }
            if variant.familyId != row.familyId {
                mismatches.append("id=\(row.sampleId): familyId不一致 json='\(variant.familyId)' tsv='\(row.familyId)'")
            }
            if variant.effectType != row.effectType {
                mismatches.append("id=\(row.sampleId): effectType不一致 json='\(variant.effectType)' tsv='\(row.effectType)'")
            }
            if variant.familyParameters != row.familyParameters {
                mismatches.append("id=\(row.sampleId): familyParameters不一致 json='\(variant.familyParameters)' tsv='\(row.familyParameters)'")
            }
            if variant.familyStringArrayValues != row.familyStringArrayValues {
                mismatches.append("id=\(row.sampleId): familyStringArrayValues不一致 json='\(variant.familyStringArrayValues)' tsv='\(row.familyStringArrayValues)'")
            }
        }

        await MainActor.run {
            ObservationRecorder.shared.record(
                id: "SKILL-ALIGN-001",
                expected: (min: 0, max: 0),
                measured: Double(mismatches.count),
                rawData: [
                    "rows": Double(rows.count),
                    "mismatches": Double(mismatches.count)
                ]
            )
        }

        if !mismatches.isEmpty {
            let preview = mismatches.prefix(20).joined(separator: "\n")
            XCTFail("SkillMaster.jsonとの不一致が\(mismatches.count)件あります:\n\(preview)")
        }
    }

    @MainActor
    func testSkillFamilyExpectationsMatchRuntimePayloads() async throws {
        let rows = try loadExpectationRows()
        let skillsById = try await loadSkillsById()

        var mismatches: [String] = []

        for row in rows {
            guard let skill = skillsById[row.sampleId] else {
                mismatches.append("id=\(row.sampleId): master_data.dbにスキルが存在しません")
                continue
            }

            let segments = try parseExpectedEffectSummary(row.expectedEffectSummary, skillId: row.sampleId)
            let effects = skill.effects

            if segments.count != effects.count {
                mismatches.append("id=\(row.sampleId): effect数不一致 expected=\(segments.count) actual=\(effects.count)")
                continue
            }

            for (index, segment) in segments.enumerated() {
                let effect = effects[index]
                let actualEffectType = effect.effectType.identifier
                if segment.effectType != actualEffectType {
                    mismatches.append("id=\(row.sampleId)#\(index): effectType不一致 expected=\(segment.effectType) actual=\(actualEffectType)")
                    continue
                }

                for (key, expectedValue) in segment.paramValues {
                    guard let actualValue = resolveParamValue(expectedKey: key, parameters: effect.parameters) else {
                        mismatches.append("id=\(row.sampleId)#\(index): param.\(key)が見つかりません")
                        continue
                    }
                    if actualValue != expectedValue {
                        mismatches.append("id=\(row.sampleId)#\(index): param.\(key)不一致 expected=\(expectedValue) actual=\(actualValue)")
                    }
                }

                for (key, expectedValue) in segment.valueValues {
                    guard let actualValue = resolveValueValue(key: key, values: effect.values) else {
                        mismatches.append("id=\(row.sampleId)#\(index): value.\(key)が見つかりません")
                        continue
                    }
                    if actualValue != expectedValue {
                        mismatches.append("id=\(row.sampleId)#\(index): value.\(key)不一致 expected=\(expectedValue) actual=\(actualValue)")
                    }
                }

                for (key, expectedValues) in segment.arrayValues {
                    guard let actualValues = resolveArrayValues(key: key, arrays: effect.arrayValues) else {
                        mismatches.append("id=\(row.sampleId)#\(index): array.\(key)が見つかりません")
                        continue
                    }
                    if actualValues != expectedValues {
                        mismatches.append("id=\(row.sampleId)#\(index): array.\(key)不一致 expected=\(expectedValues) actual=\(actualValues)")
                    }
                }

                if !segment.statScaleValues.isEmpty {
                    let statScale = resolveStatScale(parameters: effect.parameters, values: effect.values)
                    for (key, expectedValue) in segment.statScaleValues {
                        guard let actualValue = statScale[key] else {
                            mismatches.append("id=\(row.sampleId)#\(index): statScale.\(key)が見つかりません")
                            continue
                        }
                        if actualValue != expectedValue {
                            mismatches.append("id=\(row.sampleId)#\(index): statScale.\(key)不一致 expected=\(expectedValue) actual=\(actualValue)")
                        }
                    }
                }

                let semanticTokens = deriveSemanticTokens(effect: effect, effectType: effect.effectType)
                if !segment.semanticTokens.isEmpty {
                    let expectedTokens = Set(segment.semanticTokens)
                    let actualTokens = Set(semanticTokens)
                    if expectedTokens != actualTokens {
                        mismatches.append("id=\(row.sampleId)#\(index): semantic不一致 expected=\(expectedTokens.sorted()) actual=\(actualTokens.sorted())")
                    }
                }
            }
        }

        await MainActor.run {
            ObservationRecorder.shared.record(
                id: "SKILL-ALIGN-002",
                expected: (min: 0, max: 0),
                measured: Double(mismatches.count),
                rawData: [
                    "rows": Double(rows.count),
                    "mismatches": Double(mismatches.count)
                ]
            )
        }

        if !mismatches.isEmpty {
            let preview = mismatches.prefix(30).joined(separator: "\n")
            XCTFail("SkillFamilyExpectations.tsvとランタイムの不一致が\(mismatches.count)件あります:\n\(preview)")
        }
    }

    // MARK: - Expectations

    private struct ExpectationRow: Sendable {
        let familyId: String
        let effectType: String
        let familyParameters: String
        let familyStringArrayValues: String
        let sampleId: UInt16
        let sampleLabel: String
        let sampleDescription: String
        let expectedEffectSummary: String
    }

    private struct ExpectedEffectSegment: Sendable {
        let effectType: String
        let paramValues: [String: String]
        let valueValues: [String: String]
        let arrayValues: [String: [Int]]
        let statScaleValues: [String: String]
        let semanticTokens: [String]
    }

    private func loadExpectationRows() throws -> [ExpectationRow] {
        let url = try resolveExpectationTSVURL()
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(whereSeparator: \.isNewline)
        guard let headerLine = lines.first else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let headers = headerLine.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        var indexMap: [String: Int] = [:]
        for (index, name) in headers.enumerated() {
            indexMap[name] = index
        }

        func field(_ fields: [String], _ name: String) -> String {
            guard let index = indexMap[name], index < fields.count else { return "" }
            return fields[index]
        }

        var rows: [ExpectationRow] = []
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            var fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if fields.count < headers.count {
                fields.append(contentsOf: repeatElement("", count: headers.count - fields.count))
            }

            let idString = field(fields, "sampleId").trimmingCharacters(in: .whitespaces)
            guard let id = UInt16(idString) else {
                throw CocoaError(.fileReadCorruptFile)
            }

            rows.append(ExpectationRow(
                familyId: field(fields, "familyId"),
                effectType: field(fields, "effectType"),
                familyParameters: field(fields, "familyParameters"),
                familyStringArrayValues: field(fields, "familyStringArrayValues"),
                sampleId: id,
                sampleLabel: field(fields, "sampleLabel"),
                sampleDescription: field(fields, "sampleDescription"),
                expectedEffectSummary: field(fields, "expectedEffectSummary")
            ))
        }
        return rows
    }

    private func parseExpectedEffectSummary(_ summary: String, skillId: UInt16) throws -> [ExpectedEffectSegment] {
        let parts = summary.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        return try parts.map { part in
            let tokens = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            var effectType: String?
            var params: [String: String] = [:]
            var values: [String: String] = [:]
            var arrays: [String: [Int]] = [:]
            var statScale: [String: String] = [:]
            var semantics: [String] = []

            for token in tokens {
                if token.hasPrefix("effectType=") {
                    effectType = String(token.dropFirst("effectType=".count))
                    continue
                }
                if token.hasPrefix("param.") {
                    let trimmed = token.dropFirst("param.".count)
                    let parts = trimmed.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        params[String(parts[0])] = String(parts[1])
                    }
                    continue
                }
                if token.hasPrefix("value.") {
                    let trimmed = token.dropFirst("value.".count)
                    let parts = trimmed.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        values[String(parts[0])] = String(parts[1])
                    }
                    continue
                }
                if token.hasPrefix("array.") {
                    let trimmed = token.dropFirst("array.".count)
                    let parts = trimmed.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        let key = String(parts[0])
                        let raw = String(parts[1])
                        arrays[key] = parseArrayValues(raw)
                    }
                    continue
                }
                if token.hasPrefix("statScale.") {
                    let trimmed = token.dropFirst("statScale.".count)
                    let parts = trimmed.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        statScale[String(parts[0])] = String(parts[1])
                    }
                    continue
                }
                semantics.append(String(token))
            }

            guard let resolved = effectType else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId) expectedEffectSummary に effectType がありません")
            }

            return ExpectedEffectSegment(
                effectType: resolved,
                paramValues: params,
                valueValues: values,
                arrayValues: arrays,
                statScaleValues: statScale,
                semanticTokens: semantics
            )
        }
    }

    private func parseArrayValues(_ raw: String) -> [Int] {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if trimmed.isEmpty { return [] }
        return trimmed.split(separator: ",").compactMap { Int($0) }.sorted()
    }

    // MARK: - Runtime Alignment

    @MainActor
    private func resolveParamValue(expectedKey: String, parameters: [EffectParamKey: Int]) -> String? {
        let targetKey = EffectParamKey.allCases.first { String(describing: $0) == expectedKey }
        if let key = targetKey, let value = parameters[key] {
            return formatParamValue(key: key, value: value)
        }

        // alias: statusType -> status
        if expectedKey == "status", let value = parameters[.statusType] {
            return formatParamValue(key: .statusType, value: value)
        }

        // alias: equipmentType <-> equipmentCategory
        if expectedKey == "equipmentType", let value = parameters[.equipmentCategory] {
            return formatParamValue(key: .equipmentCategory, value: value)
        }
        if expectedKey == "equipmentCategory", let value = parameters[.equipmentType] {
            return formatParamValue(key: .equipmentType, value: value)
        }

        return nil
    }

    private func resolveValueValue(key: String, values: [EffectValueKey: Double]) -> String? {
        guard let valueKey = EffectValueKey.allCases.first(where: { String(describing: $0) == key }),
              let raw = values[valueKey] else {
            return nil
        }
        return formatValueValue(key: valueKey, value: raw)
    }

    private func resolveArrayValues(key: String, arrays: [EffectArrayKey: [Int]]) -> [Int]? {
        guard let arrayKey = EffectArrayKey.allCases.first(where: { String(describing: $0) == key }),
              let raw = arrays[arrayKey] else {
            return nil
        }
        return raw.sorted()
    }

    private func resolveStatScale(parameters: [EffectParamKey: Int], values: [EffectValueKey: Double]) -> [String: String] {
        var result: [String: String] = [:]
        if let statValue = parameters[.scalingStat] {
            result["stat"] = formatBaseStatValue(statValue)
        }
        if let coefficient = values[.scalingCoefficient] {
            result["percent"] = formatNumber(coefficient)
        }
        return result
    }

    @MainActor
    private func deriveSemanticTokens(effect: SkillDefinition.Effect, effectType: SkillEffectType) -> [String] {
        switch effectType {
        case .actionOrderShuffle:
            return ["target=party", "result.shuffleActionOrder=true"]
        case .actionOrderShuffleEnemy:
            return ["target=enemy", "result.shuffleActionOrder=true"]
        case .autoDegradationRepair:
            return ["trigger=turnEnd", "requires=degradationRepair", "result.triggerDegradationRepair=true", "bonusFrom=degradationRepairBoost"]
        case .autoStatusCureOnAlly:
            return ["trigger=allyStatusApplied", "target=ally", "result.castCure=immediate"]
        case .coverRowsBehind:
            let condition = resolveParamValue(expectedKey: "condition", parameters: effect.parameters) ?? "unknown"
            return ["condition=\(condition)", "target=allyBackRow", "result.cover=true"]
        case .firstStrike:
            return ["target=self", "result.firstStrike=true"]
        case .parry:
            if effect.values[.bonusPercent] != nil {
                return ["affects=successRate"]
            }
            return ["trigger=onMeleeHit", "check=firstHit", "result.stopMultiHit=remaining", "successRate.decreaseBy=attacker.additionalDamage"]
        case .reverseHealing:
            return ["trigger=onNormalAttack", "result.replaceWith=reverseHealingMagicAttack", "damageSource=magicalHealingScore", "notOnSkillAction=true"]
        case .shieldBlock:
            if effect.values[.bonusPercent] != nil {
                return ["affects=successRate"]
            }
            return ["trigger=onMeleeHit", "check=firstHit", "result.stopMultiHit=remaining", "successRate.decreaseBy=attacker.additionalDamage"]
        default:
            return []
        }
    }

    @MainActor
    private func formatParamValue(key: EffectParamKey, value: Int) -> String {
        switch key {
        case .damageType:
            return Self.damageTypeByRaw[value] ?? String(value)
        case .stat, .sourceStat, .targetStat, .statType:
            return formatStatValue(value)
        case .scalingStat:
            return formatBaseStatValue(value)
        case .equipmentCategory, .equipmentType:
            return Self.itemCategoryByRaw[value] ?? String(value)
        case .school:
            return Self.spellSchoolByRaw[value] ?? String(value)
        case .profile:
            return Self.profileByRaw[value] ?? String(value)
        case .action:
            return Self.effectActionByRaw[value] ?? String(value)
        case .mode:
            return Self.effectModeByRaw[value] ?? String(value)
        case .stacking:
            return Self.stackingByRaw[value] ?? String(value)
        case .target:
            return Self.targetByRaw[value] ?? String(value)
        case .trigger:
            return Self.triggerByRaw[value] ?? String(value)
        case .condition:
            return Self.conditionByRaw[value] ?? String(value)
        case .type, .variant:
            return Self.effectVariantByRaw[value] ?? String(value)
        case .hpScale:
            if let scale = BattleActor.SkillEffects.ResurrectionActive.HPScale(rawValue: UInt8(value)) {
                return scale.identifier
            }
            return String(value)
        case .targetStatus:
            return Self.statusTypeByRaw[value] ?? String(value)
        case .targetId:
            return Self.targetIdByRaw[value] ?? String(value)
        case .specialAttackId:
            return Self.specialAttackByRaw[value] ?? String(value)
        case .requiresAllyBehind, .requiresMartial, .farApt, .nearApt:
            return value == 1 ? "true" : "false"
        case .statusType:
            return Self.statusTypeByRaw[value] ?? String(value)
        case .status, .statusId:
            return String(value)
        default:
            return String(value)
        }
    }

    private func formatValueValue(key: EffectValueKey, value: Double) -> String {
        formatNumber(value)
    }

    private func formatStatValue(_ value: Int) -> String {
        if value == 99 { return "all" }
        if let combat = CombatStat(rawValue: UInt8(value)) {
            return combat.identifier
        }
        if let base = BaseStat(rawValue: UInt8(value)) {
            return base.identifier
        }
        return String(value)
    }

    private func formatBaseStatValue(_ value: Int) -> String {
        if let base = BaseStat(rawValue: UInt8(value)) {
            return base.identifier
        }
        return String(value)
    }

    private func formatNumber(_ value: Double) -> String {
        let rounded = (value * 1_000_000).rounded() / 1_000_000
        if rounded == rounded.rounded(.towardZero) {
            return String(Int(rounded))
        }
        var text = String(format: "%.6f", rounded)
        while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) {
            if text.hasSuffix(".") {
                text.removeLast()
                break
            }
            text.removeLast()
        }
        return text
    }

    // MARK: - JSON Index

    private struct JSONVariantEntry: Sendable {
        let id: UInt16
        let label: String
        let description: String
        let familyId: String
        let effectType: String
        let familyParameters: String
        let familyStringArrayValues: String
    }

    private func loadSkillMasterIndex() throws -> [UInt16: JSONVariantEntry] {
        let url = try resolveSkillMasterJSONURL()
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = json as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var variantsById: [UInt16: JSONVariantEntry] = [:]

        for (_, categoryValue) in root {
            guard let category = categoryValue as? [String: Any],
                  let families = category["families"] as? [[String: Any]] else {
                continue
            }

            for family in families {
                guard let familyId = family["familyId"] as? String,
                      let effectType = family["effectType"] as? String,
                      let variants = family["variants"] as? [[String: Any]] else {
                    continue
                }

                let familyParameters = formatJSONParameters(family["parameters"])
                let familyStringArrayValues = formatJSONStringArrayValues(family["stringArrayValues"])

                for variant in variants {
                    guard let id = variant["id"] as? Int,
                          let label = variant["label"] as? String,
                          let description = variant["description"] as? String else {
                        continue
                    }

                    variantsById[UInt16(id)] = JSONVariantEntry(
                        id: UInt16(id),
                        label: label,
                        description: description,
                        familyId: familyId,
                        effectType: effectType,
                        familyParameters: familyParameters,
                        familyStringArrayValues: familyStringArrayValues
                    )
                }
            }
        }

        return variantsById
    }

    private func formatJSONParameters(_ raw: Any?) -> String {
        guard let dict = raw as? [String: Any], !dict.isEmpty else { return "" }
        let keys = dict.keys.sorted()
        let parts = keys.compactMap { key -> String? in
            guard let value = dict[key] else { return nil }
            return "\(key)=\(formatJSONValue(value))"
        }
        return parts.joined(separator: ";")
    }

    private func formatJSONStringArrayValues(_ raw: Any?) -> String {
        guard let dict = raw as? [String: Any], !dict.isEmpty else { return "" }
        let keys = dict.keys.sorted()
        let parts = keys.compactMap { key -> String? in
            guard let array = dict[key] as? [Any] else { return nil }
            let values = array.map { formatJSONValue($0) }.joined(separator: ",")
            return "\(key)=[\(values)]"
        }
        return parts.joined(separator: ";")
    }

    private func formatJSONValue(_ value: Any) -> String {
        switch value {
        case let intValue as Int:
            return String(intValue)
        case let doubleValue as Double:
            return formatNumber(doubleValue)
        case let stringValue as String:
            return stringValue
        case let boolValue as Bool:
            return boolValue ? "true" : "false"
        default:
            return String(describing: value)
        }
    }

    // MARK: - Master Data

    @MainActor
    private func loadSkillsById() async throws -> [UInt16: SkillDefinition] {
        let databaseURL = try resolveMasterDataURL()
        let manager = SQLiteMasterDataManager()
        try await manager.initialize(databaseURL: databaseURL)
        let cache = try await MasterDataLoader.load(manager: manager)
        return Dictionary(uniqueKeysWithValues: cache.allSkills.map { ($0.id, $0) })
    }

    private func resolveMasterDataURL() throws -> URL {
        if let url = Bundle.main.url(forResource: "master_data", withExtension: "db") {
            return url
        }
        let bundle = Bundle(for: SkillFamilyExpectationAlignmentTests.self)
        if let url = bundle.url(forResource: "master_data", withExtension: "db") {
            return url
        }
        XCTFail("master_data.db が見つかりません")
        throw SQLiteMasterDataError.bundledDatabaseNotFound
    }

    private func resolveExpectationTSVURL() throws -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        let regressionDir = testFile.deletingLastPathComponent()
        let testsDir = regressionDir.deletingLastPathComponent()
        let dataURL = testsDir.appendingPathComponent("TestData/SkillFamilyExpectations.tsv")
        if FileManager.default.fileExists(atPath: dataURL.path) {
            return dataURL
        }
        XCTFail("SkillFamilyExpectations.tsv が見つかりません")
        throw CocoaError(.fileNoSuchFile)
    }

    private func resolveSkillMasterJSONURL() throws -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        let regressionDir = testFile.deletingLastPathComponent()
        let testsDir = regressionDir.deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent()
        let jsonURL = projectRoot.appendingPathComponent("MasterData/SkillMaster.json")
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            return jsonURL
        }
        XCTFail("SkillMaster.json が見つかりません")
        throw CocoaError(.fileNoSuchFile)
    }

    // MARK: - Param Mapping

    private static let damageTypeByRaw: [Int: String] = [
        1: "physical",
        2: "magical",
        3: "breath",
        4: "penetration",
        5: "healing",
        99: "all"
    ]

    private static let itemCategoryByRaw: [Int: String] = {
        var result: [Int: String] = [:]
        for category in ItemSaleCategory.allCases {
            result[Int(category.rawValue)] = category.identifier
        }
        result[25] = "dagger"
        return result
    }()

    private static let spellSchoolByRaw: [Int: String] = [
        1: "mage",
        2: "priest"
    ]

    private static let profileByRaw: [Int: String] = [
        1: "balanced",
        2: "near",
        3: "mixed",
        4: "far"
    ]

    private static let effectActionByRaw: [Int: String] = [
        1: "breathCounter",
        2: "counterAttack",
        3: "extraAttack",
        4: "forget",
        5: "learn",
        6: "magicCounter",
        7: "partyHeal",
        8: "physicalCounter",
        9: "physicalPursuit"
    ]

    private static let effectModeByRaw: [Int: String] = [
        1: "preemptive"
    ]

    private static let stackingByRaw: [Int: String] = [
        1: "add",
        2: "additive",
        3: "multiply"
    ]

    private static let targetByRaw: [Int: String] = [
        1: "ally",
        2: "attacker",
        3: "breathCounter",
        4: "counter",
        5: "counterOnEvade",
        6: "crisisEvasion",
        7: "criticalCombo",
        8: "enemy",
        9: "extraAction",
        10: "fightingSpirit",
        11: "firstStrike",
        12: "instantResurrection",
        13: "killer",
        14: "magicCounter",
        15: "magicSupport",
        16: "manaDecomposition",
        17: "parry",
        18: "party",
        19: "pursuit",
        20: "reattack",
        21: "reflectionRecovery",
        22: "self"
    ]

    private static let triggerByRaw: [Int: String] = [
        1: "afterTurn8",
        2: "allyDamagedPhysical",
        3: "allyDefeated",
        4: "allyMagicAttack",
        5: "battleStart",
        6: "selfAttackNoKill",
        7: "selfDamagedMagical",
        8: "selfDamagedPhysical",
        9: "selfEvadePhysical",
        10: "selfKilledEnemy",
        11: "selfMagicAttack",
        12: "turnElapsed",
        13: "turnStart"
    ]

    private static let effectVariantByRaw: [Int: String] = [
        1: "betweenFloors",
        2: "breath",
        3: "cold",
        4: "fire",
        5: "thunder"
    ]

    private static let targetIdByRaw: [Int: String] = [
        1: "human",
        2: "special_a",
        3: "special_b",
        4: "special_c",
        5: "vampire"
    ]

    private static let specialAttackByRaw: [Int: String] = [
        1: "specialA",
        2: "specialB",
        3: "specialC",
        4: "specialD",
        5: "specialE"
    ]

    private static let statusTypeByRaw: [Int: String] = [
        1: "all",
        2: "instantDeath",
        3: "resurrection.active"
    ]

    private static let conditionByRaw: [Int: String] = [
        1: "allyHPBelow50"
    ]
}
