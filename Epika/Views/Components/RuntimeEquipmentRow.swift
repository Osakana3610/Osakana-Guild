import SwiftUI

struct RuntimeEquipmentRow: View {
    let equipment: RuntimeEquipment
    let showPrice: Bool
    let price: Int?
    let currencyType: RuntimeEquipment.CurrencyType
    let isAffordable: Bool
    let isSelected: Bool
    let onTap: (() -> Void)?

    init(
        equipment: RuntimeEquipment,
        showPrice: Bool = false,
        price: Int? = nil,
        currencyType: RuntimeEquipment.CurrencyType = .gold,
        isAffordable: Bool = true,
        isSelected: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.equipment = equipment
        self.showPrice = showPrice
        self.price = price
        self.currencyType = currencyType
        self.isAffordable = isAffordable
        self.isSelected = isSelected
        self.onTap = onTap
    }

    var body: some View {
        HStack(spacing: 12) {
            // 選択状態のチェックマーク
            if onTap != nil {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(.primary)
                    .font(.title2)
            }

            // 装備アイコン
            EquipmentIcon(equipment: equipment)

            // 装備情報
            VStack(alignment: .leading, spacing: 4) {
                Text(equipment.displayName)
                    .font(.body)
                    .lineLimit(1)

                EquipmentStatsView(equipment: equipment)

                // 装備中表示は画面側文脈で判定するため、この行では表示しない
            }

            Spacer()

            // 価格表示
            if showPrice, let price = price {
                PriceView(
                    price: price,
                    currencyType: currencyType,
                    isAffordable: isAffordable
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        )
    }
}

struct EquipmentIcon: View {
    let equipment: RuntimeEquipment

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: equipment.category.iconName)
                    .foregroundColor(.secondary)
                    .font(.title3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
            )
    }
}

struct EquipmentStatsView: View {
    let equipment: RuntimeEquipment

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                if equipment.baseValue > 0 {
                    StatChip(label: "基本価値", value: equipment.baseValue, color: .green)
                }
            }

            // 戦闘ステ加算のプレビュー（新ロジック準拠）
            TaskView(equipment: equipment)
        }
    }
}

private struct TaskView: View {
    let equipment: RuntimeEquipment
    @State private var deltas: [(String, Int)] = []

    var body: some View {
        if !deltas.isEmpty {
            HStack(spacing: 6) {
                ForEach(deltas, id: \.0) { d in
                    let color: Color = d.1 >= 0 ? .blue : .red
                    StatChip(label: d.0, value: d.1, color: color)
                }
            }
            .task {
                let vals = await UniversalItemDisplayService.shared.getCombatDeltaDisplay(for: equipment)
                await MainActor.run { self.deltas = vals }
            }
        } else {
            // 初回ロード
            HStack {}.task {
                let vals = await UniversalItemDisplayService.shared.getCombatDeltaDisplay(for: equipment)
                await MainActor.run { self.deltas = vals }
            }
        }
    }
}

struct StatChip: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.primary)
            Text("\(value)")
                .font(.caption2)
                .bold()
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(color.opacity(0.1))
        .cornerRadius(3)
    }
}

// MARK: - Extensions for Preview（削除）

 
