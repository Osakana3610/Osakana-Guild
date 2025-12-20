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
//   - スキルリスト: 各スキル名を箇条書き（• スキル名）
//   - スキルなしの場合: 「スキルなし」テキスト
//   - learnedSkillsは装備由来のスキルのみ含む（新構造）
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
    let character: RuntimeCharacter

    var body: some View {
        let skills = character.learnedSkills
        Group {
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
