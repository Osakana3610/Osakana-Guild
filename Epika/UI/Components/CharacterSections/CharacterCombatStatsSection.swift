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
//              命中、回避、必殺率、攻撃回数、魔法回復力、
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
    let character: CachedCharacter

    var body: some View {
        let stats = character.combat
        let isMartial = character.isMartialEligible
        let physicalLabel = isMartial ? L10n.CombatStat.physicalAttackMartial : CombatStat.physicalAttackScore.displayName
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            CombatStatRow(label: CombatStat.maxHP.displayName, value: stats.maxHP)
            CombatStatRow(label: physicalLabel, value: stats.physicalAttackScore)
            CombatStatRow(label: CombatStat.magicalAttackScore.displayName, value: stats.magicalAttackScore)
            CombatStatRow(label: CombatStat.physicalDefenseScore.displayName, value: stats.physicalDefenseScore)
            CombatStatRow(label: CombatStat.magicalDefenseScore.displayName, value: stats.magicalDefenseScore)
            CombatStatRow(label: CombatStat.hitScore.displayName, value: stats.hitScore)
            CombatStatRow(label: CombatStat.evasionScore.displayName, value: stats.evasionScore)
            CombatStatRow(label: CombatStat.criticalChancePercent.displayName, valueText: "\(stats.criticalChancePercent)%")
            CombatStatRowDouble(label: CombatStat.attackCount.displayName, value: stats.attackCount)
            CombatStatRow(label: CombatStat.magicalHealingScore.displayName, value: stats.magicalHealingScore)
            CombatStatRow(label: CombatStat.trapRemovalScore.displayName, value: stats.trapRemovalScore)
            CombatStatRow(label: CombatStat.additionalDamageScore.displayName, value: stats.additionalDamageScore)
            CombatStatRow(label: CombatStat.breathDamageScore.displayName, value: stats.breathDamageScore)
        }
    }
}

struct CombatStatRow: View {
    let label: String
    let valueText: String

    init(label: String, value: Int) {
        self.label = label
        self.valueText = value.formattedWithComma()
    }

    init(label: String, valueText: String) {
        self.label = label
        self.valueText = valueText
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
            Spacer()
            Text(valueText)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }
}

struct CombatStatRowDouble: View {
    let label: String
    let value: Double

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
            Spacer()
            Text(value.formattedWithComma(maximumFractionDigits: 1))
                .font(.body)
                .foregroundStyle(.primary)
        }
    }
}
