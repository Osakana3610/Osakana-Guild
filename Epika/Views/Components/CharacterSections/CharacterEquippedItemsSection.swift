import SwiftUI

/// キャラクターの装備中アイテム一覧を表示するセクション
/// CharacterSectionType: equippedItems
@MainActor
struct CharacterEquippedItemsSection: View {
    let equippedItems: [RuntimeCharacterProgress.EquippedItem]
    let itemDefinitions: [UInt16: ItemDefinition]
    let onUnequip: ((RuntimeCharacterProgress.EquippedItem) async throws -> Void)?

    @State private var unequipError: String?
    @State private var isUnequipping = false

    init(
        equippedItems: [RuntimeCharacterProgress.EquippedItem],
        itemDefinitions: [UInt16: ItemDefinition],
        onUnequip: ((RuntimeCharacterProgress.EquippedItem) async throws -> Void)? = nil
    ) {
        self.equippedItems = equippedItems
        self.itemDefinitions = itemDefinitions
        self.onUnequip = onUnequip
    }

    var body: some View {
        GroupBox("装備中アイテム (\(totalCount)/\(EquipmentProgressService.maxEquippedItems))") {
            if equippedItems.isEmpty {
                Text("装備なし")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(equippedItems, id: \.stackKey) { item in
                        equippedItemRow(item)
                    }
                }

                if let error = unequipError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var totalCount: Int {
        equippedItems.reduce(0) { $0 + $1.quantity }
    }

    @ViewBuilder
    private func equippedItemRow(_ item: RuntimeCharacterProgress.EquippedItem) -> some View {
        let definition = itemDefinitions[item.itemId]
        let name = definition?.name ?? "不明なアイテム"

        HStack {
            Text("• \(name)")
            if item.quantity > 1 {
                Text("x\(item.quantity)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if onUnequip != nil {
                Button {
                    unequipItem(item)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .disabled(isUnequipping)
            }
        }
    }

    private func unequipItem(_ item: RuntimeCharacterProgress.EquippedItem) {
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
