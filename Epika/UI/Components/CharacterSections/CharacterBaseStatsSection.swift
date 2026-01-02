// ==============================================================================
// CharacterBaseStatsSection.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクターの基本能力値（力・知恵・精神・体力・敏捷・運）を表示
//   - 装備ボーナスと視覚的なプログレスバーで能力値を表現
//
// 【View構成】
//   - 1カラムのグリッド（BaseStatRow × 6）
//   - 各行: ラベル + 数値 + 装備ボーナス + プログレスバー
//   - SimpleStatProgressBar: 能力値をカプセル型バーで視覚化
//   - Dynamic Type対応（barSizeとspacingが動的に変化）
//
// 【使用箇所】
//   - キャラクター詳細画面（CharacterSectionType.baseStats）
//
// ==============================================================================

import SwiftUI

/// キャラクターの基本能力値を表示するセクション
/// CharacterSectionType: baseStats
@MainActor
struct CharacterBaseStatsSection: View {
    let character: CachedCharacter

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
            BaseStatRow(label: "力", value: character.attributes.strength)
            BaseStatRow(label: "知恵", value: character.attributes.wisdom)
            BaseStatRow(label: "精神", value: character.attributes.spirit)
            BaseStatRow(label: "体力", value: character.attributes.vitality)
            BaseStatRow(label: "敏捷", value: character.attributes.agility)
            BaseStatRow(label: "運", value: character.attributes.luck)
        }
    }
}

struct BaseStatRow: View {
    let label: String
    let value: Int
    let equipmentBonus: Int
    let maxValue: Int

    init(label: String, value: Int, equipmentBonus: Int = 0, maxValue: Int = 99) {
        self.label = label
        self.value = value
        self.equipmentBonus = equipmentBonus
        self.maxValue = maxValue
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label.count == 1 ? "\(label)　" : label)
                .font(.subheadline)
                .foregroundStyle(.primary)

            HStack(alignment: .center, spacing: 4) {
                Text(paddedTwoDigit(value))
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("(\(paddedSignedTwoDigit(equipmentBonus)))")
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 0) {
                SimpleStatProgressBar(currentValue: value, maxValue: maxValue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func paddedTwoDigit(_ value: Int) -> String {
        let raw = String(format: "%2d", value)
        return raw.replacingOccurrences(of: " ", with: "\u{2007}")
    }

    private func paddedSignedTwoDigit(_ value: Int) -> String {
        let raw = String(format: "%+2d", value)
        return raw.replacingOccurrences(of: " ", with: "\u{2007}")
    }
}

struct SimpleStatProgressBar: View {
    let currentValue: Int
    let maxValue: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let clamped = max(1, min(currentValue, maxValue))
        let barCount = min(clamped, maxBarCount)
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { _ in
                Capsule()
                    .fill(Color.primary.opacity(0.8))
                    .frame(width: barSize.width, height: barSize.height)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var barSize: CGSize {
        switch dynamicTypeSize {
        case .xSmall, .small:
            return CGSize(width: 2, height: 10)
        case .medium:
            return CGSize(width: 2, height: 12)
        case .large:
            return CGSize(width: 3, height: 14)
        case .xLarge:
            return CGSize(width: 3, height: 16)
        case .xxLarge:
            return CGSize(width: 3, height: 18)
        case .xxxLarge:
            return CGSize(width: 4, height: 20)
        default: // accessibility sizes
            return CGSize(width: 5, height: 24)
        }
    }

    private var barSpacing: CGFloat {
        isAccessibilityCategory ? 3 : 2
    }

    private var maxBarCount: Int {
        isAccessibilityCategory ? 20 : 40
    }

    private var isAccessibilityCategory: Bool {
        switch dynamicTypeSize {
        case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
            return true
        default:
            return false
        }
    }
}
