import Foundation
import SQLite3

private struct JobMasterFile: Decodable, Sendable {
    struct Job: Decodable, Sendable {
        let id: String
        let name: String
        let category: String
        let growthTendency: String?
        let combatCoefficients: [String: Double]
        let skills: [String]?
    }

    let jobs: [Job]
}

extension SQLiteMasterDataManager {
    func importJobMaster(_ data: Data) async throws -> Int {
        let file = try await MainActor.run { () throws -> JobMasterFile in
            let decoder = JSONDecoder()
            return try decoder.decode(JobMasterFile.self, from: data)
        }

        try withTransaction {
            try execute("DELETE FROM jobs;")

            let insertJobSQL = """
                INSERT INTO jobs (id, name, category, growth_tendency)
                VALUES (?, ?, ?, ?);
            """
            let insertCoefficientSQL = "INSERT INTO job_combat_coefficients (job_id, stat, value) VALUES (?, ?, ?);"
            let insertSkillSQL = "INSERT INTO job_skills (job_id, order_index, skill_id) VALUES (?, ?, ?);"

            let jobStatement = try prepare(insertJobSQL)
            let coefficientStatement = try prepare(insertCoefficientSQL)
            let skillStatement = try prepare(insertSkillSQL)
            defer {
                sqlite3_finalize(jobStatement)
                sqlite3_finalize(coefficientStatement)
                sqlite3_finalize(skillStatement)
            }

            for job in file.jobs {
                bindText(jobStatement, index: 1, value: job.id)
                bindText(jobStatement, index: 2, value: job.name)
                bindText(jobStatement, index: 3, value: job.category)
                bindText(jobStatement, index: 4, value: job.growthTendency)
                try step(jobStatement)
                reset(jobStatement)

                for (stat, value) in job.combatCoefficients {
                    bindText(coefficientStatement, index: 1, value: job.id)
                    bindText(coefficientStatement, index: 2, value: stat)
                    bindDouble(coefficientStatement, index: 3, value: value)
                    try step(coefficientStatement)
                    reset(coefficientStatement)
                }

                if let skills = job.skills {
                    for (index, skill) in skills.enumerated() {
                        bindText(skillStatement, index: 1, value: job.id)
                        bindInt(skillStatement, index: 2, value: index)
                        bindText(skillStatement, index: 3, value: skill)
                        try step(skillStatement)
                        reset(skillStatement)
                    }
                }
            }
        }

        return file.jobs.count
    }
}
