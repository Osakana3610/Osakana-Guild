import SwiftUI

/// キャラクターの習得スキル一覧を表示するセクション
/// CharacterSectionType: ownedSkills
@MainActor
struct CharacterSkillsSection: View {
    let character: RuntimeCharacter

    var body: some View {
        GroupBox("習得スキル") {
            let skills = character.learnedSkills
            if skills.isEmpty {
                Text("スキルなし")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(skills, id: \.id) { skill in
                        Text("• \(skill.name)")
                    }
                }
            }
        }
    }
}
