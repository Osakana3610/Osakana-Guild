// ==============================================================================
// BattleStatsView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 全キャラクターの戦闘能力を一覧表示
//   - HP・物攻・魔攻・物防・魔防の確認
//
// 【View構成】
//   - キャラクター名と戦闘ステータスをリスト表示
//   - 空状態の表示
//
// 【使用箇所】
//   - GuildView（戦闘能力一覧）
//
// ==============================================================================

import SwiftUI

struct BattleStatsView: View {
    let characters: [CachedCharacter]

    var body: some View {
        List {
            if characters.isEmpty {
                Text("キャラクターがいません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(characters, id: \.id) { character in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(character.name)
                            .font(.headline)
                        HStack(spacing: 12) {
                            statItem(label: "HP", value: character.combat.maxHP)
                            statItem(label: "物攻", value: character.combat.physicalAttack)
                            statItem(label: "魔攻", value: character.combat.magicalAttack)
                            statItem(label: "物防", value: character.combat.physicalDefense)
                            statItem(label: "魔防", value: character.combat.magicalDefense)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .avoidBottomGameInfo()
        .navigationTitle("戦闘能力一覧")
    }

    private func statItem(label: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Text(value.formattedWithComma())
        }
    }
}
