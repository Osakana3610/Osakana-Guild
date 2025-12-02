import SwiftUI

/// キャラクターの戦闘ステータスを表示するセクション
/// CharacterSectionType: combatStats
@MainActor
struct CharacterCombatStatsSection: View {
    let character: RuntimeCharacter

    var body: some View {
        GroupBox("戦闘ステータス") {
            let stats = character.combatStats
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
