// ==============================================================================
// EquipmentStatDeltaView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 装備変更時のステータス差分を視覚的に表示
//   - 正の変化は緑、負の変化は赤で色分け表示
//
// 【View構成】
//   - GlassEffectModifierを使用した装飾
//   - 差分の配列を受け取り、各項目を1行ずつ表示
//   - 攻撃回数は10倍スケールを0.1倍して表示（小数点1桁）
//   - StatLabelResolverで内部キーを日本語ラベルに変換
//
// 【使用箇所】
//   - 装備変更画面
//   - 装備プレビュー表示
//
// ==============================================================================

import SwiftUI

/// 装備変更時のステータス差分を表示するビュー
/// ItemDropNotificationView風のデザイン（GlassEffectModifier使用）
@MainActor
struct EquipmentStatDeltaView: View {
    let deltas: [(label: String, value: Int)]

    var body: some View {
        if !deltas.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(deltas, id: \.label) { delta in
                    deltaRow(delta)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: deltas.map { $0.label })
        }
    }

    private func deltaRow(_ delta: (label: String, value: Int)) -> some View {
        let isPositive = delta.value > 0
        let sign = isPositive ? "+" : ""
        // 攻撃回数は10倍スケールで保存されているため、0.1倍して表示
        let rawValueText: String = if delta.label == L10n.CombatStat.attackCount {
            String(format: "%.1f", Double(delta.value) * 0.1)
        } else {
            "\(delta.value)"
        }
        let suffix = delta.label == L10n.CombatStat.criticalChancePercent ? "%" : ""
        let text = "[\(sign)\(rawValueText)\(suffix)] \(delta.label)"

        return Text(text)
            .font(.subheadline)
            .fontWeight(.regular)
            .foregroundColor(isPositive ? .green : .red)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .modifier(GlassEffectModifier(isSuperRare: false))
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// ステータスキーから表示用ラベルへの変換
struct StatLabelResolver {
    static func label(for stat: String) -> String {
        switch stat.lowercased() {
        case "strength": return BaseStat.strength.displayName
        case "wisdom": return BaseStat.wisdom.displayName
        case "spirit": return BaseStat.spirit.displayName
        case "vitality": return BaseStat.vitality.displayName
        case "agility": return BaseStat.agility.displayName
        case "luck": return BaseStat.luck.displayName
        case "hp", "maxhp": return CombatStat.maxHP.displayName
        case "physicalattack": return CombatStat.physicalAttackScore.displayName
        case "magicalattack": return CombatStat.magicalAttackScore.displayName
        case "physicaldefense": return CombatStat.physicalDefenseScore.displayName
        case "magicaldefense": return CombatStat.magicalDefenseScore.displayName
        case "hitrate": return CombatStat.hitScore.displayName
        case "evasionrate": return CombatStat.evasionScore.displayName
        case "criticalrate": return CombatStat.criticalChancePercent.displayName
        case "attackcount": return CombatStat.attackCount.displayName
        case "magicalhealing": return CombatStat.magicalHealingScore.displayName
        case "trapremoval": return CombatStat.trapRemovalScore.displayName
        case "additionaldamage": return CombatStat.additionalDamageScore.displayName
        case "breathdamage": return CombatStat.breathDamageScore.displayName
        default: return stat
        }
    }
}
