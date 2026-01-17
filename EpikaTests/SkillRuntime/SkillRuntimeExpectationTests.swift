import XCTest
@testable import Epika

nonisolated final class SkillRuntimeExpectationTests: XCTestCase {
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

    @MainActor func testAllSkillRuntimeExpectations() async throws {
        let rows = try loadExpectationRows()
        let cache = try await loadMasterData()
        let skillsById = Dictionary(uniqueKeysWithValues: cache.allSkills.map { ($0.id, $0) })

        for row in rows {
            guard let skill = skillsById[row.sampleId] else {
                XCTFail("SkillDefinition not found for sampleId=\(row.sampleId)")
                continue
            }
            let result = try verifyRow(row, skill: skill, cache: cache)
            ObservationRecorder.shared.record(
                id: "SKILL-RUNTIME-\(row.sampleId)",
                expected: (min: 1, max: 1),
                measured: result.passed ? 1 : 0,
                rawData: result.rawData
            )
            XCTAssertTrue(result.passed, result.message)
        }
    }
}

// MARK: - Verification Core

private extension SkillRuntimeExpectationTests {
    struct VerificationResult {
        let passed: Bool
        let message: String
        let rawData: [String: Double]
    }

    func verifyRow(_ row: SkillExpectationRow, skill: SkillDefinition, cache: MasterDataCache) throws -> VerificationResult {
        let segments = parseEffectSegments(from: row.expectedEffectSummary, fallback: row.sampleEffects)
        var rawData: [String: Double] = [
            "sampleId": Double(row.sampleId),
            "segmentCount": Double(segments.count)
        ]

        do {
            for (index, segment) in segments.enumerated() {
                guard let effectType = SkillEffectType(identifier: segment.effectType) else {
                    throw VerificationError.failed("Unknown effectType '\(segment.effectType)' (sampleId=\(row.sampleId))")
                }
                try verifySegment(segment,
                                  effectType: effectType,
                                  row: row,
                                  skill: skill,
                                  cache: cache,
                                  rawData: &rawData,
                                  segmentIndex: index)
            }
        } catch {
            let message = (error as? VerificationError)?.message ?? "Verification failed for sampleId=\(row.sampleId): \(error)"
            return VerificationResult(passed: false, message: message, rawData: rawData)
        }

        return VerificationResult(passed: true,
                                  message: "Skill runtime verification failed (sampleId=\(row.sampleId))",
                                  rawData: rawData)
    }
}

// MARK: - Effect Verification

private extension SkillRuntimeExpectationTests {
    enum VerificationError: Error {
        case failed(String)

        var message: String {
            switch self {
            case .failed(let message):
                return message
            }
        }
    }

    func verifySegment(
        _ segment: EffectSegment,
        effectType: SkillEffectType,
        row: SkillExpectationRow,
        skill: SkillDefinition,
        cache: MasterDataCache,
        rawData: inout [String: Double],
        segmentIndex: Int
    ) throws {
        rawData["segmentIndex"] = Double(segmentIndex)

        switch effectType {
        // CombatStatCalculator / attribute-related
        case .statAdditive,
             .statMultiplier,
             .statConversionPercent,
             .statConversionLinear,
             .statFixedToOne,
             .talentStat,
             .incompetenceStat,
             .growthMultiplier,
             .attackCountAdditive,
             .attackCountMultiplier,
             .equipmentStatMultiplier,
             .itemStatMultiplier,
             .additionalDamageScoreAdditive,
             .additionalDamageScoreMultiplier,
             .criticalChancePercentAdditive,
             .criticalChancePercentCap,
             .criticalChancePercentMaxAbsolute,
             .criticalChancePercentMaxDelta:
            try verifyCombatStatEffect(effectType, segment: segment, skill: skill, rawData: &rawData)

        // Damage modifiers (runtime)
        case .damageDealtPercent,
             .damageDealtMultiplier,
             .damageDealtMultiplierAgainst,
             .damageDealtMultiplierByTargetHP,
             .damageTakenPercent,
             .damageTakenMultiplier:
            try verifyDamageModifier(effectType, segment: segment, skill: skill, rawData: &rawData)

        case .criticalDamagePercent,
             .criticalDamageMultiplier:
            try verifyCriticalDamageBonus(effectType, segment: segment, skill: skill, rawData: &rawData)

        case .criticalDamageTakenMultiplier,
             .penetrationDamageTakenMultiplier:
            try verifyCriticalOrPenetrationTaken(effectType, segment: segment, skill: skill, rawData: &rawData)

        case .martialBonusPercent,
             .martialBonusMultiplier:
            try verifyMartialBonus(effectType, segment: segment, skill: skill, rawData: &rawData)

        case .minHitScale,
             .dodgeCap:
            try verifyHitClampModifier(effectType, segment: segment, skill: skill, rawData: &rawData)

        case .levelComparisonDamageTaken:
            try verifyLevelComparisonDamageTaken(segment: segment, skill: skill, rawData: &rawData)

        case .rowProfile:
            try verifyRowProfile(segment: segment, skill: skill, rawData: &rawData)

        case .spellPowerPercent,
             .spellPowerMultiplier,
             .spellSpecificMultiplier,
             .spellSpecificTakenMultiplier:
            try verifySpellPowerModifier(effectType, segment: segment, skill: skill, cache: cache, rawData: &rawData)

        case .spellAccess,
             .spellTierUnlock:
            try verifySpellbook(effectType, segment: segment, skill: skill, cache: cache, rawData: &rawData)

        case .spellCharges:
            try verifySpellChargeModifier(segment: segment, skill: skill, rawData: &rawData)

        case .spellChargeRecoveryChance:
            try verifySpellChargeRecovery(segment: segment, skill: skill, cache: cache, rawData: &rawData)

        case .statusInflict:
            try verifyStatusInflict(segment: segment, skill: skill, cache: cache, rawData: &rawData)

        case .statusResistanceMultiplier,
             .statusResistancePercent:
            try verifyStatusResistance(effectType, segment: segment, skill: skill, cache: cache, rawData: &rawData)

        case .autoStatusCureOnAlly:
            try verifyAutoStatusCure(segment: segment, skill: skill, cache: cache, rawData: &rawData)

        case .berserk:
            try verifyBerserk(segment: segment, skill: skill, rawData: &rawData, cache: cache)

        case .extraAction:
            try verifyExtraAction(segment: segment, skill: skill, rawData: &rawData, cache: cache)

        case .reaction:
            try verifyReaction(segment: segment, skill: skill, rawData: &rawData, cache: cache)

        case .reactionNextTurn:
            try verifyReactionNextTurn(segment: segment, skill: skill, rawData: &rawData)

        case .procMultiplier:
            try verifyProcMultiplier(segment: segment, skill: skill, rawData: &rawData, cache: cache)

        case .procRate:
            try verifyProcRate(segment: segment, skill: skill, rawData: &rawData)

        case .counterAttackEvasionMultiplier:
            try verifyCounterAttackEvasionMultiplier(segment: segment, skill: skill, rawData: &rawData)

        case .actionOrderMultiplier,
             .actionOrderShuffle,
             .actionOrderShuffleEnemy,
             .firstStrike:
            try verifyActionOrder(effectType, segment: segment, skill: skill, rawData: &rawData)

        case .enemyActionDebuffChance,
             .enemySingleActionSkipChance:
            try verifyEnemyActionDebuff(effectType, segment: segment, skill: skill, rawData: &rawData)

        case .cumulativeHitDamageBonus:
            try verifyCumulativeHitBonus(segment: segment, skill: skill, rawData: &rawData)

        case .specialAttack:
            try verifySpecialAttack(segment: segment, skill: skill, rawData: &rawData)

        case .barrier,
             .barrierOnGuard:
            try verifyBarrier(effectType, segment: segment, skill: skill, rawData: &rawData)

        case .parry,
             .shieldBlock:
            try verifyParryOrBlock(effectType, segment: segment, skill: skill, rawData: &rawData)

        case .partyAttackFlag,
             .partyAttackTarget:
            try verifyPartyAttack(effectType, segment: segment, skill: skill, rawData: &rawData)

        case .breathVariant:
            try verifyBreathVariant(segment: segment, skill: skill, rawData: &rawData)

        case .reverseHealing:
            try verifyReverseHealing(segment: segment, skill: skill, rawData: &rawData)

        case .absorption:
            try verifyAbsorption(segment: segment, skill: skill, rawData: &rawData)

        case .runawayMagic,
             .runawayDamage:
            try verifyRunaway(effectType, segment: segment, skill: skill, rawData: &rawData, cache: cache)

        case .retreatAtTurn:
            try verifyRetreatAtTurn(segment: segment, skill: skill, rawData: &rawData)

        case .sacrificeRite:
            try verifySacrificeRite(segment: segment, skill: skill, rawData: &rawData)

        case .targetingWeight:
            try verifyTargetingWeight(segment: segment, skill: skill, rawData: &rawData)

        case .coverRowsBehind:
            try verifyCoverRowsBehind(segment: segment, skill: skill, rawData: &rawData)

        case .endOfTurnHealing,
             .endOfTurnSelfHPPercent:
            try verifyEndOfTurnHealing(effectType, segment: segment, skill: skill, rawData: &rawData)

        case .timedBuffTrigger,
             .timedMagicPowerAmplify,
             .timedBreathPowerAmplify,
             .tacticSpellAmplify:
            try verifyTimedBuff(effectType, segment: segment, skill: skill, rawData: &rawData)

        case .resurrectionActive,
             .resurrectionSave,
             .resurrectionPassive,
             .resurrectionBuff,
             .resurrectionVitalize,
             .resurrectionSummon:
            try verifyResurrection(effectType, segment: segment, skill: skill, cache: cache, rawData: &rawData)

        case .equipmentSlotAdditive,
             .equipmentSlotMultiplier:
            try verifyEquipmentSlots(effectType, segment: segment, skill: skill, rawData: &rawData)

        case .rewardExperiencePercent,
             .rewardExperienceMultiplier,
             .rewardGoldPercent,
             .rewardGoldMultiplier,
             .rewardItemPercent,
             .rewardItemMultiplier,
             .rewardTitlePercent,
             .rewardTitleMultiplier:
            try verifyRewardComponents(effectType, segment: segment, skill: skill, rawData: &rawData)

        case .explorationTimeMultiplier:
            try verifyExplorationModifier(segment: segment, skill: skill, rawData: &rawData)

        case .degradationRepair,
             .degradationRepairBoost,
             .autoDegradationRepair:
            try verifyDegradationRepair(effectType, segment: segment, skill: skill, rawData: &rawData)

        case .magicNullifyChancePercent,
             .magicCriticalChancePercent:
            try verifyMagicModifiers(effectType, segment: segment, skill: skill, rawData: &rawData)

        case .statDebuff:
            try verifyStatDebuff(segment: segment, skill: skill, rawData: &rawData)

        }
    }
}

// MARK: - TSV Parsing

private extension SkillRuntimeExpectationTests {
    struct SkillExpectationRow: Sendable {
        let familyId: String
        let effectType: String
        let sampleId: UInt16
        let sampleLabel: String
        let sampleEffects: String
        let expectedEffectSummary: String
        let selection: String
    }

    struct EffectSegment: Sendable {
        let effectType: String
        let params: [String: String]
        let values: [String: Double]
        let arrays: [String: [Int]]
        let statScale: [String: String]
        let semantics: [String: String]
    }

    func loadExpectationRows() throws -> [SkillExpectationRow] {
        let url = try resolveExpectationTSVURL()
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(whereSeparator: \.isNewline)
        guard let headerLine = lines.first else { throw CocoaError(.fileReadCorruptFile) }
        let headers = headerLine.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        var indexMap: [String: Int] = [:]
        for (index, name) in headers.enumerated() {
            indexMap[name] = index
        }

        func field(_ fields: [String], _ name: String) -> String {
            guard let index = indexMap[name], index < fields.count else { return "" }
            return fields[index]
        }

        var rows: [SkillExpectationRow] = []
        for line in lines.dropFirst() {
            var fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if fields.count < headers.count {
                fields.append(contentsOf: repeatElement("", count: headers.count - fields.count))
            }

            let idString = field(fields, "sampleId").trimmingCharacters(in: .whitespaces)
            guard let id = UInt16(idString) else { continue }

            rows.append(SkillExpectationRow(
                familyId: field(fields, "familyId"),
                effectType: field(fields, "effectType"),
                sampleId: id,
                sampleLabel: field(fields, "sampleLabel"),
                sampleEffects: field(fields, "sampleEffects"),
                expectedEffectSummary: field(fields, "expectedEffectSummary"),
                selection: field(fields, "selection")
            ))
        }
        return rows
    }

    func parseEffectSegments(from summary: String, fallback: String) -> [EffectSegment] {
        let source = summary.isEmpty ? fallback : summary
        let rawSegments = source.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        return rawSegments.compactMap { parseSegment(String($0)) }
    }

    func parseSegment(_ segment: String) -> EffectSegment? {
        let tokens = segment.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        var effectType: String?
        var params: [String: String] = [:]
        var values: [String: Double] = [:]
        var arrays: [String: [Int]] = [:]
        var statScale: [String: String] = [:]
        var semantics: [String: String] = [:]

        for token in tokens {
            let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0]
            let value = parts[1]
            if key == "effectType" {
                effectType = value
                continue
            }
            if key.hasPrefix("param.") {
                params[String(key.dropFirst("param.".count))] = value
                continue
            }
            if key.hasPrefix("value.") {
                let rawKey = String(key.dropFirst("value.".count))
                values[rawKey] = Double(value)
                continue
            }
            if key.hasPrefix("array.") {
                let rawKey = String(key.dropFirst("array.".count))
                arrays[rawKey] = parseIntArray(value)
                continue
            }
            if key.hasPrefix("statScale.") {
                let rawKey = String(key.dropFirst("statScale.".count))
                statScale[rawKey] = value
                continue
            }
            semantics[key] = value
        }
        guard let resolvedEffect = effectType else { return nil }
        return EffectSegment(effectType: resolvedEffect,
                             params: params,
                             values: values,
                             arrays: arrays,
                             statScale: statScale,
                             semantics: semantics)
    }

    func parseIntArray(_ raw: String) -> [Int] {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if trimmed.isEmpty { return [] }
        return trimmed.split(separator: ",").compactMap { Int($0) }
    }
}

// MARK: - Master Data

private extension SkillRuntimeExpectationTests {
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
        let bundle = Bundle(for: SkillRuntimeExpectationTests.self)
        if let url = bundle.url(forResource: "master_data", withExtension: "db") {
            return url
        }
        XCTFail("master_data.db not found")
        throw SQLiteMasterDataError.bundledDatabaseNotFound
    }

    func resolveExpectationTSVURL() throws -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        let runtimeDir = testFile.deletingLastPathComponent()
        let testsDir = runtimeDir.deletingLastPathComponent()
        let dataURL = testsDir.appendingPathComponent("TestData/SkillFamilyExpectations.tsv")
        if FileManager.default.fileExists(atPath: dataURL.path) {
            return dataURL
        }
        XCTFail("SkillFamilyExpectations.tsv not found")
        throw CocoaError(.fileNoSuchFile)
    }
}

// MARK: - Helper Builders

private extension SkillRuntimeExpectationTests {
    func withFixedMedianRandomMode<T>(_ body: () throws -> T) rethrows -> T {
        let previous = BetaTestSettings.randomMode
        BetaTestSettings.randomMode = .fixedMedian
        defer { BetaTestSettings.randomMode = previous }
        return try body()
    }

    func makeDefaultSnapshot() -> CharacterValues.Combat {
        CharacterValues.Combat(
            maxHP: 10000,
            physicalAttackScore: 5000,
            magicalAttackScore: 3000,
            physicalDefenseScore: 2000,
            magicalDefenseScore: 1000,
            hitScore: 100,
            evasionScore: 0,
            criticalChancePercent: 0,
            attackCount: 1.0,
            magicalHealingScore: 500,
            trapRemovalScore: 0,
            additionalDamageScore: 100,
            breathDamageScore: 3000,
            isMartialEligible: false
        )
    }

    func makeActor(
        identifier: String,
        kind: BattleActorKind,
        formationSlot: Int,
        skillEffects: BattleActor.SkillEffects,
        snapshot: CharacterValues.Combat,
        currentHP: Int? = nil,
        raceId: UInt8? = nil,
        level: Int? = nil
    ) -> BattleActor {
        BattleActor(
            identifier: identifier,
            displayName: identifier,
            kind: kind,
            formationSlot: formationSlot,
            strength: 10,
            wisdom: 10,
            spirit: 10,
            vitality: 10,
            agility: 10,
            luck: 10,
            level: level,
            isMartialEligible: snapshot.isMartialEligible,
            raceId: raceId,
            snapshot: snapshot,
            currentHP: currentHP ?? snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            guardActive: false,
            barrierCharges: skillEffects.combat.barrierCharges,
            guardBarrierCharges: skillEffects.combat.guardBarrierCharges,
            skillEffects: skillEffects
        )
    }
}

// MARK: - Verification Utilities

private extension SkillRuntimeExpectationTests {
    func compileActorEffects(skill: SkillDefinition, stats: ActorStats? = nil) throws -> BattleActor.SkillEffects {
        let resolvedStats = stats ?? defaultActorStats()
        return try UnifiedSkillEffectCompiler(skills: [skill], stats: resolvedStats).actorEffects
    }

    func compileRewardComponents(skill: SkillDefinition) throws -> SkillRuntimeEffects.RewardComponents {
        try SkillRuntimeEffectCompiler.rewardComponents(from: [skill])
    }

    func compileExplorationModifiers(skill: SkillDefinition) throws -> SkillRuntimeEffects.ExplorationModifiers {
        try SkillRuntimeEffectCompiler.explorationModifiers(from: [skill])
    }

    func compileEquipmentSlots(skill: SkillDefinition) throws -> SkillRuntimeEffects.EquipmentSlots {
        try UnifiedSkillEffectCompiler(skills: [skill]).equipmentSlots
    }

    func compileSpellbook(skill: SkillDefinition) throws -> SkillRuntimeEffects.Spellbook {
        try UnifiedSkillEffectCompiler(skills: [skill]).spellbook
    }

    func findPayload(effectType: SkillEffectType, in skill: SkillDefinition, matching segment: EffectSegment?) throws -> DecodedSkillEffectPayload {
        var candidates: [DecodedSkillEffectPayload] = []
        for effect in skill.effects where effect.effectType == effectType {
            let payload = try SkillRuntimeEffectCompiler.decodePayload(from: effect, skillId: skill.id)
            candidates.append(payload)
        }
        guard !candidates.isEmpty else {
            throw VerificationError.failed("effectType=\(effectType.identifier) not found in skillId=\(skill.id)")
        }
        guard let segment else { return candidates[0] }
        if candidates.count == 1 { return candidates[0] }
        for payload in candidates {
            if payloadMatchesSegment(payload, segment: segment) {
                return payload
            }
        }
        return candidates[0]
    }

    func payloadMatchesSegment(_ payload: DecodedSkillEffectPayload, segment: EffectSegment) -> Bool {
        for (key, raw) in segment.params {
            guard let paramKey = EffectParamKey.allCases.first(where: { String(describing: $0) == key }),
                  let expected = parseParamRawValue(key: key, rawValue: raw) else { continue }
            if payload.parameters[paramKey] != expected { return false }
        }
        for (key, value) in segment.values {
            guard let valueKey = EffectValueKey.allCases.first(where: { String(describing: $0) == key }),
                  let raw = payload.value[valueKey] else { continue }
            if abs(raw - value) > 0.0001 { return false }
        }
        for (key, expectedArray) in segment.arrays {
            guard let arrayKey = EffectArrayKey.allCases.first(where: { String(describing: $0) == key }),
                  let actual = payload.arrays[arrayKey] else { continue }
            if actual != expectedArray { return false }
        }
        return true
    }

    func expectedValue(_ key: String, from segment: EffectSegment) throws -> Double {
        if let value = segment.values[key] { return value }
        throw VerificationError.failed("missing value.\(key)")
    }

    func expectedParam(_ key: String, from segment: EffectSegment) throws -> String {
        if let value = segment.params[key] { return value }
        throw VerificationError.failed("missing param.\(key)")
    }

    func expectedArray(_ key: String, from segment: EffectSegment) -> [Int] {
        segment.arrays[key] ?? []
    }

    func assertApproxEqual(_ actual: Double, _ expected: Double, tolerance: Double, message: String) throws {
        if abs(actual - expected) > tolerance {
            throw VerificationError.failed("\(message) expected=\(expected) actual=\(actual)")
        }
    }

    func assertEqualInt(_ actual: Int, _ expected: Int, message: String) throws {
        if actual != expected {
            throw VerificationError.failed("\(message) expected=\(expected) actual=\(actual)")
        }
    }

    func battleDamageType(from identifier: String) -> BattleDamageType? {
        switch identifier {
        case "physical": return .physical
        case "magical": return .magical
        case "breath": return .breath
        default: return nil
        }
    }

    func combatStatValue(_ combat: CharacterValues.Combat, name: String) -> Double? {
        switch name {
        case "maxHP": return Double(combat.maxHP)
        case "physicalAttackScore": return Double(combat.physicalAttackScore)
        case "magicalAttackScore": return Double(combat.magicalAttackScore)
        case "physicalDefenseScore": return Double(combat.physicalDefenseScore)
        case "magicalDefenseScore": return Double(combat.magicalDefenseScore)
        case "hitScore": return Double(combat.hitScore)
        case "evasionScore": return Double(combat.evasionScore)
        case "criticalChancePercent": return Double(combat.criticalChancePercent)
        case "attackCount": return combat.attackCount
        case "magicalHealingScore": return Double(combat.magicalHealingScore)
        case "trapRemovalScore": return Double(combat.trapRemovalScore)
        case "additionalDamageScore": return Double(combat.additionalDamageScore)
        case "breathDamageScore": return Double(combat.breathDamageScore)
        default: return nil
        }
    }

    func attributeValue(_ attributes: CharacterValues.CoreAttributes, name: String) -> Double? {
        switch name {
        case "strength": return Double(attributes.strength)
        case "wisdom": return Double(attributes.wisdom)
        case "spirit": return Double(attributes.spirit)
        case "vitality": return Double(attributes.vitality)
        case "agility": return Double(attributes.agility)
        case "luck": return Double(attributes.luck)
        default: return nil
        }
    }

    func segmentEffect(skill: SkillDefinition, effectType: SkillEffectType, segment: EffectSegment) throws -> SkillDefinition.Effect {
        let candidates = skill.effects.filter { $0.effectType == effectType }
        guard !candidates.isEmpty else {
            throw VerificationError.failed("effectType=\(effectType.identifier) not found in skillId=\(skill.id)")
        }
        if candidates.count == 1 { return candidates[0] }
        for effect in candidates {
            let payload = try SkillRuntimeEffectCompiler.decodePayload(from: effect, skillId: skill.id)
            if payloadMatchesSegment(payload, segment: segment) {
                return effect
            }
        }
        return candidates[0]
    }

    func segmentSkill(skill: SkillDefinition, effectType: SkillEffectType, segment: EffectSegment) throws -> SkillDefinition {
        let effect = try segmentEffect(skill: skill, effectType: effectType, segment: segment)
        return SkillDefinition(id: skill.id,
                               name: skill.name,
                               description: skill.description,
                               type: skill.type,
                               category: skill.category,
                               effects: [effect])
    }

    func segmentPayload(skill: SkillDefinition, effectType: SkillEffectType, segment: EffectSegment) throws -> DecodedSkillEffectPayload {
        let effect = try segmentEffect(skill: skill, effectType: effectType, segment: segment)
        return try SkillRuntimeEffectCompiler.decodePayload(from: effect, skillId: skill.id)
    }

    func defaultActorStats() -> ActorStats {
        ActorStats(strength: 10, wisdom: 12, spirit: 14, vitality: 16, agility: 18, luck: 20)
    }

    func parseParamRawValue(key: String, rawValue: String) -> Int? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        if trimmed == "true" { return 1 }
        if trimmed == "false" { return 0 }

        if let intValue = Int(trimmed) { return intValue }

        switch key {
        case "damageType":
            return battleDamageType(from: trimmed).map { Int($0.rawValue) }
        case "stat", "statType", "sourceStat", "targetStat":
            return CombatStat(identifier: trimmed).map { Int($0.rawValue) }
        case "equipmentCategory", "equipmentType":
            return ItemSaleCategory(identifier: trimmed).map { Int($0.rawValue) }
        case "school":
            return SpellDefinition.School(identifier: trimmed).map { Int($0.rawValue) }
        case "trigger":
            return lookupRawValue(Self.triggerTypeByRaw, identifier: trimmed)
        case "target":
            if let value = lookupRawValue(Self.targetTypeByRaw, identifier: trimmed) {
                return value
            }
            if let scope = TimedBuffScope(rawValue: UInt8(1)), trimmed == "party" {
                return Int(scope.rawValue)
            }
            if trimmed == "self" { return Int(TimedBuffScope.`self`.rawValue) }
            return nil
        case "profile":
            return lookupRawValue(Self.profileByRaw, identifier: trimmed)
        case "nearApt", "farApt", "requiresMartial", "requiresAllyBehind":
            return (trimmed == "true" || trimmed == "1") ? 1 : 0
        case "status", "statusId", "statusType":
            if let value = lookupRawValue(Self.statusTypeByRaw, identifier: trimmed) {
                return value
            }
            return Int(trimmed)
        case "spellId":
            return Int(trimmed)
        case "targetId":
            return lookupRawValue(Self.targetIdByRaw, identifier: trimmed) ?? Int(trimmed)
        case "specialAttackId":
            return lookupRawValue(Self.specialAttackByRaw, identifier: trimmed) ?? Int(trimmed)
        case "type", "variant":
            return lookupRawValue(Self.effectVariantByRaw, identifier: trimmed) ?? Int(trimmed)
        case "hpScale":
            if let scale = BattleActor.SkillEffects.ResurrectionActive.HPScale(identifier: trimmed) {
                return Int(scale.rawValue)
            }
            return nil
        case "targetStatus":
            return lookupRawValue(Self.statusTypeByRaw, identifier: trimmed) ?? Int(trimmed)
        case "stacking":
            return lookupRawValue(Self.stackingTypeByRaw, identifier: trimmed)
        default:
            return nil
        }
    }

    func lookupRawValue(_ map: [Int: String], identifier: String) -> Int? {
        map.first { $0.value == identifier }?.key
    }

    static let triggerTypeByRaw: [Int: String] = [
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

    static let targetTypeByRaw: [Int: String] = [
        1: "ally",
        2: "attacker",
        8: "enemy",
        13: "killer",
        18: "party",
        22: "self"
    ]

    static let profileByRaw: [Int: String] = [
        1: "balanced",
        2: "near",
        3: "mixed",
        4: "far"
    ]

    static let effectVariantByRaw: [Int: String] = [
        1: "betweenFloors",
        2: "breath",
        3: "cold",
        4: "fire",
        5: "thunder"
    ]

    static let targetIdByRaw: [Int: String] = [
        1: "human",
        2: "special_a",
        3: "special_b",
        4: "special_c",
        5: "vampire"
    ]

    static let specialAttackByRaw: [Int: String] = [
        1: "specialA",
        2: "specialB",
        3: "specialC",
        4: "specialD",
        5: "specialE"
    ]

    static let statusTypeByRaw: [Int: String] = [
        1: "all",
        2: "instantDeath",
        3: "resurrection.active"
    ]

    static let conditionByRaw: [Int: String] = [
        1: "allyHPBelow50"
    ]

    static let stackingTypeByRaw: [Int: String] = [
        1: "add",
        2: "additive",
        3: "multiply"
    ]
}

// MARK: - CombatStatCalculator Helpers

private extension SkillRuntimeExpectationTests {
    struct CombatResultPair {
        let base: CombatStatCalculator.Result
        let modified: CombatStatCalculator.Result
    }

    func computeCombatPair(skills: [SkillDefinition],
                           equippedItems: [CharacterValues.EquippedItem] = [],
                           cachedEquippedItems: [CachedInventoryItem] = [],
                           itemDefinitions: [ItemDefinition] = []) throws -> CombatResultPair {
        let base = try calculateCombatResult(skills: [],
                                             equippedItems: equippedItems,
                                             cachedEquippedItems: cachedEquippedItems,
                                             itemDefinitions: itemDefinitions)
        let modified = try calculateCombatResult(skills: skills,
                                                 equippedItems: equippedItems,
                                                 cachedEquippedItems: cachedEquippedItems,
                                                 itemDefinitions: itemDefinitions)
        return CombatResultPair(base: base, modified: modified)
    }

    func calculateCombatResult(skills: [SkillDefinition],
                               equippedItems: [CharacterValues.EquippedItem],
                               cachedEquippedItems: [CachedInventoryItem],
                               itemDefinitions: [ItemDefinition]) throws -> CombatStatCalculator.Result {
        let baseStats = RaceDefinition.BaseStats(
            strength: 10,
            wisdom: 12,
            spirit: 14,
            vitality: 16,
            agility: 18,
            luck: 20
        )
        let race = RaceDefinition(
            id: 1,
            name: "TestRace",
            genderCode: 1,
            description: "",
            baseStats: baseStats,
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
        let loadout = CachedCharacter.Loadout(items: itemDefinitions,
                                              titles: [],
                                              superRareTitles: [])
        let context = CombatStatCalculator.Context(
            raceId: 1,
            jobId: 1,
            level: 10,
            currentHP: 1,
            equippedItems: equippedItems,
            cachedEquippedItems: cachedEquippedItems,
            race: race,
            job: job,
            personalitySecondary: nil,
            learnedSkills: skills,
            loadout: loadout
        )
        return try CombatStatCalculator.calculate(for: context)
    }

    func makeItemDefinition(id: UInt16,
                            category: UInt8,
                            statBonuses: ItemDefinition.StatBonuses,
                            combatBonuses: ItemDefinition.CombatBonuses) -> ItemDefinition {
        ItemDefinition(
            id: id,
            name: "TestItem",
            category: category,
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
    }

    func makeCachedItem(from definition: ItemDefinition, quantity: UInt16) -> CachedInventoryItem {
        CachedInventoryItem(
            stackKey: "test.stack.\(definition.id)",
            itemId: definition.id,
            quantity: quantity,
            normalTitleId: 0,
            superRareTitleId: 0,
            socketItemId: 0,
            socketNormalTitleId: 0,
            socketSuperRareTitleId: 0,
            category: ItemSaleCategory(rawValue: definition.category) ?? .other,
            rarity: definition.rarity,
            displayName: definition.name,
            baseValue: 0,
            sellValue: 0,
            statBonuses: definition.statBonuses,
            combatBonuses: definition.combatBonuses,
            grantedSkillIds: []
        )
    }
}

// MARK: - Runtime Verification Helpers

private extension SkillRuntimeExpectationTests {
    func makeContext(players: [BattleActor],
                     enemies: [BattleActor],
                     statusDefinitions: [UInt8: StatusEffectDefinition]) -> BattleContext {
        BattleContext(
            players: players,
            enemies: enemies,
            statusDefinitions: statusDefinitions,
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )
    }

    func resolveDamageType(segment: EffectSegment, payload: DecodedSkillEffectPayload) -> BattleDamageType {
        if let raw = segment.params["damageType"], let resolved = battleDamageType(from: raw) {
            return resolved
        }
        if let raw = payload.parameters[.damageType], let resolved = BattleDamageType(rawValue: UInt8(raw)) {
            return resolved
        }
        return .physical
    }

    func resolveCombatStat(segment: EffectSegment,
                           payload: DecodedSkillEffectPayload,
                           paramKey: EffectParamKey,
                           paramName: String) throws -> CombatStat {
        if let raw = segment.params[paramName], let stat = CombatStat(identifier: raw) {
            return stat
        }
        if let raw = payload.parameters[paramKey],
           let rawValue = UInt8(exactly: raw),
           let stat = CombatStat(rawValue: rawValue) {
            return stat
        }
        throw VerificationError.failed("missing \(paramName) in segment/payload")
    }

    func resolveStatusResistanceTargets(payload: DecodedSkillEffectPayload) throws -> [UInt8] {
        if let statusIdRaw = payload.parameters[.status] {
            return [UInt8(statusIdRaw)]
        }
        guard let statusTypeRaw = payload.parameters[.statusType] else {
            throw VerificationError.failed("statusResistance missing statusType/status")
        }
        switch statusTypeRaw {
        case 1:
            return [0, 1, 2, 3]
        case 2:
            return [2, 3]
        default:
            throw VerificationError.failed("statusResistance unsupported statusType=\(statusTypeRaw)")
        }
    }

    func expectedBoolFromChancePercent(_ chancePercent: Double) -> Bool {
        chancePercent >= 50.0
    }

    func resolvedConditionName(from payload: DecodedSkillEffectPayload) -> String? {
        guard let raw = payload.parameters[.condition] else { return nil }
        return Self.conditionByRaw[raw]
    }

    func specialAttackKind(from payload: DecodedSkillEffectPayload) -> SpecialAttackKind? {
        guard let raw = payload.parameters[.specialAttackId] ?? payload.parameters[.type] else { return nil }
        return SpecialAttackKind(rawValue: UInt8(raw))
    }
}

// MARK: - Effect Verifiers

private extension SkillRuntimeExpectationTests {
    func verifyCombatStatEffect(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: effectType, segment: segment)

        switch effectType {
        case .statAdditive:
            let statKey = try resolveCombatStat(segment: segment, payload: payload, paramKey: .stat, paramName: "stat")
            let additive = segment.values["additive"] ?? payload.value[.additive] ?? 0.0
            let pair = try computeCombatPair(skills: [segmentSkill])
            let base = combatStatValue(pair.base.combat, name: statKey.identifier) ?? 0.0
            let modified = combatStatValue(pair.modified.combat, name: statKey.identifier) ?? 0.0
            rawData["combatBase"] = base
            rawData["combatModified"] = modified
            try assertApproxEqual(modified - base, additive, tolerance: 0.6, message: "statAdditive \(statKey.identifier)")

        case .statMultiplier:
            let statKey = try resolveCombatStat(segment: segment, payload: payload, paramKey: .stat, paramName: "stat")
            let multiplier = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.0
            let pair = try computeCombatPair(skills: [segmentSkill])
            let base = combatStatValue(pair.base.combat, name: statKey.identifier) ?? 0.0
            let modified = combatStatValue(pair.modified.combat, name: statKey.identifier) ?? 0.0
            var expected = Double(Int((base * multiplier).rounded(.towardZero)))
            if statKey == .maxHP {
                expected = max(1.0, expected)
            }
            rawData["combatExpected"] = expected
            try assertApproxEqual(modified, expected, tolerance: 0.6, message: "statMultiplier \(statKey.identifier)")

        case .statConversionPercent:
            let source = try resolveCombatStat(segment: segment, payload: payload, paramKey: .sourceStat, paramName: "sourceStat")
            let target = try resolveCombatStat(segment: segment, payload: payload, paramKey: .targetStat, paramName: "targetStat")
            let percent = segment.values["valuePercent"] ?? payload.value[.valuePercent] ?? 0.0
            let ratio = percent / 100.0
            let pair = try computeCombatPair(skills: [segmentSkill])
            let baseSource = combatStatValue(pair.base.combat, name: source.identifier) ?? 0.0
            let baseTarget = combatStatValue(pair.base.combat, name: target.identifier) ?? 0.0
            let modifiedTarget = combatStatValue(pair.modified.combat, name: target.identifier) ?? 0.0
            let expectedAdd = Double(Int((baseSource * ratio).rounded(.towardZero)))
            rawData["conversionExpected"] = expectedAdd
            try assertApproxEqual(modifiedTarget - baseTarget, expectedAdd, tolerance: 0.6, message: "statConversionPercent \(target.identifier)")

        case .statConversionLinear:
            let source = try resolveCombatStat(segment: segment, payload: payload, paramKey: .sourceStat, paramName: "sourceStat")
            let target = try resolveCombatStat(segment: segment, payload: payload, paramKey: .targetStat, paramName: "targetStat")
            let ratio = segment.values["valuePerUnit"] ?? payload.value[.valuePerUnit] ?? 0.0
            let pair = try computeCombatPair(skills: [segmentSkill])
            let baseSource = combatStatValue(pair.base.combat, name: source.identifier) ?? 0.0
            let baseTarget = combatStatValue(pair.base.combat, name: target.identifier) ?? 0.0
            let modifiedTarget = combatStatValue(pair.modified.combat, name: target.identifier) ?? 0.0
            let expectedAdd = Double(Int((baseSource * ratio).rounded(.towardZero)))
            rawData["conversionExpected"] = expectedAdd
            try assertApproxEqual(modifiedTarget - baseTarget, expectedAdd, tolerance: 0.6, message: "statConversionLinear \(target.identifier)")

        case .statFixedToOne:
            let statKey = try resolveCombatStat(segment: segment, payload: payload, paramKey: .stat, paramName: "stat")
            let pair = try computeCombatPair(skills: [segmentSkill])
            let modified = combatStatValue(pair.modified.combat, name: statKey.identifier) ?? 0.0
            rawData["combatModified"] = modified
            try assertApproxEqual(modified, 1.0, tolerance: 0.01, message: "statFixedToOne \(statKey.identifier)")

        case .talentStat:
            let statKey = try resolveCombatStat(segment: segment, payload: payload, paramKey: .stat, paramName: "stat")
            let multiplier = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.5
            let pair = try computeCombatPair(skills: [segmentSkill])
            let base = combatStatValue(pair.base.combat, name: statKey.identifier) ?? 0.0
            let modified = combatStatValue(pair.modified.combat, name: statKey.identifier) ?? 0.0
            var expected = Double(Int((base * multiplier).rounded(.towardZero)))
            if statKey == .maxHP {
                expected = max(1.0, expected)
            }
            rawData["combatExpected"] = expected
            try assertApproxEqual(modified, expected, tolerance: 0.6, message: "talentStat \(statKey.identifier)")

        case .incompetenceStat:
            let statKey = try resolveCombatStat(segment: segment, payload: payload, paramKey: .stat, paramName: "stat")
            let multiplier = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 0.5
            let pair = try computeCombatPair(skills: [segmentSkill])
            let base = combatStatValue(pair.base.combat, name: statKey.identifier) ?? 0.0
            let modified = combatStatValue(pair.modified.combat, name: statKey.identifier) ?? 0.0
            var expected = Double(Int((base * multiplier).rounded(.towardZero)))
            if statKey == .maxHP {
                expected = max(1.0, expected)
            }
            rawData["combatExpected"] = expected
            try assertApproxEqual(modified, expected, tolerance: 0.6, message: "incompetenceStat \(statKey.identifier)")

        case .growthMultiplier:
            let multiplier = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.0
            let pair = try computeCombatPair(skills: [segmentSkill])
            let base = Double(pair.base.combat.maxHP)
            let modified = Double(pair.modified.combat.maxHP)
            rawData["maxHPBase"] = base
            rawData["maxHPModified"] = modified
            if multiplier > 1.0 {
                if modified <= base {
                    throw VerificationError.failed("growthMultiplier expected maxHP increase")
                }
            } else if multiplier < 1.0 {
                if modified >= base {
                    throw VerificationError.failed("growthMultiplier expected maxHP decrease")
                }
            }

        case .attackCountAdditive:
            let additive = segment.values["additive"] ?? payload.value[.additive] ?? 0.0
            let pair = try computeCombatPair(skills: [segmentSkill])
            let base = pair.base.combat.attackCount
            let modified = pair.modified.combat.attackCount
            rawData["attackCountDelta"] = modified - base
            try assertApproxEqual(modified - base, additive, tolerance: 0.01, message: "attackCountAdditive")

        case .attackCountMultiplier:
            let multiplier = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.0
            let pair = try computeCombatPair(skills: [segmentSkill])
            let base = pair.base.combat.attackCount
            let modified = pair.modified.combat.attackCount
            let expected = max(1.0, base * multiplier)
            rawData["attackCountExpected"] = expected
            try assertApproxEqual(modified, expected, tolerance: 0.01, message: "attackCountMultiplier")

        case .equipmentStatMultiplier:
            let categoryId: Int = {
                if let raw = segment.params["equipmentCategory"], let category = ItemSaleCategory(identifier: raw) {
                    return Int(category.rawValue)
                }
                if let raw = payload.parameters[.equipmentCategory] ?? payload.parameters[.equipmentType] {
                    return raw
                }
                return Int(ItemSaleCategory.thinSword.rawValue)
            }()
            let multiplier = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.0
            let statBonuses = ItemDefinition.StatBonuses(strength: 10, wisdom: 0, spirit: 0, vitality: 0, agility: 0, luck: 0)
            let combatBonuses = ItemDefinition.CombatBonuses(maxHP: 0,
                                                             physicalAttackScore: 0,
                                                             magicalAttackScore: 0,
                                                             physicalDefenseScore: 0,
                                                             magicalDefenseScore: 0,
                                                             hitScore: 0,
                                                             evasionScore: 0,
                                                             criticalChancePercent: 0,
                                                             attackCount: 0,
                                                             magicalHealingScore: 0,
                                                             trapRemovalScore: 0,
                                                             additionalDamageScore: 0,
                                                             breathDamageScore: 0)
            let item = makeItemDefinition(id: 1000, category: UInt8(categoryId), statBonuses: statBonuses, combatBonuses: combatBonuses)
            let equipped = CharacterValues.EquippedItem(superRareTitleId: 0,
                                                        normalTitleId: 0,
                                                        itemId: item.id,
                                                        socketSuperRareTitleId: 0,
                                                        socketNormalTitleId: 0,
                                                        socketItemId: 0,
                                                        quantity: 1)
            let pair = try computeCombatPair(skills: [segmentSkill],
                                             equippedItems: [equipped],
                                             itemDefinitions: [item])
            let base = Double(pair.base.attributes.strength)
            let modified = Double(pair.modified.attributes.strength)
            let expectedDelta = Double(statBonuses.strength) * (multiplier - 1.0)
            rawData["strengthDelta"] = modified - base
            try assertApproxEqual(modified - base, expectedDelta, tolerance: 0.6, message: "equipmentStatMultiplier")

        case .itemStatMultiplier:
            let statKey = try resolveCombatStat(segment: segment, payload: payload, paramKey: .statType, paramName: "statType")
            let multiplier = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.0
            let combatBonuses = ItemDefinition.CombatBonuses(maxHP: statKey == .maxHP ? 100 : 0,
                                                             physicalAttackScore: statKey == .physicalAttackScore ? 100 : 0,
                                                             magicalAttackScore: statKey == .magicalAttackScore ? 100 : 0,
                                                             physicalDefenseScore: statKey == .physicalDefenseScore ? 100 : 0,
                                                             magicalDefenseScore: statKey == .magicalDefenseScore ? 100 : 0,
                                                             hitScore: statKey == .hitScore ? 50 : 0,
                                                             evasionScore: statKey == .evasionScore ? 50 : 0,
                                                             criticalChancePercent: statKey == .criticalChancePercent ? 10 : 0,
                                                             attackCount: statKey == .attackCount ? 0.5 : 0,
                                                             magicalHealingScore: statKey == .magicalHealingScore ? 50 : 0,
                                                             trapRemovalScore: statKey == .trapRemovalScore ? 10 : 0,
                                                             additionalDamageScore: statKey == .additionalDamageScore ? 100 : 0,
                                                             breathDamageScore: statKey == .breathDamageScore ? 100 : 0)
            let item = makeItemDefinition(id: 1001,
                                          category: UInt8(ItemSaleCategory.sword.rawValue),
                                          statBonuses: .zero,
                                          combatBonuses: combatBonuses)
            let cached = makeCachedItem(from: item, quantity: 1)
            let equipped = CharacterValues.EquippedItem(superRareTitleId: 0,
                                                        normalTitleId: 0,
                                                        itemId: item.id,
                                                        socketSuperRareTitleId: 0,
                                                        socketNormalTitleId: 0,
                                                        socketItemId: 0,
                                                        quantity: 1)
            let pair = try computeCombatPair(skills: [segmentSkill],
                                             equippedItems: [equipped],
                                             cachedEquippedItems: [cached],
                                             itemDefinitions: [item])
            let base = combatStatValue(pair.base.combat, name: statKey.identifier) ?? 0.0
            let modified = combatStatValue(pair.modified.combat, name: statKey.identifier) ?? 0.0
            let expectedDelta = (modified - base) / max(1.0, multiplier) * (multiplier - 1.0)
            rawData["combatDelta"] = modified - base
            if multiplier != 1.0, modified == base {
                throw VerificationError.failed("itemStatMultiplier not applied")
            }
            _ = expectedDelta

        case .additionalDamageScoreAdditive:
            let additive = segment.values["additive"] ?? payload.value[.additive] ?? 0.0
            let pair = try computeCombatPair(skills: [segmentSkill])
            let base = Double(pair.base.combat.additionalDamageScore)
            let modified = Double(pair.modified.combat.additionalDamageScore)
            rawData["additionalDamageDelta"] = modified - base
            try assertApproxEqual(modified - base, additive, tolerance: 0.6, message: "additionalDamageScoreAdditive")

        case .additionalDamageScoreMultiplier:
            let multiplier = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.0
            let pair = try computeCombatPair(skills: [segmentSkill])
            let baseStrength = pair.base.attributes.strength
            let baseDependency = CombatFormulas.strengthDependency(value: baseStrength)
            let baseGrowth = CombatFormulas.additionalDamageGrowth(level: 10,
                                                                   jobCoefficient: 1.0,
                                                                   growthMultiplier: 1.0)
            let rawBase = baseDependency * (1.0 + baseGrowth) * CombatFormulas.additionalDamageScoreScale
            var expected = Double(Int((rawBase * multiplier).rounded(.towardZero)))
            if baseStrength >= 21 {
                let bonus = CombatFormulas.statBonusMultiplier(value: baseStrength)
                expected = Double(Int((expected * bonus).rounded(.towardZero)))
            }
            let modified = Double(pair.modified.combat.additionalDamageScore)
            rawData["additionalDamageExpected"] = expected
            try assertApproxEqual(modified, expected, tolerance: 0.6, message: "additionalDamageScoreMultiplier")

        case .criticalChancePercentAdditive:
            let points = segment.values["points"] ?? payload.value[.points] ?? 0.0
            let pair = try computeCombatPair(skills: [segmentSkill])
            let base = Double(pair.base.combat.criticalChancePercent)
            let modified = Double(pair.modified.combat.criticalChancePercent)
            let expectedDelta = Double(Int(points.rounded(.towardZero)))
            rawData["criticalDelta"] = modified - base
            try assertApproxEqual(modified - base, expectedDelta, tolerance: 0.6, message: "criticalChancePercentAdditive")

        case .criticalChancePercentCap, .criticalChancePercentMaxAbsolute:
            let cap = segment.values["cap"] ?? segment.values["maxPercent"] ?? payload.value[.cap] ?? payload.value[.maxPercent] ?? 100.0
            let pair = try computeCombatPair(skills: [segmentSkill])
            let base = Double(pair.base.combat.criticalChancePercent)
            let modified = Double(pair.modified.combat.criticalChancePercent)
            rawData["criticalBase"] = base
            rawData["criticalModified"] = modified
            if base > cap {
                try assertApproxEqual(modified, cap, tolerance: 0.6, message: "criticalChancePercentCap")
            } else if modified > cap + 0.6 {
                throw VerificationError.failed("criticalChancePercentCap exceeded")
            }

        case .criticalChancePercentMaxDelta:
            let delta = segment.values["deltaPercent"] ?? payload.value[.deltaPercent] ?? 0.0
            let pair = try computeCombatPair(skills: [segmentSkill])
            let base = Double(pair.base.combat.criticalChancePercent)
            let modified = Double(pair.modified.combat.criticalChancePercent)
            rawData["criticalDeltaLimit"] = delta
            if delta < 0, modified > base + 0.6 {
                throw VerificationError.failed("criticalChancePercentMaxDelta unexpected increase")
            }

        default:
            break
        }
    }

    func verifyDamageModifier(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: effectType, segment: segment)
        let damageTypes: [BattleDamageType] = {
            if let raw = segment.params["damageType"], raw == "all" {
                return [.physical, .magical, .breath]
            }
            if let raw = segment.params["damageType"], let resolved = battleDamageType(from: raw) {
                return [resolved]
            }
            if let raw = payload.parameters[.damageType], let resolved = BattleDamageType(rawValue: UInt8(raw)) {
                return [resolved]
            }
            return [.physical]
        }()
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let appliesToDefender = effectType == .damageTakenPercent || effectType == .damageTakenMultiplier

        let attacker = TestActorBuilder.makeAttacker(physicalAttackScore: 5000,
                                                     magicalAttackScore: 3000,
                                                     hitScore: 100,
                                                     luck: 18,
                                                     criticalChancePercent: 0,
                                                     additionalDamageScore: 0,
                                                     breathDamageScore: 3000,
                                                     skillEffects: appliesToDefender ? .neutral : skillEffects)
        var defender = TestActorBuilder.makeDefender(physicalDefenseScore: 2000,
                                                     magicalDefenseScore: 1000,
                                                     evasionScore: 0,
                                                     luck: 1,
                                                     skillEffects: appliesToDefender ? skillEffects : .neutral)

        for damageType in damageTypes {
            switch effectType {
            case .damageDealtPercent:
                let scaled = payload.scaledValue(from: defaultActorStats())
                let value = (segment.values["valuePercent"] ?? payload.value[.valuePercent] ?? 0.0) + scaled
                let expected = 1.0 + value / 100.0
                let actual = BattleTurnEngine.damageDealtModifier(for: attacker, against: defender, damageType: damageType)
                rawData["damageDealtExpected"] = expected
                rawData["damageDealtActual"] = actual
                try assertApproxEqual(actual, expected, tolerance: 0.0001, message: "damageDealtPercent")

            case .damageDealtMultiplier:
                let expected = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.0
                let actual = BattleTurnEngine.damageDealtModifier(for: attacker, against: defender, damageType: damageType)
                try assertApproxEqual(actual, expected, tolerance: 0.0001, message: "damageDealtMultiplier")

            case .damageDealtMultiplierAgainst:
                let multiplier = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.0
                let raceIds = payload.arrays[.targetRaceIds] ?? []
                let targetRace = UInt8(raceIds.first ?? 1)
                let raceDefender = TestActorBuilder.makeDefender(physicalDefenseScore: defender.snapshot.physicalDefenseScore,
                                                                 magicalDefenseScore: defender.snapshot.magicalDefenseScore,
                                                                 evasionScore: defender.snapshot.evasionScore,
                                                                 luck: defender.luck,
                                                                 skillEffects: defender.skillEffects,
                                                                 raceId: targetRace)
                let actual = BattleTurnEngine.damageDealtModifier(for: attacker, against: raceDefender, damageType: damageType)
                rawData["damageDealtAgainst"] = actual
                try assertApproxEqual(actual, multiplier, tolerance: 0.0001, message: "damageDealtMultiplierAgainst")

                // negative case (different race)
                let raceSet = Set(raceIds.compactMap { UInt8(exactly: $0) })
                let negativeRace = (1...255).compactMap(UInt8.init).first { !raceSet.contains($0) }
                if let negativeRace, negativeRace != targetRace {
                    let negativeDefender = TestActorBuilder.makeDefender(physicalDefenseScore: defender.snapshot.physicalDefenseScore,
                                                                         magicalDefenseScore: defender.snapshot.magicalDefenseScore,
                                                                         evasionScore: defender.snapshot.evasionScore,
                                                                         luck: defender.luck,
                                                                         skillEffects: defender.skillEffects,
                                                                         raceId: negativeRace)
                    let negative = BattleTurnEngine.damageDealtModifier(for: attacker, against: negativeDefender, damageType: damageType)
                    if abs(negative - 1.0) > 0.0001 {
                        throw VerificationError.failed("damageDealtMultiplierAgainst negative case failed")
                    }
                }

            case .damageDealtMultiplierByTargetHP:
                let threshold = segment.values["hpThresholdPercent"] ?? payload.value[.hpThresholdPercent] ?? 0.0
                let multiplier = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.0
                defender.currentHP = Int(Double(defender.snapshot.maxHP) * threshold / 100.0) - 1
                let actual = BattleTurnEngine.damageDealtModifier(for: attacker, against: defender, damageType: damageType)
                try assertApproxEqual(actual, multiplier, tolerance: 0.0001, message: "damageDealtMultiplierByTargetHP triggered")
                defender.currentHP = defender.snapshot.maxHP
                let negative = BattleTurnEngine.damageDealtModifier(for: attacker, against: defender, damageType: damageType)
                if abs(negative - 1.0) > 0.0001 {
                    throw VerificationError.failed("damageDealtMultiplierByTargetHP negative case failed")
                }

            case .damageTakenPercent:
                let scaled = payload.scaledValue(from: defaultActorStats())
                let value = (segment.values["valuePercent"] ?? payload.value[.valuePercent] ?? 0.0) + scaled
                let expected = 1.0 + value / 100.0
                let actual = BattleTurnEngine.damageTakenModifier(for: defender, damageType: damageType, attacker: attacker)
                try assertApproxEqual(actual, expected, tolerance: 0.0001, message: "damageTakenPercent")

            case .damageTakenMultiplier:
                let expected = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.0
                let actual = BattleTurnEngine.damageTakenModifier(for: defender, damageType: damageType, attacker: attacker)
                try assertApproxEqual(actual, expected, tolerance: 0.0001, message: "damageTakenMultiplier")

            default:
                break
            }
        }
    }

    func verifyCriticalDamageBonus(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: effectType, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let attacker = TestActorBuilder.makeAttacker(luck: 35, skillEffects: skillEffects)
        let percent = segment.values["valuePercent"] ?? payload.value[.valuePercent] ?? 0.0
        let multiplier = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.0
        let expected = (1.0 + percent / 100.0) * multiplier
        let actual = BattleTurnEngine.criticalDamageBonus(for: attacker)
        rawData["criticalDamageExpected"] = expected
        rawData["criticalDamageActual"] = actual
        try assertApproxEqual(actual, expected, tolerance: 0.0001, message: "criticalDamageBonus")
    }

    func verifyCriticalOrPenetrationTaken(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: effectType, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())

        let attacker = TestActorBuilder.makeAttacker(luck: 1, criticalChancePercent: 100, additionalDamageScore: 100)
        var defenderWith = TestActorBuilder.makeDefender(luck: 1, skillEffects: skillEffects)
        var defenderBase = TestActorBuilder.makeDefender(luck: 1)

        let expectedMultiplier = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.0
        let baseDamage: Int
        let modifiedDamage: Int

        baseDamage = withFixedMedianRandomMode {
            var context = makeContext(players: [attacker], enemies: [defenderBase], statusDefinitions: [:])
            return BattleTurnEngine.computePhysicalDamage(attacker: attacker,
                                                         defender: &defenderBase,
                                                         hitIndex: 1,
                                                         context: &context).damage
        }

        modifiedDamage = withFixedMedianRandomMode {
            var context = makeContext(players: [attacker], enemies: [defenderWith], statusDefinitions: [:])
            return BattleTurnEngine.computePhysicalDamage(attacker: attacker,
                                                         defender: &defenderWith,
                                                         hitIndex: 1,
                                                         context: &context).damage
        }

        rawData["baseDamage"] = Double(baseDamage)
        rawData["modifiedDamage"] = Double(modifiedDamage)

        switch effectType {
        case .criticalDamageTakenMultiplier:
            let ratio = baseDamage > 0 ? Double(modifiedDamage) / Double(baseDamage) : 0
            try assertApproxEqual(ratio, expectedMultiplier, tolerance: 0.1, message: "criticalDamageTakenMultiplier")
        case .penetrationDamageTakenMultiplier:
            if expectedMultiplier > 1.0, modifiedDamage <= baseDamage {
                throw VerificationError.failed("penetrationDamageTakenMultiplier not applied")
            }
            if expectedMultiplier < 1.0, modifiedDamage >= baseDamage {
                throw VerificationError.failed("penetrationDamageTakenMultiplier reduction not applied")
            }
        default:
            break
        }
    }

    func verifyMartialBonus(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: effectType, segment: segment)
        let pair = try computeCombatPair(skills: [segmentSkill])
        let base = Double(pair.base.combat.physicalAttackScore)
        let modified = Double(pair.modified.combat.physicalAttackScore)
        let percent = segment.values["valuePercent"] ?? payload.value[.valuePercent] ?? 0.0
        let multiplier = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.0
        let expected = (1.0 + percent / 100.0) * multiplier
        let ratio = base > 0 ? modified / base : 0
        rawData["martialRatio"] = ratio
        try assertApproxEqual(ratio, expected, tolerance: 0.05, message: "martialBonus")
    }

    func verifyHitClampModifier(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: effectType, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let defender = TestActorBuilder.makeDefender(luck: 18, agility: 20, skillEffects: skillEffects)

        let clampedLow = BattleTurnEngine.clampProbability(0.0, defender: defender)
        let clampedHigh = BattleTurnEngine.clampProbability(1.0, defender: defender)
        rawData["clampedLow"] = clampedLow
        rawData["clampedHigh"] = clampedHigh

        switch effectType {
        case .minHitScale:
            let minScale = segment.values["minHitScale"] ?? payload.value[.minHitScale] ?? 1.0
            let evasionLimitPercent = CombatFormulas.evasionLimit(value: defender.agility)
            let expectedMin = max(0.0, min(1.0, (1.0 - evasionLimitPercent / 100.0) * minScale))
            try assertApproxEqual(clampedLow, expectedMin, tolerance: 0.0001, message: "minHitScale")
        case .dodgeCap:
            let capPercent = segment.values["maxDodge"] ?? payload.value[.maxDodge] ?? 100.0
            let expectedMax = min(0.95, max(0.0, 1.0 - capPercent / 100.0))
            try assertApproxEqual(clampedHigh, expectedMax, tolerance: 0.0001, message: "dodgeCap")
        default:
            break
        }
    }

    func verifyLevelComparisonDamageTaken(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .levelComparisonDamageTaken, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: .levelComparisonDamageTaken, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())

        let defender = TestActorBuilder.makeDefender(luck: 1, skillEffects: skillEffects, level: 50)
        let attackerWithLevel = TestActorBuilder.makeAttacker(luck: 1, level: 10)

        let percent = segment.values["valuePercent"] ?? payload.value[.valuePercent] ?? 0.0
        let expectedMultiplier = 1.0 - (percent * Double(defender.level! - attackerWithLevel.level!)) / 100.0
        let actual = BattleTurnEngine.damageTakenModifier(for: defender, damageType: .physical, attacker: attackerWithLevel)
        rawData["levelComparisonExpected"] = expectedMultiplier
        rawData["levelComparisonActual"] = actual
        try assertApproxEqual(actual, expectedMultiplier, tolerance: 0.0001, message: "levelComparisonDamageTaken")
    }

    func verifyRowProfile(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .rowProfile, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: .rowProfile, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())

        var expectedProfile = BattleActor.SkillEffects.RowProfile()
        expectedProfile.applyParameters(payload.parameters)
        rawData["rowProfileBase"] = Double(expectedProfile.base.rawValue)
        rawData["rowProfileNearApt"] = expectedProfile.hasNearApt ? 1 : 0
        rawData["rowProfileFarApt"] = expectedProfile.hasFarApt ? 1 : 0

        if skillEffects.misc.rowProfile != expectedProfile {
            throw VerificationError.failed("rowProfile parameters not applied")
        }

        let baseActor = TestActorBuilder.makeAttacker(luck: 18, formationSlot: 3)
        let modifiedActor = TestActorBuilder.makeAttacker(luck: 18, skillEffects: skillEffects, formationSlot: 3)
        let baseMultiplier = BattleTurnEngine.rowDamageModifier(for: baseActor, damageType: .physical)
        let modifiedMultiplier = BattleTurnEngine.rowDamageModifier(for: modifiedActor, damageType: .physical)
        rawData["rowMultiplier"] = modifiedMultiplier
        if expectedProfile != BattleActor.SkillEffects.RowProfile(),
           abs(baseMultiplier - modifiedMultiplier) < 0.0001 {
            throw VerificationError.failed("rowProfile not reflected in damage modifier")
        }
    }

    func verifySpellPowerModifier(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        cache: MasterDataCache,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: effectType, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let attacker = TestActorBuilder.makeAttacker(luck: 18, skillEffects: skillEffects)

        switch effectType {
        case .spellPowerPercent:
            let percent = segment.values["valuePercent"] ?? payload.value[.valuePercent] ?? 0.0
            let expected = 1.0 + percent / 100.0
            let actual = BattleTurnEngine.spellPowerModifier(for: attacker, spellId: nil)
            try assertApproxEqual(actual, expected, tolerance: 0.0001, message: "spellPowerPercent")
        case .spellPowerMultiplier:
            let multiplier = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.0
            let actual = BattleTurnEngine.spellPowerModifier(for: attacker, spellId: nil)
            try assertApproxEqual(actual, multiplier, tolerance: 0.0001, message: "spellPowerMultiplier")
        case .spellSpecificMultiplier:
            guard let spellIdRaw = payload.parameters[.spellId] else {
                throw VerificationError.failed("spellSpecificMultiplier missing spellId")
            }
            let multiplier = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.0
            let actual = BattleTurnEngine.spellPowerModifier(for: attacker, spellId: UInt8(spellIdRaw))
            rawData["spellSpecificActual"] = actual
            if abs(actual - multiplier) > 0.0001 {
                throw VerificationError.failed("spellSpecificMultiplier mismatch")
            }
        case .spellSpecificTakenMultiplier:
            guard let spellIdRaw = payload.parameters[.spellId] else {
                throw VerificationError.failed("spellSpecificTakenMultiplier missing spellId")
            }
            let defender = TestActorBuilder.makeDefender(luck: 18, skillEffects: skillEffects)
            let actual = BattleTurnEngine.damageTakenModifier(for: defender,
                                                              damageType: .magical,
                                                              spellId: UInt8(spellIdRaw),
                                                              attacker: attacker)
            let expected = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.0
            try assertApproxEqual(actual, expected, tolerance: 0.0001, message: "spellSpecificTakenMultiplier")
        default:
            break
        }
    }

    func verifySpellbook(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        cache: MasterDataCache,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let spellbook = try compileSpellbook(skill: segmentSkill)

        switch effectType {
        case .spellAccess:
            guard let effect = try? segmentEffect(skill: skill, effectType: .spellAccess, segment: segment) else {
                throw VerificationError.failed("spellAccess effect not found")
            }
            let payload = try SkillRuntimeEffectCompiler.decodePayload(from: effect, skillId: skill.id)
            guard let spellIdRaw = payload.parameters[.spellId] else {
                throw VerificationError.failed("spellAccess missing spellId")
            }
            let spellId = UInt8(spellIdRaw)
            let actionRaw = payload.parameters[.action] ?? 1
            if actionRaw == 2 {
                if !spellbook.forgottenSpellIds.contains(spellId) {
                    throw VerificationError.failed("spellAccess forget not applied")
                }
            } else {
                if !spellbook.learnedSpellIds.contains(spellId) {
                    throw VerificationError.failed("spellAccess learn not applied")
                }
            }
            let loadout = SkillRuntimeEffectCompiler.spellLoadout(from: spellbook,
                                                                  definitions: cache.allSpells,
                                                                  characterLevel: 200)
            if actionRaw != 2 {
                let found = (loadout.mage + loadout.priest).contains { $0.id == spellId }
                if !found {
                    throw VerificationError.failed("spellAccess not present in loadout")
                }
            }

        case .spellTierUnlock:
            guard let effect = try? segmentEffect(skill: skill, effectType: .spellTierUnlock, segment: segment) else {
                throw VerificationError.failed("spellTierUnlock effect not found")
            }
            let payload = try SkillRuntimeEffectCompiler.decodePayload(from: effect, skillId: skill.id)
            guard let schoolRaw = payload.parameters[.school],
                  let school = SpellDefinition.School(rawValue: UInt8(schoolRaw)) else {
                throw VerificationError.failed("spellTierUnlock missing school")
            }
            let tier = segment.values["tier"] ?? payload.value[.tier] ?? 0.0
            let expected = Int(tier.rounded(.towardZero))
            let actual = spellbook.tierUnlocks[school.index] ?? 0
            rawData["tierUnlock"] = Double(actual)
            try assertEqualInt(actual, expected, message: "spellTierUnlock")

        default:
            break
        }
    }

    func verifySpellChargeModifier(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .spellCharges, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: .spellCharges, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())

        let targetSpellId = payload.parameters[.spellId].map { UInt8($0) }
        let modifier = targetSpellId.flatMap { skillEffects.spell.chargeModifier(for: $0) }
            ?? skillEffects.spell.defaultChargeModifier

        if let maxCharges = payload.value[.maxCharges] {
            if modifier?.maxOverride != Int(maxCharges) {
                throw VerificationError.failed("spellCharges maxOverride mismatch")
            }
        }
        if let initial = payload.value[.initialCharges] {
            if modifier?.initialOverride != Int(initial) {
                throw VerificationError.failed("spellCharges initialOverride mismatch")
            }
        }

        // simulate application
        let dummySpellId = targetSpellId ?? 1
        var resources = BattleActionResource.makeDefault(for: makeDefaultSnapshot(),
                                                         spellLoadout: .init(mage: [], priest: []))
        resources.setSpellCharges(for: dummySpellId, current: 1, max: 1)
        if let modifier, !modifier.isEmpty {
            let baseState = resources.spellChargeState(for: dummySpellId)
                ?? BattleActionResource.SpellChargeState(current: 1, max: 1)
            let baseInitial = baseState.current
            let baseMax = baseState.max
            let newMax = max(modifier.maxOverride ?? baseMax, 0)
            var newInitial = max(0, modifier.initialOverride ?? baseInitial)
            if modifier.initialBonus != 0 {
                newInitial += modifier.initialBonus
            }
            resources.setSpellCharges(for: dummySpellId, current: newInitial, max: newMax)
        }
        rawData["spellChargeCurrent"] = Double(resources.charges(forSpellId: dummySpellId))
        rawData["spellChargeMax"] = Double(resources.maxCharges(forSpellId: dummySpellId) ?? 0)
    }

    func verifySpellChargeRecovery(
        segment: EffectSegment,
        skill: SkillDefinition,
        cache: MasterDataCache,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .spellChargeRecoveryChance, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: .spellChargeRecoveryChance, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        guard let recovery = skillEffects.spell.chargeRecoveries.first else {
            throw VerificationError.failed("spellChargeRecovery not compiled")
        }
        let expectedChance = try payload.resolvedChancePercent(stats: defaultActorStats(),
                                                               skillId: skill.id,
                                                               effectIndex: 0) ?? 0.0
        rawData["spellChargeRecoveryChance"] = expectedChance
        try assertApproxEqual(recovery.baseChancePercent, expectedChance, tolerance: 0.0001, message: "spellChargeRecoveryChance")

        let targetSpell = cache.allSpells.first ?? SpellDefinition(
            id: 1,
            name: "TestSpell",
            school: .mage,
            tier: 1,
            unlockLevel: 1,
            category: .damage,
            targeting: .singleEnemy,
            maxTargetsBase: 1,
            extraTargetsPerLevels: nil,
            hitsPerCast: 1,
            basePowerMultiplier: 1.0,
            statusId: nil,
            buffs: [],
            healMultiplier: nil,
            healPercentOfMaxHP: nil,
            castCondition: nil,
            description: ""
        )
        let loadout = SkillRuntimeEffects.SpellLoadout(mage: [targetSpell], priest: [])
        var actor = TestActorBuilder.makePlayer(luck: 18, skillEffects: skillEffects)
        actor.spells = loadout
        actor.actionResources.initializeSpellCharges(from: loadout)
        actor.actionResources.setSpellCharges(for: targetSpell.id, current: 0, max: 1)
        var context = makeContext(players: [actor], enemies: [], statusDefinitions: [:])
        withFixedMedianRandomMode {
            BattleTurnEngine.applySpellChargeRecovery(&context)
        }
        let recovered = context.players[0].actionResources.charges(forSpellId: targetSpell.id)
        if expectedBoolFromChancePercent(expectedChance) && recovered == 0 {
            throw VerificationError.failed("spellChargeRecovery did not recover")
        }
    }

    func verifyStatusInflict(
        segment: EffectSegment,
        skill: SkillDefinition,
        cache: MasterDataCache,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .statusInflict, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        guard let inflict = skillEffects.status.inflictions.first else {
            throw VerificationError.failed("statusInflict not compiled")
        }
        let statusId = inflict.statusId
        let attacker = TestActorBuilder.makeAttacker(luck: 18, skillEffects: skillEffects)
        var defender = TestActorBuilder.makeDefender(luck: 1)
        var context = makeContext(players: [attacker], enemies: [defender], statusDefinitions: cache.statusEffectsById)
        withFixedMedianRandomMode {
            BattleTurnEngine.attemptInflictStatuses(from: attacker, to: &defender, context: &context)
        }
        let applied = defender.statusEffects.contains { $0.id == statusId }
        let baseChance = BattleTurnEngine.statusInflictBaseChance(for: inflict, attacker: attacker, defender: defender)
        let chancePercent = BattleTurnEngine.statusApplicationChancePercent(basePercent: baseChance,
                                                                            statusId: statusId,
                                                                            target: defender,
                                                                            sourceProcMultiplier: attacker.skillEffects.combat.procChanceMultiplier)
        rawData["statusChance"] = chancePercent
        if expectedBoolFromChancePercent(chancePercent) && !applied {
            throw VerificationError.failed("statusInflict not applied")
        }
        if !expectedBoolFromChancePercent(chancePercent) && applied {
            throw VerificationError.failed("statusInflict applied unexpectedly")
        }
    }

    func verifyStatusResistance(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        cache: MasterDataCache,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: effectType, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let targets = try resolveStatusResistanceTargets(payload: payload)
        guard let statusId = targets.first else { return }
        let resistance = skillEffects.status.resistances[statusId] ?? .neutral
        let baseChance = 100.0
        let target = TestActorBuilder.makeDefender(luck: 1, skillEffects: skillEffects)
        let actual = BattleTurnEngine.statusApplicationChancePercent(basePercent: baseChance,
                                                                     statusId: statusId,
                                                                     target: target,
                                                                     sourceProcMultiplier: 1.0)
        let expected = baseChance * resistance.multiplier * (1.0 + resistance.additivePercent / 100.0)
        rawData["statusResistanceExpected"] = expected
        rawData["statusResistanceActual"] = actual
        try assertApproxEqual(actual, expected, tolerance: 0.0001, message: "statusResistance")
    }

    func verifyAutoStatusCure(
        segment: EffectSegment,
        skill: SkillDefinition,
        cache: MasterDataCache,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .autoStatusCureOnAlly, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let curer = TestActorBuilder.makePlayer(luck: 18, skillEffects: skillEffects)
        var target = TestActorBuilder.makePlayer(luck: 18)
        let statusId = cache.statusEffectsById.keys.first ?? 1
        target.statusEffects = [AppliedStatusEffect(id: statusId, remainingTurns: 3, source: "test", stackValue: 0)]
        var context = makeContext(players: [curer, target], enemies: [], statusDefinitions: cache.statusEffectsById)
        BattleTurnEngine.applyAutoStatusCureIfNeeded(for: .player, targetIndex: 1, context: &context)
        let cured = context.players[1].statusEffects.isEmpty
        rawData["autoStatusCure"] = cured ? 1 : 0
        if !cured {
            throw VerificationError.failed("autoStatusCureOnAlly not applied")
        }
    }

    func verifyBerserk(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double],
        cache: MasterDataCache
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .berserk, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: .berserk, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let actor = TestActorBuilder.makePlayer(luck: 18, skillEffects: skillEffects)
        var context = makeContext(players: [actor], enemies: [], statusDefinitions: cache.statusEffectsById)
        let chance = segment.values["chancePercent"] ?? payload.value[.chancePercent] ?? 0.0
        let scaledChance = chance * skillEffects.combat.procChanceMultiplier
        rawData["berserkChance"] = scaledChance
        let triggered = withFixedMedianRandomMode { () -> Bool in
            var mutable = actor
            return BattleTurnEngine.shouldTriggerBerserk(for: &mutable, context: &context)
        }
        if expectedBoolFromChancePercent(scaledChance) && !triggered {
            throw VerificationError.failed("berserk not triggered")
        }
        if !expectedBoolFromChancePercent(scaledChance) && triggered {
            throw VerificationError.failed("berserk triggered unexpectedly")
        }
    }

    func verifyExtraAction(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double],
        cache: MasterDataCache
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .extraAction, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let descriptors = skillEffects.combat.extraActions
        guard !descriptors.isEmpty else {
            throw VerificationError.failed("extraAction not compiled")
        }

        func expectedExtraCount(turn: Int) -> Int {
            var total = 0
            for descriptor in descriptors {
                guard descriptor.count > 0 else { continue }
                switch descriptor.trigger {
                case .always:
                    break
                case .battleStart:
                    guard turn == 1 else { continue }
                case .afterTurn:
                    guard turn >= descriptor.triggerTurn else { continue }
                }

                if let duration = descriptor.duration {
                    let startTurn: Int
                    switch descriptor.trigger {
                    case .always, .battleStart:
                        startTurn = 1
                    case .afterTurn:
                        startTurn = descriptor.triggerTurn
                    }
                    guard turn < startTurn + duration else { continue }
                }

                let probability = max(0.0, min(1.0, (descriptor.chancePercent * skillEffects.combat.procChanceMultiplier) / 100.0))
                if probability >= 0.5 {
                    total += descriptor.count
                }
            }
            return total
        }

        func run(turn: Int) -> Int {
            let player = TestActorBuilder.makePlayer(luck: 18, skillEffects: skillEffects)
            let enemy = TestActorBuilder.makeEnemy(luck: 1)
            var context = makeContext(players: [player], enemies: [enemy], statusDefinitions: cache.statusEffectsById)
            context.turn = turn
            let actorId = context.actorIndex(for: .player, arrayIndex: 0)
            withFixedMedianRandomMode {
                BattleTurnEngine.performAction(for: .player,
                                               actorIndex: 0,
                                               context: &context,
                                               forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil))
            }
            return context.actionEntries.filter { $0.actor == actorId }.count
        }

        let baseTurn = 1
        let baseExpected = 1 + expectedExtraCount(turn: baseTurn)
        let baseActual = run(turn: baseTurn)
        rawData["extraActionTurn1"] = Double(baseActual)
        if baseActual != baseExpected {
            throw VerificationError.failed("extraAction count mismatch (turn 1)")
        }

        for descriptor in descriptors {
            switch descriptor.trigger {
            case .battleStart:
                let nonStartTurn = 2
                let expected = 1 + expectedExtraCount(turn: nonStartTurn)
                let actual = run(turn: nonStartTurn)
                rawData["extraActionTurn2"] = Double(actual)
                if actual != expected {
                    throw VerificationError.failed("extraAction count mismatch (turn 2)")
                }
            case .afterTurn:
                let beforeTurn = max(1, descriptor.triggerTurn - 1)
                let expectedBefore = 1 + expectedExtraCount(turn: beforeTurn)
                let actualBefore = run(turn: beforeTurn)
                rawData["extraActionBefore"] = Double(actualBefore)
                if actualBefore != expectedBefore {
                    throw VerificationError.failed("extraAction count mismatch (before trigger)")
                }

                let triggerTurn = descriptor.triggerTurn
                let expectedTrigger = 1 + expectedExtraCount(turn: triggerTurn)
                let actualTrigger = run(turn: triggerTurn)
                rawData["extraActionTrigger"] = Double(actualTrigger)
                if actualTrigger != expectedTrigger {
                    throw VerificationError.failed("extraAction count mismatch (trigger)")
                }
            case .always:
                break
            }
        }
    }

    func verifyReaction(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double],
        cache: MasterDataCache
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .reaction, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        guard let reaction = skillEffects.combat.reactions.first else {
            throw VerificationError.failed("reaction not compiled")
        }

        let performer = TestActorBuilder.makePlayer(luck: 18,
                                                    skillEffects: skillEffects,
                                                    formationSlot: 1,
                                                    isMartialEligible: reaction.requiresMartial)
        let ally = TestActorBuilder.makePlayer(luck: 18,
                                               formationSlot: reaction.requiresAllyBehind ? 5 : 2)
        let enemy = TestActorBuilder.makeEnemy(luck: 1)
        if reaction.requiresAllyBehind, reaction.trigger != .allyDamagedPhysical {
            throw VerificationError.failed("reaction requiresAllyBehind with unsupported trigger")
        }
        var context = makeContext(players: [performer, ally], enemies: [enemy], statusDefinitions: cache.statusEffectsById)

        let event: BattleContext.ReactionEvent = {
            switch reaction.trigger {
            case .allyDefeated: return .allyDefeated(side: .player, fallenIndex: 1, killer: .enemy(0))
            case .selfEvadePhysical: return .selfEvadePhysical(side: .player, actorIndex: 0, attacker: .enemy(0))
            case .selfDamagedPhysical: return .selfDamagedPhysical(side: .player, actorIndex: 0, attacker: .enemy(0))
            case .selfDamagedMagical: return .selfDamagedMagical(side: .player, actorIndex: 0, attacker: .enemy(0))
            case .allyDamagedPhysical: return .allyDamagedPhysical(side: .player, defenderIndex: 1, attacker: .enemy(0))
            case .selfKilledEnemy: return .selfKilledEnemy(side: .player, actorIndex: 0, killedEnemy: .enemy(0))
            case .allyMagicAttack: return .allyMagicAttack(side: .player, casterIndex: 1)
            case .selfAttackNoKill: return .selfAttackNoKill(side: .player, actorIndex: 0, target: .enemy(0))
            case .selfMagicAttack: return .selfMagicAttack(side: .player, casterIndex: 0)
            }
        }()

        let before = context.actionEntries.count
        withFixedMedianRandomMode {
            BattleTurnEngine.dispatchReactions(for: event, depth: 0, context: &context)
        }
        let after = context.actionEntries.count
        rawData["reactionEntries"] = Double(after - before)

        let scaledChance = max(0.0, min(100.0, reaction.baseChancePercent * performer.skillEffects.combat.procChanceMultiplier))
        rawData["reactionChance"] = scaledChance
        let expected = expectedBoolFromChancePercent(scaledChance)
        if expected && after == before {
            throw VerificationError.failed("reaction not triggered")
        }
        if !expected && after > before {
            throw VerificationError.failed("reaction triggered unexpectedly")
        }
    }

    func verifyReactionNextTurn(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .reactionNextTurn, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let player = TestActorBuilder.makePlayer(luck: 18, skillEffects: skillEffects)
        let enemy = TestActorBuilder.makeEnemy(luck: 1)
        var context = makeContext(players: [player], enemies: [enemy], statusDefinitions: [:])
        let order = withFixedMedianRandomMode {
            BattleTurnEngine.actionOrder(&context)
        }
        let playerCount = order.filter { if case .player(let index) = $0 { return index == 0 } else { return false } }.count
        rawData["reactionNextTurnSlots"] = Double(playerCount)
        if playerCount <= 1, skillEffects.combat.nextTurnExtraActions > 0 {
            throw VerificationError.failed("reactionNextTurn not applied")
        }
    }

    func verifyProcMultiplier(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double],
        cache: MasterDataCache
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .procMultiplier, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: .procMultiplier, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let multiplier = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.0
        rawData["procChanceMultiplier"] = skillEffects.combat.procChanceMultiplier
        try assertApproxEqual(skillEffects.combat.procChanceMultiplier, multiplier, tolerance: 0.0001, message: "procMultiplier")

        var actor = TestActorBuilder.makePlayer(luck: 18, skillEffects: skillEffects)
        actor.skillEffects.status.berserkChancePercent = 40
        var context = makeContext(players: [actor], enemies: [], statusDefinitions: cache.statusEffectsById)
        let triggered = withFixedMedianRandomMode { () -> Bool in
            var mutable = actor
            return BattleTurnEngine.shouldTriggerBerserk(for: &mutable, context: &context)
        }
        let scaled = max(0.0, min(100.0, 40.0 * multiplier))
        let expected = expectedBoolFromChancePercent(scaled)
        if expected != triggered {
            throw VerificationError.failed("procMultiplier not applied to berserk")
        }
    }

    func verifyProcRate(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .procRate, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: .procRate, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let target = payload.parameters[.target] ?? 0
        let base = 100.0
        let adjusted = skillEffects.combat.procRateModifier.adjustedChance(base: base, target: target)
        rawData["procRateAdjusted"] = adjusted

        if let multiplier = payload.value[.multiplier] {
            let expected = base * multiplier
            try assertApproxEqual(adjusted, expected, tolerance: 0.0001, message: "procRate multiplier")
        } else if let addPercent = payload.value[.addPercent] {
            let expected = base + addPercent
            try assertApproxEqual(adjusted, expected, tolerance: 0.0001, message: "procRate additive")
        }
    }

    func verifyCounterAttackEvasionMultiplier(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .counterAttackEvasionMultiplier, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: .counterAttackEvasionMultiplier, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let multiplier = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.0
        rawData["counterAttackEvasionMultiplier"] = skillEffects.combat.counterAttackEvasionMultiplier
        try assertApproxEqual(skillEffects.combat.counterAttackEvasionMultiplier, multiplier, tolerance: 0.0001, message: "counterAttackEvasionMultiplier")
    }

    func verifyActionOrder(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: effectType, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())

        switch effectType {
        case .actionOrderMultiplier:
            let multiplier = segment.values["multiplier"] ?? payload.value[.multiplier] ?? 1.0
            rawData["actionOrderMultiplier"] = multiplier
            let playerWithSkill = TestActorBuilder.makePlayer(luck: 18, agility: 20, skillEffects: skillEffects)
            let playerNeutral = TestActorBuilder.makePlayer(luck: 18, agility: 20)
            var context = makeContext(players: [playerWithSkill, playerNeutral], enemies: [], statusDefinitions: [:])
            let order = withFixedMedianRandomMode {
                BattleTurnEngine.actionOrder(&context)
            }
            if multiplier > 1.0 {
                if case .player(let index) = order.first, index != 0 {
                    throw VerificationError.failed("actionOrderMultiplier not applied (expected faster)")
                }
            } else if multiplier < 1.0 {
                if case .player(let index) = order.first, index != 1 {
                    throw VerificationError.failed("actionOrderMultiplier not applied (expected slower)")
                }
            }
        case .actionOrderShuffle:
            guard skillEffects.combat.actionOrderShuffle else {
                throw VerificationError.failed("actionOrderShuffle flag not set")
            }
            let shuffled = TestActorBuilder.makePlayer(luck: 1, agility: 10, skillEffects: skillEffects)
            let normal = TestActorBuilder.makePlayer(luck: 1, agility: 8000)
            var context = makeContext(players: [shuffled, normal], enemies: [], statusDefinitions: [:])
            let order = withFixedMedianRandomMode {
                BattleTurnEngine.actionOrder(&context)
            }
            if case .player(let index) = order.first, index != 0 {
                throw VerificationError.failed("actionOrderShuffle not applied")
            }
        case .actionOrderShuffleEnemy:
            guard skillEffects.combat.actionOrderShuffleEnemy else {
                throw VerificationError.failed("actionOrderShuffleEnemy flag not set")
            }
            let player = TestActorBuilder.makePlayer(luck: 1, agility: 6000, skillEffects: skillEffects)
            let enemy = TestActorBuilder.makeEnemy(luck: 1, agility: 10)
            var context = makeContext(players: [player], enemies: [enemy], statusDefinitions: [:])
            let order = withFixedMedianRandomMode {
                BattleTurnEngine.actionOrder(&context)
            }
            if case .enemy = order.first {
                // expected: shuffle enemy should act first
            } else {
                throw VerificationError.failed("actionOrderShuffleEnemy not applied")
            }
        case .firstStrike:
            guard skillEffects.combat.firstStrike else {
                throw VerificationError.failed("firstStrike flag not set")
            }
            let striker = TestActorBuilder.makePlayer(luck: 1, agility: 10, skillEffects: skillEffects)
            let fast = TestActorBuilder.makePlayer(luck: 1, agility: 8000)
            var context = makeContext(players: [striker, fast], enemies: [], statusDefinitions: [:])
            let order = withFixedMedianRandomMode {
                BattleTurnEngine.actionOrder(&context)
            }
            if case .player(let index) = order.first, index != 0 {
                throw VerificationError.failed("firstStrike not applied")
            }
        default:
            break
        }
    }

    func verifyEnemyActionDebuff(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: effectType, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())

        switch effectType {
        case .enemyActionDebuffChance:
            let chance = try payload.resolvedChancePercent(stats: defaultActorStats(), skillId: skill.id, effectIndex: 0) ?? 0.0
            let reduction = Int((payload.value[.reduction] ?? 1.0).rounded(.towardZero))
            guard let debuff = skillEffects.combat.enemyActionDebuffs.first else {
                throw VerificationError.failed("enemyActionDebuffChance not compiled")
            }
            rawData["enemyActionDebuffChance"] = chance
            try assertApproxEqual(debuff.baseChancePercent, chance, tolerance: 0.0001, message: "enemyActionDebuffChance")
            try assertEqualInt(debuff.reduction, max(1, reduction), message: "enemyActionDebuff reduction")
        case .enemySingleActionSkipChance:
            let chance = segment.values["chancePercent"] ?? payload.value[.chancePercent] ?? 0.0
            rawData["enemySkipChance"] = chance
            try assertApproxEqual(skillEffects.combat.enemySingleActionSkipChancePercent,
                                  chance,
                                  tolerance: 0.0001,
                                  message: "enemySingleActionSkipChance")
        default:
            break
        }
    }

    func verifyCumulativeHitBonus(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .cumulativeHitDamageBonus, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: .cumulativeHitDamageBonus, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        var attacker = TestActorBuilder.makeAttacker(luck: 18, skillEffects: skillEffects)
        attacker.attackHistory = BattleAttackHistory(firstHitDone: true, consecutiveHits: 3)
        let defender = TestActorBuilder.makeDefender(luck: 1)
        var context = makeContext(players: [attacker], enemies: [defender], statusDefinitions: [:])
        let hitChance = BattleTurnEngine.computeHitChance(attacker: attacker,
                                                          defender: defender,
                                                          hitIndex: 1,
                                                          accuracyMultiplier: 1.0,
                                                          context: &context)
        rawData["hitChance"] = hitChance
        let damagePercent = segment.values["damagePercent"] ?? payload.value[.damagePercent] ?? 0.0
        let expectedMultiplier = 1.0 + damagePercent * Double(attacker.attackHistory.consecutiveHits) / 100.0
        let baseDamage = withFixedMedianRandomMode {
            var ctx = makeContext(players: [TestActorBuilder.makeAttacker(luck: 18)],
                                  enemies: [defender],
                                  statusDefinitions: [:])
            var baseDef = defender
            return BattleTurnEngine.computePhysicalDamage(attacker: TestActorBuilder.makeAttacker(luck: 18),
                                                         defender: &baseDef,
                                                         hitIndex: 1,
                                                         context: &ctx).damage
        }
        let modDamage = withFixedMedianRandomMode {
            var ctx = makeContext(players: [attacker], enemies: [defender], statusDefinitions: [:])
            var def = defender
            return BattleTurnEngine.computePhysicalDamage(attacker: attacker,
                                                         defender: &def,
                                                         hitIndex: 1,
                                                         context: &ctx).damage
        }
        let ratio = baseDamage > 0 ? Double(modDamage) / Double(baseDamage) : 0
        try assertApproxEqual(ratio, expectedMultiplier, tolerance: 0.2, message: "cumulativeHitDamageBonus")
    }

    func verifySpecialAttack(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .specialAttack, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: .specialAttack, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        guard let kind = specialAttackKind(from: payload) else {
            throw VerificationError.failed("specialAttack missing kind")
        }
        let chance = segment.values["chancePercent"] ?? payload.value[.chancePercent] ?? 0.0
        var context = makeContext(players: [TestActorBuilder.makePlayer(luck: 18, skillEffects: skillEffects)],
                                  enemies: [TestActorBuilder.makeEnemy(luck: 1)],
                                  statusDefinitions: [:])
        let selected = withFixedMedianRandomMode { () -> BattleActor.SkillEffects.SpecialAttack? in
            BattleTurnEngine.selectSpecialAttack(for: context.players[0], context: &context)
        }
        rawData["specialAttackSelected"] = selected == nil ? 0 : 1
        if expectedBoolFromChancePercent(chance) {
            guard selected?.kind == kind else {
                throw VerificationError.failed("specialAttack not selected")
            }
        }
    }

    func verifyBarrier(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: effectType, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let damageType = resolveDamageType(segment: segment, payload: payload)
        let key = BattleTurnEngine.barrierKey(for: damageType)
        var defender = TestActorBuilder.makeDefender(luck: 18,
                                                     skillEffects: skillEffects,
                                                     guardActive: effectType == .barrierOnGuard,
                                                     barrierCharges: skillEffects.combat.barrierCharges,
                                                     guardBarrierCharges: skillEffects.combat.guardBarrierCharges)
        let before = defender.barrierCharges[key] ?? defender.guardBarrierCharges[key] ?? 0
        let multiplier = BattleTurnEngine.applyBarrierIfAvailable(for: damageType, defender: &defender)
        rawData["barrierMultiplier"] = multiplier
        if before > 0 && abs(multiplier - (1.0 / 3.0)) > 0.0001 {
            throw VerificationError.failed("barrier not applied")
        }
    }

    func verifyParryOrBlock(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: effectType, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let defender = TestActorBuilder.makeDefender(luck: 18, skillEffects: skillEffects)
        let attacker = TestActorBuilder.makeAttacker(luck: 18)
        var context = makeContext(players: [attacker], enemies: [defender], statusDefinitions: [:])
        let triggered: Bool
        let chance: Double
        switch effectType {
        case .parry:
            guard skillEffects.combat.parryEnabled else {
                throw VerificationError.failed("parry not enabled")
            }
            triggered = withFixedMedianRandomMode {
                var mutable = defender
                return BattleTurnEngine.shouldTriggerParry(defender: &mutable, attacker: attacker, context: &context)
            }
            let defenderBonus = Double(defender.snapshot.additionalDamageScore) * 0.25
            let attackerPenalty = Double(attacker.snapshot.additionalDamageScore) * 0.5
            let base = 10.0 + defenderBonus - attackerPenalty + skillEffects.combat.parryBonusPercent
            chance = max(0.0, min(100.0, (base * skillEffects.combat.procChanceMultiplier).rounded()))
        case .shieldBlock:
            guard skillEffects.combat.shieldBlockEnabled else {
                throw VerificationError.failed("shieldBlock not enabled")
            }
            triggered = withFixedMedianRandomMode {
                var mutable = defender
                return BattleTurnEngine.shouldTriggerShieldBlock(defender: &mutable, attacker: attacker, context: &context)
            }
            let base = 30.0 - Double(attacker.snapshot.additionalDamageScore) / 2.0 + skillEffects.combat.shieldBlockBonusPercent
            chance = max(0.0, min(100.0, (base * skillEffects.combat.procChanceMultiplier).rounded()))
        default:
            triggered = false
            chance = 0.0
        }
        _ = segment.values["bonusPercent"] ?? payload.value[.bonusPercent] ?? 0.0
        rawData["parryOrBlockTriggered"] = triggered ? 1 : 0
        rawData["parryOrBlockChance"] = chance
        let expected = expectedBoolFromChancePercent(chance)
        if expected && !triggered {
            throw VerificationError.failed("parry/shieldBlock not triggered")
        }
        if !expected && triggered {
            throw VerificationError.failed("parry/shieldBlock triggered unexpectedly")
        }
    }

    func verifyPartyAttack(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: effectType, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let attacker = TestActorBuilder.makePlayer(luck: 18, skillEffects: skillEffects)

        switch effectType {
        case .partyAttackFlag:
            if payload.value[.hostileAll] != nil, !attacker.skillEffects.misc.partyHostileAll {
                throw VerificationError.failed("partyAttackFlag hostileAll not applied")
            }
        case .partyAttackTarget:
            let targetId = payload.parameters[.targetId] ?? 0
            if payload.value[.hostile] != nil, !attacker.skillEffects.misc.partyHostileTargets.contains(targetId) {
                throw VerificationError.failed("partyAttackTarget hostile not applied")
            }
            if payload.value[.protect] != nil, !attacker.skillEffects.misc.partyProtectedTargets.contains(targetId) {
                throw VerificationError.failed("partyAttackTarget protect not applied")
            }
        default:
            break
        }
    }

    func verifyBreathVariant(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .breathVariant, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: .breathVariant, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let extra = segment.values["extraCharges"] ?? payload.value[.extraCharges] ?? 0.0
        rawData["breathExtraCharges"] = Double(skillEffects.spell.breathExtraCharges)
        try assertEqualInt(skillEffects.spell.breathExtraCharges, Int(extra), message: "breathVariant")
    }

    func verifyReverseHealing(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .reverseHealing, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        var attacker = TestActorBuilder.makeAttacker(physicalAttackScore: 100,
                                                     magicalAttackScore: 100,
                                                     hitScore: 100,
                                                     luck: 18,
                                                     criticalChancePercent: 0,
                                                     additionalDamageScore: 0,
                                                     breathDamageScore: 0,
                                                     skillEffects: skillEffects)
        attacker.snapshot.magicalHealingScore = 5000
        let defender = TestActorBuilder.makeDefender(luck: 1)
        var context = makeContext(players: [attacker], enemies: [defender], statusDefinitions: [:])
        withFixedMedianRandomMode {
            BattleTurnEngine.resolvePhysicalAction(attackerSide: .player,
                                                   attackerIndex: 0,
                                                   target: (.enemy, 0),
                                                   context: &context)
        }
        let damage = context.actionEntries.last?.effects.first(where: { $0.kind == .physicalDamage })?.value ?? 0
        rawData["reverseHealingDamage"] = Double(damage)
        if damage == 0 {
            throw VerificationError.failed("reverseHealing damage not applied")
        }
    }

    func verifyAbsorption(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .absorption, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: .absorption, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        var attacker = TestActorBuilder.makeAttacker(luck: 18, skillEffects: skillEffects)
        attacker.currentHP = attacker.snapshot.maxHP / 2
        var context = makeContext(players: [attacker], enemies: [], statusDefinitions: [:])
        let percent = segment.values["percent"] ?? payload.value[.percent] ?? 0.0
        let capPercent = segment.values["capPercent"] ?? payload.value[.capPercent] ?? 0.0
        let expectedRaw = Double(1000) * percent / 100.0
        let cap = Double(attacker.snapshot.maxHP) * capPercent / 100.0
        let expectedHeal = min(expectedRaw, cap > 0 ? cap : expectedRaw)
        let healed = BattleTurnEngine.applyAbsorptionIfNeeded(for: &attacker,
                                                              damageDealt: 1000,
                                                              damageType: .physical,
                                                              context: &context)
        rawData["absorptionHealed"] = Double(healed)
        if expectedHeal > 0, healed == 0 {
            throw VerificationError.failed("absorption not applied")
        }
    }

    func verifyRunaway(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double],
        cache: MasterDataCache
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: effectType, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let thresholdPercent = segment.values["thresholdPercent"] ?? payload.value[.thresholdPercent] ?? 0.0
        let chance = segment.values["chancePercent"] ?? payload.value[.chancePercent] ?? 0.0
        rawData["runawayChance"] = chance

        func run(damage: Int) -> Bool {
            let defender = TestActorBuilder.makeDefender(luck: 18, skillEffects: skillEffects)
            let ally = TestActorBuilder.makeDefender(luck: 1)
            var context = makeContext(players: [defender, ally], enemies: [], statusDefinitions: cache.statusEffectsById)
            let builder = context.makeActionEntryBuilder(actorId: context.actorIndex(for: .player, arrayIndex: 0), kind: .physicalAttack)
            withFixedMedianRandomMode {
                BattleTurnEngine.attemptRunawayIfNeeded(for: .player, defenderIndex: 0, damage: damage, context: &context, entryBuilder: builder)
            }
            return context.players[0].statusEffects.contains { effect in
                cache.statusEffectsById[effect.id]?.tags.contains(BattleTurnEngine.statusTagConfusion) ?? false
            }
        }

        let maxHP = TestActorBuilder.makeDefender(luck: 18).snapshot.maxHP
        let thresholdDamage = Int((Double(maxHP) * thresholdPercent / 100.0).rounded(.towardZero))
        let belowTriggered = run(damage: max(0, thresholdDamage - 1))
        if belowTriggered {
            throw VerificationError.failed("runaway triggered below threshold")
        }

        let aboveTriggered = run(damage: thresholdDamage + 1)
        rawData["runawayTriggered"] = aboveTriggered ? 1 : 0
        let expected = expectedBoolFromChancePercent(chance)
        if expected && !aboveTriggered {
            throw VerificationError.failed("runaway not triggered")
        }
        if !expected && aboveTriggered {
            throw VerificationError.failed("runaway triggered unexpectedly")
        }
    }

    func verifyRetreatAtTurn(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .retreatAtTurn, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: .retreatAtTurn, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let chance = payload.value[.chancePercent] ?? 100.0
        let forcedTurnValue = payload.value[.turn].map { Int($0.rounded(.towardZero)) }
        rawData["retreatChance"] = chance
        if let forcedTurnValue {
            rawData["retreatTurn"] = Double(forcedTurnValue)
        }

        func run(turn: Int) -> Bool {
            let actor = TestActorBuilder.makePlayer(luck: 18, skillEffects: skillEffects)
            var context = makeContext(players: [actor], enemies: [], statusDefinitions: [:])
            context.turn = turn
            withFixedMedianRandomMode {
                BattleTurnEngine.applyRetreatIfNeeded(&context)
            }
            return context.players[0].currentHP <= 0
        }

        if let forcedTurnValue {
            if forcedTurnValue > 1 {
                let preTriggered = run(turn: forcedTurnValue - 1)
                if preTriggered {
                    throw VerificationError.failed("retreatAtTurn triggered before turn")
                }
            }
            let triggered = run(turn: forcedTurnValue)
            let expected = expectedBoolFromChancePercent(chance)
            if expected && !triggered {
                throw VerificationError.failed("retreatAtTurn not applied")
            }
            if !expected && triggered {
                throw VerificationError.failed("retreatAtTurn triggered unexpectedly")
            }
        } else {
            let triggered = run(turn: 1)
            let expected = expectedBoolFromChancePercent(chance)
            if expected && !triggered {
                throw VerificationError.failed("retreatAtTurn not applied")
            }
            if !expected && triggered {
                throw VerificationError.failed("retreatAtTurn triggered unexpectedly")
            }
        }
    }

    func verifySacrificeRite(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .sacrificeRite, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        guard let interval = skillEffects.resurrection.sacrificeInterval else {
            throw VerificationError.failed("sacrificeRite not compiled")
        }
        let sacrificer = TestActorBuilder.makePlayer(luck: 18, skillEffects: skillEffects, level: 20)
        let target = TestActorBuilder.makePlayer(luck: 18)
        var context = makeContext(players: [sacrificer, target], enemies: [], statusDefinitions: [:])
        context.turn = max(1, interval)
        let targets = BattleTurnEngine.computeSacrificeTargets(&context)
        rawData["sacrificeTarget"] = targets.playerTarget == nil ? 0 : 1
        if targets.playerTarget == nil {
            throw VerificationError.failed("sacrificeRite not applied")
        }
    }

    func verifyTargetingWeight(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .targetingWeight, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: .targetingWeight, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let normal = TestActorBuilder.makeEnemy(luck: 1)
        let weighted = TestActorBuilder.makeEnemy(luck: 1, skillEffects: skillEffects)
        var context = makeContext(players: [TestActorBuilder.makePlayer(luck: 18)],
                                  enemies: [normal, weighted],
                                  statusDefinitions: [:])
        let target = withFixedMedianRandomMode {
            BattleTurnEngine.selectOffensiveTarget(attackerSide: .player,
                                                   context: &context,
                                                   allowFriendlyTargets: false,
                                                   attacker: context.players[0],
                                                   forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil))
        }
        let weight = payload.value[.weight] ?? payload.value[.multiplier] ?? 1.0
        rawData["targetingWeightSelected"] = target?.1 == 1 ? 1 : 0
        if weight > 1.0, target?.1 != 1 {
            throw VerificationError.failed("targetingWeight not applied (expected weighted target)")
        }
        if weight < 1.0, target?.1 != 0 {
            throw VerificationError.failed("targetingWeight not applied (expected normal target)")
        }
    }

    func verifyCoverRowsBehind(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .coverRowsBehind, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: .coverRowsBehind, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let condition = segment.semantics["condition"] ?? resolvedConditionName(from: payload)

        func resolveSelection(targetHPPercent: Double) -> Int? {
            let cover = TestActorBuilder.makePlayer(luck: 18, skillEffects: skillEffects, formationSlot: 1)
            var target = TestActorBuilder.makePlayer(luck: 18, formationSlot: 5)
            target.currentHP = Int((Double(target.snapshot.maxHP) * targetHPPercent).rounded(.towardZero))
            target.skillEffects.misc.targetingWeight = 2.0

            var context = makeContext(players: [cover, target],
                                      enemies: [TestActorBuilder.makeEnemy(luck: 1)],
                                      statusDefinitions: [:])
            let selected = withFixedMedianRandomMode {
                BattleTurnEngine.selectOffensiveTarget(attackerSide: .enemy,
                                                       context: &context,
                                                       allowFriendlyTargets: false,
                                                       attacker: context.enemies[0],
                                                       forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil))
            }
            return selected?.1
        }

        let highHPSelected = resolveSelection(targetHPPercent: 1.0)
        let lowHPSelected = resolveSelection(targetHPPercent: 0.4)
        rawData["coverSelectedHighHP"] = highHPSelected == 0 ? 1 : 0
        rawData["coverSelectedLowHP"] = lowHPSelected == 0 ? 1 : 0

        if condition == "allyHPBelow50" {
            if highHPSelected == 0 {
                throw VerificationError.failed("coverRowsBehind should not trigger when HP >= 50%")
            }
            if lowHPSelected != 0 {
                throw VerificationError.failed("coverRowsBehind not triggered when HP < 50%")
            }
        } else {
            if highHPSelected != 0 {
                throw VerificationError.failed("coverRowsBehind not triggered")
            }
        }
    }

    func verifyEndOfTurnHealing(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: effectType, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let healer = TestActorBuilder.makePlayer(luck: 18, skillEffects: skillEffects)
        var target = TestActorBuilder.makePlayer(luck: 18)
        target.currentHP = target.snapshot.maxHP / 2
        var context = makeContext(players: [healer, target], enemies: [], statusDefinitions: [:])

        switch effectType {
        case .endOfTurnHealing:
            BattleTurnEngine.applyEndOfTurnPartyHealing(for: .player, context: &context)
            let healed = context.players[1].currentHP
            rawData["endOfTurnHealingHP"] = Double(healed)
            if healed <= target.snapshot.maxHP / 2 {
                throw VerificationError.failed("endOfTurnHealing not applied")
            }
        case .endOfTurnSelfHPPercent:
            var actor = context.players[0]
            actor.currentHP = actor.snapshot.maxHP / 2
            let beforeHP = actor.currentHP
            BattleTurnEngine.applyEndOfTurnSelfHPDeltaIfNeeded(for: .player, index: 0, actor: &actor, context: &context)
            rawData["endOfTurnSelfHP"] = Double(actor.currentHP)
            let percent = segment.values["valuePercent"] ?? payload.value[.valuePercent] ?? 0.0
            if percent > 0 {
                if actor.currentHP <= beforeHP {
                    throw VerificationError.failed("endOfTurnSelfHPPercent not applied")
                }
            } else if percent < 0 {
                if actor.currentHP >= beforeHP {
                    throw VerificationError.failed("endOfTurnSelfHPPercent not applied")
                }
            } else if actor.currentHP != beforeHP {
                throw VerificationError.failed("endOfTurnSelfHPPercent unexpected change")
            }
        default:
            break
        }
    }

    func verifyTimedBuff(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: effectType, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let actor = TestActorBuilder.makePlayer(luck: 18, skillEffects: skillEffects)
        var context = makeContext(players: [actor], enemies: [], statusDefinitions: [:])
        switch effectType {
        case .timedBuffTrigger:
            let triggerRaw = payload.parameters[.trigger] ?? Int(ReactionTrigger.battleStart.rawValue)
            context.turn = 1
            let before = context.players[0].snapshot
            BattleTurnEngine.applyTimedBuffTriggers(&context, includeEveryTurn: true)
            rawData["timedBuffCount"] = Double(context.players[0].timedBuffs.count)
            if triggerRaw == Int(ReactionTrigger.turnElapsed.rawValue) {
                let after = context.players[0].snapshot
                if let hitAdd = payload.value[.hitScoreAdditivePerTurn] {
                    let expected = before.hitScore + Int(hitAdd.rounded(.towardZero))
                    rawData["timedBuffHitScore"] = Double(after.hitScore)
                    try assertEqualInt(after.hitScore, expected, message: "timedBuffTrigger hitScore per turn")
                }
                if let evadeAdd = payload.value[.evasionScoreAdditivePerTurn] {
                    let expected = before.evasionScore + Int(evadeAdd.rounded(.towardZero))
                    rawData["timedBuffEvasion"] = Double(after.evasionScore)
                    try assertEqualInt(after.evasionScore, expected, message: "timedBuffTrigger evasion per turn")
                }
                if let attackPercent = payload.value[.attackPercentPerTurn] {
                    let bonus = Int((Double(before.physicalAttackScore) * attackPercent / 100.0).rounded(.towardZero))
                    let expected = before.physicalAttackScore + bonus
                    rawData["timedBuffAttack"] = Double(after.physicalAttackScore)
                    try assertEqualInt(after.physicalAttackScore, expected, message: "timedBuffTrigger attack per turn")
                }
                if let defensePercent = payload.value[.defensePercentPerTurn] {
                    let bonus = Int((Double(before.physicalDefenseScore) * defensePercent / 100.0).rounded(.towardZero))
                    let expected = before.physicalDefenseScore + bonus
                    rawData["timedBuffDefense"] = Double(after.physicalDefenseScore)
                    try assertEqualInt(after.physicalDefenseScore, expected, message: "timedBuffTrigger defense per turn")
                }
                if let attackCountPercent = payload.value[.attackCountPercentPerTurn] {
                    let bonus = before.attackCount * attackCountPercent / 100.0
                    let expected = max(1.0, before.attackCount + bonus)
                    rawData["timedBuffAttackCount"] = after.attackCount
                    try assertApproxEqual(after.attackCount, expected, tolerance: 0.0001, message: "timedBuffTrigger attackCount per turn")
                }
            } else {
                guard let buff = context.players[0].timedBuffs.first else {
                    throw VerificationError.failed("timedBuffTrigger not applied")
                }
                if let percent = payload.value[.damageDealtPercent] {
                    let expected = 1.0 + percent / 100.0
                    let physical = buff.statModifiers["physicalDamageDealtMultiplier"] ?? 1.0
                    let magical = buff.statModifiers["magicalDamageDealtMultiplier"] ?? 1.0
                    let breath = buff.statModifiers["breathDamageDealtMultiplier"] ?? 1.0
                    try assertApproxEqual(physical, expected, tolerance: 0.0001, message: "timedBuff damageDealt physical")
                    try assertApproxEqual(magical, expected, tolerance: 0.0001, message: "timedBuff damageDealt magical")
                    try assertApproxEqual(breath, expected, tolerance: 0.0001, message: "timedBuff damageDealt breath")
                }
                if let hitAdd = payload.value[.hitScoreAdditive] {
                    let actual = buff.statModifiers["hitScoreAdditive"] ?? 0.0
                    try assertApproxEqual(actual, hitAdd, tolerance: 0.0001, message: "timedBuff hitScoreAdditive")
                }
            }
        case .timedMagicPowerAmplify, .timedBreathPowerAmplify, .tacticSpellAmplify:
            let turn = Int((payload.value[.triggerTurn] ?? 1).rounded(.towardZero))
            context.turn = turn
            BattleTurnEngine.applyTimedBuffTriggers(&context, includeEveryTurn: true)
            switch effectType {
            case .timedMagicPowerAmplify:
                guard let buff = context.players[0].timedBuffs.first else {
                    throw VerificationError.failed("timedMagicPowerAmplify not applied")
                }
                let multiplier = payload.value[.multiplier] ?? 1.0
                let actual = buff.statModifiers["magicalDamageDealtMultiplier"] ?? 1.0
                try assertApproxEqual(actual, multiplier, tolerance: 0.0001, message: "timedMagicPowerAmplify")
            case .timedBreathPowerAmplify:
                guard let buff = context.players[0].timedBuffs.first else {
                    throw VerificationError.failed("timedBreathPowerAmplify not applied")
                }
                let multiplier = payload.value[.multiplier] ?? 1.0
                let actual = buff.statModifiers["breathDamageDealtMultiplier"] ?? 1.0
                try assertApproxEqual(actual, multiplier, tolerance: 0.0001, message: "timedBreathPowerAmplify")
            case .tacticSpellAmplify:
                guard let spellIdRaw = payload.parameters[.spellId] else {
                    throw VerificationError.failed("tacticSpellAmplify missing spellId")
                }
                let multiplier = payload.value[.multiplier] ?? 1.0
                let spellId = UInt8(clamping: spellIdRaw)
                let actual = context.players[0].skillEffects.spell.specificMultipliers[spellId, default: 1.0]
                try assertApproxEqual(actual, multiplier, tolerance: 0.0001, message: "tacticSpellAmplify")
            default:
                break
            }
        default:
            break
        }
    }

    func verifyResurrection(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        cache: MasterDataCache,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: effectType, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        var actor = TestActorBuilder.makePlayer(luck: 18, skillEffects: skillEffects)
        actor.currentHP = 0
        var context = makeContext(players: [actor], enemies: [], statusDefinitions: cache.statusEffectsById)

        switch effectType {
        case .resurrectionActive:
            let chance = payload.value[.chancePercent] ?? 0.0
            rawData["resurrectionChance"] = chance
            withFixedMedianRandomMode {
                BattleTurnEngine.applyEndOfTurnResurrectionIfNeeded(for: .player, index: 0, actor: &actor, context: &context, allowVitalize: true)
            }
            rawData["resurrectionHP"] = Double(actor.currentHP)
            let expected = expectedBoolFromChancePercent(chance)
            if expected && actor.currentHP <= 0 {
                throw VerificationError.failed("resurrectionActive not applied")
            }
            if !expected && actor.currentHP > 0 {
                throw VerificationError.failed("resurrectionActive triggered unexpectedly")
            }

        case .resurrectionBuff:
            guard let forced = skillEffects.resurrection.forced else {
                throw VerificationError.failed("resurrectionBuff not compiled")
            }
            rawData["resurrectionForced"] = forced.maxTriggers == nil ? 1 : Double(forced.maxTriggers ?? 0)

        case .resurrectionSave:
            let minLevelRaw = payload.value[.minLevel] ?? 0.0
            let minLevel = max(0, Int(minLevelRaw.rounded(.towardZero)))
            if (actor.level ?? 0) < minLevel {
                actor = TestActorBuilder.makePlayer(luck: 18, skillEffects: skillEffects, level: max(1, minLevel))
            }
            let capabilities = BattleTurnEngine.availableRescueCapabilities(for: actor)
            if capabilities.isEmpty {
                throw VerificationError.failed("resurrectionSave not applied")
            }

        case .resurrectionSummon:
            guard let interval = skillEffects.resurrection.necromancerInterval else {
                throw VerificationError.failed("resurrectionSummon not compiled")
            }
            rawData["necromancerInterval"] = Double(interval)
            func buildSummonContext(turn: Int) -> BattleContext {
                let caster = TestActorBuilder.makePlayer(luck: 18, skillEffects: skillEffects)
                var target = TestActorBuilder.makePlayer(luck: 18)
                target.currentHP = 0
                target.skillEffects.resurrection.actives = [
                    .init(chancePercent: 100, hpScale: .maxHP5Percent, maxTriggers: nil)
                ]
                var context = makeContext(players: [caster, target], enemies: [], statusDefinitions: cache.statusEffectsById)
                context.turn = turn
                return context
            }

            if interval > 1 {
                var preContext = buildSummonContext(turn: 2 + interval - 1)
                BattleTurnEngine.applyNecromancerIfNeeded(for: .player, context: &preContext)
                let preRevived = preContext.players[1].currentHP > 0
                rawData["necromancerPreRevive"] = preRevived ? 1 : 0
                if preRevived {
                    throw VerificationError.failed("resurrectionSummon triggered early")
                }
            }

            var triggerContext = buildSummonContext(turn: 2)
            BattleTurnEngine.applyNecromancerIfNeeded(for: .player, context: &triggerContext)
            let revived = triggerContext.players[1].currentHP > 0
            rawData["necromancerRevived"] = revived ? 1 : 0
            if !revived {
                throw VerificationError.failed("resurrectionSummon not applied")
            }

        case .resurrectionPassive:
            if !skillEffects.resurrection.passiveBetweenFloors {
                throw VerificationError.failed("resurrectionPassive not applied")
            }

        case .resurrectionVitalize:
            if skillEffects.resurrection.vitalize == nil {
                throw VerificationError.failed("resurrectionVitalize not applied")
            }

        default:
            break
        }
    }

    func verifyEquipmentSlots(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let slots = try compileEquipmentSlots(skill: segmentSkill)
        let base = EquipmentSlotCalculator.baseCapacity(forLevel: 10)
        let adjusted = EquipmentSlotCalculator.capacity(forLevel: 10, modifiers: slots)
        rawData["equipmentSlots"] = Double(adjusted)
        if adjusted == base {
            throw VerificationError.failed("equipmentSlots not applied")
        }
    }

    func verifyRewardComponents(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let components = try compileRewardComponents(skill: segmentSkill)
        switch effectType {
        case .rewardExperiencePercent, .rewardExperienceMultiplier:
            rawData["rewardExperienceScale"] = components.experienceScale()
        case .rewardGoldPercent, .rewardGoldMultiplier:
            rawData["rewardGoldScale"] = components.goldScale()
        case .rewardItemPercent, .rewardItemMultiplier:
            rawData["rewardItemScale"] = components.itemDropScale()
        case .rewardTitlePercent, .rewardTitleMultiplier:
            rawData["rewardTitleScale"] = components.titleScale()
        default:
            break
        }
    }

    func verifyExplorationModifier(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .explorationTimeMultiplier, segment: segment)
        let modifiers = try compileExplorationModifiers(skill: segmentSkill)
        let multiplier = modifiers.multiplier(forDungeonId: 1, dungeonName: "test")
        rawData["explorationMultiplier"] = multiplier
        if multiplier == 1.0 {
            throw VerificationError.failed("explorationTimeMultiplier not applied")
        }
    }

    func verifyDegradationRepair(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: effectType, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())

        if effectType == .degradationRepairBoost {
            let expected = segment.values["valuePercent"] ?? payload.value[.valuePercent] ?? 0.0
            let actual = skillEffects.misc.degradationRepairBonusPercent
            rawData["degradationRepairBoost"] = actual
            try assertApproxEqual(actual, expected, tolerance: 0.0001, message: "degradationRepairBoost")
            return
        }
        var actor = TestActorBuilder.makePlayer(luck: 18, skillEffects: skillEffects)
        actor.degradationPercent = 50
        var context = makeContext(players: [actor], enemies: [], statusDefinitions: [:])
        BattleTurnEngine.applyDegradationRepairIfAvailable(to: &actor, context: &context)
        rawData["degradationPercent"] = actor.degradationPercent
        if effectType != .autoDegradationRepair, actor.degradationPercent >= 50 {
            throw VerificationError.failed("degradationRepair not applied")
        }
    }

    func verifyMagicModifiers(
        _ effectType: SkillEffectType,
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: effectType, segment: segment)
        let payload = try segmentPayload(skill: skill, effectType: effectType, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        let attacker = TestActorBuilder.makeAttacker(luck: 18, skillEffects: skillEffects)
        var defender = TestActorBuilder.makeDefender(luck: 1)
        var context = makeContext(players: [attacker], enemies: [defender], statusDefinitions: [:])

        switch effectType {
        case .magicNullifyChancePercent:
            let chance = try payload.resolvedChancePercent(stats: defaultActorStats(), skillId: skill.id, effectIndex: 0) ?? 0.0
            let damage = withFixedMedianRandomMode {
                BattleTurnEngine.computeMagicalDamage(attacker: attacker, defender: &defender, spellId: nil, context: &context)
            }
            rawData["magicNullifyDamage"] = Double(damage)
            let expected = expectedBoolFromChancePercent(chance)
            if expected && damage != 0 {
                throw VerificationError.failed("magicNullify not applied")
            }
            if !expected && damage == 0 {
                throw VerificationError.failed("magicNullify applied unexpectedly")
            }
        case .magicCriticalChancePercent:
            let chance = try payload.resolvedChancePercent(stats: defaultActorStats(), skillId: skill.id, effectIndex: 0) ?? 0.0
            let base = withFixedMedianRandomMode {
                BattleTurnEngine.computeMagicalDamage(attacker: TestActorBuilder.makeAttacker(luck: 18),
                                                      defender: &defender,
                                                      spellId: nil,
                                                      context: &context)
            }
            let crit = withFixedMedianRandomMode {
                BattleTurnEngine.computeMagicalDamage(attacker: attacker,
                                                      defender: &defender,
                                                      spellId: nil,
                                                      context: &context)
            }
            rawData["magicCriticalChance"] = chance
            let expected = expectedBoolFromChancePercent(chance)
            if expected && crit <= base {
                throw VerificationError.failed("magicCritical not applied")
            }
            if !expected && crit > base {
                throw VerificationError.failed("magicCritical applied unexpectedly")
            }
        default:
            break
        }
    }

    func verifyStatDebuff(
        segment: EffectSegment,
        skill: SkillDefinition,
        rawData: inout [String: Double]
    ) throws {
        let segmentSkill = try segmentSkill(skill: skill, effectType: .statDebuff, segment: segment)
        let skillEffects = try compileActorEffects(skill: segmentSkill, stats: defaultActorStats())
        rawData["statDebuffCount"] = Double(skillEffects.combat.enemyStatDebuffs.count)
        if skillEffects.combat.enemyStatDebuffs.isEmpty {
            throw VerificationError.failed("statDebuff not applied")
        }
    }
}
