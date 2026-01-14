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
                            statItem(label: L10n.CombatStat.maxHPShort, value: character.combat.maxHP)
                            statItem(label: L10n.CombatStat.physicalAttackShort, value: character.combat.physicalAttackScore)
                            statItem(label: L10n.CombatStat.magicalAttackShort, value: character.combat.magicalAttackScore)
                            statItem(label: L10n.CombatStat.physicalDefenseShort, value: character.combat.physicalDefenseScore)
                            statItem(label: L10n.CombatStat.magicalDefenseShort, value: character.combat.magicalDefenseScore)
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
