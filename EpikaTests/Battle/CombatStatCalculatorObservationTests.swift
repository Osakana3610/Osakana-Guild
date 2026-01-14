import XCTest
@testable import Epika

nonisolated final class CombatStatCalculatorObservationTests: XCTestCase {

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

    @MainActor func testCombatStatBaselineScenario() throws {
        let baseStats = RaceDefinition.BaseStats(
            strength: 10,
            wisdom: 12,
            spirit: 14,
            vitality: 16,
            agility: 18,
            luck: 20
        )
        let coefficients = makeCoefficients()
        let combat = try calculateCombat(level: 1, stats: baseStats, coefficients: coefficients)

        let rawData = makeRawData(level: 1, stats: baseStats, coefficients: coefficients)

        recordInt(id: "BATTLE-STAT-001", expected: 176, measured: combat.maxHP, rawData: rawData)
        recordInt(id: "BATTLE-STAT-002", expected: 11, measured: combat.physicalAttackScore, rawData: rawData)
        recordInt(id: "BATTLE-STAT-003", expected: 13, measured: combat.magicalAttackScore, rawData: rawData)
        recordInt(id: "BATTLE-STAT-004", expected: 17, measured: combat.physicalDefenseScore, rawData: rawData)
        recordInt(id: "BATTLE-STAT-005", expected: 15, measured: combat.magicalDefenseScore, rawData: rawData)
        recordInt(id: "BATTLE-STAT-006", expected: 130, measured: combat.hitScore, rawData: rawData)
        recordInt(id: "BATTLE-STAT-007", expected: 20, measured: combat.evasionScore, rawData: rawData)
        recordInt(id: "BATTLE-STAT-008", expected: 2, measured: combat.criticalChancePercent, rawData: rawData)
        recordDouble(id: "BATTLE-STAT-009", expected: 1.0, measured: combat.attackCount, rawData: rawData)
        recordInt(id: "BATTLE-STAT-010", expected: 30, measured: combat.magicalHealingScore, rawData: rawData)
        recordInt(id: "BATTLE-STAT-011", expected: 10, measured: combat.trapRemovalScore, rawData: rawData)
        recordInt(id: "BATTLE-STAT-012", expected: 1, measured: combat.additionalDamageScore, rawData: rawData)
        recordInt(id: "BATTLE-STAT-013", expected: 13, measured: combat.breathDamageScore, rawData: rawData)
    }

    @MainActor func testCombatStatTwentyOneBonuses() throws {
        let coefficients = makeCoefficients()

        let strengthStats = RaceDefinition.BaseStats(
            strength: 35,
            wisdom: 12,
            spirit: 14,
            vitality: 16,
            agility: 18,
            luck: 20
        )
        let strengthCombat = try calculateCombat(level: 1, stats: strengthStats, coefficients: coefficients)
        let strengthRaw = makeRawData(level: 1, stats: strengthStats, coefficients: coefficients)
        recordInt(id: "BATTLE-STAT-101", expected: 68, measured: strengthCombat.physicalAttackScore, rawData: strengthRaw)
        recordInt(id: "BATTLE-STAT-102", expected: 34, measured: strengthCombat.additionalDamageScore, rawData: strengthRaw)

        let wisdomStats = RaceDefinition.BaseStats(
            strength: 10,
            wisdom: 35,
            spirit: 14,
            vitality: 16,
            agility: 18,
            luck: 20
        )
        let wisdomCombat = try calculateCombat(level: 1, stats: wisdomStats, coefficients: coefficients)
        let wisdomRaw = makeRawData(level: 1, stats: wisdomStats, coefficients: coefficients)
        recordInt(id: "BATTLE-STAT-103", expected: 68, measured: wisdomCombat.magicalAttackScore, rawData: wisdomRaw)
        recordInt(id: "BATTLE-STAT-104", expected: 54, measured: wisdomCombat.magicalHealingScore, rawData: wisdomRaw)
        recordInt(id: "BATTLE-STAT-105", expected: 68, measured: wisdomCombat.breathDamageScore, rawData: wisdomRaw)

        let vitalityStats = RaceDefinition.BaseStats(
            strength: 10,
            wisdom: 12,
            spirit: 14,
            vitality: 35,
            agility: 18,
            luck: 20
        )
        let vitalityCombat = try calculateCombat(level: 1, stats: vitalityStats, coefficients: coefficients)
        let vitalityRaw = makeRawData(level: 1, stats: vitalityStats, coefficients: coefficients)
        recordInt(id: "BATTLE-STAT-106", expected: 20, measured: vitalityCombat.physicalDefenseScore, rawData: vitalityRaw)

        let spiritStats = RaceDefinition.BaseStats(
            strength: 10,
            wisdom: 12,
            spirit: 35,
            vitality: 16,
            agility: 18,
            luck: 20
        )
        let spiritCombat = try calculateCombat(level: 1, stats: spiritStats, coefficients: coefficients)
        let spiritRaw = makeRawData(level: 1, stats: spiritStats, coefficients: coefficients)
        recordInt(id: "BATTLE-STAT-107", expected: 20, measured: spiritCombat.magicalDefenseScore, rawData: spiritRaw)

        let luckStats = RaceDefinition.BaseStats(
            strength: 10,
            wisdom: 12,
            spirit: 14,
            vitality: 16,
            agility: 18,
            luck: 35
        )
        let luckCombat = try calculateCombat(level: 1, stats: luckStats, coefficients: coefficients)
        let luckRaw = makeRawData(level: 1, stats: luckStats, coefficients: coefficients)
        recordInt(id: "BATTLE-STAT-108", expected: 10, measured: luckCombat.criticalChancePercent, rawData: luckRaw)
    }

    @MainActor func testCriticalChancePercentCapDelta() throws {
        let coefficients = makeCoefficients(criticalChancePercent: 10.0)
        let stats = RaceDefinition.BaseStats(
            strength: 10,
            wisdom: 12,
            spirit: 14,
            vitality: 16,
            agility: 35,
            luck: 20
        )
        let capEffect = makeEffect(
            index: 1,
            type: .criticalChancePercentCap,
            values: [.cap: 50]
        )
        let deltaEffect = makeEffect(
            index: 2,
            type: .criticalChancePercentMaxDelta,
            values: [.deltaPercent: -10]
        )
        let skill = makeSkill(id: 9001, effects: [capEffect, deltaEffect])
        let combat = try calculateCombat(level: 1, stats: stats, coefficients: coefficients, skills: [skill])

        var rawData = makeRawData(level: 1, stats: stats, coefficients: coefficients)
        rawData["criticalCap"] = 50
        rawData["criticalCapDelta"] = -10
        rawData["criticalCoefficient"] = 10
        recordInt(id: "BATTLE-STAT-201", expected: 40, measured: combat.criticalChancePercent, rawData: rawData)
    }

    @MainActor func testStatConversionPercent() throws {
        let coefficients = makeCoefficients()
        let stats = RaceDefinition.BaseStats(
            strength: 10,
            wisdom: 12,
            spirit: 14,
            vitality: 16,
            agility: 18,
            luck: 20
        )
        let conversionEffect = makeEffect(
            index: 1,
            type: .statConversionPercent,
            parameters: [
                .sourceStat: Int(CombatStat.physicalAttackScore.rawValue),
                .targetStat: Int(CombatStat.hitScore.rawValue)
            ],
            values: [.valuePercent: 50]
        )
        let skill = makeSkill(id: 9002, effects: [conversionEffect])
        let combat = try calculateCombat(level: 1, stats: stats, coefficients: coefficients, skills: [skill])

        var rawData = makeRawData(level: 1, stats: stats, coefficients: coefficients)
        rawData["sourceStat"] = Double(CombatStat.physicalAttackScore.rawValue)
        rawData["targetStat"] = Double(CombatStat.hitScore.rawValue)
        rawData["conversionPercent"] = 50
        recordInt(id: "BATTLE-STAT-301", expected: 136, measured: combat.hitScore, rawData: rawData)
    }

    @MainActor func testStatFixedToOne() throws {
        let coefficients = makeCoefficients()
        let stats = RaceDefinition.BaseStats(
            strength: 10,
            wisdom: 12,
            spirit: 14,
            vitality: 16,
            agility: 35,
            luck: 20
        )
        let fixedAttack = makeEffect(
            index: 1,
            type: .statFixedToOne,
            parameters: [.stat: Int(CombatStat.physicalAttackScore.rawValue)]
        )
        let fixedCount = makeEffect(
            index: 2,
            type: .statFixedToOne,
            parameters: [.stat: Int(CombatStat.attackCount.rawValue)]
        )
        let skill = makeSkill(id: 9003, effects: [fixedAttack, fixedCount])
        let combat = try calculateCombat(level: 1, stats: stats, coefficients: coefficients, skills: [skill])

        let passed = combat.physicalAttackScore == 1 && combat.attackCount == 1
        var rawData = makeRawData(level: 1, stats: stats, coefficients: coefficients)
        rawData["physicalAttackScore"] = Double(combat.physicalAttackScore)
        rawData["attackCount"] = combat.attackCount
        recordPass(id: "BATTLE-STAT-302", passed: passed, rawData: rawData)
    }
}

private extension CombatStatCalculatorObservationTests {
    @MainActor func calculateCombat(
        level: Int,
        stats: RaceDefinition.BaseStats,
        coefficients: JobDefinition.CombatCoefficients,
        skills: [SkillDefinition] = []
    ) throws -> CharacterValues.Combat {
        let race = RaceDefinition(
            id: 1,
            name: "TestRace",
            genderCode: 1,
            description: "",
            baseStats: stats,
            maxLevel: 200
        )
        let job = JobDefinition(
            id: 1,
            name: "TestJob",
            combatCoefficients: coefficients,
            learnedSkillIds: []
        )
        let context = CombatStatCalculator.Context(
            raceId: 1,
            jobId: 1,
            level: level,
            currentHP: 1,
            equippedItems: [],
            cachedEquippedItems: [],
            race: race,
            job: job,
            personalitySecondary: nil,
            learnedSkills: skills,
            loadout: CachedCharacter.Loadout(items: [], titles: [], superRareTitles: [])
        )
        return try CombatStatCalculator.calculate(for: context).combat
    }

    @MainActor func makeCoefficients(
        maxHP: Double = 1.0,
        physicalAttackScore: Double = 1.0,
        magicalAttackScore: Double = 1.0,
        physicalDefenseScore: Double = 1.0,
        magicalDefenseScore: Double = 1.0,
        hitScore: Double = 1.0,
        evasionScore: Double = 1.0,
        criticalChancePercent: Double = 1.0,
        attackCount: Double = 1.0,
        magicalHealingScore: Double = 1.0,
        trapRemovalScore: Double = 1.0,
        additionalDamageScore: Double = 1.0,
        breathDamageScore: Double = 1.0
    ) -> JobDefinition.CombatCoefficients {
        JobDefinition.CombatCoefficients(
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
            trapRemovalScore: trapRemovalScore,
            additionalDamageScore: additionalDamageScore,
            breathDamageScore: breathDamageScore
        )
    }

    @MainActor func makeSkill(id: UInt16, effects: [SkillDefinition.Effect]) -> SkillDefinition {
        SkillDefinition(
            id: id,
            name: "TestSkill\(id)",
            description: "",
            type: .passive,
            category: .combat,
            effects: effects
        )
    }

    @MainActor func makeEffect(
        index: Int,
        type: SkillEffectType,
        parameters: [EffectParamKey: Int] = [:],
        values: [EffectValueKey: Double] = [:]
    ) -> SkillDefinition.Effect {
        SkillDefinition.Effect(
            index: index,
            effectType: type,
            familyId: nil,
            parameters: parameters,
            values: values,
            arrayValues: [:]
        )
    }

    @MainActor func makeRawData(
        level: Int,
        stats: RaceDefinition.BaseStats,
        coefficients: JobDefinition.CombatCoefficients
    ) -> [String: Double] {
        [
            "level": Double(level),
            "strength": Double(stats.strength),
            "wisdom": Double(stats.wisdom),
            "spirit": Double(stats.spirit),
            "vitality": Double(stats.vitality),
            "agility": Double(stats.agility),
            "luck": Double(stats.luck),
            "c_maxHP": coefficients.maxHP,
            "c_physicalAttackScore": coefficients.physicalAttackScore,
            "c_magicalAttackScore": coefficients.magicalAttackScore,
            "c_physicalDefenseScore": coefficients.physicalDefenseScore,
            "c_magicalDefenseScore": coefficients.magicalDefenseScore,
            "c_hitScore": coefficients.hitScore,
            "c_evasionScore": coefficients.evasionScore,
            "c_criticalChancePercent": coefficients.criticalChancePercent,
            "c_attackCount": coefficients.attackCount,
            "c_magicalHealingScore": coefficients.magicalHealingScore,
            "c_trapRemovalScore": coefficients.trapRemovalScore,
            "c_additionalDamageScore": coefficients.additionalDamageScore,
            "c_breathDamageScore": coefficients.breathDamageScore
        ]
    }

    @MainActor func recordInt(
        id: String,
        expected: Int,
        measured: Int,
        rawData: [String: Double],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        ObservationRecorder.shared.record(
            id: id,
            expected: (min: Double(expected), max: Double(expected)),
            measured: Double(measured),
            rawData: rawData
        )
        XCTAssertEqual(measured, expected, "\(id) expected \(expected), got \(measured)", file: file, line: line)
    }

    @MainActor func recordDouble(
        id: String,
        expected: Double,
        measured: Double,
        rawData: [String: Double],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        ObservationRecorder.shared.record(
            id: id,
            expected: (min: expected, max: expected),
            measured: measured,
            rawData: rawData
        )
        XCTAssertEqual(measured, expected, accuracy: 0.0001, "\(id) expected \(expected), got \(measured)", file: file, line: line)
    }

    @MainActor func recordPass(
        id: String,
        passed: Bool,
        rawData: [String: Double],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        ObservationRecorder.shared.record(
            id: id,
            expected: (min: 1, max: 1),
            measured: passed ? 1 : 0,
            rawData: rawData
        )
        XCTAssertTrue(passed, "\(id) expected pass", file: file, line: line)
    }
}
