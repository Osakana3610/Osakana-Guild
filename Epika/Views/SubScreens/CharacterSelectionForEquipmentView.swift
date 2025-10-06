import SwiftUI

struct CharacterSelectionForEquipmentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("アイテムを装備") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("装備管理機能は現在再設計中です。")
                            .font(.body)
                        Text("次回のアップデートまでお待ちください。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .listStyle(.insetGrouped)
            .avoidBottomGameInfo()
            .navigationTitle("アイテムを装備")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
