// ==============================================================================
// CharacterSkillsSection.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクターの習得スキル一覧を表示
//   - 装備から付与されたスキルのリスト表示
//
// 【View構成】
//   - スキルリスト: 各スキル名を箇条書き（• スキル名）、ID順でソート
//   - スキルなしの場合: 「スキルなし」テキスト
//
// 【使用箇所】
//   - キャラクター詳細画面（CharacterSectionType.ownedSkills）
//
// ==============================================================================

import SwiftUI

/// キャラクターの習得スキル一覧を表示するセクション
/// CharacterSectionType: ownedSkills
@MainActor
struct CharacterSkillsSection: View {
    let character: CachedCharacter
    @State private var selectedSkill: SkillDefinition?

    var body: some View {
        let skills = character.learnedSkills.sorted { $0.id < $1.id }
        Group {
            if skills.isEmpty {
                Text("スキルなし")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(skills, id: \.id) { skill in
                        Text("• \(skill.name)")
                            .onTapGesture {
                                selectedSkill = skill
                            }
                    }
                }
            }
        }
        .alert(item: $selectedSkill) { skill in
            Alert(
                title: Text(skill.name),
                message: Text(skill.description),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
