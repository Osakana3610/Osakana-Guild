import SwiftUI

/// 3層構造のHPバー
/// - 背景（グレー）: 最大HP
/// - 変動部分（赤/緑）: ダメージまたは回復量
/// - 現在HP（グレー）: 現在のHP
struct HPBarView: View {
    let currentHP: Int
    let previousHP: Int
    let maxHP: Int
    var showNumbers: Bool = true

    /// Dynamic Type対応: caption2フォントのサイズに連動
    @ScaledMetric(relativeTo: .caption2) private var barHeight: CGFloat = 14

    private var currentRatio: CGFloat {
        guard maxHP > 0 else { return 0 }
        return CGFloat(max(0, min(currentHP, maxHP))) / CGFloat(maxHP)
    }

    private var previousRatio: CGFloat {
        guard maxHP > 0 else { return 0 }
        return CGFloat(max(0, min(previousHP, maxHP))) / CGFloat(maxHP)
    }

    /// ダメージ: currentHP < previousHP
    /// 回復: currentHP > previousHP
    private var isDamage: Bool { currentHP < previousHP }
    private var isHeal: Bool { currentHP > previousHP }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .leading) {
                // 背景（グレー）- 最大HP
                RoundedRectangle(cornerRadius: barHeight / 2)
                    .fill(Color(.systemGray4))
                    .frame(height: barHeight)

                if isDamage {
                    // ダメージ時: 赤（前のHP位置まで） + グレー（現在HP）
                    // 赤部分（減少分）
                    RoundedRectangle(cornerRadius: barHeight / 2)
                        .fill(Color(.systemRed).opacity(0.7))
                        .frame(width: max(0, width * previousRatio), height: barHeight)

                    // グレー部分（現在HP）- 不透明
                    RoundedRectangle(cornerRadius: barHeight / 2)
                        .fill(Color(.systemGray2))
                        .frame(width: max(0, width * currentRatio), height: barHeight)
                } else if isHeal {
                    // 回復時: 緑（現在HP位置まで） + グレー（前のHP）
                    // 緑部分（回復後の位置まで）
                    RoundedRectangle(cornerRadius: barHeight / 2)
                        .fill(Color(.systemGreen).opacity(0.7))
                        .frame(width: max(0, width * currentRatio), height: barHeight)

                    // グレー部分（元のHP）- 不透明
                    RoundedRectangle(cornerRadius: barHeight / 2)
                        .fill(Color(.systemGray2))
                        .frame(width: max(0, width * previousRatio), height: barHeight)
                } else {
                    // 変動なし: グレーのみ
                    RoundedRectangle(cornerRadius: barHeight / 2)
                        .fill(Color(.systemGray2))
                        .frame(width: max(0, width * currentRatio), height: barHeight)
                }

                // 数値表示（バーの上に重ねる）
                if showNumbers {
                    Text("\(currentHP)/\(maxHP)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.primary)
                        .shadow(color: Color(.systemBackground), radius: 1, x: 0, y: 0.5)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .frame(height: barHeight)
    }
}

// MARK: - Convenience Initializers

extension HPBarView {
    /// 変動なしの場合（previousHP = currentHP）
    init(currentHP: Int, maxHP: Int, showNumbers: Bool = true) {
        self.currentHP = currentHP
        self.previousHP = currentHP
        self.maxHP = maxHP
        self.showNumbers = showNumbers
    }
}

#Preview("Damage") {
    VStack(spacing: 16) {
        HPBarView(currentHP: 50, previousHP: 80, maxHP: 100)
        HPBarView(currentHP: 20, previousHP: 80, maxHP: 100)
        HPBarView(currentHP: 0, previousHP: 30, maxHP: 100)
    }
    .padding()
}

#Preview("Heal") {
    VStack(spacing: 16) {
        HPBarView(currentHP: 80, previousHP: 50, maxHP: 100)
        HPBarView(currentHP: 100, previousHP: 20, maxHP: 100)
    }
    .padding()
}

#Preview("No Change") {
    VStack(spacing: 16) {
        HPBarView(currentHP: 75, maxHP: 100)
        HPBarView(currentHP: 100, maxHP: 100)
        HPBarView(currentHP: 0, maxHP: 100)
    }
    .padding()
}
