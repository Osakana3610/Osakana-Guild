// ==============================================================================
// CharacterEquippedItemsSection.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクターの装備中アイテム一覧を表示
//   - 装備解除および詳細表示機能を提供
//
// 【View構成】
//   - 装備アイテムのリスト表示（アイテム名 + 数量）
//   - 装備なしの場合は「装備なし」テキスト
//   - 各行に装備解除ボタンと詳細ボタン（オプション）
//   - 装備数サマリー（summaryText）を親画面のヘッダーで使用可能
//
// 【使用箇所】
//   - キャラクター詳細画面（CharacterSectionType.equippedItems）
//
// ==============================================================================

import SwiftUI

/// キャラクターの装備中アイテム一覧を表示するセクション
/// CharacterSectionType: equippedItems
@MainActor
struct CharacterEquippedItemsSection: View {
    let equippedItems: [EquipmentDisplayItem]
    let equipmentCapacity: Int
    let onUnequip: ((EquipmentDisplayItem, @escaping (Result<Void, Error>) -> Void) -> Void)?
    let onDetail: ((EquipmentDisplayItem) -> Void)?

    @State private var unequipError: String?
    @State private var isUnequipping = false

    init(
        equippedItems: [EquipmentDisplayItem],
        equipmentCapacity: Int,
        onUnequip: ((EquipmentDisplayItem, @escaping (Result<Void, Error>) -> Void) -> Void)? = nil,
        onDetail: ((EquipmentDisplayItem) -> Void)? = nil
    ) {
        self.equippedItems = equippedItems
        self.equipmentCapacity = equipmentCapacity
        self.onUnequip = onUnequip
        self.onDetail = onDetail
    }

    var body: some View {
        Group {
            if equippedItems.isEmpty {
                Text("装備なし")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(equippedItems, id: \.id) { item in
                    equippedItemRow(item)
                }

                if let error = unequipError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    /// 装備数サマリー（親側でヘッダーに使用）
    var summaryText: String {
        "\(totalCount)/\(equipmentCapacity)"
    }

    private var totalCount: Int {
        equippedItems.reduce(0) { $0 + $1.quantity }
    }

    @ViewBuilder
    private func equippedItemRow(_ item: EquipmentDisplayItem) -> some View {
        let hasSuperRare = item.superRareTitleId > 0

        HStack {
            Button {
                unequipItem(item)
            } label: {
                HStack {
                    Text("• \(item.displayName)")
                        .fontWeight(hasSuperRare ? .bold : .regular)
                    if item.quantity > 1 {
                        Text("x\(item.quantity)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onUnequip == nil || isUnequipping)

            if onDetail != nil {
                Button {
                    onDetail?(item)
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func unequipItem(_ item: EquipmentDisplayItem) {
        guard let onUnequip else { return }
        isUnequipping = true
        unequipError = nil

        onUnequip(item) { result in
            Task { @MainActor in
                switch result {
                case .success:
                    isUnequipping = false
                case .failure(let error):
                    unequipError = error.localizedDescription
                    isUnequipping = false
                }
            }
        }
    }
}
