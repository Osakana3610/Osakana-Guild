// ==============================================================================
// SQLiteMasterDataQueries.Jobs.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 職業定義、戦闘係数、スキル習得条件、メタデータの取得クエリを提供
//
// 【公開API】
//   - fetchAllJobs() -> [JobDefinition]
//   - fetchAllJobSkillUnlocks() -> [jobId: [(level, skillId)]]
//   - fetchAllJobMetadata() -> [jobId: (category, growthTendency)]
//
// 【使用箇所】
//   - MasterDataLoader.load(manager:)
//
// ==============================================================================

import Foundation
import SQLite3

// MARK: - Jobs
extension SQLiteMasterDataManager {
    func fetchAllJobs() throws -> [JobDefinition] {
        struct CoefficientBuilder {
            var maxHP: Double = 0.0
            var physicalAttackScore: Double = 0.0
            var magicalAttackScore: Double = 0.0
            var physicalDefenseScore: Double = 0.0
            var magicalDefenseScore: Double = 0.0
            var hitScore: Double = 0.0
            var evasionScore: Double = 0.0
            var criticalChancePercent: Double = 0.0
            var attackCount: Double = 0.0
            var magicalHealingScore: Double = 0.0
            var trapRemovalScore: Double = 0.0
            var additionalDamageScore: Double = 0.0
            var breathDamageScore: Double = 0.0

            mutating func set(stat: CombatStat, value: Double) {
                switch stat {
                case .maxHP: maxHP = value
                case .physicalAttackScore: physicalAttackScore = value
                case .magicalAttackScore: magicalAttackScore = value
                case .physicalDefenseScore: physicalDefenseScore = value
                case .magicalDefenseScore: magicalDefenseScore = value
                case .hitScore: hitScore = value
                case .evasionScore: evasionScore = value
                case .criticalChancePercent: criticalChancePercent = value
                case .attackCount: attackCount = value
                case .magicalHealingScore: magicalHealingScore = value
                case .trapRemovalScore: trapRemovalScore = value
                case .additionalDamageScore: additionalDamageScore = value
                case .breathDamageScore: breathDamageScore = value
                }
            }

            func build() -> JobDefinition.CombatCoefficients {
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
        }

        struct Builder {
            var id: UInt8
            var name: String
            var coefficients = CoefficientBuilder()
            var learnedSkillIds: [UInt16] = []
        }

        var builders: [UInt8: Builder] = [:]
        var order: [UInt8] = []
        let baseSQL = "SELECT id, name FROM jobs ORDER BY id;"
        let baseStatement = try prepare(baseSQL)
        defer { sqlite3_finalize(baseStatement) }
        while sqlite3_step(baseStatement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(baseStatement, 1) else { continue }
            let id = UInt8(sqlite3_column_int(baseStatement, 0))
            builders[id] = Builder(
                id: id,
                name: String(cString: nameC)
            )
            order.append(id)
        }

        let coefficientSQL = "SELECT job_id, stat, value FROM job_combat_coefficients;"
        let coefficientStatement = try prepare(coefficientSQL)
        defer { sqlite3_finalize(coefficientStatement) }
        while sqlite3_step(coefficientStatement) == SQLITE_ROW {
            let jobId = UInt8(sqlite3_column_int(coefficientStatement, 0))
            guard var builder = builders[jobId] else { continue }
            let statRaw = UInt8(sqlite3_column_int(coefficientStatement, 1))
            guard let stat = CombatStat(rawValue: statRaw) else { continue }
            builder.coefficients.set(stat: stat, value: sqlite3_column_double(coefficientStatement, 2))
            builders[builder.id] = builder
        }

        let skillSQL = "SELECT job_id, skill_id FROM job_skills ORDER BY job_id, order_index;"
        let skillStatement = try prepare(skillSQL)
        defer { sqlite3_finalize(skillStatement) }
        while sqlite3_step(skillStatement) == SQLITE_ROW {
            let jobId = UInt8(sqlite3_column_int(skillStatement, 0))
            guard var builder = builders[jobId] else { continue }
            let skillId = UInt16(sqlite3_column_int(skillStatement, 1))
            builder.learnedSkillIds.append(skillId)
            builders[builder.id] = builder
        }

        return order.compactMap { builders[$0] }.map { builder in
            JobDefinition(
                id: builder.id,
                name: builder.name,
                combatCoefficients: builder.coefficients.build(),
                learnedSkillIds: builder.learnedSkillIds
            )
        }
    }

    /// 職業のスキル習得レベル情報を取得
    /// - Returns: [jobId: [(level, skillId)]]
    func fetchAllJobSkillUnlocks() throws -> [UInt8: [(level: Int, skillId: UInt16)]] {
        var result: [UInt8: [(level: Int, skillId: UInt16)]] = [:]
        let sql = "SELECT job_id, level_requirement, skill_id FROM job_skill_unlocks ORDER BY job_id, level_requirement;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            let jobId = UInt8(sqlite3_column_int(statement, 0))
            let level = Int(sqlite3_column_int(statement, 1))
            let skillId = UInt16(sqlite3_column_int(statement, 2))
            result[jobId, default: []].append((level: level, skillId: skillId))
        }
        return result
    }

    /// 職業の追加情報（カテゴリ、成長傾向）を取得
    /// - Returns: [jobId: (category, growthTendency)]
    func fetchAllJobMetadata() throws -> [UInt8: (category: UInt8, growthTendency: UInt8?)] {
        var result: [UInt8: (category: UInt8, growthTendency: UInt8?)] = [:]
        let sql = "SELECT id, category, growth_tendency FROM jobs;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            let jobId = UInt8(sqlite3_column_int(statement, 0))
            let category = UInt8(sqlite3_column_int(statement, 1))
            let growthTendency: UInt8? = sqlite3_column_type(statement, 2) == SQLITE_NULL
                ? nil
                : UInt8(sqlite3_column_int(statement, 2))
            result[jobId] = (category: category, growthTendency: growthTendency)
        }
        return result
    }
}
