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

    @MainActor func testStatConversionLinear() throws {
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
            type: .statConversionLinear,
            parameters: [
                .sourceStat: Int(CombatStat.hitScore.rawValue),
                .targetStat: Int(CombatStat.maxHP.rawValue)
            ],
            values: [.valuePerUnit: 0.1]
        )
        let skill = makeSkill(id: 9004, effects: [conversionEffect])
        let combat = try calculateCombat(level: 1, stats: stats, coefficients: coefficients, skills: [skill])

        var rawData = makeRawData(level: 1, stats: stats, coefficients: coefficients)
        rawData["sourceStat"] = Double(CombatStat.hitScore.rawValue)
        rawData["targetStat"] = Double(CombatStat.maxHP.rawValue)
        rawData["conversionRatio"] = 0.1
        recordInt(id: "BATTLE-STAT-401", expected: 189, measured: combat.maxHP, rawData: rawData)
    }

    @MainActor func testAttackCountRoundingHalfDown() throws {
        let coefficients = makeCoefficients()
        let stats = RaceDefinition.BaseStats(
            strength: 10,
            wisdom: 12,
            spirit: 14,
            vitality: 16,
            agility: 35,
            luck: 20
        )
        let combat = try calculateCombat(level: 1, stats: stats, coefficients: coefficients)

        let rawData = makeRawData(level: 1, stats: stats, coefficients: coefficients)
        recordDouble(id: "BATTLE-STAT-402", expected: 2.0, measured: combat.attackCount, rawData: rawData)
    }

    @MainActor func testAttackCountClampedToMinimum() throws {
        let coefficients = makeCoefficients()
        let stats = RaceDefinition.BaseStats(
            strength: 10,
            wisdom: 12,
            spirit: 14,
            vitality: 16,
            agility: 35,
            luck: 20
        )
        let attackCountEffect = makeEffect(
            index: 1,
            type: .attackCountAdditive,
            values: [.additive: -3.0]
        )
        let skill = makeSkill(id: 9005, effects: [attackCountEffect])
        let combat = try calculateCombat(level: 1, stats: stats, coefficients: coefficients, skills: [skill])

        var rawData = makeRawData(level: 1, stats: stats, coefficients: coefficients)
        rawData["attackCountAdditive"] = -3.0
        recordDouble(id: "BATTLE-STAT-403", expected: 1.0, measured: combat.attackCount, rawData: rawData)
    }

    @MainActor func testCriticalChanceClampedLowerBound() throws {
        let coefficients = makeCoefficients()
        let stats = RaceDefinition.BaseStats(
            strength: 10,
            wisdom: 12,
            spirit: 14,
            vitality: 16,
            agility: 18,
            luck: 20
        )
        let criticalEffect = makeEffect(
            index: 1,
            type: .criticalChancePercentAdditive,
            values: [.points: -200]
        )
        let skill = makeSkill(id: 9006, effects: [criticalEffect])
        let combat = try calculateCombat(level: 1, stats: stats, coefficients: coefficients, skills: [skill])

        var rawData = makeRawData(level: 1, stats: stats, coefficients: coefficients)
        rawData["criticalAdditive"] = -200.0
        recordInt(id: "BATTLE-STAT-404", expected: 0, measured: combat.criticalChancePercent, rawData: rawData)
    }

    @MainActor func testCriticalChanceClampedUpperBound() throws {
        let coefficients = makeCoefficients()
        let stats = RaceDefinition.BaseStats(
            strength: 10,
            wisdom: 12,
            spirit: 14,
            vitality: 16,
            agility: 18,
            luck: 20
        )
        let criticalEffect = makeEffect(
            index: 1,
            type: .criticalChancePercentAdditive,
            values: [.points: 200]
        )
        let skill = makeSkill(id: 9007, effects: [criticalEffect])
        let combat = try calculateCombat(level: 1, stats: stats, coefficients: coefficients, skills: [skill])

        var rawData = makeRawData(level: 1, stats: stats, coefficients: coefficients)
        rawData["criticalAdditive"] = 200.0
        recordInt(id: "BATTLE-STAT-405", expected: 100, measured: combat.criticalChancePercent, rawData: rawData)
    }

    @MainActor func testMaxHPClampedToMinimum() throws {
        let coefficients = makeCoefficients()
        let stats = RaceDefinition.BaseStats(
            strength: 10,
            wisdom: 12,
            spirit: 14,
            vitality: 16,
            agility: 18,
            luck: 20
        )
        let maxHPEffect = makeEffect(
            index: 1,
            type: .statAdditive,
            parameters: [.stat: Int(CombatStat.maxHP.rawValue)],
            values: [.additive: -1000]
        )
        let skill = makeSkill(id: 9008, effects: [maxHPEffect])
        let combat = try calculateCombat(level: 1, stats: stats, coefficients: coefficients, skills: [skill])

        var rawData = makeRawData(level: 1, stats: stats, coefficients: coefficients)
        rawData["maxHPAdditive"] = -1000.0
        recordInt(id: "BATTLE-STAT-406", expected: 1, measured: combat.maxHP, rawData: rawData)
    }

    @MainActor func testLevelDependentValueHumanBoundaries() {
        let cases: [(level: Int, expected: Double, id: String)] = [
            (level: 30, expected: 3.0, id: "BATTLE-FORMULA-001"),
            (level: 31, expected: 3.15, id: "BATTLE-FORMULA-002"),
            (level: 61, expected: 7.725, id: "BATTLE-FORMULA-003"),
            (level: 81, expected: 12.225, id: "BATTLE-FORMULA-004"),
            (level: 101, expected: 16.6125, id: "BATTLE-FORMULA-005"),
            (level: 151, expected: 22.29375, id: "BATTLE-FORMULA-006"),
            (level: 181, expected: 27.440625, id: "BATTLE-FORMULA-007")
        ]

        for testCase in cases {
            let measured = CombatFormulas.levelDependentValue(raceId: 1, level: testCase.level)
            let rawData: [String: Double] = [
                "raceId": 1.0,
                "level": Double(testCase.level)
            ]
            recordDouble(id: testCase.id, expected: testCase.expected, measured: measured, rawData: rawData)
        }
    }

    @MainActor func testLevelDependentValueNonHumanBoundaries() {
        let cases: [(level: Int, expected: Double, id: String)] = [
            (level: 80, expected: 12.0, id: "BATTLE-FORMULA-008"),
            (level: 81, expected: 12.45, id: "BATTLE-FORMULA-009"),
            (level: 181, expected: 57.45, id: "BATTLE-FORMULA-010")
        ]

        for testCase in cases {
            let measured = CombatFormulas.levelDependentValue(raceId: 3, level: testCase.level)
            let rawData: [String: Double] = [
                "raceId": 3.0,
                "level": Double(testCase.level)
            ]
            recordDouble(id: testCase.id, expected: testCase.expected, measured: measured, rawData: rawData)
        }
    }

    @MainActor func testAgilityDependencyBoundaries() {
        let cases: [(agility: Int, expected: Double, id: String)] = [
            (agility: 20, expected: 20.0, id: "BATTLE-FORMULA-011"),
            (agility: 21, expected: 20.84, id: "BATTLE-FORMULA-012"),
            (agility: 35, expected: 50.0, id: "BATTLE-FORMULA-013"),
            (agility: 34, expected: 45.52, id: "BATTLE-FORMULA-014")
        ]

        for testCase in cases {
            let measured = CombatFormulas.agilityDependency(value: testCase.agility)
            let rawData: [String: Double] = [
                "agility": Double(testCase.agility)
            ]
            recordDouble(id: testCase.id, expected: testCase.expected, measured: measured, rawData: rawData)
        }
    }

    @MainActor func testStrengthDependencyBoundaries() {
        let cases: [(strength: Int, expected: Double, id: String)] = [
            (strength: 9, expected: 5.0, id: "BATTLE-FORMULA-015"),
            (strength: 10, expected: 5.0, id: "BATTLE-FORMULA-016"),
            (strength: 25, expected: 15.0, id: "BATTLE-FORMULA-017"),
            (strength: 30, expected: 30.0, id: "BATTLE-FORMULA-018"),
            (strength: 33, expected: 45.0, id: "BATTLE-FORMULA-019"),
            (strength: 35, expected: 60.0, id: "BATTLE-FORMULA-020"),
            (strength: 34, expected: 52.5, id: "BATTLE-FORMULA-021")
        ]

        for testCase in cases {
            let measured = CombatFormulas.strengthDependency(value: testCase.strength)
            let rawData: [String: Double] = [
                "strength": Double(testCase.strength)
            ]
            recordDouble(id: testCase.id, expected: testCase.expected, measured: measured, rawData: rawData)
        }
    }

    @MainActor func testAdditionalDamageGrowth() {
        let level = 10
        let jobCoefficient = 2.0
        let growthMultiplier = 1.5
        let expected = 0.75

        let measured = CombatFormulas.additionalDamageGrowth(
            level: level,
            jobCoefficient: jobCoefficient,
            growthMultiplier: growthMultiplier
        )
        let rawData: [String: Double] = [
            "level": Double(level),
            "jobCoefficient": jobCoefficient,
            "growthMultiplier": growthMultiplier
        ]
        recordDouble(id: "BATTLE-FORMULA-022", expected: expected, measured: measured, rawData: rawData)
    }

    @MainActor func testStatBonusMultiplierBoundaries() {
        let cases: [(value: Int, expected: Double, id: String)] = [
            (value: 20, expected: 1.0, id: "BATTLE-FORMULA-023"),
            (value: 21, expected: 1.04, id: "BATTLE-FORMULA-024"),
            (value: 35, expected: 1.8009435055069165, id: "BATTLE-FORMULA-025")
        ]

        for testCase in cases {
            let measured = CombatFormulas.statBonusMultiplier(value: testCase.value)
            let rawData: [String: Double] = [
                "value": Double(testCase.value)
            ]
            recordDouble(id: testCase.id, expected: testCase.expected, measured: measured, rawData: rawData)
        }
    }

    @MainActor func testResistancePercentBoundaries() {
        let cases: [(value: Int, expected: Double, id: String)] = [
            (value: 20, expected: 1.0, id: "BATTLE-FORMULA-026"),
            (value: 21, expected: 0.96, id: "BATTLE-FORMULA-027"),
            (value: 35, expected: 0.5420863798609088, id: "BATTLE-FORMULA-028")
        ]

        for testCase in cases {
            let measured = CombatFormulas.resistancePercent(value: testCase.value)
            let rawData: [String: Double] = [
                "value": Double(testCase.value)
            ]
            recordDouble(id: testCase.id, expected: testCase.expected, measured: measured, rawData: rawData)
        }
    }

    @MainActor func testEvasionLimitBoundaries() {
        let cases: [(agility: Int, expected: Double, id: String)] = [
            (agility: 20, expected: 95.0, id: "BATTLE-FORMULA-029"),
            (agility: 21, expected: 95.6, id: "BATTLE-FORMULA-030"),
            (agility: 35, expected: 99.26513073049944, id: "BATTLE-FORMULA-031")
        ]

        for testCase in cases {
            let measured = CombatFormulas.evasionLimit(value: testCase.agility)
            let rawData: [String: Double] = [
                "agility": Double(testCase.agility)
            ]
            recordDouble(id: testCase.id, expected: testCase.expected, measured: measured, rawData: rawData)
        }
    }

    @MainActor func testFinalAttackCountBoundaries() {
        let levelFactor = 0.1
        let jobCoefficient = 1.0
        let talentMultiplier = 1.0
        let passiveMultiplier = 1.0
        let additive = 0.0
        let cases: [(agility: Int, expected: Int, id: String)] = [
            (agility: 20, expected: 1, id: "BATTLE-FORMULA-032"),
            (agility: 30, expected: 2, id: "BATTLE-FORMULA-033"),
            (agility: 35, expected: 2, id: "BATTLE-FORMULA-034")
        ]

        for testCase in cases {
            let measured = CombatFormulas.finalAttackCount(
                agility: testCase.agility,
                levelFactor: levelFactor,
                jobCoefficient: jobCoefficient,
                talentMultiplier: talentMultiplier,
                passiveMultiplier: passiveMultiplier,
                additive: additive
            )
            let rawData: [String: Double] = [
                "agility": Double(testCase.agility),
                "levelFactor": levelFactor,
                "jobCoefficient": jobCoefficient,
                "talentMultiplier": talentMultiplier,
                "passiveMultiplier": passiveMultiplier,
                "additive": additive
            ]
            recordInt(id: testCase.id, expected: testCase.expected, measured: measured, rawData: rawData)
        }
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
