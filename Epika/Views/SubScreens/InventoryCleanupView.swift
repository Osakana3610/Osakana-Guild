import SwiftUI

struct InventoryCleanupView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("在庫整理") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("在庫整理機能は現在利用できません。")
                            .font(.body)
                        Text("アイテム一括整理の改善版を準備中です。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .listStyle(.insetGrouped)
            .avoidBottomGameInfo()
            .navigationTitle("在庫整理")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
