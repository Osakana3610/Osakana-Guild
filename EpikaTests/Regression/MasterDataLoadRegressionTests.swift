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
        let jsonFamilyIds = try loadSkillMasterFamilyIds()

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

        let tsvFamilyIds = Set(rows.map { $0.familyId }.filter { !$0.isEmpty })
        let missingFamilies = jsonFamilyIds.subtracting(tsvFamilyIds).sorted()
        let extraFamilies = tsvFamilyIds.subtracting(jsonFamilyIds).sorted()
        if !missingFamilies.isEmpty {
            let preview = missingFamilies.prefix(20).joined(separator: ",")
            mismatches.append("familyId: TSVに存在しないJSON familyIdが\(missingFamilies.count)件あります: \(preview)")
        }
        if !extraFamilies.isEmpty {
            let preview = extraFamilies.prefix(20).joined(separator: ",")
            mismatches.append("familyId: JSONに存在しないTSV familyIdが\(extraFamilies.count)件あります: \(preview)")
        }

        await MainActor.run {
            ObservationRecorder.shared.record(
                id: "SKILL-ALIGN-001",
                expected: (min: 0, max: 0),
                measured: Double(mismatches.count),
                rawData: [
                    "rows": Double(rows.count),
                    "mismatches": Double(mismatches.count),
                    "familyCountJSON": Double(jsonFamilyIds.count),
                    "familyCountTSV": Double(tsvFamilyIds.count),
                    "missingFamilyCount": Double(missingFamilies.count),
                    "extraFamilyCount": Double(extraFamilies.count)
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

    @MainActor
    func testSkillFamilyExpectationsMatchRuntimeOutputs() async throws {
        let rows = try loadExpectationRows()
        let skillsById = try await loadSkillsById()
        let actorStats = ActorStats(strength: 10, wisdom: 12, spirit: 14, vitality: 16, agility: 18, luck: 20)
        let combatFixture = makeCombatFixture()

        var mismatches: [String] = []

        for row in rows {
            guard let actualSkill = skillsById[row.sampleId] else {
                mismatches.append("id=\(row.sampleId): master_data.dbにスキルが存在しません")
                continue
            }

            let segments = try parseExpectedEffectSummary(row.expectedEffectSummary, skillId: row.sampleId)
            if segments.count != actualSkill.effects.count {
                mismatches.append("id=\(row.sampleId): effect数不一致 expected=\(segments.count) actual=\(actualSkill.effects.count)")
                continue
            }

            let expectedSkill: SkillDefinition
            do {
                expectedSkill = try buildExpectedSkill(row: row, actualSkill: actualSkill, segments: segments)
            } catch {
                mismatches.append("id=\(row.sampleId): 期待値スキル生成失敗 \(error)")
                continue
            }

            do {
                let actualOutputs = try makeRuntimeOutputs(skill: actualSkill,
                                                           actorStats: actorStats,
                                                           combatFixture: combatFixture)
                let expectedOutputs = try makeRuntimeOutputs(skill: expectedSkill,
                                                             actorStats: actorStats,
                                                             combatFixture: combatFixture)
                let diffs = diffRuntimeOutputs(actual: actualOutputs, expected: expectedOutputs)
                if !diffs.isEmpty {
                    mismatches.append("id=\(row.sampleId): runtime差異[\(diffs.joined(separator: ","))]")
                }
            } catch {
                mismatches.append("id=\(row.sampleId): runtime出力生成失敗 \(error)")
            }
        }

        await MainActor.run {
            ObservationRecorder.shared.record(
                id: "SKILL-ALIGN-003",
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
            XCTFail("SkillFamilyExpectations.tsvとランタイム出力の不一致が\(mismatches.count)件あります:\n\(preview)")
        }
    }

    @MainActor
    func testSkillFamilyExpectationsMatchRuntimeActivations() async throws {
        let rows = try loadExpectationRows()
        let skillsById = try await loadSkillsById()
        let statusDefinitions = try await loadStatusDefinitionsById()
        let actorStats = ActorStats(strength: 200, wisdom: 200, spirit: 200, vitality: 200, agility: 200, luck: 200)

        var mismatches: [String] = []
        var totalSegments = 0
        var activationSegments = 0
        var skippedSegments = 0

        let previousRandomMode = BetaTestSettings.randomMode
        BetaTestSettings.randomMode = .fixedMedian
        defer { BetaTestSettings.randomMode = previousRandomMode }

        for row in rows {
            guard let actualSkill = skillsById[row.sampleId] else {
                mismatches.append("id=\(row.sampleId): master_data.dbにスキルが存在しません")
                continue
            }

            let segments = try parseExpectedEffectSummary(row.expectedEffectSummary, skillId: row.sampleId)
            totalSegments += segments.count
            if segments.count != actualSkill.effects.count {
                mismatches.append("id=\(row.sampleId): effect数不一致 expected=\(segments.count) actual=\(actualSkill.effects.count)")
                continue
            }

            let familyParameters = parseFamilyParameters(row.familyParameters)
            let procChanceMultiplier = computeProcChanceMultiplier(from: segments)

            for (index, segment) in segments.enumerated() {
                guard let effectType = SkillEffectType(identifier: segment.effectType) else {
                    skippedSegments += 1
                    continue
                }
                guard Self.activationEffectTypes.contains(effectType) else {
                    skippedSegments += 1
                    continue
                }
                activationSegments += 1

                let mergedParams = mergeParameters(family: familyParameters, segment: segment)
                let actualSegmentSkill = SkillDefinition(
                    id: actualSkill.id,
                    name: actualSkill.name,
                    description: actualSkill.description,
                    type: actualSkill.type,
                    category: actualSkill.category,
                    effects: [actualSkill.effects[index]]
                )
                var actualEffects = try compileActorEffects(skill: actualSegmentSkill, stats: actorStats)
                actualEffects.combat.procChanceMultiplier *= procChanceMultiplier

                do {
                    let probes = try activationProbes(
                        effectType: effectType,
                        segment: segment,
                        mergedParams: mergedParams,
                        actualEffects: actualEffects,
                        actorStats: actorStats,
                        procChanceMultiplier: procChanceMultiplier,
                        statusDefinitions: statusDefinitions
                    )

                    for probe in probes where probe.expected != probe.actual {
                        mismatches.append("id=\(row.sampleId)#\(index): \(probe.label) expected=\(probe.expected) actual=\(probe.actual)")
                    }
                } catch {
                    mismatches.append("id=\(row.sampleId)#\(index): activation判定失敗 \(error)")
                }
            }
        }

        await MainActor.run {
            ObservationRecorder.shared.record(
                id: "SKILL-ALIGN-004",
                expected: (min: 0, max: 0),
                measured: Double(mismatches.count),
                rawData: [
                    "rows": Double(rows.count),
                    "segments": Double(totalSegments),
                    "activationSegments": Double(activationSegments),
                    "skippedSegments": Double(skippedSegments),
                    "mismatches": Double(mismatches.count)
                ]
            )
        }

        if !mismatches.isEmpty {
            let preview = mismatches.prefix(30).joined(separator: "\n")
            XCTFail("SkillFamilyExpectations.tsvとランタイム発動条件の不一致が\(mismatches.count)件あります:\n\(preview)")
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

    // MARK: - Runtime Output Alignment

    private struct RuntimeOutputs: Sendable {
        let actorEffects: BattleActor.SkillEffects
        let equipmentSlots: SkillRuntimeEffects.EquipmentSlots
        let spellbook: SkillRuntimeEffects.Spellbook
        let rewardComponents: SkillRuntimeEffects.RewardComponents
        let explorationModifiers: SkillRuntimeEffects.ExplorationModifiers
        let attributes: CharacterValues.CoreAttributes
        let combat: CharacterValues.Combat
    }

    private struct CombatFixture: Sendable {
        let race: RaceDefinition
        let job: JobDefinition
        let equippedItems: [CharacterValues.EquippedItem]
        let cachedEquippedItems: [CachedInventoryItem]
        let loadout: CachedCharacter.Loadout
    }

    @MainActor
    private func makeCombatFixture() -> CombatFixture {
        let race = RaceDefinition(
            id: 1,
            name: "TestRace",
            genderCode: 1,
            description: "",
            baseStats: RaceDefinition.BaseStats(
                strength: 10,
                wisdom: 12,
                spirit: 14,
                vitality: 16,
                agility: 18,
                luck: 20
            ),
            maxLevel: 200
        )
        let coefficients = JobDefinition.CombatCoefficients(
            maxHP: 1.0,
            physicalAttackScore: 1.0,
            magicalAttackScore: 1.0,
            physicalDefenseScore: 1.0,
            magicalDefenseScore: 1.0,
            hitScore: 1.0,
            evasionScore: 1.0,
            criticalChancePercent: 1.0,
            attackCount: 1.0,
            magicalHealingScore: 1.0,
            trapRemovalScore: 1.0,
            additionalDamageScore: 1.0,
            breathDamageScore: 1.0
        )
        let job = JobDefinition(
            id: 1,
            name: "TestJob",
            combatCoefficients: coefficients,
            learnedSkillIds: []
        )

        let statBonuses = ItemDefinition.StatBonuses(
            strength: 1,
            wisdom: 1,
            spirit: 1,
            vitality: 1,
            agility: 1,
            luck: 1
        )
        let combatBonuses = ItemDefinition.CombatBonuses(
            maxHP: 1,
            physicalAttackScore: 1,
            magicalAttackScore: 1,
            physicalDefenseScore: 1,
            magicalDefenseScore: 1,
            hitScore: 1,
            evasionScore: 1,
            criticalChancePercent: 1,
            attackCount: 1.0,
            magicalHealingScore: 1,
            trapRemovalScore: 1,
            additionalDamageScore: 1,
            breathDamageScore: 1
        )

        var itemDefinitions: [ItemDefinition] = []
        var cachedItems: [CachedInventoryItem] = []
        var equippedItems: [CharacterValues.EquippedItem] = []

        for (index, category) in ItemSaleCategory.allCases.enumerated() {
            let itemId = UInt16(10_000 + index)
            let definition = ItemDefinition(
                id: itemId,
                name: "TestItem-\(category.identifier)",
                category: category.rawValue,
                basePrice: 0,
                sellValue: 0,
                rarity: nil,
                statBonuses: statBonuses,
                combatBonuses: combatBonuses,
                allowedRaceIds: [],
                allowedJobIds: [],
                allowedGenderCodes: [],
                bypassRaceIds: [],
                grantedSkillIds: []
            )
            itemDefinitions.append(definition)

            let cached = CachedInventoryItem(
                stackKey: "test-\(itemId)",
                itemId: itemId,
                quantity: 1,
                normalTitleId: 0,
                superRareTitleId: 0,
                socketItemId: 0,
                socketNormalTitleId: 0,
                socketSuperRareTitleId: 0,
                category: category,
                rarity: nil,
                displayName: definition.name,
                baseValue: 0,
                sellValue: 0,
                statBonuses: statBonuses,
                combatBonuses: combatBonuses,
                grantedSkillIds: []
            )
            cachedItems.append(cached)
            equippedItems.append(cached.toEquippedItem())
        }

        let loadout = CachedCharacter.Loadout(items: itemDefinitions, titles: [], superRareTitles: [])

        return CombatFixture(
            race: race,
            job: job,
            equippedItems: equippedItems,
            cachedEquippedItems: cachedItems,
            loadout: loadout
        )
    }

    @MainActor
    private func makeRuntimeOutputs(
        skill: SkillDefinition,
        actorStats: ActorStats,
        combatFixture: CombatFixture
    ) throws -> RuntimeOutputs {
        let compiler = try UnifiedSkillEffectCompiler(skills: [skill], stats: actorStats)
        let rewardComponents = try SkillRuntimeEffectCompiler.rewardComponents(from: [skill])
        let explorationModifiers = try SkillRuntimeEffectCompiler.explorationModifiers(from: [skill])

        let context = CombatStatCalculator.Context(
            raceId: combatFixture.race.id,
            jobId: combatFixture.job.id,
            level: 10,
            currentHP: 10,
            equippedItems: combatFixture.equippedItems,
            cachedEquippedItems: combatFixture.cachedEquippedItems,
            race: combatFixture.race,
            job: combatFixture.job,
            personalitySecondary: nil,
            learnedSkills: [skill],
            loadout: combatFixture.loadout
        )
        let result = try CombatStatCalculator.calculate(for: context)

        return RuntimeOutputs(
            actorEffects: compiler.actorEffects,
            equipmentSlots: compiler.equipmentSlots,
            spellbook: compiler.spellbook,
            rewardComponents: rewardComponents,
            explorationModifiers: explorationModifiers,
            attributes: result.attributes,
            combat: result.combat
        )
    }

    @MainActor
    private func diffRuntimeOutputs(actual: RuntimeOutputs, expected: RuntimeOutputs) -> [String] {
        var diffs: [String] = []
        if actual.actorEffects != expected.actorEffects { diffs.append("actorEffects") }
        if actual.equipmentSlots != expected.equipmentSlots { diffs.append("equipmentSlots") }
        if actual.spellbook != expected.spellbook { diffs.append("spellbook") }
        if actual.rewardComponents != expected.rewardComponents { diffs.append("rewardComponents") }
        if !matchesExplorationModifiers(actual.explorationModifiers, expected.explorationModifiers) { diffs.append("explorationModifiers") }
        if actual.attributes != expected.attributes { diffs.append("attributes") }
        if actual.combat != expected.combat { diffs.append("combat") }
        return diffs
    }

    @MainActor
    private func matchesExplorationModifiers(
        _ lhs: SkillRuntimeEffects.ExplorationModifiers,
        _ rhs: SkillRuntimeEffects.ExplorationModifiers
    ) -> Bool {
        guard lhs.entries.count == rhs.entries.count else { return false }
        for (left, right) in zip(lhs.entries, rhs.entries) {
            if left.dungeonId != right.dungeonId { return false }
            if left.dungeonName != right.dungeonName { return false }
            if !isApproximatelyEqual(left.multiplier, right.multiplier, tolerance: 1e-9) { return false }
        }
        return true
    }

    @MainActor
    private func isApproximatelyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    @MainActor
    private func buildExpectedSkill(
        row: ExpectationRow,
        actualSkill: SkillDefinition,
        segments: [ExpectedEffectSegment]
    ) throws -> SkillDefinition {
        var effects: [SkillDefinition.Effect] = []
        for (index, segment) in segments.enumerated() {
            guard let effectType = SkillEffectType(identifier: segment.effectType) else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(row.sampleId) effectType不明: \(segment.effectType)")
            }
            let template = index < actualSkill.effects.count ? actualSkill.effects[index] : nil
            let effectIndex = template?.index ?? index
            let familyId = template?.familyId
            let parameters = try parseExpectedParameters(segment.paramValues, statScale: segment.statScaleValues, skillId: row.sampleId)
            let values = try parseExpectedValues(segment.valueValues, statScale: segment.statScaleValues, skillId: row.sampleId)
            let arrayValues = try parseExpectedArrays(segment.arrayValues, skillId: row.sampleId)
            effects.append(SkillDefinition.Effect(
                index: effectIndex,
                effectType: effectType,
                familyId: familyId,
                parameters: parameters,
                values: values,
                arrayValues: arrayValues
            ))
        }

        return SkillDefinition(
            id: actualSkill.id,
            name: row.sampleLabel,
            description: row.sampleDescription,
            type: actualSkill.type,
            category: actualSkill.category,
            effects: effects
        )
    }

    private func parseExpectedParameters(
        _ paramValues: [String: String],
        statScale: [String: String],
        skillId: UInt16
    ) throws -> [EffectParamKey: Int] {
        var params: [EffectParamKey: Int] = [:]
        for (key, rawValue) in paramValues {
            let resolvedKey = resolveEffectParamKey(expectedKey: key)
            guard let resolvedKey else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId) paramキー不明: \(key)")
            }
            guard let parsedValue = parseParamRawValue(expectedKey: key, rawValue: rawValue) else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId) param値不明: \(key)=\(rawValue)")
            }
            params[resolvedKey] = parsedValue
        }

        if let stat = statScale["stat"] {
            if let baseStat = BaseStat(identifier: stat) {
                params[.scalingStat] = Int(baseStat.rawValue)
            } else if let parsed = Int(stat) {
                params[.scalingStat] = parsed
            } else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId) statScale.stat不明: \(stat)")
            }
        }

        return params
    }

    private func parseExpectedValues(
        _ valueValues: [String: String],
        statScale: [String: String],
        skillId: UInt16
    ) throws -> [EffectValueKey: Double] {
        var values: [EffectValueKey: Double] = [:]
        for (key, rawValue) in valueValues {
            let resolvedKey = resolveEffectValueKey(expectedKey: key)
            guard let resolvedKey else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId) valueキー不明: \(key)")
            }
            guard let parsedValue = parseValueRawValue(rawValue) else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId) value値不明: \(key)=\(rawValue)")
            }
            values[resolvedKey] = parsedValue
        }

        if let percent = statScale["percent"] {
            guard let parsed = parseValueRawValue(percent) else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId) statScale.percent不明: \(percent)")
            }
            values[.scalingCoefficient] = parsed
        }

        return values
    }

    private func parseExpectedArrays(
        _ arrayValues: [String: [Int]],
        skillId: UInt16
    ) throws -> [EffectArrayKey: [Int]] {
        var arrays: [EffectArrayKey: [Int]] = [:]
        for (key, values) in arrayValues {
            guard let resolvedKey = resolveEffectArrayKey(expectedKey: key) else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId) arrayキー不明: \(key)")
            }
            arrays[resolvedKey] = values.sorted()
        }
        return arrays
    }

    private func resolveEffectParamKey(expectedKey: String) -> EffectParamKey? {
        if let key = EffectParamKey.allCases.first(where: { String(describing: $0) == expectedKey }) {
            return key
        }
        if expectedKey == "statusType" { return .status }
        if expectedKey == "status" { return .statusType }
        if expectedKey == "equipmentType" { return .equipmentCategory }
        if expectedKey == "equipmentCategory" { return .equipmentType }
        return nil
    }

    private func resolveEffectValueKey(expectedKey: String) -> EffectValueKey? {
        EffectValueKey.allCases.first { String(describing: $0) == expectedKey }
    }

    private func resolveEffectArrayKey(expectedKey: String) -> EffectArrayKey? {
        EffectArrayKey.allCases.first { String(describing: $0) == expectedKey }
    }

    private func parseParamRawValue(expectedKey: String, rawValue: String) -> Int? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        if trimmed == "true" { return 1 }
        if trimmed == "false" { return 0 }
        if let intValue = Int(trimmed) { return intValue }

        switch expectedKey {
        case "damageType":
            return lookupRawValue(Self.damageTypeByRaw, identifier: trimmed)
        case "stat", "sourceStat", "targetStat", "statType":
            if trimmed == "all" { return 99 }
            if let combat = CombatStat(identifier: trimmed) { return Int(combat.rawValue) }
            if let base = BaseStat(identifier: trimmed) { return Int(base.rawValue) }
            return nil
        case "scalingStat":
            if let base = BaseStat(identifier: trimmed) { return Int(base.rawValue) }
            return nil
        case "equipmentCategory", "equipmentType":
            if trimmed == "dagger" { return 25 }
            if let category = ItemSaleCategory(identifier: trimmed) { return Int(category.rawValue) }
            return lookupRawValue(Self.itemCategoryByRaw, identifier: trimmed)
        case "school":
            if let school = SpellDefinition.School(identifier: trimmed) { return Int(school.rawValue) }
            return nil
        case "profile":
            if let profile = BattleActor.SkillEffects.RowProfile.Base(identifier: trimmed) { return Int(profile.rawValue) }
            return nil
        case "action":
            return lookupRawValue(Self.effectActionByRaw, identifier: trimmed)
        case "mode":
            return lookupRawValue(Self.effectModeByRaw, identifier: trimmed)
        case "stacking":
            return lookupRawValue(Self.stackingByRaw, identifier: trimmed)
        case "target":
            return lookupRawValue(Self.targetByRaw, identifier: trimmed)
        case "trigger":
            return lookupRawValue(Self.triggerByRaw, identifier: trimmed)
        case "condition":
            return lookupRawValue(Self.conditionByRaw, identifier: trimmed)
        case "type", "variant":
            return lookupRawValue(Self.effectVariantByRaw, identifier: trimmed)
        case "hpScale":
            if let scale = BattleActor.SkillEffects.ResurrectionActive.HPScale(identifier: trimmed) {
                return Int(scale.rawValue)
            }
            return nil
        case "targetStatus", "statusType", "status":
            return lookupRawValue(Self.statusTypeByRaw, identifier: trimmed) ?? Int(trimmed)
        case "targetId":
            return lookupRawValue(Self.targetIdByRaw, identifier: trimmed) ?? Int(trimmed)
        case "specialAttackId":
            return lookupRawValue(Self.specialAttackByRaw, identifier: trimmed) ?? Int(trimmed)
        default:
            return Int(trimmed)
        }
    }

    private func parseValueRawValue(_ rawValue: String) -> Double? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        if trimmed == "true" { return 1.0 }
        if trimmed == "false" { return 0.0 }
        return Double(trimmed)
    }

    private func lookupRawValue(_ map: [Int: String], identifier: String) -> Int? {
        map.first { $0.value == identifier }?.key
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

    // MARK: - Activation Alignment

    private struct ActivationProbe: Sendable {
        let label: String
        let expected: Int
        let actual: Int
    }

    private static let activationEffectTypes: Set<SkillEffectType> = [
        .extraAction,
        .reaction,
        .parry,
        .shieldBlock,
        .berserk,
        .statusInflict,
        .magicNullifyChancePercent,
        .magicCriticalChancePercent,
        .spellChargeRecoveryChance,
        .specialAttack,
        .enemyActionDebuffChance,
        .enemySingleActionSkipChance,
        .timedBuffTrigger,
        .tacticSpellAmplify,
        .timedMagicPowerAmplify,
        .timedBreathPowerAmplify,
        .runawayMagic,
        .runawayDamage,
        .retreatAtTurn,
        .resurrectionActive,
        .resurrectionSave,
        .autoStatusCureOnAlly
    ]

    private func parseFamilyParameters(_ raw: String) -> [String: String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }
        let pairs = trimmed.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        var result: [String: String] = [:]
        for pair in pairs {
            guard !pair.isEmpty else { continue }
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            result[String(parts[0])] = String(parts[1])
        }
        return result
    }

    private func mergeParameters(family: [String: String], segment: ExpectedEffectSegment) -> [String: String] {
        var merged = family
        for (key, value) in segment.paramValues {
            merged[key] = value
        }
        return merged
    }

    private func computeProcChanceMultiplier(from segments: [ExpectedEffectSegment]) -> Double {
        var multiplier = 1.0
        for segment in segments where segment.effectType == SkillEffectType.procMultiplier.identifier {
            guard let raw = segment.valueValues["multiplier"],
                  let value = parseValueRawValue(raw) else { continue }
            multiplier *= value
        }
        return multiplier
    }

    @MainActor
    private func compileActorEffects(skill: SkillDefinition, stats: ActorStats) throws -> BattleActor.SkillEffects {
        let compiler = try UnifiedSkillEffectCompiler(skills: [skill], stats: stats)
        return compiler.actorEffects
    }

    private func doubleValue(_ key: String, in values: [String: String]) -> Double? {
        guard let raw = values[key] else { return nil }
        return parseValueRawValue(raw)
    }

    private func intValue(
        _ key: String,
        in values: [String: String],
        rounding: FloatingPointRoundingRule = .towardZero
    ) -> Int? {
        guard let value = doubleValue(key, in: values) else { return nil }
        return Int(value.rounded(rounding))
    }

    private func boolParam(_ key: String, in params: [String: String]) -> Bool {
        guard let raw = params[key]?.lowercased() else { return false }
        return raw == "true" || raw == "1"
    }

    private func scaledValue(from segment: ExpectedEffectSegment, stats: ActorStats) throws -> Double {
        guard let statKey = segment.statScaleValues["stat"],
              let percentRaw = segment.statScaleValues["percent"] else {
            return 0.0
        }
        guard let coefficient = parseValueRawValue(percentRaw) else {
            throw RuntimeError.invalidConfiguration(reason: "statScale.percent 不正: \(percentRaw)")
        }
        guard let statValue = resolveBaseStatValue(statKey, stats: stats) else {
            throw RuntimeError.invalidConfiguration(reason: "statScale.stat 不正: \(statKey)")
        }
        return Double(statValue) * coefficient
    }

    private func resolvedChancePercent(from segment: ExpectedEffectSegment, stats: ActorStats) throws -> Double? {
        if let chance = doubleValue("chancePercent", in: segment.valueValues) {
            return chance
        }
        if let coefficient = doubleValue("baseChancePercent", in: segment.valueValues) {
            guard let statKey = segment.paramValues["scalingStat"] else {
                throw RuntimeError.invalidConfiguration(reason: "scalingStat がありません")
            }
            guard let statValue = resolveBaseStatValue(statKey, stats: stats) else {
                throw RuntimeError.invalidConfiguration(reason: "scalingStat 不正: \(statKey)")
            }
            return Double(statValue) * coefficient
        }
        return nil
    }

    private func resolveBaseStatValue(_ raw: String, stats: ActorStats) -> Int? {
        if let base = BaseStat(identifier: raw) {
            return stats.value(for: Int(base.rawValue))
        }
        if let parsed = Int(raw) {
            return stats.value(for: parsed)
        }
        return nil
    }

    private func clampProbability(_ probability: Double) -> Double {
        max(0.0, min(1.0, probability))
    }

    private func expectedBool(probability: Double) -> Bool {
        clampProbability(probability) >= 0.5
    }

    private func expectedBool(percentChance: Int) -> Bool {
        percentChance >= 50
    }

    private func probe(label: String, expected: Int, actual: Int) -> ActivationProbe {
        ActivationProbe(label: label, expected: expected, actual: actual)
    }

    private func probe(label: String, expected: Bool, actual: Bool) -> ActivationProbe {
        ActivationProbe(label: label, expected: expected ? 1 : 0, actual: actual ? 1 : 0)
    }

    @MainActor
    private func makeSnapshot(
        maxHP: Int = 10000,
        physicalAttackScore: Int = 1000,
        magicalAttackScore: Int = 1000,
        physicalDefenseScore: Int = 500,
        magicalDefenseScore: Int = 500,
        hitScore: Int = 100,
        evasionScore: Int = 0,
        criticalChancePercent: Int = 0,
        attackCount: Double = 1.0,
        magicalHealingScore: Int = 500,
        additionalDamageScore: Int = 0,
        breathDamageScore: Int = 0,
        isMartialEligible: Bool = false
    ) -> CharacterValues.Combat {
        CharacterValues.Combat(
            maxHP: maxHP,
            physicalAttackScore: physicalAttackScore,
            magicalAttackScore: magicalAttackScore,
            physicalDefenseScore: physicalDefenseScore,
            magicalDefenseScore: magicalDefenseScore,
            hitScore: hitScore,
            evasionScore: evasionScore,
            criticalChancePercent: criticalChancePercent,
            attackCount: attackCount,
            magicalHealingScore: magicalHealingScore,
            trapRemovalScore: 0,
            additionalDamageScore: additionalDamageScore,
            breathDamageScore: breathDamageScore,
            isMartialEligible: isMartialEligible
        )
    }

    @MainActor
    private func makeActor(
        identifier: String,
        displayName: String,
        kind: BattleActorKind,
        formationSlot: BattleFormationSlot,
        stats: ActorStats,
        snapshot: CharacterValues.Combat,
        currentHP: Int? = nil,
        actionRates: BattleActionRates = BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
        actionResources: BattleActionResource = BattleActionResource(),
        skillEffects: BattleActor.SkillEffects,
        partyMemberId: UInt8? = nil,
        level: Int? = nil,
        enemyMasterIndex: UInt16? = nil,
        spellbook: SkillRuntimeEffects.Spellbook = .empty,
        spells: SkillRuntimeEffects.SpellLoadout = .empty
    ) -> BattleActor {
        BattleActor(
            identifier: identifier,
            displayName: displayName,
            kind: kind,
            formationSlot: formationSlot,
            strength: stats.strength,
            wisdom: stats.wisdom,
            spirit: stats.spirit,
            vitality: stats.vitality,
            agility: stats.agility,
            luck: stats.luck,
            partyMemberId: partyMemberId,
            level: level,
            jobName: nil,
            avatarIndex: nil,
            isMartialEligible: snapshot.isMartialEligible,
            raceId: nil,
            enemyMasterIndex: enemyMasterIndex,
            snapshot: snapshot,
            currentHP: currentHP ?? snapshot.maxHP,
            actionRates: actionRates,
            actionResources: actionResources,
            skillEffects: skillEffects,
            spellbook: spellbook,
            spells: spells
        )
    }

    @MainActor
    private func makeContext(
        players: [BattleActor],
        enemies: [BattleActor],
        statusDefinitions: [UInt8: StatusEffectDefinition]
    ) -> BattleContext {
        BattleContext(
            players: players,
            enemies: enemies,
            statusDefinitions: statusDefinitions,
            skillDefinitions: [:],
            random: GameRandomSource()
        )
    }

    private func countActionEntries(
        _ entries: [BattleActionEntry],
        actorId: UInt16,
        turn: Int? = nil
    ) -> Int {
        entries.filter { entry in
            if let turn {
                guard entry.turn == UInt8(clamping: turn) else { return false }
            }
            return entry.actor == actorId
        }.count
    }

    private func countEffects(
        _ entries: [BattleActionEntry],
        kind: BattleActionEntry.Effect.Kind,
        actorId: UInt16? = nil,
        turn: Int? = nil
    ) -> Int {
        entries.filter { entry in
            if let actorId {
                guard entry.actor == actorId else { return false }
            }
            if let turn {
                guard entry.turn == UInt8(clamping: turn) else { return false }
            }
            return entry.effects.contains { $0.kind == kind }
        }.count
    }

    @MainActor
    private func makeTestSpell(id: UInt8,
                               school: SpellDefinition.School,
                               category: SpellDefinition.Category) -> SpellDefinition {
        let targeting: SpellDefinition.Targeting = category == .healing ? .singleAlly : .singleEnemy
        return SpellDefinition(
            id: id,
            name: "TestSpell-\(id)",
            school: school,
            tier: 1,
            unlockLevel: 1,
            category: category,
            targeting: targeting,
            maxTargetsBase: 1,
            extraTargetsPerLevels: nil,
            hitsPerCast: 1,
            basePowerMultiplier: category == .damage ? 1.0 : nil,
            statusId: nil,
            buffs: [],
            healMultiplier: category == .healing ? 1.0 : nil,
            healPercentOfMaxHP: nil,
            castCondition: nil,
            description: "test"
        )
    }

    @MainActor
    private func makeTestSpellLoadout() -> SkillRuntimeEffects.SpellLoadout {
        let mage = makeTestSpell(id: 1, school: .mage, category: .damage)
        let priest = makeTestSpell(id: 2, school: .priest, category: .healing)
        return SkillRuntimeEffects.SpellLoadout(mage: [mage], priest: [priest])
    }

    @MainActor
    private func makeSpellResource(loadout: SkillRuntimeEffects.SpellLoadout, current: Int, max: Int) -> BattleActionResource {
        var resource = BattleActionResource()
        for spell in loadout.mage {
            resource.setSpellCharges(for: spell.id, current: current, max: max)
        }
        for spell in loadout.priest {
            resource.setSpellCharges(for: spell.id, current: current, max: max)
        }
        return resource
    }

    @MainActor
    private func activationProbes(
        effectType: SkillEffectType,
        segment: ExpectedEffectSegment,
        mergedParams: [String: String],
        actualEffects: BattleActor.SkillEffects,
        actorStats: ActorStats,
        procChanceMultiplier: Double,
        statusDefinitions: [UInt8: StatusEffectDefinition]
    ) throws -> [ActivationProbe] {
        switch effectType {
        case .extraAction:
            let chance = try resolvedChancePercent(from: segment, stats: actorStats) ?? 100.0
            let count = intValue("count", in: segment.valueValues) ?? 1
            let duration = intValue("duration", in: segment.valueValues)
            let triggerKey = mergedParams["trigger"] ?? "always"

            enum TriggerKind {
                case always
                case battleStart
                case afterTurn8
            }

            let trigger: TriggerKind
            switch triggerKey {
            case "battleStart":
                trigger = .battleStart
            case "afterTurn8":
                trigger = .afterTurn8
            default:
                trigger = .always
            }

            func expectedExtraActions(at turn: Int) -> Int {
                guard count > 0 else { return 0 }
                let matchesTrigger: Bool
                let startTurn: Int
                switch trigger {
                case .always:
                    matchesTrigger = true
                    startTurn = 1
                case .battleStart:
                    matchesTrigger = (turn == 1)
                    startTurn = 1
                case .afterTurn8:
                    matchesTrigger = (turn >= 8)
                    startTurn = 8
                }
                guard matchesTrigger else { return 0 }
                if let duration {
                    guard turn < startTurn + duration else { return 0 }
                }
                let probability = clampProbability((chance * procChanceMultiplier) / 100.0)
                return expectedBool(probability: probability) ? count : 0
            }

            func actualExtraActions(at turn: Int) -> Int {
                let snapshot = makeSnapshot(maxHP: 100000, physicalAttackScore: 10, physicalDefenseScore: 1000)
                let player = makeActor(
                    identifier: "extra.player",
                    displayName: "Extra Player",
                    kind: .player,
                    formationSlot: 1,
                    stats: actorStats,
                    snapshot: snapshot,
                    skillEffects: actualEffects,
                    partyMemberId: 1
                )
                let enemySnapshot = makeSnapshot(maxHP: 100000, physicalAttackScore: 1, physicalDefenseScore: 1000)
                let enemy = makeActor(
                    identifier: "extra.enemy",
                    displayName: "Extra Enemy",
                    kind: .enemy,
                    formationSlot: 1,
                    stats: actorStats,
                    snapshot: enemySnapshot,
                    skillEffects: .neutral,
                    enemyMasterIndex: 0
                )
                var context = makeContext(players: [player], enemies: [enemy], statusDefinitions: statusDefinitions)
                context.turn = turn
                let forcedTargets = BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)
                BattleTurnEngine.performAction(for: .player, actorIndex: 0, context: &context, forcedTargets: forcedTargets)
                let actorId = context.actorIndex(for: .player, arrayIndex: 0)
                let total = countActionEntries(context.actionEntries, actorId: actorId)
                return max(0, total - 1)
            }

            let turns: [Int]
            switch trigger {
            case .battleStart:
                turns = [1, 2]
            case .afterTurn8:
                turns = [7, 8]
            case .always:
                turns = [1, 2]
            }

            return turns.map { turn in
                let expected = expectedExtraActions(at: turn)
                let actual = actualExtraActions(at: turn)
                return probe(label: "extraAction.turn\(turn)", expected: expected, actual: actual)
            }

        case .reaction:
            guard let triggerKey = mergedParams["trigger"] else {
                return [probe(label: "reaction.trigger.missing", expected: 1, actual: 0)]
            }

            func makeEvent(allyIndex: Int) -> BattleContext.ReactionEvent? {
                switch triggerKey {
                case "allyDefeated":
                    return .allyDefeated(side: .player, fallenIndex: allyIndex, killer: .enemy(0))
                case "selfEvadePhysical":
                    return .selfEvadePhysical(side: .player, actorIndex: 0, attacker: .enemy(0))
                case "selfDamagedPhysical":
                    return .selfDamagedPhysical(side: .player, actorIndex: 0, attacker: .enemy(0))
                case "selfDamagedMagical":
                    return .selfDamagedMagical(side: .player, actorIndex: 0, attacker: .enemy(0))
                case "allyDamagedPhysical":
                    return .allyDamagedPhysical(side: .player, defenderIndex: allyIndex, attacker: .enemy(0))
                case "selfKilledEnemy":
                    return .selfKilledEnemy(side: .player, actorIndex: 0, killedEnemy: .enemy(0))
                case "allyMagicAttack":
                    return .allyMagicAttack(side: .player, casterIndex: allyIndex)
                case "selfAttackNoKill":
                    return .selfAttackNoKill(side: .player, actorIndex: 0, target: .enemy(0))
                case "selfMagicAttack":
                    return .selfMagicAttack(side: .player, casterIndex: 0)
                default:
                    return nil
                }
            }

            let chance = try resolvedChancePercent(from: segment, stats: actorStats) ?? 100.0
            let rawChance = chance * procChanceMultiplier
            let cappedChance = max(0, min(100, Int(floor(rawChance))))
            let expectedTrigger = expectedBool(percentChance: cappedChance)
            let requiresMartial = boolParam("requiresMartial", in: mergedParams)
            let requiresAllyBehind = boolParam("requiresAllyBehind", in: mergedParams)

            func reactionTriggered(martialEligible: Bool, allyBehind: Bool) -> Bool {
                let performerSlot: BattleFormationSlot = allyBehind ? 1 : 5
                let allySlot: BattleFormationSlot = allyBehind ? 5 : 1
                let snapshot = makeSnapshot(physicalAttackScore: 1000,
                                            physicalDefenseScore: 1000,
                                            isMartialEligible: martialEligible)
                let performer = makeActor(
                    identifier: "reaction.actor",
                    displayName: "Reaction Actor",
                    kind: .player,
                    formationSlot: performerSlot,
                    stats: actorStats,
                    snapshot: snapshot,
                    skillEffects: actualEffects,
                    partyMemberId: 1
                )
                let allySnapshot = makeSnapshot(maxHP: 10000, physicalDefenseScore: 1000)
                let ally = makeActor(
                    identifier: "reaction.ally",
                    displayName: "Reaction Ally",
                    kind: .player,
                    formationSlot: allySlot,
                    stats: actorStats,
                    snapshot: allySnapshot,
                    skillEffects: .neutral,
                    partyMemberId: 2
                )
                let enemySnapshot = makeSnapshot(maxHP: 10000, physicalAttackScore: 1000, physicalDefenseScore: 500)
                let enemy = makeActor(
                    identifier: "reaction.enemy",
                    displayName: "Reaction Enemy",
                    kind: .enemy,
                    formationSlot: 1,
                    stats: actorStats,
                    snapshot: enemySnapshot,
                    skillEffects: .neutral,
                    enemyMasterIndex: 0
                )
                var context = makeContext(players: [performer, ally], enemies: [enemy], statusDefinitions: statusDefinitions)
                guard let event = makeEvent(allyIndex: 1) else { return false }
                BattleTurnEngine.dispatchReactions(for: event, depth: 0, context: &context)
                return countEffects(context.actionEntries, kind: .reactionAttack) > 0
            }

            var probes: [ActivationProbe] = []
            if makeEvent(allyIndex: 1) == nil {
                probes.append(probe(label: "reaction.trigger.unsupported.\(triggerKey)", expected: 1, actual: 0))
                return probes
            }

            let martialEligible = requiresMartial ? true : false
            let allyBehind = requiresAllyBehind ? true : false
            let actualTriggered = reactionTriggered(martialEligible: martialEligible, allyBehind: allyBehind)
            probes.append(probe(label: "reaction.trigger.\(triggerKey)", expected: expectedTrigger, actual: actualTriggered))

            if requiresMartial {
                let actualNotMartial = reactionTriggered(martialEligible: false, allyBehind: allyBehind)
                probes.append(probe(label: "reaction.requiresMartial", expected: false, actual: actualNotMartial))
            }

            if requiresAllyBehind, triggerKey == "allyDamagedPhysical" {
                let actualNoBehind = reactionTriggered(martialEligible: martialEligible, allyBehind: false)
                probes.append(probe(label: "reaction.requiresAllyBehind", expected: false, actual: actualNoBehind))
            }

            return probes

        case .parry:
            let defenderBonus = Double(10) * 0.25
            let attackerPenalty = Double(20) * 0.5
            let base = 10.0 + defenderBonus - attackerPenalty + actualEffects.combat.parryBonusPercent
            let chance = max(0, min(100, Int((base * procChanceMultiplier).rounded())))
            let expected = expectedBool(percentChance: chance)

            let defenderSnapshot = makeSnapshot(additionalDamageScore: 10)
            let defender = makeActor(
                identifier: "parry.defender",
                displayName: "Parry Defender",
                kind: .player,
                formationSlot: 1,
                stats: actorStats,
                snapshot: defenderSnapshot,
                skillEffects: actualEffects,
                partyMemberId: 1
            )
            let attackerSnapshot = makeSnapshot(additionalDamageScore: 20)
            let attacker = makeActor(
                identifier: "parry.attacker",
                displayName: "Parry Attacker",
                kind: .enemy,
                formationSlot: 1,
                stats: actorStats,
                snapshot: attackerSnapshot,
                skillEffects: .neutral,
                enemyMasterIndex: 0
            )
            var context = makeContext(players: [defender], enemies: [attacker], statusDefinitions: statusDefinitions)
            var mutableDefender = defender
            let actual = BattleTurnEngine.shouldTriggerParry(defender: &mutableDefender, attacker: attacker, context: &context)
            return [probe(label: "parry", expected: expected, actual: actual)]

        case .shieldBlock:
            let attackerPenalty = Double(20) / 2.0
            let base = 30.0 - attackerPenalty + actualEffects.combat.shieldBlockBonusPercent
            let chance = max(0, min(100, Int((base * procChanceMultiplier).rounded())))
            let expected = expectedBool(percentChance: chance)

            let defenderSnapshot = makeSnapshot(additionalDamageScore: 10)
            let defender = makeActor(
                identifier: "shield.defender",
                displayName: "Shield Defender",
                kind: .player,
                formationSlot: 1,
                stats: actorStats,
                snapshot: defenderSnapshot,
                skillEffects: actualEffects,
                partyMemberId: 1
            )
            let attackerSnapshot = makeSnapshot(additionalDamageScore: 20)
            let attacker = makeActor(
                identifier: "shield.attacker",
                displayName: "Shield Attacker",
                kind: .enemy,
                formationSlot: 1,
                stats: actorStats,
                snapshot: attackerSnapshot,
                skillEffects: .neutral,
                enemyMasterIndex: 0
            )
            var context = makeContext(players: [defender], enemies: [attacker], statusDefinitions: statusDefinitions)
            var mutableDefender = defender
            let actual = BattleTurnEngine.shouldTriggerShieldBlock(defender: &mutableDefender, attacker: attacker, context: &context)
            return [probe(label: "shieldBlock", expected: expected, actual: actual)]

        case .berserk:
            let chanceValue = doubleValue("chancePercent", in: segment.valueValues) ?? 0.0
            let scaledChance = chanceValue * procChanceMultiplier
            let cappedChance = max(0, min(100, Int(scaledChance.rounded(.towardZero))))
            let expected = expectedBool(percentChance: cappedChance)
            let snapshot = makeSnapshot()
            var actor = makeActor(
                identifier: "berserk.actor",
                displayName: "Berserk Actor",
                kind: .player,
                formationSlot: 1,
                stats: actorStats,
                snapshot: snapshot,
                skillEffects: actualEffects,
                partyMemberId: 1
            )
            var context = makeContext(players: [actor], enemies: [], statusDefinitions: statusDefinitions)
            let actual = BattleTurnEngine.shouldTriggerBerserk(for: &actor, context: &context)
            return [probe(label: "berserk", expected: expected, actual: actual)]

        case .statusInflict:
            let statusId = intValue("statusId", in: segment.paramValues) ?? Int(mergedParams["statusId"] ?? "0") ?? 0
            var chance = try resolvedChancePercent(from: segment, stats: actorStats) ?? 0.0
            if statusId == Int(BattleTurnEngine.confusionStatusId) {
                let span: Double = 34.0
                let spiritDelta = Double(actorStats.spirit - 0)
                let normalized = max(0.0, min(1.0, (spiritDelta + span) / (span * 2.0)))
                chance *= normalized
            }
            chance *= procChanceMultiplier
            let expected = expectedBool(probability: chance / 100.0)

            let attackerSnapshot = makeSnapshot()
            let attacker = makeActor(
                identifier: "status.attacker",
                displayName: "Status Attacker",
                kind: .player,
                formationSlot: 1,
                stats: actorStats,
                snapshot: attackerSnapshot,
                skillEffects: actualEffects,
                partyMemberId: 1
            )
            let defenderSnapshot = makeSnapshot()
            let defenderStats = ActorStats(strength: 0, wisdom: 0, spirit: 0, vitality: 0, agility: 0, luck: 0)
            var defender = makeActor(
                identifier: "status.defender",
                displayName: "Status Defender",
                kind: .enemy,
                formationSlot: 1,
                stats: defenderStats,
                snapshot: defenderSnapshot,
                skillEffects: .neutral,
                enemyMasterIndex: 0
            )
            var context = makeContext(players: [attacker], enemies: [defender], statusDefinitions: statusDefinitions)
            BattleTurnEngine.attemptInflictStatuses(from: attacker, to: &defender, context: &context)
            let actual = defender.statusEffects.contains { $0.id == UInt8(clamping: statusId) }
            return [probe(label: "statusInflict", expected: expected, actual: actual)]

        case .magicNullifyChancePercent:
            let chance = max(0.0, min(100.0, try resolvedChancePercent(from: segment, stats: actorStats) ?? 0.0))
            let cappedChance = max(0, min(100, Int(chance.rounded())))
            let expected = expectedBool(percentChance: cappedChance)

            let attackerSnapshot = makeSnapshot(magicalAttackScore: 2000)
            let attacker = makeActor(
                identifier: "magic.attacker",
                displayName: "Magic Attacker",
                kind: .player,
                formationSlot: 1,
                stats: actorStats,
                snapshot: attackerSnapshot,
                skillEffects: .neutral,
                partyMemberId: 1
            )
            let defenderSnapshot = makeSnapshot(magicalDefenseScore: 200)
            var defender = makeActor(
                identifier: "magic.defender",
                displayName: "Magic Defender",
                kind: .enemy,
                formationSlot: 1,
                stats: actorStats,
                snapshot: defenderSnapshot,
                skillEffects: actualEffects,
                enemyMasterIndex: 0
            )
            var context = makeContext(players: [attacker], enemies: [defender], statusDefinitions: statusDefinitions)
            let damage = BattleTurnEngine.computeMagicalDamage(attacker: attacker, defender: &defender, spellId: nil, context: &context)
            let actual = (damage == 0)
            return [probe(label: "magicNullify", expected: expected, actual: actual)]

        case .magicCriticalChancePercent:
            let chance = max(0.0, min(100.0, try resolvedChancePercent(from: segment, stats: actorStats) ?? 0.0))
            let cappedChance = max(0, min(100, Int(chance.rounded())))
            let expected = expectedBool(percentChance: cappedChance)

            let attackerSnapshot = makeSnapshot(magicalAttackScore: 2000)
            let attacker = makeActor(
                identifier: "crit.attacker",
                displayName: "Crit Attacker",
                kind: .player,
                formationSlot: 1,
                stats: actorStats,
                snapshot: attackerSnapshot,
                skillEffects: actualEffects,
                partyMemberId: 1
            )
            let defenderSnapshot = makeSnapshot(magicalDefenseScore: 200)
            var defender = makeActor(
                identifier: "crit.defender",
                displayName: "Crit Defender",
                kind: .enemy,
                formationSlot: 1,
                stats: actorStats,
                snapshot: defenderSnapshot,
                skillEffects: .neutral,
                enemyMasterIndex: 0
            )
            var contextWithCrit = makeContext(players: [attacker], enemies: [defender], statusDefinitions: statusDefinitions)
            let damageWithCrit = BattleTurnEngine.computeMagicalDamage(attacker: attacker, defender: &defender, spellId: nil, context: &contextWithCrit)

            var noCritEffects = actualEffects
            noCritEffects.spell.magicCriticalChancePercent = 0
            let noCritAttacker = makeActor(
                identifier: "crit.base.attacker",
                displayName: "Crit Base Attacker",
                kind: .player,
                formationSlot: 1,
                stats: actorStats,
                snapshot: attackerSnapshot,
                skillEffects: noCritEffects,
                partyMemberId: 1
            )
            var baseDefender = makeActor(
                identifier: "crit.base.defender",
                displayName: "Crit Base Defender",
                kind: .enemy,
                formationSlot: 1,
                stats: actorStats,
                snapshot: defenderSnapshot,
                skillEffects: .neutral,
                enemyMasterIndex: 0
            )
            var contextBase = makeContext(players: [noCritAttacker], enemies: [baseDefender], statusDefinitions: statusDefinitions)
            let damageWithoutCrit = BattleTurnEngine.computeMagicalDamage(attacker: noCritAttacker, defender: &baseDefender, spellId: nil, context: &contextBase)

            let actual = damageWithCrit > damageWithoutCrit
            return [probe(label: "magicCritical", expected: expected, actual: actual)]

        case .spellChargeRecoveryChance:
            let chance = max(0.0, min(100.0, try resolvedChancePercent(from: segment, stats: actorStats) ?? 0.0))
            let expected = expectedBool(probability: chance / 100.0)

            let loadout = makeTestSpellLoadout()
            let resource = makeSpellResource(loadout: loadout, current: 0, max: 1)
            let snapshot = makeSnapshot(magicalHealingScore: 500)
            let actor = makeActor(
                identifier: "charge.actor",
                displayName: "Charge Actor",
                kind: .player,
                formationSlot: 1,
                stats: actorStats,
                snapshot: snapshot,
                actionResources: resource,
                skillEffects: actualEffects,
                partyMemberId: 1,
                spells: loadout
            )
            var context = makeContext(players: [actor], enemies: [], statusDefinitions: statusDefinitions)
            BattleTurnEngine.applySpellChargeRecovery(&context)
            let actorId = context.actorIndex(for: .player, arrayIndex: 0)
            let actual = countEffects(context.actionEntries, kind: .spellChargeRecover, actorId: actorId) > 0
            return [probe(label: "spellChargeRecovery", expected: expected, actual: actual)]

        case .specialAttack:
            let baseChance = try resolvedChancePercent(from: segment, stats: actorStats).map { Int($0.rounded(.towardZero)) } ?? 50
            let cappedChance = max(0, min(100, baseChance))
            let expected = expectedBool(percentChance: cappedChance)
            let isPreemptive = mergedParams["mode"] == "preemptive"

            let snapshot = makeSnapshot(physicalAttackScore: 1000, physicalDefenseScore: 1000)
            let attacker = makeActor(
                identifier: "special.actor",
                displayName: "Special Actor",
                kind: .player,
                formationSlot: 1,
                stats: actorStats,
                snapshot: snapshot,
                skillEffects: actualEffects,
                partyMemberId: 1
            )
            let enemySnapshot = makeSnapshot(maxHP: 1000, physicalDefenseScore: 100)
            let enemy = makeActor(
                identifier: "special.enemy",
                displayName: "Special Enemy",
                kind: .enemy,
                formationSlot: 1,
                stats: actorStats,
                snapshot: enemySnapshot,
                skillEffects: .neutral,
                enemyMasterIndex: 0
            )
            var context = makeContext(players: [attacker], enemies: [enemy], statusDefinitions: statusDefinitions)

            if isPreemptive {
                BattleTurnEngine.executePreemptiveAttacks(&context)
                let actorId = context.actorIndex(for: .player, arrayIndex: 0)
                let actual = countActionEntries(context.actionEntries, actorId: actorId) > 0
                return [probe(label: "specialAttack.preemptive", expected: expected, actual: actual)]
            } else {
                let actual = BattleTurnEngine.selectSpecialAttack(for: attacker, context: &context) != nil
                return [probe(label: "specialAttack.normal", expected: expected, actual: actual)]
            }

        case .enemyActionDebuffChance:
            let chance = max(0.0, min(100.0, try resolvedChancePercent(from: segment, stats: actorStats) ?? 0.0))
            let expectedTriggered = expectedBool(probability: chance / 100.0)
            let reduction = intValue("reduction", in: segment.valueValues) ?? 1

            var enemyEffects = BattleActor.SkillEffects.neutral
            enemyEffects.combat.nextTurnExtraActions = 1
            let playerSnapshot = makeSnapshot(maxHP: 10000, physicalAttackScore: 1, physicalDefenseScore: 1000)
            let player = makeActor(
                identifier: "debuff.player",
                displayName: "Debuff Player",
                kind: .player,
                formationSlot: 1,
                stats: actorStats,
                snapshot: playerSnapshot,
                actionRates: BattleActionRates(attack: 0, priestMagic: 0, mageMagic: 0, breath: 0),
                skillEffects: actualEffects,
                partyMemberId: 1
            )
            let enemySnapshot = makeSnapshot(maxHP: 10000, physicalAttackScore: 1, physicalDefenseScore: 1000)
            let enemy = makeActor(
                identifier: "debuff.enemy",
                displayName: "Debuff Enemy",
                kind: .enemy,
                formationSlot: 1,
                stats: actorStats,
                snapshot: enemySnapshot,
                actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
                skillEffects: enemyEffects,
                enemyMasterIndex: 0
            )
            var players = [player]
            var enemies = [enemy]
            var random = GameRandomSource()
            let result = BattleTurnEngine.runBattle(
                players: &players,
                enemies: &enemies,
                statusEffects: statusDefinitions,
                skillDefinitions: [:],
                random: &random
            )
            let enemyActorId = UInt16(1_000)
            let actualCount = countActionEntries(result.battleLog.entries, actorId: enemyActorId, turn: 1)
            let baseSlots = max(1, 1 + enemyEffects.combat.nextTurnExtraActions)
            let expectedSlots = max(1, baseSlots - (expectedTriggered ? reduction : 0))
            return [probe(label: "enemyActionDebuff", expected: expectedSlots, actual: actualCount)]

        case .enemySingleActionSkipChance:
            let baseChance = doubleValue("chancePercent", in: segment.valueValues) ?? 0.0
            let chance = max(0.0, min(100.0, baseChance))
            let expectedTriggered = expectedBool(probability: chance / 100.0)

            let playerSnapshot = makeSnapshot(maxHP: 10000, physicalAttackScore: 1, physicalDefenseScore: 1000)
            let player = makeActor(
                identifier: "skip.player",
                displayName: "Skip Player",
                kind: .player,
                formationSlot: 1,
                stats: actorStats,
                snapshot: playerSnapshot,
                actionRates: BattleActionRates(attack: 0, priestMagic: 0, mageMagic: 0, breath: 0),
                skillEffects: actualEffects,
                partyMemberId: 1
            )
            let enemySnapshot = makeSnapshot(maxHP: 10000, physicalAttackScore: 1, physicalDefenseScore: 1000)
            let enemy = makeActor(
                identifier: "skip.enemy",
                displayName: "Skip Enemy",
                kind: .enemy,
                formationSlot: 1,
                stats: actorStats,
                snapshot: enemySnapshot,
                actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
                skillEffects: .neutral,
                enemyMasterIndex: 0
            )
            var players = [player]
            var enemies = [enemy]
            var random = GameRandomSource()
            let result = BattleTurnEngine.runBattle(
                players: &players,
                enemies: &enemies,
                statusEffects: statusDefinitions,
                skillDefinitions: [:],
                random: &random
            )
            let enemyActorId = UInt16(1_000)
            let actualCount = countActionEntries(result.battleLog.entries, actorId: enemyActorId, turn: 1)
            let expectedCount = expectedTriggered ? 0 : 1
            return [probe(label: "enemySingleActionSkip", expected: expectedCount, actual: actualCount)]

        case .timedBuffTrigger:
            let triggerKey = mergedParams["trigger"] ?? "battleStart"
            let turns: [Int]
            switch triggerKey {
            case "turnElapsed":
                turns = [1, 2]
            default:
                turns = [1, 2]
            }

            func expectedForTurn(_ turn: Int) -> Int {
                switch triggerKey {
                case "turnElapsed":
                    return 1
                default:
                    return turn == 1 ? 1 : 0
                }
            }

            return turns.map { turn in
                let snapshot = makeSnapshot()
                let actor = makeActor(
                    identifier: "timed.actor",
                    displayName: "Timed Actor",
                    kind: .player,
                    formationSlot: 1,
                    stats: actorStats,
                    snapshot: snapshot,
                    skillEffects: actualEffects,
                    partyMemberId: 1
                )
                var context = makeContext(players: [actor], enemies: [], statusDefinitions: statusDefinitions)
                context.turn = turn
                BattleTurnEngine.applyTimedBuffTriggers(&context)
                let actorId = context.actorIndex(for: .player, arrayIndex: 0)
                let actual = countEffects(context.actionEntries, kind: .buffApply, actorId: actorId) > 0 ? 1 : 0
                let expected = expectedForTurn(turn)
                return probe(label: "timedBuff.turn\(turn)", expected: expected, actual: actual)
            }

        case .tacticSpellAmplify, .timedMagicPowerAmplify, .timedBreathPowerAmplify:
            guard let turnValue = doubleValue("triggerTurn", in: segment.valueValues) else {
                return [probe(label: "timedAmplify.triggerTurn.missing", expected: 1, actual: 0)]
            }
            let triggerTurn = max(1, Int(turnValue.rounded(.towardZero)))
            let otherTurn = triggerTurn == 1 ? 2 : 1

            func applyAndCount(turn: Int) -> Int {
                let snapshot = makeSnapshot()
                let actor = makeActor(
                    identifier: "amp.actor",
                    displayName: "Amplify Actor",
                    kind: .player,
                    formationSlot: 1,
                    stats: actorStats,
                    snapshot: snapshot,
                    skillEffects: actualEffects,
                    partyMemberId: 1
                )
                var context = makeContext(players: [actor], enemies: [], statusDefinitions: statusDefinitions)
                context.turn = turn
                BattleTurnEngine.applyTimedBuffTriggers(&context)
                let actorId = context.actorIndex(for: .player, arrayIndex: 0)
                return countEffects(context.actionEntries, kind: .buffApply, actorId: actorId) > 0 ? 1 : 0
            }

            let labelPrefix: String
            switch effectType {
            case .tacticSpellAmplify:
                labelPrefix = "tacticSpellAmplify"
            case .timedMagicPowerAmplify:
                labelPrefix = "timedMagicPowerAmplify"
            default:
                labelPrefix = "timedBreathPowerAmplify"
            }

            return [
                probe(label: "\(labelPrefix).turn\(triggerTurn)", expected: 1, actual: applyAndCount(turn: triggerTurn)),
                probe(label: "\(labelPrefix).turn\(otherTurn)", expected: 0, actual: applyAndCount(turn: otherTurn))
            ]

        case .runawayMagic, .runawayDamage:
            let chanceValue = doubleValue("chancePercent", in: segment.valueValues) ?? 0.0
            let threshold = doubleValue("thresholdPercent", in: segment.valueValues) ?? 0.0
            let chance = clampProbability((chanceValue * procChanceMultiplier) / 100.0)
            let expectedTriggered = expectedBool(probability: chance)
            let labelPrefix = effectType == .runawayMagic ? "runawayMagic" : "runawayDamage"

            func triggered(damage: Int) -> Bool {
                let snapshot = makeSnapshot(maxHP: 1000)
                let defender = makeActor(
                    identifier: "runaway.defender",
                    displayName: "Runaway Defender",
                    kind: .player,
                    formationSlot: 1,
                    stats: actorStats,
                    snapshot: snapshot,
                    skillEffects: actualEffects,
                    partyMemberId: 1
                )
                let allySnapshot = makeSnapshot(maxHP: 1000)
                let ally = makeActor(
                    identifier: "runaway.ally",
                    displayName: "Runaway Ally",
                    kind: .player,
                    formationSlot: 2,
                    stats: actorStats,
                    snapshot: allySnapshot,
                    skillEffects: .neutral,
                    partyMemberId: 2
                )
                var context = makeContext(players: [defender, ally], enemies: [], statusDefinitions: statusDefinitions)
                let actorId = context.actorIndex(for: .player, arrayIndex: 0)
                let entryBuilder = context.makeActionEntryBuilder(actorId: actorId, kind: .damageSelf)
                BattleTurnEngine.attemptRunawayIfNeeded(for: .player, defenderIndex: 0, damage: damage, context: &context, entryBuilder: entryBuilder)
                let entry = entryBuilder.build()
                return entry.effects.contains { $0.kind == .statusRampage }
            }

            let maxHP = 1000.0
            let thresholdDamage = Int((maxHP * threshold / 100.0).rounded(.towardZero))
            let above = max(1, thresholdDamage + 1)
            let below = max(0, thresholdDamage - 1)
            return [
                probe(label: "\(labelPrefix).aboveThreshold", expected: expectedTriggered, actual: triggered(damage: above)),
                probe(label: "\(labelPrefix).belowThreshold", expected: false, actual: triggered(damage: below))
            ]

        case .retreatAtTurn:
            let turnValue = doubleValue("turn", in: segment.valueValues)
            let chanceValue = doubleValue("chancePercent", in: segment.valueValues)
            let retreatTurn = turnValue.map { max(1, Int($0.rounded(.towardZero))) }
            let chance = chanceValue ?? 100.0
            let shouldTrigger = expectedBool(probability: chance / 100.0)
            let labelPrefix = "retreatAtTurn"

            func triggered(turn: Int) -> Bool {
                let snapshot = makeSnapshot(maxHP: 1000)
                let actor = makeActor(
                    identifier: "retreat.actor",
                    displayName: "Retreat Actor",
                    kind: .player,
                    formationSlot: 1,
                    stats: actorStats,
                    snapshot: snapshot,
                    skillEffects: actualEffects,
                    partyMemberId: 1
                )
                var context = makeContext(players: [actor], enemies: [], statusDefinitions: statusDefinitions)
                context.turn = turn
                BattleTurnEngine.applyRetreatIfNeeded(&context)
                let actorId = context.actorIndex(for: .player, arrayIndex: 0)
                return countEffects(context.actionEntries, kind: .withdraw, actorId: actorId) > 0
            }

            if let retreatTurn {
                let before = max(1, retreatTurn - 1)
                return [
                    probe(label: "\(labelPrefix).turn\(before)", expected: false, actual: triggered(turn: before)),
                    probe(label: "\(labelPrefix).turn\(retreatTurn)", expected: shouldTrigger, actual: triggered(turn: retreatTurn))
                ]
            } else {
                return [
                    probe(label: "\(labelPrefix).turn1", expected: shouldTrigger, actual: triggered(turn: 1))
                ]
            }

        case .resurrectionActive:
            let baseChance = doubleValue("chancePercent", in: segment.valueValues) ?? 0.0
            let cappedChance = max(0, min(100, Int(baseChance.rounded(.towardZero))))
            let expected = expectedBool(percentChance: cappedChance)
            let maxTriggers = intValue("maxTriggers", in: segment.valueValues)

            func triggered(used: Int) -> Bool {
                let snapshot = makeSnapshot(maxHP: 1000, magicalHealingScore: 100)
                var actor = makeActor(
                    identifier: "resurrect.actor",
                    displayName: "Resurrect Actor",
                    kind: .player,
                    formationSlot: 1,
                    stats: actorStats,
                    snapshot: snapshot,
                    currentHP: 0,
                    skillEffects: actualEffects,
                    partyMemberId: 1
                )
                actor.resurrectionTriggersUsed = used
                var context = makeContext(players: [actor], enemies: [], statusDefinitions: statusDefinitions)
                BattleTurnEngine.applyEndOfTurnResurrectionIfNeeded(for: .player, index: 0, actor: &actor, context: &context, allowVitalize: true)
                let actorId = context.actorIndex(for: .player, arrayIndex: 0)
                return countEffects(context.actionEntries, kind: .resurrection, actorId: actorId) > 0
            }

            var probes: [ActivationProbe] = []
            probes.append(probe(label: "resurrectionActive", expected: expected, actual: triggered(used: 0)))
            if let maxTriggers {
                probes.append(probe(label: "resurrectionActive.maxTriggers", expected: false, actual: triggered(used: maxTriggers)))
            }
            return probes

        case .resurrectionSave:
            let minLevel = intValue("minLevel", in: segment.valueValues) ?? 0
            let guaranteed = boolParam("guaranteed", in: segment.valueValues)
            let usesPriest = boolParam("usesPriestMagic", in: segment.valueValues)
            let chance = guaranteed ? 100 : 0
            let expected = expectedBool(percentChance: chance)

            func attemptRescue(level: Int) -> Bool {
                let loadout = makeTestSpellLoadout()
                let resource = makeSpellResource(loadout: loadout, current: 1, max: 1)
                let snapshot = makeSnapshot(maxHP: 1000, magicalHealingScore: 100)
                let rescuer = makeActor(
                    identifier: "rescue.actor",
                    displayName: "Rescue Actor",
                    kind: .player,
                    formationSlot: 1,
                    stats: actorStats,
                    snapshot: snapshot,
                    actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
                    actionResources: resource,
                    skillEffects: actualEffects,
                    partyMemberId: 1,
                    level: level,
                    spells: usesPriest ? loadout : .empty
                )
                let fallenSnapshot = makeSnapshot(maxHP: 1000, magicalHealingScore: 100)
                let fallen = makeActor(
                    identifier: "rescue.fallen",
                    displayName: "Rescue Fallen",
                    kind: .player,
                    formationSlot: 2,
                    stats: actorStats,
                    snapshot: fallenSnapshot,
                    currentHP: 0,
                    skillEffects: .neutral,
                    partyMemberId: 2,
                    level: 1
                )
                var context = makeContext(players: [rescuer, fallen], enemies: [], statusDefinitions: statusDefinitions)
                return BattleTurnEngine.attemptRescue(of: 1, side: .player, context: &context)
            }

            var probes: [ActivationProbe] = []
            probes.append(probe(label: "resurrectionSave", expected: expected, actual: attemptRescue(level: max(1, minLevel))))
            if minLevel > 0 {
                probes.append(probe(label: "resurrectionSave.minLevel", expected: false, actual: attemptRescue(level: max(0, minLevel - 1))))
            }
            return probes

        case .autoStatusCureOnAlly:
            let snapshot = makeSnapshot(maxHP: 1000)
            let curer = makeActor(
                identifier: "cure.actor",
                displayName: "Cure Actor",
                kind: .player,
                formationSlot: 1,
                stats: actorStats,
                snapshot: snapshot,
                skillEffects: actualEffects,
                partyMemberId: 1
            )
            var target = makeActor(
                identifier: "cure.target",
                displayName: "Cure Target",
                kind: .player,
                formationSlot: 2,
                stats: actorStats,
                snapshot: snapshot,
                skillEffects: .neutral,
                partyMemberId: 2
            )
            target.statusEffects = [AppliedStatusEffect(id: 1, remainingTurns: 3, source: "test", stackValue: 0.0)]
            var context = makeContext(players: [curer, target], enemies: [], statusDefinitions: statusDefinitions)
            BattleTurnEngine.applyAutoStatusCureIfNeeded(for: .player, targetIndex: 1, context: &context)
            let actorId = context.actorIndex(for: .player, arrayIndex: 1)
            let actual = countEffects(context.actionEntries, kind: .statusRecover, actorId: actorId) > 0
            return [probe(label: "autoStatusCureOnAlly", expected: true, actual: actual)]

        default:
            return []
        }
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

    private func loadSkillMasterFamilyIds() throws -> Set<String> {
        let url = try resolveSkillMasterJSONURL()
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = json as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var familyIds: Set<String> = []

        for (_, categoryValue) in root {
            guard let category = categoryValue as? [String: Any],
                  let families = category["families"] as? [[String: Any]] else {
                continue
            }

            for family in families {
                if let familyId = family["familyId"] as? String {
                    familyIds.insert(familyId)
                }
            }
        }

        return familyIds
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

    @MainActor
    private func loadStatusDefinitionsById() async throws -> [UInt8: StatusEffectDefinition] {
        let databaseURL = try resolveMasterDataURL()
        let manager = SQLiteMasterDataManager()
        try await manager.initialize(databaseURL: databaseURL)
        let cache = try await MasterDataLoader.load(manager: manager)
        return Dictionary(uniqueKeysWithValues: cache.allStatusEffects.map { ($0.id, $0) })
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
