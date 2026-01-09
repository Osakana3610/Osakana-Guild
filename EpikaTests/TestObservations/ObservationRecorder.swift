import Foundation

/// テスト観点の記録結果
struct ObservationResult: Codable {
    let id: String
    let timestamp: String
    let expected: ExpectedRange
    let measured: Double
    let passed: Bool
    let rawData: [String: Double]

    struct ExpectedRange: Codable {
        let min: Double?
        let max: Double?

        func contains(_ value: Double) -> Bool {
            let aboveMin = min.map { value >= $0 } ?? true
            let belowMax = max.map { value <= $0 } ?? true
            return aboveMin && belowMax
        }
    }
}

/// テスト実行の記録
struct TestRunRecord: Codable {
    let runId: String
    let startTime: String
    let endTime: String?
    let results: [ObservationResult]
}

/// テスト観点を記録するユーティリティ
///
/// 使い方:
/// ```swift
/// func testSomething() {
///     let result = someFunctionUnderTest()
///
///     ObservationRecorder.shared.record(
///         id: "BATTLE-PHYS-001",
///         expected: (min: 2073, max: 2157),
///         measured: result.averageDamage,
///         rawData: ["totalDamage": result.total, "count": Double(result.count)]
///     )
///
///     XCTAssertTrue(result.isValid)
/// }
/// ```
final class ObservationRecorder {
    static let shared = ObservationRecorder()

    private var results: [ObservationResult] = []
    private let runId: String
    private let startTime: Date

    private init() {
        self.runId = ISO8601DateFormatter().string(from: Date())
        self.startTime = Date()
    }

    // MARK: - Recording

    /// 観点を記録する
    /// - Parameters:
    ///   - id: 観点ID（BattleObservations.jsonのidと一致させる）
    ///   - expected: 期待範囲（min, max）。nilは制限なし
    ///   - measured: 実測値
    ///   - rawData: 詳細データ（デバッグ・検証用）
    func record(
        id: String,
        expected: (min: Double?, max: Double?),
        measured: Double,
        rawData: [String: Double] = [:]
    ) {
        let expectedRange = ObservationResult.ExpectedRange(min: expected.min, max: expected.max)
        let passed = expectedRange.contains(measured)

        let result = ObservationResult(
            id: id,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            expected: expectedRange,
            measured: measured,
            passed: passed,
            rawData: rawData
        )

        results.append(result)
    }

    /// 相対比較の観点を記録する（A < B の検証など）
    /// - Parameters:
    ///   - id: 観点ID
    ///   - comparison: 比較の説明
    ///   - passed: 比較結果
    ///   - rawData: 詳細データ
    func recordComparison(
        id: String,
        comparison: String,
        passed: Bool,
        rawData: [String: Double]
    ) {
        let result = ObservationResult(
            id: id,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            expected: ObservationResult.ExpectedRange(min: nil, max: nil),
            measured: passed ? 1 : 0,
            passed: passed,
            rawData: rawData
        )

        results.append(result)
    }

    // MARK: - Export

    /// 結果をJSONファイルに出力する
    /// - Returns: 出力先のURL
    @discardableResult
    func export() throws -> URL {
        let outputDir = try Self.outputDirectory()

        // ディレクトリがなければ作成
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let record = TestRunRecord(
            runId: runId,
            startTime: ISO8601DateFormatter().string(from: startTime),
            endTime: ISO8601DateFormatter().string(from: Date()),
            results: results
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)

        let filename = "observations-\(runId.replacingOccurrences(of: ":", with: "-")).json"
        let fileURL = outputDir.appendingPathComponent(filename)

        try data.write(to: fileURL)

        return fileURL
    }

    /// 結果をリセットする（テスト間で使用）
    func reset() {
        results.removeAll()
    }

    // MARK: - Output Directory

    /// 出力ディレクトリを取得する
    /// プロジェクトルート/.test-output/
    static func outputDirectory() throws -> URL {
        // テスト実行時のBundle.mainはテストバンドル
        // __FILE__からプロジェクトルートを推定
        let thisFile = URL(fileURLWithPath: #file)

        // EpikaTests/TestObservations/ObservationRecorder.swift
        // → プロジェクトルートは3階層上
        let projectRoot = thisFile
            .deletingLastPathComponent()  // TestObservations/
            .deletingLastPathComponent()  // EpikaTests/
            .deletingLastPathComponent()  // Epika/

        return projectRoot.appendingPathComponent(".test-output")
    }

    // MARK: - Summary

    /// 結果のサマリーを取得
    var summary: String {
        let total = results.count
        let passed = results.filter(\.passed).count
        let failed = total - passed

        var lines = [
            "=== Test Observation Summary ===",
            "Run ID: \(runId)",
            "Total: \(total), Passed: \(passed), Failed: \(failed)",
            ""
        ]

        if failed > 0 {
            lines.append("Failed observations:")
            for result in results where !result.passed {
                lines.append("  - \(result.id): measured=\(result.measured), expected=\(result.expected.min ?? 0)...\(result.expected.max ?? .infinity)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
