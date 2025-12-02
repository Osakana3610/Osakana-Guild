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

    @ViewBuilder
    private func deltaRow(_ delta: (label: String, value: Int)) -> some View {
        let isPositive = delta.value > 0
        let sign = isPositive ? "+" : ""
        let text = "[\(sign)\(delta.value)] \(delta.label)"

        Text(text)
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
        case "strength": return "力"
        case "wisdom": return "知恵"
        case "spirit": return "精神"
        case "vitality": return "体力"
        case "agility": return "敏捷"
        case "luck": return "運"
        case "hp", "maxhp": return "最大HP"
        case "physicalattack": return "物理攻撃"
        case "magicalattack": return "魔法攻撃"
        case "physicaldefense": return "物理防御"
        case "magicaldefense": return "魔法防御"
        case "hitrate": return "命中"
        case "evasionrate": return "回避"
        case "criticalrate": return "クリティカル"
        case "attackcount": return "攻撃回数"
        case "magicalhealing": return "魔法治療"
        case "trapremoval": return "罠解除"
        case "additionaldamage": return "追加ダメージ"
        case "breathdamage": return "ブレスダメージ"
        default: return stat
        }
    }
}
