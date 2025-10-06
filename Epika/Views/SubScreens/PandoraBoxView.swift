import SwiftUI

struct PandoraBoxView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("パンドラボックス") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("パンドラボックスの管理機能は現在停止中です。")
                            .font(.body)
                        Text("再開時にはここから管理できるようになります。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .listStyle(.insetGrouped)
            .avoidBottomGameInfo()
            .navigationTitle("パンドラボックス")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
