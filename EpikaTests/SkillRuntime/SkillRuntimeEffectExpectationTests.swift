import XCTest
@testable import Epika

nonisolated final class SkillRuntimeEffectExpectationTests: XCTestCase {
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

    @MainActor func testSkillEffectExpectations() throws {
        let physical = Int(BattleDamageType.physical.rawValue)
        let magical = Int(BattleDamageType.magical.rawValue)
        let breath = Int(BattleDamageType.breath.rawValue)

        func makeSkill(effects: [SkillDefinition.Effect]) -> SkillDefinition {
            SkillDefinition(
                id: 9000,
                name: "EffectExpectations",
                description: "",
                type: .passive,
                category: .combat,
                effects: effects
            )
        }

        func makeEffect(
            index: Int = 0,
            type: SkillEffectType,
            parameters: [EffectParamKey: Int] = [:],
            values: [EffectValueKey: Double] = [:],
            arrays: [EffectArrayKey: [Int]] = [:]
        ) -> SkillDefinition.Effect {
            SkillDefinition.Effect(
                index: index,
                effectType: type,
                parameters: parameters,
                values: values,
                arrayValues: arrays
            )
        }

        func compile(_ effect: SkillDefinition.Effect, stats: ActorStats? = nil) throws -> BattleActor.SkillEffects {
            let skill = makeSkill(effects: [effect])
            return try UnifiedSkillEffectCompiler(skills: [skill], stats: stats).actorEffects
        }

        func compileCombatInputs(_ effect: SkillDefinition.Effect, stats: ActorStats? = nil) throws -> CombatStatSkillEffectInputs {
            let skill = makeSkill(effects: [effect])
            let result = try SkillEffectAggregationService.aggregate(
                input: SkillEffectAggregationInput(skills: [skill], actorStats: stats)
            )
            return result.combatStatInputs
        }

        func aggregate(_ effect: SkillDefinition.Effect, stats: ActorStats? = nil) throws -> SkillEffectAggregationResult {
            let skill = makeSkill(effects: [effect])
            return try SkillEffectAggregationService.aggregate(
                input: SkillEffectAggregationInput(skills: [skill], actorStats: stats)
            )
        }

        func recordDouble(
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

        func recordInt(
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

        func recordPass(
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

        func isTriggerModeAtTurn(
            _ mode: BattleActor.SkillEffects.TimedBuffTrigger.TriggerMode?,
            turn: Int
        ) -> Bool {
            guard let mode else { return false }
            switch mode {
            case .atTurn(let value):
                return value == turn
            case .everyTurn:
                return false
            }
        }

        func isTriggerModeEveryTurn(
            _ mode: BattleActor.SkillEffects.TimedBuffTrigger.TriggerMode?
        ) -> Bool {
            if case .everyTurn = mode {
                return true
            }
            return false
        }

        // MARK: - Damage

        do {
            let effect = makeEffect(type: .damageDealtPercent,
                                    parameters: [.damageType: physical],
                                    values: [.valuePercent: 10])
            let measured = try compile(effect).damage.dealt.physical
            recordDouble(id: "SKILL-EFFECT-001",
                         expected: 1.1,
                         measured: measured,
                         rawData: ["damageType": Double(physical), "valuePercent": 10])
        }

        do {
            let effect = makeEffect(type: .damageDealtMultiplier,
                                    parameters: [.damageType: physical],
                                    values: [.multiplier: 1.5])
            let measured = try compile(effect).damage.dealt.physical
            recordDouble(id: "SKILL-EFFECT-002",
                         expected: 1.5,
                         measured: measured,
                         rawData: ["damageType": Double(physical), "multiplier": 1.5])
        }

        do {
            let effect = makeEffect(type: .damageTakenPercent,
                                    parameters: [.damageType: breath],
                                    values: [.valuePercent: -20])
            let measured = try compile(effect).damage.taken.breath
            recordDouble(id: "SKILL-EFFECT-003",
                         expected: 0.8,
                         measured: measured,
                         rawData: ["damageType": Double(breath), "valuePercent": -20])
        }

        do {
            let effect = makeEffect(type: .damageTakenMultiplier,
                                    parameters: [.damageType: magical],
                                    values: [.multiplier: 0.7])
            let measured = try compile(effect).damage.taken.magical
            recordDouble(id: "SKILL-EFFECT-004",
                         expected: 0.7,
                         measured: measured,
                         rawData: ["damageType": Double(magical), "multiplier": 0.7])
        }

        do {
            let raceId = 3
            let effect = makeEffect(type: .damageDealtMultiplierAgainst,
                                    values: [.multiplier: 1.25],
                                    arrays: [.targetRaceIds: [raceId]])
            let measured = try compile(effect).damage.dealtAgainst.value(for: UInt8(raceId))
            recordDouble(id: "SKILL-EFFECT-005",
                         expected: 1.25,
                         measured: measured,
                         rawData: ["raceId": Double(raceId), "multiplier": 1.25])
        }

        do {
            let effect = makeEffect(type: .criticalDamagePercent,
                                    values: [.valuePercent: 30])
            let measured = try compile(effect).damage.criticalPercent
            recordDouble(id: "SKILL-EFFECT-006",
                         expected: 30,
                         measured: measured,
                         rawData: ["valuePercent": 30])
        }

        do {
            let effect = makeEffect(type: .criticalDamageMultiplier,
                                    values: [.multiplier: 1.4])
            let measured = try compile(effect).damage.criticalMultiplier
            recordDouble(id: "SKILL-EFFECT-007",
                         expected: 1.4,
                         measured: measured,
                         rawData: ["multiplier": 1.4])
        }

        do {
            let effect = makeEffect(type: .criticalDamageTakenMultiplier,
                                    values: [.multiplier: 0.9])
            let measured = try compile(effect).damage.criticalTakenMultiplier
            recordDouble(id: "SKILL-EFFECT-008",
                         expected: 0.9,
                         measured: measured,
                         rawData: ["multiplier": 0.9])
        }

        do {
            let effect = makeEffect(type: .penetrationDamageTakenMultiplier,
                                    values: [.multiplier: 0.6])
            let measured = try compile(effect).damage.penetrationTakenMultiplier
            recordDouble(id: "SKILL-EFFECT-009",
                         expected: 0.6,
                         measured: measured,
                         rawData: ["multiplier": 0.6])
        }

        do {
            let effect = makeEffect(type: .martialBonusPercent,
                                    values: [.valuePercent: 12])
            let measured = try compile(effect).damage.martialBonusPercent
            recordDouble(id: "SKILL-EFFECT-010",
                         expected: 12,
                         measured: measured,
                         rawData: ["valuePercent": 12])
        }

        do {
            let effect = makeEffect(type: .martialBonusMultiplier,
                                    values: [.multiplier: 1.3])
            let measured = try compile(effect).damage.martialBonusMultiplier
            recordDouble(id: "SKILL-EFFECT-011",
                         expected: 1.3,
                         measured: measured,
                         rawData: ["multiplier": 1.3])
        }

        do {
            let effect = makeEffect(type: .minHitScale,
                                    values: [.minHitScale: 0.6])
            let measured = try compile(effect).damage.minHitScale ?? 0
            recordDouble(id: "SKILL-EFFECT-012",
                         expected: 0.6,
                         measured: measured,
                         rawData: ["minHitScale": 0.6])
        }

        do {
            let effect = makeEffect(type: .magicNullifyChancePercent,
                                    values: [.chancePercent: 15])
            let measured = try compile(effect).damage.magicNullifyChancePercent
            recordDouble(id: "SKILL-EFFECT-013",
                         expected: 15,
                         measured: measured,
                         rawData: ["chancePercent": 15])
        }

        do {
            let effect = makeEffect(type: .levelComparisonDamageTaken,
                                    values: [.valuePercent: -5])
            let measured = try compile(effect).damage.levelComparisonDamageTakenPercent
            recordDouble(id: "SKILL-EFFECT-014",
                         expected: -5,
                         measured: measured,
                         rawData: ["valuePercent": -5])
        }

        do {
            let effect = makeEffect(type: .damageDealtMultiplierByTargetHP,
                                    values: [.hpThresholdPercent: 30, .multiplier: 1.5])
            let entries = try compile(effect).damage.hpThresholdMultipliers
            let passed = entries.count == 1 && entries.first?.hpThresholdPercent == 30 && entries.first?.multiplier == 1.5
            recordPass(id: "SKILL-EFFECT-015",
                       passed: passed,
                       rawData: ["hpThresholdPercent": 30, "multiplier": 1.5, "count": Double(entries.count)])
        }

        do {
            let effect = makeEffect(type: .absorption,
                                    values: [.percent: 20, .capPercent: 50])
            let effects = try compile(effect)
            let passed = effects.misc.absorptionPercent == 20 && effects.misc.absorptionCapPercent == 50
            recordPass(id: "SKILL-EFFECT-016",
                       passed: passed,
                       rawData: ["percent": 20, "capPercent": 50])
        }

        // MARK: - Combat

        do {
            let effect = makeEffect(type: .procMultiplier,
                                    values: [.multiplier: 1.2])
            let measured = try compile(effect).combat.procChanceMultiplier
            recordDouble(id: "SKILL-EFFECT-017",
                         expected: 1.2,
                         measured: measured,
                         rawData: ["multiplier": 1.2])
        }

        do {
            let effect = makeEffect(type: .procRate,
                                    parameters: [.target: 2, .stacking: Int(StackingType.add.rawValue)],
                                    values: [.addPercent: 15])
            let measured = try compile(effect).combat.procRateModifier.additives[2] ?? 0
            recordDouble(id: "SKILL-EFFECT-018",
                         expected: 15,
                         measured: measured,
                         rawData: ["target": 2, "addPercent": 15])
        }

        do {
            let effect = makeEffect(type: .procRate,
                                    parameters: [.target: 2, .stacking: Int(StackingType.multiply.rawValue)],
                                    values: [.multiplier: 1.5])
            let measured = try compile(effect).combat.procRateModifier.multipliers[2] ?? 1
            recordDouble(id: "SKILL-EFFECT-019",
                         expected: 1.5,
                         measured: measured,
                         rawData: ["target": 2, "multiplier": 1.5])
        }

        do {
            let effect = makeEffect(type: .extraAction,
                                    parameters: [.trigger: 5],
                                    values: [.chancePercent: 25, .count: 2, .duration: 3])
            let extraActions = try compile(effect).combat.extraActions
            let entry = extraActions.first
            let passed = extraActions.count == 1
                && entry?.chancePercent == 25
                && entry?.count == 2
                && entry?.trigger == .battleStart
                && entry?.triggerTurn == 1
                && entry?.duration == 3
            recordPass(id: "SKILL-EFFECT-020",
                       passed: passed,
                       rawData: ["chancePercent": 25, "count": 2, "trigger": 5, "duration": 3, "countEntries": Double(extraActions.count)])
        }

        do {
            let effect = makeEffect(type: .reactionNextTurn,
                                    values: [.count: 2])
            let measured = try compile(effect).combat.nextTurnExtraActions
            recordInt(id: "SKILL-EFFECT-021",
                      expected: 2,
                      measured: measured,
                      rawData: ["count": 2])
        }

        do {
            let effect = makeEffect(type: .actionOrderMultiplier,
                                    values: [.multiplier: 1.1])
            let measured = try compile(effect).combat.actionOrderMultiplier
            recordDouble(id: "SKILL-EFFECT-022",
                         expected: 1.1,
                         measured: measured,
                         rawData: ["multiplier": 1.1])
        }

        do {
            let effect = makeEffect(type: .actionOrderShuffle)
            let measured = try compile(effect).combat.actionOrderShuffle
            recordPass(id: "SKILL-EFFECT-023",
                       passed: measured,
                       rawData: ["expected": 1])
        }

        do {
            let effect = makeEffect(type: .actionOrderShuffleEnemy)
            let measured = try compile(effect).combat.actionOrderShuffleEnemy
            recordPass(id: "SKILL-EFFECT-024",
                       passed: measured,
                       rawData: ["expected": 1])
        }

        do {
            let effect = makeEffect(type: .counterAttackEvasionMultiplier,
                                    values: [.multiplier: 1.3])
            let measured = try compile(effect).combat.counterAttackEvasionMultiplier
            recordDouble(id: "SKILL-EFFECT-025",
                         expected: 1.3,
                         measured: measured,
                         rawData: ["multiplier": 1.3])
        }

        do {
            let effect = makeEffect(type: .parry,
                                    values: [.bonusPercent: 10])
            let combat = try compile(effect).combat
            let passed = combat.parryEnabled && combat.parryBonusPercent == 10
            recordPass(id: "SKILL-EFFECT-026",
                       passed: passed,
                       rawData: ["bonusPercent": 10])
        }

        do {
            let effect = makeEffect(type: .shieldBlock,
                                    values: [.bonusPercent: 15])
            let combat = try compile(effect).combat
            let passed = combat.shieldBlockEnabled && combat.shieldBlockBonusPercent == 15
            recordPass(id: "SKILL-EFFECT-027",
                       passed: passed,
                       rawData: ["bonusPercent": 15])
        }

        do {
            let effect = makeEffect(type: .barrier,
                                    parameters: [.damageType: physical],
                                    values: [.charges: 2])
            let measured = try compile(effect).combat.barrierCharges[UInt8(physical)] ?? 0
            recordInt(id: "SKILL-EFFECT-028",
                      expected: 2,
                      measured: measured,
                      rawData: ["damageType": Double(physical), "charges": 2])
        }

        do {
            let effect = makeEffect(type: .barrierOnGuard,
                                    parameters: [.damageType: magical],
                                    values: [.charges: 3])
            let measured = try compile(effect).combat.guardBarrierCharges[UInt8(magical)] ?? 0
            recordInt(id: "SKILL-EFFECT-029",
                      expected: 3,
                      measured: measured,
                      rawData: ["damageType": Double(magical), "charges": 3])
        }

        do {
            let effect = makeEffect(type: .enemyActionDebuffChance,
                                    values: [.chancePercent: 40, .reduction: 2])
            let entries = try compile(effect).combat.enemyActionDebuffs
            let entry = entries.first
            let passed = entries.count == 1
                && entry?.baseChancePercent == 40
                && entry?.reduction == 2
            recordPass(id: "SKILL-EFFECT-030",
                       passed: passed,
                       rawData: ["chancePercent": 40, "reduction": 2, "count": Double(entries.count)])
        }

        do {
            let effect = makeEffect(type: .cumulativeHitDamageBonus,
                                    values: [.damagePercent: 5, .hitScoreAdditive: 2])
            let bonus = try compile(effect).combat.cumulativeHitBonus
            let passed = bonus?.damagePercentPerHit == 5 && bonus?.hitScorePerHit == 2
            recordPass(id: "SKILL-EFFECT-031",
                       passed: passed,
                       rawData: ["damagePercent": 5, "hitScoreAdditive": 2])
        }

        do {
            let effect = makeEffect(type: .enemySingleActionSkipChance,
                                    values: [.chancePercent: 30])
            let measured = try compile(effect).combat.enemySingleActionSkipChancePercent
            recordDouble(id: "SKILL-EFFECT-032",
                         expected: 30,
                         measured: measured,
                         rawData: ["chancePercent": 30])
        }

        do {
            let effect = makeEffect(type: .firstStrike)
            let measured = try compile(effect).combat.firstStrike
            recordPass(id: "SKILL-EFFECT-033",
                       passed: measured,
                       rawData: ["expected": 1])
        }

        do {
            let effect = makeEffect(type: .statDebuff,
                                    parameters: [.stat: 1, .target: 1],
                                    values: [.valuePercent: -10])
            let debuffs = try compile(effect).combat.enemyStatDebuffs
            let entry = debuffs.first
            let passed = debuffs.count == 1
                && entry?.stat == 1
                && entry?.multiplier == 0.9
            recordPass(id: "SKILL-EFFECT-034",
                       passed: passed,
                       rawData: ["stat": 1, "valuePercent": -10, "count": Double(debuffs.count)])
        }

        do {
            let effect = makeEffect(type: .attackCountAdditive)
            let measured = try compile(effect).combat.hasAttackCountAdditive
            recordPass(id: "SKILL-EFFECT-035",
                       passed: measured,
                       rawData: ["expected": 1])
        }

        do {
            let effect = makeEffect(type: .targetingWeight,
                                    values: [.weight: 0.7])
            let measured = try compile(effect).misc.targetingWeight
            recordDouble(id: "SKILL-EFFECT-036",
                         expected: 0.7,
                         measured: measured,
                         rawData: ["weight": 0.7])
        }

        do {
            let effect = makeEffect(type: .coverRowsBehind,
                                    parameters: [.condition: Int(SkillConditionType.allyHPBelow50.rawValue)])
            let misc = try compile(effect).misc
            let passed = misc.coverRowsBehind && misc.coverRowsBehindCondition == .allyHPBelow50
            recordPass(id: "SKILL-EFFECT-037",
                       passed: passed,
                       rawData: ["condition": Double(SkillConditionType.allyHPBelow50.rawValue)])
        }

        // MARK: - Spell

        do {
            let effect = makeEffect(type: .spellPowerPercent,
                                    values: [.valuePercent: 15])
            let measured = try compile(effect).spell.power.percent
            recordDouble(id: "SKILL-EFFECT-038",
                         expected: 15,
                         measured: measured,
                         rawData: ["valuePercent": 15])
        }

        do {
            let effect = makeEffect(type: .spellPowerMultiplier,
                                    values: [.multiplier: 1.2])
            let measured = try compile(effect).spell.power.multiplier
            recordDouble(id: "SKILL-EFFECT-039",
                         expected: 1.2,
                         measured: measured,
                         rawData: ["multiplier": 1.2])
        }

        do {
            let effect = makeEffect(type: .spellSpecificMultiplier,
                                    parameters: [.spellId: 2],
                                    values: [.multiplier: 1.4])
            let measured = try compile(effect).spell.specificMultipliers[2] ?? 1
            recordDouble(id: "SKILL-EFFECT-040",
                         expected: 1.4,
                         measured: measured,
                         rawData: ["spellId": 2, "multiplier": 1.4])
        }

        do {
            let effect = makeEffect(type: .spellSpecificTakenMultiplier,
                                    parameters: [.spellId: 2],
                                    values: [.multiplier: 0.8])
            let measured = try compile(effect).spell.specificTakenMultipliers[2] ?? 1
            recordDouble(id: "SKILL-EFFECT-041",
                         expected: 0.8,
                         measured: measured,
                         rawData: ["spellId": 2, "multiplier": 0.8])
        }

        do {
            let effect = makeEffect(type: .spellCharges,
                                    values: [
                                        .maxCharges: 5,
                                        .initialCharges: 2,
                                        .initialBonus: 1,
                                        .regenEveryTurns: 2,
                                        .regenAmount: 1,
                                        .regenCap: 1,
                                        .maxTriggers: 3,
                                        .gainOnPhysicalHit: 1
                                    ])
            let modifier = try compile(effect).spell.defaultChargeModifier
            let passed = modifier?.maxOverride == 5
                && modifier?.initialOverride == 2
                && modifier?.initialBonus == 1
                && modifier?.regen?.every == 2
                && modifier?.regen?.amount == 1
                && modifier?.regen?.cap == 1
                && modifier?.regen?.maxTriggers == 3
                && modifier?.gainOnPhysicalHit == 1
            recordPass(id: "SKILL-EFFECT-042",
                       passed: passed,
                       rawData: ["maxCharges": 5, "initialCharges": 2, "initialBonus": 1, "regenEvery": 2, "regenAmount": 1, "regenCap": 1, "maxTriggers": 3, "gainOnPhysicalHit": 1])
        }

        do {
            let effect = makeEffect(type: .magicCriticalEnable)
            let measured = try compile(effect).spell.magicCriticalEnabled
            recordPass(id: "SKILL-EFFECT-043",
                       passed: measured,
                       rawData: ["expected": 1])
        }

        do {
            let effect = makeEffect(type: .spellChargeRecoveryChance,
                                    parameters: [.school: 1],
                                    values: [.chancePercent: 20])
            let recoveries = try compile(effect).spell.chargeRecoveries
            let entry = recoveries.first
            let passed = recoveries.count == 1
                && entry?.baseChancePercent == 20
                && entry?.school == 1
            recordPass(id: "SKILL-EFFECT-044",
                       passed: passed,
                       rawData: ["chancePercent": 20, "school": 1, "count": Double(recoveries.count)])
        }

        do {
            let effect = makeEffect(type: .breathVariant,
                                    values: [.extraCharges: 2])
            let measured = try compile(effect).spell.breathExtraCharges
            recordInt(id: "SKILL-EFFECT-045",
                      expected: 2,
                      measured: measured,
                      rawData: ["extraCharges": 2])
        }

        // MARK: - Status

        do {
            let effect = makeEffect(type: .statusResistancePercent,
                                    parameters: [.status: 2],
                                    values: [.valuePercent: 15])
            let resistance = try compile(effect).status.resistances[2]
            let measured = resistance?.additivePercent ?? 0
            recordDouble(id: "SKILL-EFFECT-046",
                         expected: 15,
                         measured: measured,
                         rawData: ["status": 2, "valuePercent": 15])
        }

        do {
            let effect = makeEffect(type: .statusResistanceMultiplier,
                                    parameters: [.status: 3],
                                    values: [.multiplier: 0.7])
            let resistance = try compile(effect).status.resistances[3]
            let measured = resistance?.multiplier ?? 1
            recordDouble(id: "SKILL-EFFECT-047",
                         expected: 0.7,
                         measured: measured,
                         rawData: ["status": 3, "multiplier": 0.7])
        }

        do {
            let effect = makeEffect(type: .statusInflict,
                                    parameters: [.statusId: 1],
                                    values: [.chancePercent: 25])
            let entries = try compile(effect).status.inflictions
            let entry = entries.first
            let passed = entries.count == 1
                && entry?.statusId == 1
                && entry?.baseChancePercent == 25
            recordPass(id: "SKILL-EFFECT-048",
                       passed: passed,
                       rawData: ["statusId": 1, "chancePercent": 25, "count": Double(entries.count)])
        }

        do {
            let effect = makeEffect(type: .berserk,
                                    values: [.chancePercent: 10])
            let measured = try compile(effect).status.berserkChancePercent ?? 0
            recordDouble(id: "SKILL-EFFECT-049",
                         expected: 10,
                         measured: measured,
                         rawData: ["chancePercent": 10])
        }

        do {
            let effect = makeEffect(type: .autoStatusCureOnAlly)
            let measured = try compile(effect).status.autoStatusCureOnAlly
            recordPass(id: "SKILL-EFFECT-050",
                       passed: measured,
                       rawData: ["expected": 1])
        }

        // MARK: - Resurrection

        do {
            let effect = makeEffect(type: .resurrectionSave,
                                    values: [.usesPriestMagic: 1, .minLevel: 3, .guaranteed: 1])
            let entries = try compile(effect).resurrection.rescueCapabilities
            let entry = entries.first
            let passed = entries.count == 1
                && entry?.usesPriestMagic == true
                && entry?.minLevel == 3
                && entry?.guaranteed == true
            recordPass(id: "SKILL-EFFECT-051",
                       passed: passed,
                       rawData: ["usesPriestMagic": 1, "minLevel": 3, "guaranteed": 1, "count": Double(entries.count)])
        }

        do {
            let effect = makeEffect(type: .resurrectionActive,
                                    parameters: [.hpScale: 2],
                                    values: [.chancePercent: 30, .maxTriggers: 2, .instant: 1])
            let resurrection = try compile(effect).resurrection
            let entry = resurrection.actives.first
            let passed = resurrection.rescueModifiers.ignoreActionCost
                && resurrection.actives.count == 1
                && entry?.chancePercent == 30
                && entry?.hpScale == .maxHP5Percent
                && entry?.maxTriggers == 2
            recordPass(id: "SKILL-EFFECT-052",
                       passed: passed,
                       rawData: ["chancePercent": 30, "hpScale": 2, "maxTriggers": 2, "instant": 1, "count": Double(resurrection.actives.count)])
        }

        do {
            let effect = makeEffect(type: .resurrectionBuff,
                                    values: [.guaranteed: 1, .maxTriggers: 3])
            let forced = try compile(effect).resurrection.forced
            let passed = forced?.maxTriggers == 3
            recordPass(id: "SKILL-EFFECT-053",
                       passed: passed,
                       rawData: ["guaranteed": 1, "maxTriggers": 3])
        }

        do {
            let effect = makeEffect(type: .resurrectionVitalize,
                                    values: [.removePenalties: 1, .rememberSkills: 1],
                                    arrays: [.removeSkillIds: [10], .grantSkillIds: [20]])
            let vitalize = try compile(effect).resurrection.vitalize
            let passed = vitalize?.removePenalties == true
                && vitalize?.rememberSkills == true
                && vitalize?.removeSkillIds == [10]
                && vitalize?.grantSkillIds == [20]
            recordPass(id: "SKILL-EFFECT-054",
                       passed: passed,
                       rawData: ["removePenalties": 1, "rememberSkills": 1, "removeSkillId": 10, "grantSkillId": 20])
        }

        do {
            let effect = makeEffect(type: .resurrectionSummon,
                                    values: [.everyTurns: 3])
            let measured = try compile(effect).resurrection.necromancerInterval ?? 0
            recordInt(id: "SKILL-EFFECT-055",
                      expected: 3,
                      measured: measured,
                      rawData: ["everyTurns": 3])
        }

        do {
            let effect = makeEffect(type: .resurrectionPassive,
                                    parameters: [.type: 1],
                                    values: [.chancePercent: 15])
            let resurrection = try compile(effect).resurrection
            let passed = resurrection.passiveBetweenFloors
                && resurrection.passiveBetweenFloorsChancePercent == 15
            recordPass(id: "SKILL-EFFECT-056",
                       passed: passed,
                       rawData: ["type": 1, "chancePercent": 15])
        }

        do {
            let effect = makeEffect(type: .sacrificeRite,
                                    values: [.everyTurns: 4])
            let measured = try compile(effect).resurrection.sacrificeInterval ?? 0
            recordInt(id: "SKILL-EFFECT-057",
                      expected: 4,
                      measured: measured,
                      rawData: ["everyTurns": 4])
        }

        // MARK: - Misc

        do {
            let effect = makeEffect(type: .rowProfile,
                                    parameters: [.profile: 4, .nearApt: 1, .farApt: 1])
            let profile = try compile(effect).misc.rowProfile
            let passed = profile.base == .far && profile.hasNearApt && profile.hasFarApt
            recordPass(id: "SKILL-EFFECT-058",
                       passed: passed,
                       rawData: ["profile": 4, "nearApt": 1, "farApt": 1])
        }

        do {
            let effect = makeEffect(type: .endOfTurnHealing,
                                    values: [.valuePercent: 5])
            let measured = try compile(effect).misc.endOfTurnHealingPercent
            recordDouble(id: "SKILL-EFFECT-059",
                         expected: 5,
                         measured: measured,
                         rawData: ["valuePercent": 5])
        }

        do {
            let effect = makeEffect(type: .endOfTurnSelfHPPercent,
                                    values: [.valuePercent: -10])
            let measured = try compile(effect).misc.endOfTurnSelfHPPercent
            recordDouble(id: "SKILL-EFFECT-060",
                         expected: -10,
                         measured: measured,
                         rawData: ["valuePercent": -10])
        }

        do {
            let effect = makeEffect(type: .partyAttackFlag,
                                    values: [.hostileAll: 1, .vampiricImpulse: 1])
            let misc = try compile(effect).misc
            let passed = misc.partyHostileAll && misc.vampiricImpulse && !misc.vampiricSuppression
            recordPass(id: "SKILL-EFFECT-061",
                       passed: passed,
                       rawData: ["hostileAll": 1, "vampiricImpulse": 1])
        }

        do {
            let effect = makeEffect(type: .partyAttackTarget,
                                    parameters: [.targetId: 7],
                                    values: [.hostile: 1, .protect: 1])
            let misc = try compile(effect).misc
            let passed = misc.partyHostileTargets.contains(7) && misc.partyProtectedTargets.contains(7)
            recordPass(id: "SKILL-EFFECT-062",
                       passed: passed,
                       rawData: ["targetId": 7, "hostile": 1, "protect": 1])
        }

        do {
            let effect = makeEffect(type: .reverseHealing)
            let measured = try compile(effect).misc.reverseHealingEnabled
            recordPass(id: "SKILL-EFFECT-063",
                       passed: measured,
                       rawData: ["expected": 1])
        }

        do {
            let effect = makeEffect(type: .equipmentStatMultiplier,
                                    parameters: [.equipmentType: 2],
                                    values: [.multiplier: 1.1])
            let measured = try compileCombatInputs(effect).equipmentMultipliers[2] ?? 1
            recordDouble(id: "SKILL-EFFECT-064",
                         expected: 1.1,
                         measured: measured,
                         rawData: ["equipmentType": 2, "multiplier": 1.1])
        }

        do {
            let effect = makeEffect(type: .dodgeCap,
                                    values: [.maxDodge: 0.8, .minHitScale: 0.6])
            let result = try compile(effect)
            let passed = result.misc.dodgeCapMax == 0.8 && result.damage.minHitScale == 0.6
            recordPass(id: "SKILL-EFFECT-065",
                       passed: passed,
                       rawData: ["maxDodge": 0.8, "minHitScale": 0.6])
        }

        do {
            let effect = makeEffect(type: .degradationRepair,
                                    values: [.minPercent: 5, .maxPercent: 10])
            let misc = try compile(effect).misc
            let passed = misc.degradationRepairMinPercent == 5 && misc.degradationRepairMaxPercent == 10
            recordPass(id: "SKILL-EFFECT-066",
                       passed: passed,
                       rawData: ["minPercent": 5, "maxPercent": 10])
        }

        do {
            let effect = makeEffect(type: .degradationRepairBoost,
                                    values: [.valuePercent: 12])
            let measured = try compile(effect).misc.degradationRepairBonusPercent
            recordDouble(id: "SKILL-EFFECT-067",
                         expected: 12,
                         measured: measured,
                         rawData: ["valuePercent": 12])
        }

        do {
            let effect = makeEffect(type: .autoDegradationRepair)
            let measured = try compile(effect).misc.autoDegradationRepair
            recordPass(id: "SKILL-EFFECT-068",
                       passed: measured,
                       rawData: ["expected": 1])
        }

        do {
            let effect = makeEffect(type: .runawayMagic,
                                    values: [.thresholdPercent: 30, .chancePercent: 20])
            let entry = try compile(effect).misc.magicRunaway
            let passed = entry?.thresholdPercent == 30 && entry?.chancePercent == 20
            recordPass(id: "SKILL-EFFECT-069",
                       passed: passed,
                       rawData: ["thresholdPercent": 30, "chancePercent": 20])
        }

        do {
            let effect = makeEffect(type: .runawayDamage,
                                    values: [.thresholdPercent: 25, .chancePercent: 15])
            let entry = try compile(effect).misc.damageRunaway
            let passed = entry?.thresholdPercent == 25 && entry?.chancePercent == 15
            recordPass(id: "SKILL-EFFECT-070",
                       passed: passed,
                       rawData: ["thresholdPercent": 25, "chancePercent": 15])
        }

        do {
            let effect = makeEffect(type: .retreatAtTurn,
                                    values: [.turn: 5, .chancePercent: 40])
            let misc = try compile(effect).misc
            let passed = misc.retreatTurn == 5 && misc.retreatChancePercent == 40
            recordPass(id: "SKILL-EFFECT-071",
                       passed: passed,
                       rawData: ["turn": 5, "chancePercent": 40])
        }

        // MARK: - Reactions / Timed Buffs

        do {
            let effect = makeEffect(type: .reaction,
                                    parameters: [
                                        .trigger: Int(ReactionTrigger.selfDamagedPhysical.rawValue),
                                        .target: Int(BattleActor.SkillEffects.Reaction.Target.attacker.rawValue),
                                        .damageType: physical,
                                        .requiresMartial: 1,
                                        .requiresAllyBehind: 1
                                    ],
                                    values: [
                                        .chancePercent: 35,
                                        .attackCountMultiplier: 0.6,
                                        .criticalChancePercentMultiplier: 1.2,
                                        .accuracyMultiplier: 0.8
                                    ])
            let reactions = try compile(effect).combat.reactions
            let entry = reactions.first
            let passed = reactions.count == 1
                && entry?.skillId == 9000
                && entry?.identifier == "9000"
                && entry?.displayName == "EffectExpectations"
                && entry?.trigger == .selfDamagedPhysical
                && entry?.target == .attacker
                && entry?.damageType == .physical
                && entry?.baseChancePercent == 35
                && abs((entry?.attackCountMultiplier ?? 0) - 0.6) < 0.0001
                && abs((entry?.criticalChancePercentMultiplier ?? 0) - 1.2) < 0.0001
                && abs((entry?.accuracyMultiplier ?? 0) - 0.8) < 0.0001
                && entry?.requiresMartial == true
                && entry?.requiresAllyBehind == true
            recordPass(id: "SKILL-EFFECT-072",
                       passed: passed,
                       rawData: ["trigger": Double(ReactionTrigger.selfDamagedPhysical.rawValue),
                                 "target": Double(BattleActor.SkillEffects.Reaction.Target.attacker.rawValue),
                                 "damageType": Double(physical),
                                 "requiresMartial": 1,
                                 "requiresAllyBehind": 1,
                                 "chancePercent": 35,
                                 "attackCountMultiplier": 0.6,
                                 "criticalChancePercentMultiplier": 1.2,
                                 "accuracyMultiplier": 0.8,
                                 "count": Double(reactions.count)])
        }

        do {
            let effect = makeEffect(type: .specialAttack,
                                    parameters: [
                                        .specialAttackId: Int(SpecialAttackKind.specialB.rawValue),
                                        .mode: 1
                                    ],
                                    values: [.chancePercent: 60])
            let specials = try compile(effect).combat.specialAttacks
            let entry = specials.preemptive.first
            let passed = specials.preemptive.count == 1
                && specials.normal.isEmpty
                && entry?.kind == .specialB
                && entry?.chancePercent == 60
                && entry?.preemptive == true
            recordPass(id: "SKILL-EFFECT-073",
                       passed: passed,
                       rawData: ["specialAttackId": Double(SpecialAttackKind.specialB.rawValue),
                                 "mode": 1,
                                 "chancePercent": 60,
                                 "preemptiveCount": Double(specials.preemptive.count)])
        }

        do {
            let effect = makeEffect(index: 0,
                                    type: .timedBuffTrigger,
                                    parameters: [
                                        .trigger: Int(ReactionTrigger.battleStart.rawValue),
                                        .target: Int(TimedBuffScope.`self`.rawValue)
                                    ],
                                    values: [
                                        .duration: 2,
                                        .damageDealtPercent: 15,
                                        .hitScoreAdditive: 3
                                    ])
            let triggers = try compile(effect).status.timedBuffTriggers
            let entry = triggers.first
            let expectedModifiers: [String: Double] = [
                "damageDealtPercent": 15,
                "hitScoreAdditive": 3
            ]
            let triggerModeMatches = isTriggerModeAtTurn(entry?.triggerMode, turn: 1)
            let passed = triggers.count == 1
                && entry?.id == "9000_0"
                && entry?.displayName == "EffectExpectations"
                && triggerModeMatches
                && entry?.modifiers == expectedModifiers
                && entry?.perTurnModifiers.isEmpty == true
                && entry?.duration == 2
                && entry?.scope == .`self`
                && entry?.category == "general"
                && entry?.sourceSkillId == 9000
            recordPass(id: "SKILL-EFFECT-074",
                       passed: passed,
                       rawData: ["trigger": Double(ReactionTrigger.battleStart.rawValue),
                                 "target": Double(TimedBuffScope.`self`.rawValue),
                                 "duration": 2,
                                 "damageDealtPercent": 15,
                                 "hitScoreAdditive": 3,
                                 "count": Double(triggers.count)])
        }

        do {
            let effect = makeEffect(index: 1,
                                    type: .timedBuffTrigger,
                                    parameters: [
                                        .trigger: Int(ReactionTrigger.turnElapsed.rawValue),
                                        .target: Int(TimedBuffScope.party.rawValue)
                                    ],
                                    values: [
                                        .hitScoreAdditivePerTurn: 1,
                                        .evasionScoreAdditivePerTurn: 2,
                                        .attackPercentPerTurn: 3,
                                        .defensePercentPerTurn: 4,
                                        .attackCountPercentPerTurn: 5
                                    ])
            let triggers = try compile(effect).status.timedBuffTriggers
            let entry = triggers.first
            let expectedPerTurn: [String: Double] = [
                "hitScoreAdditive": 1,
                "evasionScoreAdditive": 2,
                "attackPercent": 3,
                "defensePercent": 4,
                "attackCountPercent": 5
            ]
            let triggerModeMatches = isTriggerModeEveryTurn(entry?.triggerMode)
            let passed = triggers.count == 1
                && entry?.id == "9000_1"
                && entry?.displayName == "EffectExpectations"
                && triggerModeMatches
                && entry?.modifiers.isEmpty == true
                && entry?.perTurnModifiers == expectedPerTurn
                && entry?.duration == 0
                && entry?.scope == .party
                && entry?.category == "general"
                && entry?.sourceSkillId == 9000
            recordPass(id: "SKILL-EFFECT-075",
                       passed: passed,
                       rawData: ["trigger": Double(ReactionTrigger.turnElapsed.rawValue),
                                 "target": Double(TimedBuffScope.party.rawValue),
                                 "hitScoreAdditivePerTurn": 1,
                                 "evasionScoreAdditivePerTurn": 2,
                                 "attackPercentPerTurn": 3,
                                 "defensePercentPerTurn": 4,
                                 "attackCountPercentPerTurn": 5,
                                 "count": Double(triggers.count)])
        }

        do {
            let effect = makeEffect(index: 2,
                                    type: .tacticSpellAmplify,
                                    parameters: [
                                        .spellId: 2,
                                        .target: Int(TimedBuffScope.party.rawValue)
                                    ],
                                    values: [
                                        .multiplier: 1.4,
                                        .triggerTurn: 3
                                    ])
            let triggers = try compile(effect).status.timedBuffTriggers
            let entry = triggers.first
            let expectedModifiers: [String: Double] = [
                "spellSpecific:2": 1.4
            ]
            let triggerModeMatches = isTriggerModeAtTurn(entry?.triggerMode, turn: 3)
            let passed = triggers.count == 1
                && entry?.id == "9000_2"
                && entry?.displayName == "EffectExpectations"
                && triggerModeMatches
                && entry?.modifiers == expectedModifiers
                && entry?.perTurnModifiers.isEmpty == true
                && entry?.duration == 3
                && entry?.scope == .party
                && entry?.category == "spell"
                && entry?.sourceSkillId == 9000
            recordPass(id: "SKILL-EFFECT-076",
                       passed: passed,
                       rawData: ["spellId": 2,
                                 "target": Double(TimedBuffScope.party.rawValue),
                                 "multiplier": 1.4,
                                 "triggerTurn": 3,
                                 "count": Double(triggers.count)])
        }

        do {
            let effect = makeEffect(index: 3,
                                    type: .timedMagicPowerAmplify,
                                    parameters: [
                                        .target: Int(TimedBuffScope.party.rawValue)
                                    ],
                                    values: [
                                        .triggerTurn: 4,
                                        .multiplier: 1.3
                                    ])
            let triggers = try compile(effect).status.timedBuffTriggers
            let entry = triggers.first
            let expectedModifiers: [String: Double] = [
                "magicalDamageDealtMultiplier": 1.3
            ]
            let triggerModeMatches = isTriggerModeAtTurn(entry?.triggerMode, turn: 4)
            let passed = triggers.count == 1
                && entry?.id == "9000_3"
                && entry?.displayName == "EffectExpectations"
                && triggerModeMatches
                && entry?.modifiers == expectedModifiers
                && entry?.perTurnModifiers.isEmpty == true
                && entry?.duration == 4
                && entry?.scope == .party
                && entry?.category == "magic"
                && entry?.sourceSkillId == 9000
            recordPass(id: "SKILL-EFFECT-077",
                       passed: passed,
                       rawData: ["target": Double(TimedBuffScope.party.rawValue),
                                 "triggerTurn": 4,
                                 "multiplier": 1.3,
                                 "count": Double(triggers.count)])
        }

        do {
            let effect = makeEffect(index: 4,
                                    type: .timedBreathPowerAmplify,
                                    parameters: [
                                        .target: Int(TimedBuffScope.party.rawValue)
                                    ],
                                    values: [
                                        .triggerTurn: 5,
                                        .multiplier: 1.2
                                    ])
            let triggers = try compile(effect).status.timedBuffTriggers
            let entry = triggers.first
            let expectedModifiers: [String: Double] = [
                "breathDamageDealtMultiplier": 1.2
            ]
            let triggerModeMatches = isTriggerModeAtTurn(entry?.triggerMode, turn: 5)
            let passed = triggers.count == 1
                && entry?.id == "9000_4"
                && entry?.displayName == "EffectExpectations"
                && triggerModeMatches
                && entry?.modifiers == expectedModifiers
                && entry?.perTurnModifiers.isEmpty == true
                && entry?.duration == 5
                && entry?.scope == .party
                && entry?.category == "breath"
                && entry?.sourceSkillId == 9000
            recordPass(id: "SKILL-EFFECT-078",
                       passed: passed,
                       rawData: ["target": Double(TimedBuffScope.party.rawValue),
                                 "triggerTurn": 5,
                                 "multiplier": 1.2,
                                 "count": Double(triggers.count)])
        }

        // MARK: - Combat Stats / Non-battle

        do {
            let effect = makeEffect(type: .additionalDamageScoreAdditive,
                                    values: [.additive: 5])
            let inputs = try compileCombatInputs(effect)
            let measured = inputs.additives.value(for: .additionalDamageScore)
            recordDouble(id: "SKILL-EFFECT-079",
                         expected: 5,
                         measured: measured,
                         rawData: ["additive": 5])
        }

        do {
            let effect = makeEffect(type: .additionalDamageScoreMultiplier,
                                    values: [.multiplier: 1.2])
            let inputs = try compileCombatInputs(effect)
            let measured = inputs.passives.multiplier(for: .additionalDamageScore)
            recordDouble(id: "SKILL-EFFECT-080",
                         expected: 1.2,
                         measured: measured,
                         rawData: ["multiplier": 1.2])
        }

        do {
            let effect = makeEffect(type: .statAdditive,
                                    parameters: [.stat: Int(CombatStat.physicalAttackScore.rawValue)],
                                    values: [.additive: 20])
            let inputs = try compileCombatInputs(effect)
            let measured = inputs.additives.value(for: .physicalAttackScore)
            recordDouble(id: "SKILL-EFFECT-081",
                         expected: 20,
                         measured: measured,
                         rawData: ["stat": Double(CombatStat.physicalAttackScore.rawValue), "additive": 20])
        }

        do {
            let effect = makeEffect(type: .statMultiplier,
                                    parameters: [.stat: Int(CombatStat.magicalDefenseScore.rawValue)],
                                    values: [.multiplier: 1.5])
            let inputs = try compileCombatInputs(effect)
            let measured = inputs.passives.multiplier(for: .magicalDefenseScore)
            recordDouble(id: "SKILL-EFFECT-082",
                         expected: 1.5,
                         measured: measured,
                         rawData: ["stat": Double(CombatStat.magicalDefenseScore.rawValue), "multiplier": 1.5])
        }

        do {
            let effect = makeEffect(type: .statConversionPercent,
                                    parameters: [
                                        .sourceStat: Int(CombatStat.physicalDefenseScore.rawValue),
                                        .targetStat: Int(CombatStat.physicalAttackScore.rawValue)
                                    ],
                                    values: [.valuePercent: 25])
            let inputs = try compileCombatInputs(effect)
            let conversions = inputs.statConversions[.physicalAttackScore] ?? []
            let entry = conversions.first { $0.source == .physicalDefenseScore && $0.kind == .percent }
            let measured = entry?.ratio ?? 0
            recordDouble(id: "SKILL-EFFECT-083",
                         expected: 0.25,
                         measured: measured,
                         rawData: ["sourceStat": Double(CombatStat.physicalDefenseScore.rawValue),
                                   "targetStat": Double(CombatStat.physicalAttackScore.rawValue),
                                   "valuePercent": 25])
        }

        do {
            let effect = makeEffect(type: .statConversionLinear,
                                    parameters: [
                                        .sourceStat: Int(CombatStat.attackCount.rawValue),
                                        .targetStat: Int(CombatStat.criticalChancePercent.rawValue)
                                    ],
                                    values: [.valuePerUnit: 3])
            let inputs = try compileCombatInputs(effect)
            let conversions = inputs.statConversions[.criticalChancePercent] ?? []
            let entry = conversions.first { $0.source == .attackCount && $0.kind == .linear }
            let measured = entry?.ratio ?? 0
            recordDouble(id: "SKILL-EFFECT-084",
                         expected: 3,
                         measured: measured,
                         rawData: ["sourceStat": Double(CombatStat.attackCount.rawValue),
                                   "targetStat": Double(CombatStat.criticalChancePercent.rawValue),
                                   "valuePerUnit": 3])
        }

        do {
            let effect = makeEffect(type: .statFixedToOne,
                                    parameters: [.stat: Int(CombatStat.hitScore.rawValue)])
            let inputs = try compileCombatInputs(effect)
            recordPass(id: "SKILL-EFFECT-085",
                       passed: inputs.forcedToOne.contains(.hitScore),
                       rawData: ["stat": Double(CombatStat.hitScore.rawValue)])
        }

        do {
            let effect = makeEffect(type: .itemStatMultiplier,
                                    parameters: [.statType: Int(CombatStat.breathDamageScore.rawValue)],
                                    values: [.multiplier: 1.4])
            let inputs = try compileCombatInputs(effect)
            let measured = inputs.itemStatMultipliers[.breathDamageScore] ?? 1.0
            recordDouble(id: "SKILL-EFFECT-086",
                         expected: 1.4,
                         measured: measured,
                         rawData: ["statType": Double(CombatStat.breathDamageScore.rawValue), "multiplier": 1.4])
        }

        do {
            let effect = makeEffect(type: .talentStat,
                                    parameters: [.stat: Int(CombatStat.physicalAttackScore.rawValue)],
                                    values: [.multiplier: 1.6])
            let inputs = try compileCombatInputs(effect)
            let measured = inputs.talents.talentMultiplier(for: .physicalAttackScore)
            recordDouble(id: "SKILL-EFFECT-087",
                         expected: 1.6,
                         measured: measured,
                         rawData: ["stat": Double(CombatStat.physicalAttackScore.rawValue), "multiplier": 1.6])
        }

        do {
            let effect = makeEffect(type: .incompetenceStat,
                                    parameters: [.stat: Int(CombatStat.magicalAttackScore.rawValue)],
                                    values: [.multiplier: 0.4])
            let inputs = try compileCombatInputs(effect)
            let measured = inputs.talents.incompetenceMultiplier(for: .magicalAttackScore)
            recordDouble(id: "SKILL-EFFECT-088",
                         expected: 0.4,
                         measured: measured,
                         rawData: ["stat": Double(CombatStat.magicalAttackScore.rawValue), "multiplier": 0.4])
        }

        do {
            let effect = makeEffect(type: .growthMultiplier,
                                    values: [.multiplier: 1.3])
            let inputs = try compileCombatInputs(effect)
            recordDouble(id: "SKILL-EFFECT-089",
                         expected: 1.3,
                         measured: inputs.growthMultiplier,
                         rawData: ["multiplier": 1.3])
        }

        do {
            let effect = makeEffect(type: .attackCountMultiplier,
                                    values: [.multiplier: 1.25])
            let inputs = try compileCombatInputs(effect)
            let measured = inputs.passives.multiplier(for: .attackCount)
            recordDouble(id: "SKILL-EFFECT-090",
                         expected: 1.25,
                         measured: measured,
                         rawData: ["multiplier": 1.25])
        }

        do {
            let effect = makeEffect(type: .spellAccess,
                                    parameters: [.spellId: 1, .action: 1])
            let result = try aggregate(effect)
            let passed = result.spellbook.learnedSpellIds.contains(1)
            recordPass(id: "SKILL-EFFECT-091",
                       passed: passed,
                       rawData: ["spellId": 1])
        }

        do {
            let effect = makeEffect(type: .spellTierUnlock,
                                    parameters: [.school: Int(SpellDefinition.School.mage.rawValue)],
                                    values: [.tier: 3])
            let result = try aggregate(effect)
            let measured = result.spellbook.tierUnlocks[SpellDefinition.School.mage.index] ?? 0
            recordInt(id: "SKILL-EFFECT-092",
                      expected: 3,
                      measured: measured,
                      rawData: ["school": Double(SpellDefinition.School.mage.rawValue), "tier": 3])
        }

        do {
            let effect = makeEffect(type: .criticalChancePercentAdditive,
                                    values: [.points: 7])
            let inputs = try compileCombatInputs(effect)
            recordDouble(id: "SKILL-EFFECT-093",
                         expected: 7,
                         measured: inputs.critical.flatBonus,
                         rawData: ["points": 7])
        }

        do {
            let effect = makeEffect(type: .criticalChancePercentCap,
                                    values: [.cap: 80])
            let inputs = try compileCombatInputs(effect)
            recordDouble(id: "SKILL-EFFECT-094",
                         expected: 80,
                         measured: inputs.critical.cap ?? 0,
                         rawData: ["cap": 80])
        }

        do {
            let effect = makeEffect(type: .criticalChancePercentMaxDelta,
                                    values: [.deltaPercent: 5])
            let inputs = try compileCombatInputs(effect)
            recordDouble(id: "SKILL-EFFECT-095",
                         expected: 5,
                         measured: inputs.critical.capDelta,
                         rawData: ["deltaPercent": 5])
        }

        do {
            let effect = makeEffect(type: .equipmentSlotAdditive,
                                    values: [.add: 2])
            let result = try aggregate(effect)
            recordInt(id: "SKILL-EFFECT-096",
                      expected: 2,
                      measured: result.equipmentSlots.additive,
                      rawData: ["add": 2])
        }

        do {
            let effect = makeEffect(type: .equipmentSlotMultiplier,
                                    values: [.multiplier: 1.5])
            let result = try aggregate(effect)
            recordDouble(id: "SKILL-EFFECT-097",
                         expected: 1.5,
                         measured: result.equipmentSlots.multiplier,
                         rawData: ["multiplier": 1.5])
        }

        do {
            let effect = makeEffect(type: .explorationTimeMultiplier,
                                    parameters: [.dungeonName: 2],
                                    values: [.multiplier: 0.8])
            let result = try aggregate(effect)
            let measured = result.explorationModifiers.multiplier(forDungeonId: 2, dungeonName: "dummy")
            recordDouble(id: "SKILL-EFFECT-098",
                         expected: 0.8,
                         measured: measured,
                         rawData: ["dungeonId": 2, "multiplier": 0.8])
        }

        do {
            let effect = makeEffect(type: .rewardExperiencePercent,
                                    values: [.valuePercent: 20])
            let result = try aggregate(effect)
            recordDouble(id: "SKILL-EFFECT-099",
                         expected: 1.2,
                         measured: result.rewardComponents.experienceScale(),
                         rawData: ["valuePercent": 20])
        }

        do {
            let effect = makeEffect(type: .rewardExperienceMultiplier,
                                    values: [.multiplier: 1.5])
            let result = try aggregate(effect)
            recordDouble(id: "SKILL-EFFECT-100",
                         expected: 1.5,
                         measured: result.rewardComponents.experienceScale(),
                         rawData: ["multiplier": 1.5])
        }

        do {
            let effect = makeEffect(type: .rewardGoldPercent,
                                    values: [.valuePercent: 10])
            let result = try aggregate(effect)
            recordDouble(id: "SKILL-EFFECT-101",
                         expected: 1.1,
                         measured: result.rewardComponents.goldScale(),
                         rawData: ["valuePercent": 10])
        }

        do {
            let effect = makeEffect(type: .rewardGoldMultiplier,
                                    values: [.multiplier: 1.4])
            let result = try aggregate(effect)
            recordDouble(id: "SKILL-EFFECT-102",
                         expected: 1.4,
                         measured: result.rewardComponents.goldScale(),
                         rawData: ["multiplier": 1.4])
        }

        do {
            let effect = makeEffect(type: .rewardItemPercent,
                                    values: [.valuePercent: 15])
            let result = try aggregate(effect)
            recordDouble(id: "SKILL-EFFECT-103",
                         expected: 1.15,
                         measured: result.rewardComponents.itemDropScale(),
                         rawData: ["valuePercent": 15])
        }

        do {
            let effect = makeEffect(type: .rewardItemMultiplier,
                                    values: [.multiplier: 1.3])
            let result = try aggregate(effect)
            recordDouble(id: "SKILL-EFFECT-104",
                         expected: 1.3,
                         measured: result.rewardComponents.itemDropScale(),
                         rawData: ["multiplier": 1.3])
        }

        do {
            let effect = makeEffect(type: .rewardTitlePercent,
                                    values: [.valuePercent: 25])
            let result = try aggregate(effect)
            recordDouble(id: "SKILL-EFFECT-105",
                         expected: 1.25,
                         measured: result.rewardComponents.titleScale(),
                         rawData: ["valuePercent": 25])
        }

        do {
            let effect = makeEffect(type: .rewardTitleMultiplier,
                                    values: [.multiplier: 1.2])
            let result = try aggregate(effect)
            recordDouble(id: "SKILL-EFFECT-106",
                         expected: 1.2,
                         measured: result.rewardComponents.titleScale(),
                         rawData: ["multiplier": 1.2])
        }
    }
}
