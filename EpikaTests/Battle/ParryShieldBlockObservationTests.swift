import XCTest
@testable import Epika

nonisolated final class ParryShieldBlockObservationTests: XCTestCase {
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

    @MainActor func testParryStopsMultiHitAfterFirstHit() async throws {
        let row = try loadExpectationRow(familyId: "parry.general", selection: "max")
        let bonusPercent = extractValue(named: "bonusPercent", from: row.expectedEffectSummary) ?? 0
        let actorEffects = try await compileActorEffects(skillId: row.sampleId)

        XCTAssertTrue(actorEffects.combat.parryEnabled, "parry.general が有効になっていません (skillId=\(row.sampleId))")
        XCTAssertEqual(actorEffects.combat.parryBonusPercent, bonusPercent, accuracy: 0.0001, "parryBonusPercent 不一致 (skillId=\(row.sampleId))")

        let defenderAdditionalDamage = 200
        let expectedBaseChance = 10.0 + Double(defenderAdditionalDamage) * 0.25 + bonusPercent

        let result = withFixedMedianRandomMode {
            var attacker = TestActorBuilder.makeAttacker(
                physicalAttackScore: 5000,
                hitScore: 200,
                luck: 35,
                additionalDamageScore: 0
            )
            var attackerSnapshot = attacker.snapshot
            attackerSnapshot.attackCount = 3
            attacker.snapshot = attackerSnapshot

            var defender = TestActorBuilder.makeDefender(
                physicalDefenseScore: 2000,
                evasionScore: 0,
                luck: 1,
                skillEffects: actorEffects
            )
            var defenderSnapshot = defender.snapshot
            defenderSnapshot.additionalDamageScore = defenderAdditionalDamage
            defender.snapshot = defenderSnapshot

            var context = BattleContext(
                players: [attacker],
                enemies: [defender],
                statusDefinitions: [:],
                skillDefinitions: [:],
                random: GameRandomSource(seed: 1)
            )
            let attackerId = context.actorIndex(for: .player, arrayIndex: 0)
            let entryBuilder = context.makeActionEntryBuilder(actorId: attackerId, kind: .physicalAttack)

            return BattleTurnEngine.performAttack(
                attackerSide: .player,
                attackerIndex: 0,
                attacker: attacker,
                defender: defender,
                defenderSide: .enemy,
                defenderIndex: 0,
                context: &context,
                hitCountOverride: nil,
                accuracyMultiplier: 1.0,
                overrides: BattleTurnEngine.PhysicalAttackOverrides(forceHit: true),
                entryBuilder: entryBuilder
            )
        }

        ObservationRecorder.shared.record(
            id: "BATTLE-PARRY-001",
            expected: (min: 1, max: 1),
            measured: Double(result.successfulHits),
            rawData: [
                "expectedBaseChance": expectedBaseChance,
                "bonusPercent": bonusPercent,
                "defenderAdditionalDamage": Double(defenderAdditionalDamage),
                "attackCount": 3
            ]
        )

        XCTAssertTrue(result.wasParried, "パリィが発動していません")
        XCTAssertEqual(result.successfulHits, 1, "パリィ成功時は1回目のみヒットする想定です")
    }

    @MainActor func testShieldBlockStopsMultiHitAfterFirstHit() async throws {
        let row = try loadExpectationRow(familyId: "shieldBlock.general", selection: "max")
        let bonusPercent = extractValue(named: "bonusPercent", from: row.expectedEffectSummary) ?? 0
        let actorEffects = try await compileActorEffects(skillId: row.sampleId)

        XCTAssertTrue(actorEffects.combat.shieldBlockEnabled, "shieldBlock.general が有効になっていません (skillId=\(row.sampleId))")
        XCTAssertEqual(actorEffects.combat.shieldBlockBonusPercent, bonusPercent, accuracy: 0.0001, "shieldBlockBonusPercent 不一致 (skillId=\(row.sampleId))")

        let attackerAdditionalDamage = 0
        let expectedBaseChance = 30.0 - Double(attackerAdditionalDamage) / 2.0 + bonusPercent

        let result = withFixedMedianRandomMode {
            var attacker = TestActorBuilder.makeAttacker(
                physicalAttackScore: 5000,
                hitScore: 200,
                luck: 35,
                additionalDamageScore: attackerAdditionalDamage
            )
            var attackerSnapshot = attacker.snapshot
            attackerSnapshot.attackCount = 3
            attacker.snapshot = attackerSnapshot

            let defender = TestActorBuilder.makeDefender(
                physicalDefenseScore: 2000,
                evasionScore: 0,
                luck: 1,
                skillEffects: actorEffects
            )

            var context = BattleContext(
                players: [attacker],
                enemies: [defender],
                statusDefinitions: [:],
                skillDefinitions: [:],
                random: GameRandomSource(seed: 1)
            )
            let attackerId = context.actorIndex(for: .player, arrayIndex: 0)
            let entryBuilder = context.makeActionEntryBuilder(actorId: attackerId, kind: .physicalAttack)

            return BattleTurnEngine.performAttack(
                attackerSide: .player,
                attackerIndex: 0,
                attacker: attacker,
                defender: defender,
                defenderSide: .enemy,
                defenderIndex: 0,
                context: &context,
                hitCountOverride: nil,
                accuracyMultiplier: 1.0,
                overrides: BattleTurnEngine.PhysicalAttackOverrides(forceHit: true),
                entryBuilder: entryBuilder
            )
        }

        ObservationRecorder.shared.record(
            id: "BATTLE-SHIELD-001",
            expected: (min: 1, max: 1),
            measured: Double(result.successfulHits),
            rawData: [
                "expectedBaseChance": expectedBaseChance,
                "bonusPercent": bonusPercent,
                "attackerAdditionalDamage": Double(attackerAdditionalDamage),
                "attackCount": 3
            ]
        )

        XCTAssertTrue(result.wasBlocked, "盾防御が発動していません")
        XCTAssertEqual(result.successfulHits, 1, "盾防御成功時は1回目のみヒットする想定です")
    }

    // MARK: - Timed Buffs

    @MainActor func testTimedBuffBattleStartDamageDealtMultiplier() async throws {
        let row = try loadExpectationRow(familyId: "race.vampire.openingBuff", selection: "min")
        let damagePercent = try XCTUnwrap(
            extractValue(named: "damageDealtPercent", from: row.expectedEffectSummary),
            "damageDealtPercent が見つかりません (skillId=\(row.sampleId))"
        )
        let durationValue = try XCTUnwrap(
            extractValue(named: "duration", from: row.expectedEffectSummary),
            "duration が見つかりません (skillId=\(row.sampleId))"
        )
        let actorEffects = try await compileActorEffects(skillId: row.sampleId)

        let player = TestActorBuilder.makePlayer(
            physicalAttackScore: 1000,
            hitScore: 100,
            evasionScore: 0,
            luck: 1,
            skillEffects: actorEffects
        )
        let enemy = TestActorBuilder.makeEnemy(luck: 1)
        var context = BattleContext(
            players: [player],
            enemies: [enemy],
            statusDefinitions: [:],
            skillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )

        applyBattleStartTimedBuffs(&context)

        let updatedPlayer = context.players[0]
        let expectedMultiplier = 1.0 + damagePercent / 100.0
        let physical = BattleTurnEngine.damageDealtModifier(for: updatedPlayer, against: enemy, damageType: .physical)
        let magical = BattleTurnEngine.damageDealtModifier(for: updatedPlayer, against: enemy, damageType: .magical)
        let breath = BattleTurnEngine.damageDealtModifier(for: updatedPlayer, against: enemy, damageType: .breath)
        let duration = Int(durationValue.rounded(.towardZero))

        ObservationRecorder.shared.record(
            id: "BATTLE-TIMED-001",
            expected: (min: expectedMultiplier, max: expectedMultiplier),
            measured: physical,
            rawData: [
                "damagePercent": damagePercent,
                "duration": Double(duration),
                "expectedMultiplier": expectedMultiplier,
                "physicalMultiplier": physical,
                "magicalMultiplier": magical,
                "breathMultiplier": breath
            ]
        )

        XCTAssertEqual(physical, expectedMultiplier, accuracy: 0.0001, "physical 倍率が不一致です")
        XCTAssertEqual(magical, expectedMultiplier, accuracy: 0.0001, "magical 倍率が不一致です")
        XCTAssertEqual(breath, expectedMultiplier, accuracy: 0.0001, "breath 倍率が不一致です")
        XCTAssertEqual(updatedPlayer.timedBuffs.first?.remainingTurns, duration, "duration が不一致です")
    }

    @MainActor func testTimedBuffBattleStartHitScoreAdditive() async throws {
        let row = try loadExpectationRow(familyId: "race.werecat.firstTurnHit", selection: "min")
        let hitAdditive = try XCTUnwrap(
            extractValue(named: "hitScoreAdditive", from: row.expectedEffectSummary),
            "hitScoreAdditive が見つかりません (skillId=\(row.sampleId))"
        )
        let durationValue = try XCTUnwrap(
            extractValue(named: "duration", from: row.expectedEffectSummary),
            "duration が見つかりません (skillId=\(row.sampleId))"
        )
        let actorEffects = try await compileActorEffects(skillId: row.sampleId)

        let baseHitScore = 100
        let player = TestActorBuilder.makePlayer(
            hitScore: baseHitScore,
            evasionScore: 0,
            luck: 1,
            skillEffects: actorEffects
        )
        let enemy = TestActorBuilder.makeEnemy(luck: 1)
        var context = BattleContext(
            players: [player],
            enemies: [enemy],
            statusDefinitions: [:],
            skillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )

        applyBattleStartTimedBuffs(&context)

        let updatedPlayer = context.players[0]
        let bonus = BattleTurnEngine.aggregateAdditive(from: updatedPlayer.timedBuffs, key: "hitScoreAdditive")
        let duration = Int(durationValue.rounded(.towardZero))

        ObservationRecorder.shared.record(
            id: "BATTLE-TIMED-002",
            expected: (min: hitAdditive, max: hitAdditive),
            measured: bonus,
            rawData: [
                "baseHitScore": Double(baseHitScore),
                "hitScoreAdditive": hitAdditive,
                "duration": Double(duration),
                "measuredBonus": bonus
            ]
        )

        XCTAssertEqual(bonus, hitAdditive, accuracy: 0.0001, "hitScoreAdditive が不一致です")
        XCTAssertEqual(updatedPlayer.timedBuffs.first?.remainingTurns, duration, "duration が不一致です")
    }

    @MainActor func testTimedBuffTurnElapsedHitEvasionAdditive() async throws {
        let row = try loadExpectationRow(familyId: "race.human.turnBuff", selection: "min")
        let hitPerTurn = try XCTUnwrap(
            extractValue(named: "hitScoreAdditivePerTurn", from: row.expectedEffectSummary),
            "hitScoreAdditivePerTurn が見つかりません (skillId=\(row.sampleId))"
        )
        let evasionPerTurn = try XCTUnwrap(
            extractValue(named: "evasionScoreAdditivePerTurn", from: row.expectedEffectSummary),
            "evasionScoreAdditivePerTurn が見つかりません (skillId=\(row.sampleId))"
        )
        let actorEffects = try await compileActorEffects(skillId: row.sampleId)

        let baseHitScore = 100
        let baseEvasionScore = 100
        let player = TestActorBuilder.makePlayer(
            hitScore: baseHitScore,
            evasionScore: baseEvasionScore,
            luck: 1,
            skillEffects: actorEffects
        )
        let enemy = TestActorBuilder.makeEnemy(luck: 1)
        var context = BattleContext(
            players: [player],
            enemies: [enemy],
            statusDefinitions: [:],
            skillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )

        let turns = 2
        applyTurnElapsedTimedBuffs(&context, turns: turns)

        let updatedPlayer = context.players[0]
        let expectedHit = baseHitScore + Int(hitPerTurn.rounded(.towardZero)) * turns
        let expectedEvasion = baseEvasionScore + Int(evasionPerTurn.rounded(.towardZero)) * turns

        ObservationRecorder.shared.record(
            id: "BATTLE-TIMED-003",
            expected: (min: Double(expectedHit), max: Double(expectedHit)),
            measured: Double(updatedPlayer.snapshot.hitScore),
            rawData: [
                "baseHitScore": Double(baseHitScore),
                "hitPerTurn": hitPerTurn,
                "turns": Double(turns)
            ]
        )
        ObservationRecorder.shared.record(
            id: "BATTLE-TIMED-004",
            expected: (min: Double(expectedEvasion), max: Double(expectedEvasion)),
            measured: Double(updatedPlayer.snapshot.evasionScore),
            rawData: [
                "baseEvasionScore": Double(baseEvasionScore),
                "evasionPerTurn": evasionPerTurn,
                "turns": Double(turns)
            ]
        )

        XCTAssertEqual(updatedPlayer.snapshot.hitScore, expectedHit, "hitScore の累積値が不一致です")
        XCTAssertEqual(updatedPlayer.snapshot.evasionScore, expectedEvasion, "evasionScore の累積値が不一致です")
    }

    @MainActor func testTimedBuffTurnElapsedAttackCountPercent() async throws {
        let row = try loadExpectationRow(familyId: "race.amazoness.turnAttackCount", selection: "min")
        let percentPerTurn = try XCTUnwrap(
            extractValue(named: "attackCountPercentPerTurn", from: row.expectedEffectSummary),
            "attackCountPercentPerTurn が見つかりません (skillId=\(row.sampleId))"
        )
        let actorEffects = try await compileActorEffects(skillId: row.sampleId)

        var player = TestActorBuilder.makePlayer(luck: 1, skillEffects: actorEffects)
        var snapshot = player.snapshot
        snapshot.attackCount = 1.0
        player.snapshot = snapshot

        let enemy = TestActorBuilder.makeEnemy(luck: 1)
        var context = BattleContext(
            players: [player],
            enemies: [enemy],
            statusDefinitions: [:],
            skillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )

        let turns = 2
        applyTurnElapsedTimedBuffs(&context, turns: turns)

        let updatedPlayer = context.players[0]
        let expectedCount = expectedAttackCountAfterTurns(base: 1.0, percent: percentPerTurn, turns: turns)

        ObservationRecorder.shared.record(
            id: "BATTLE-TIMED-005",
            expected: (min: expectedCount, max: expectedCount),
            measured: updatedPlayer.snapshot.attackCount,
            rawData: [
                "baseAttackCount": 1.0,
                "percentPerTurn": percentPerTurn,
                "turns": Double(turns)
            ]
        )

        XCTAssertEqual(updatedPlayer.snapshot.attackCount, expectedCount, accuracy: 0.0001, "attackCount の累積値が不一致です")
    }

    @MainActor func testTimedBuffTurnElapsedAttackDefensePercent() async throws {
        let row = try loadExpectationRow(familyId: "race.oni.turnStatBuff", selection: "min")
        let attackPercentPerTurn = try XCTUnwrap(
            extractValue(named: "attackPercentPerTurn", from: row.expectedEffectSummary),
            "attackPercentPerTurn が見つかりません (skillId=\(row.sampleId))"
        )
        let defensePercentPerTurn = try XCTUnwrap(
            extractValue(named: "defensePercentPerTurn", from: row.expectedEffectSummary),
            "defensePercentPerTurn が見つかりません (skillId=\(row.sampleId))"
        )
        let actorEffects = try await compileActorEffects(skillId: row.sampleId)

        let baseAttackScore = 1000
        let baseDefenseScore = 500
        let player = TestActorBuilder.makePlayer(
            physicalAttackScore: baseAttackScore,
            physicalDefenseScore: baseDefenseScore,
            hitScore: 80,
            evasionScore: 10,
            luck: 1,
            skillEffects: actorEffects
        )
        let enemy = TestActorBuilder.makeEnemy(luck: 1)
        var context = BattleContext(
            players: [player],
            enemies: [enemy],
            statusDefinitions: [:],
            skillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )

        let turns = 2
        applyTurnElapsedTimedBuffs(&context, turns: turns)

        let updatedPlayer = context.players[0]
        let expectedAttack = expectedStatAfterTurns(base: baseAttackScore, percent: attackPercentPerTurn, turns: turns)
        let expectedDefense = expectedStatAfterTurns(base: baseDefenseScore, percent: defensePercentPerTurn, turns: turns)

        ObservationRecorder.shared.record(
            id: "BATTLE-TIMED-006",
            expected: (min: Double(expectedAttack), max: Double(expectedAttack)),
            measured: Double(updatedPlayer.snapshot.physicalAttackScore),
            rawData: [
                "baseAttackScore": Double(baseAttackScore),
                "percentPerTurn": attackPercentPerTurn,
                "turns": Double(turns)
            ]
        )
        ObservationRecorder.shared.record(
            id: "BATTLE-TIMED-007",
            expected: (min: Double(expectedDefense), max: Double(expectedDefense)),
            measured: Double(updatedPlayer.snapshot.physicalDefenseScore),
            rawData: [
                "baseDefenseScore": Double(baseDefenseScore),
                "percentPerTurn": defensePercentPerTurn,
                "turns": Double(turns)
            ]
        )

        XCTAssertEqual(updatedPlayer.snapshot.physicalAttackScore, expectedAttack, "physicalAttackScore の累積値が不一致です")
        XCTAssertEqual(updatedPlayer.snapshot.physicalDefenseScore, expectedDefense, "physicalDefenseScore の累積値が不一致です")
    }
}

private extension ParryShieldBlockObservationTests {
    struct ExpectationRow: Sendable {
        let familyId: String
        let selection: String
        let sampleId: UInt16
        let sampleLabel: String
        let expectedEffectSummary: String
    }

    func withFixedMedianRandomMode<T>(_ body: () -> T) -> T {
        let previous = BetaTestSettings.randomMode
        BetaTestSettings.randomMode = .fixedMedian
        defer { BetaTestSettings.randomMode = previous }
        return body()
    }

    func loadExpectationRow(familyId: String, selection: String) throws -> ExpectationRow {
        let rows = try loadExpectationRows()
        if let row = rows.first(where: { $0.familyId == familyId && $0.selection == selection }) {
            return row
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    func loadExpectationRows() throws -> [ExpectationRow] {
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
                continue
            }

            rows.append(ExpectationRow(
                familyId: field(fields, "familyId"),
                selection: field(fields, "selection"),
                sampleId: id,
                sampleLabel: field(fields, "sampleLabel"),
                expectedEffectSummary: field(fields, "expectedEffectSummary")
            ))
        }
        return rows
    }

    func extractValue(named key: String, from summary: String) -> Double? {
        let prefix = "value.\(key)="
        let segments = summary.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        for segment in segments {
            let tokens = segment.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            for token in tokens {
                if token.hasPrefix(prefix) {
                    let raw = token.dropFirst(prefix.count)
                    return Double(raw)
                }
            }
        }
        return nil
    }

    @MainActor
    func compileActorEffects(skillId: UInt16) async throws -> BattleActor.SkillEffects {
        let skillsById = try await loadSkillsById()
        guard let skill = skillsById[skillId] else {
            throw RuntimeError.masterDataNotFound(entity: "SkillDefinition", identifier: "\(skillId)")
        }
        return try UnifiedSkillEffectCompiler(skills: [skill]).actorEffects
    }

    @MainActor
    func loadSkillsById() async throws -> [UInt16: SkillDefinition] {
        let databaseURL = try resolveMasterDataURL()
        let manager = SQLiteMasterDataManager()
        try await manager.initialize(databaseURL: databaseURL)
        let cache = try await MasterDataLoader.load(manager: manager)
        return Dictionary(uniqueKeysWithValues: cache.allSkills.map { ($0.id, $0) })
    }

    func resolveMasterDataURL() throws -> URL {
        if let url = Bundle.main.url(forResource: "master_data", withExtension: "db") {
            return url
        }
        let bundle = Bundle(for: ParryShieldBlockObservationTests.self)
        if let url = bundle.url(forResource: "master_data", withExtension: "db") {
            return url
        }
        XCTFail("master_data.db が見つかりません")
        throw SQLiteMasterDataError.bundledDatabaseNotFound
    }

    func resolveExpectationTSVURL() throws -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        let battleDir = testFile.deletingLastPathComponent()
        let testsDir = battleDir.deletingLastPathComponent()
        let dataURL = testsDir.appendingPathComponent("TestData/SkillFamilyExpectations.tsv")
        if FileManager.default.fileExists(atPath: dataURL.path) {
            return dataURL
        }
        XCTFail("SkillFamilyExpectations.tsv が見つかりません")
        throw CocoaError(.fileNoSuchFile)
    }

    func applyBattleStartTimedBuffs(_ context: inout BattleContext) {
        context.turn = 1
        BattleTurnEngine.applyTimedBuffTriggers(&context, includeEveryTurn: false)
    }

    func applyTurnElapsedTimedBuffs(_ context: inout BattleContext, turns: Int) {
        guard turns > 0 else { return }
        for turn in 1...turns {
            context.turn = turn
            BattleTurnEngine.applyTimedBuffTriggers(&context, includeEveryTurn: true)
        }
    }

    func expectedStatAfterTurns(base: Int, percent: Double, turns: Int) -> Int {
        guard turns > 0 else { return base }
        var value = base
        for _ in 0..<turns {
            let bonus = Int((Double(value) * percent / 100.0).rounded(.towardZero))
            value += bonus
        }
        return value
    }

    func expectedAttackCountAfterTurns(base: Double, percent: Double, turns: Int) -> Double {
        guard turns > 0 else { return base }
        var value = base
        for _ in 0..<turns {
            let bonus = value * percent / 100.0
            value = max(1.0, value + bonus)
        }
        return value
    }
}
