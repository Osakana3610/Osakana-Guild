import SwiftUI

/// キャラクターのレベル・経験値情報を表示するセクション
/// CharacterSectionType: levelExp
@MainActor
struct CharacterLevelSection: View {
    let character: RuntimeCharacter

    var body: some View {
        GroupBox("レベル / 経験値") {
            VStack(alignment: .leading, spacing: 8) {
                switch experienceSummary {
                case .success(let data):
                    Text(summaryLine(from: data))
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .monospacedDigit()
                case .failure(let message):
                    Text("経験値情報を取得できません: \(message)")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

private extension CharacterLevelSection {
    enum ExperienceSummary {
        case success(ExperienceData)
        case failure(String)
    }

    struct ExperienceData {
        let level: Int
        let cap: Int
        let totalExperience: Int
        let currentProgress: Int
        let nextLevelRequirement: Int?
        let remainingToNext: Int?
        let multiplier: Double
    }

    var experienceSummary: ExperienceSummary {
        do {
            return .success(try makeExperienceData())
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func makeExperienceData() throws -> ExperienceData {
        let level = max(1, character.level)
        let cap = character.raceData?.maxLevel ?? 200
        let total = character.experience
        let progress = try CharacterExperienceTable.experienceIntoCurrentLevel(accumulatedExperience: total,
                                                                               level: level)
        let multiplier = try experienceMultiplier()
        if level >= cap {
            return ExperienceData(level: level,
                                  cap: cap,
                                  totalExperience: total,
                                  currentProgress: progress,
                                  nextLevelRequirement: nil,
                                  remainingToNext: nil,
                                  multiplier: multiplier)
        }
        let delta = try CharacterExperienceTable.experienceToNextLevel(from: level)
        let remaining = max(0, delta - progress)
        return ExperienceData(level: level,
                              cap: cap,
                              totalExperience: total,
                              currentProgress: progress,
                              nextLevelRequirement: delta,
                              remainingToNext: remaining,
                              multiplier: multiplier)
    }

    func summaryLine(from data: ExperienceData) -> String {
        let remainingText = data.remainingToNext.map(formatNumber) ?? "0"
        return "Lv\(data.level) Exp \(formatNumber(data.totalExperience)) (×\(formatMultiplier(data.multiplier))) 次のLvまで\(remainingText)"
    }

    func experienceMultiplier() throws -> Double {
        let equippedSkillIds = Set(character.progress.learnedSkills.filter { $0.isEquipped }.map { $0.skillId })
        guard !equippedSkillIds.isEmpty else { return 1.0 }
        let equippedDefinitions = character.masteredSkills.filter { equippedSkillIds.contains($0.id) }
        guard !equippedDefinitions.isEmpty else { return 1.0 }
        let components = try SkillRuntimeEffectCompiler.rewardComponents(from: equippedDefinitions)
        return components.experienceScale()
    }

    func formatNumber(_ value: Int) -> String {
        if let formatted = Self.numberFormatter.string(from: NSNumber(value: value)) {
            return formatted
        }
        return "\(value)"
    }

    func formatMultiplier(_ value: Double) -> String {
        let clamped = max(0.0, value)
        return String(format: "%.2f", clamped)
    }

    static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()
}
