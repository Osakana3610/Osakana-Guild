// ==============================================================================
// CharacterRaceSkillsSection.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクターの種族レベル習得スキル一覧を表示
//
// 【View構成】
//   - スキルリスト: レベルとスキル名を表示（Lv.X: スキル名）
//   - 未解放スキルはグレー表示
//   - スキルなしの場合: 「スキルなし」テキスト
//
// 【使用箇所】
//   - キャラクター詳細画面
//
// ==============================================================================

import SwiftUI

/// キャラクターの種族レベル習得スキル一覧を表示するセクション
@MainActor
struct CharacterRaceSkillsSection: View {
    let skillUnlocks: [(level: Int, skill: SkillDefinition)]
    let characterLevel: Int

    var body: some View {
        Group {
            if skillUnlocks.isEmpty {
                Text("スキルなし")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(skillUnlocks, id: \.skill.id) { unlock in
                        let isUnlocked = characterLevel >= unlock.level
                        Text("Lv.\(unlock.level): \(unlock.skill.name)")
                            .foregroundColor(isUnlocked ? .primary : .secondary)
                    }
                }
            }
        }
    }
}
