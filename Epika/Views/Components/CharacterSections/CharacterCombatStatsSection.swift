// ==============================================================================
// CharacterCombatStatsSection.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクターの戦闘ステータス（HP、攻撃力、防御力等）を表示
//   - 格闘適性の有無に応じて表示を調整
//
// 【View構成】
//   - 2カラムのグリッド（CombatStatRow × 13）
//   - 表示項目: 最大HP、物理攻撃、魔法攻撃、物理防御、魔法防御、
//              命中、回避、クリティカル、攻撃回数、魔法治療、
//              罠解除、追加ダメージ、ブレスダメージ
//   - 格闘適性がある場合は「物理攻撃(格闘)」と表示
//
// 【使用箇所】
//   - キャラクター詳細画面（CharacterSectionType.combatStats）
//
// ==============================================================================

import SwiftUI

/// キャラクターの戦闘ステータスを表示するセクション
/// CharacterSectionType: combatStats
@MainActor
struct CharacterCombatStatsSection: View {
    let character: RuntimeCharacter

    var body: some View {
        let stats = character.combat
        let isMartial = character.isMartialEligible
        let physicalLabel = isMartial ? "物理攻撃(格闘)" : "物理攻撃"
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            CombatStatRow(label: "最大HP", value: stats.maxHP)
            CombatStatRow(label: physicalLabel, value: stats.physicalAttack)
            CombatStatRow(label: "魔法攻撃", value: stats.magicalAttack)
            CombatStatRow(label: "物理防御", value: stats.physicalDefense)
            CombatStatRow(label: "魔法防御", value: stats.magicalDefense)
            CombatStatRow(label: "命中", value: stats.hitRate)
            CombatStatRow(label: "回避", value: stats.evasionRate)
            CombatStatRow(label: "クリティカル", value: stats.criticalRate)
            CombatStatRow(label: "攻撃回数", value: stats.attackCount)
            CombatStatRow(label: "魔法治療", value: stats.magicalHealing)
            CombatStatRow(label: "罠解除", value: stats.trapRemoval)
            CombatStatRow(label: "追加ダメージ", value: stats.additionalDamage)
            CombatStatRow(label: "ブレスダメージ", value: stats.breathDamage)
        }
    }
}

struct CombatStatRow: View {
    let label: String
    let value: Int

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text("\(value)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
