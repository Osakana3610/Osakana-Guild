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
    let displayService: UserDataLoadService
    let itemDefinitions: [UInt16: ItemDefinition]
    let onUnequip: ((EquipmentDisplayItem) async throws -> Void)?
    let onDetail: ((EquipmentDisplayItem) -> Void)?

    @State private var unequipError: String?
    @State private var isUnequipping = false

    init(
        equippedItems: [EquipmentDisplayItem],
        equipmentCapacity: Int,
        displayService: UserDataLoadService,
        itemDefinitions: [UInt16: ItemDefinition],
        onUnequip: ((EquipmentDisplayItem) async throws -> Void)? = nil,
        onDetail: ((EquipmentDisplayItem) -> Void)? = nil
    ) {
        self.equippedItems = equippedItems
        self.equipmentCapacity = equipmentCapacity
        self.displayService = displayService
        self.itemDefinitions = itemDefinitions
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
        let displayName = getDisplayName(for: item)

        HStack {
            Button {
                unequipItem(item)
            } label: {
                HStack {
                    Text("• \(displayName)")
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

    private func getDisplayName(for item: EquipmentDisplayItem) -> String {
        switch item {
        case .inventory(let record):
            return displayService.displayName(for: record.stackKey)
        case .equipped(let equipped, _):
            let itemName = itemDefinitions[equipped.itemId]?.name
            return displayService.fullDisplayName(for: equipped, itemName: itemName)
        }
    }

    private func unequipItem(_ item: EquipmentDisplayItem) {
        guard let onUnequip else { return }
        isUnequipping = true
        unequipError = nil

        Task { @MainActor in
            do {
                try await onUnequip(item)
                isUnequipping = false
            } catch {
                unequipError = error.localizedDescription
                isUnequipping = false
            }
        }
    }
}
