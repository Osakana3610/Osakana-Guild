import SwiftUI

struct GemModificationView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("宝石改造") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("宝石改造は次期バージョンで提供予定です。")
                            .font(.body)
                        Text("準備が整い次第、ここに改造手順が表示されます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .listStyle(.insetGrouped)
            .avoidBottomGameInfo()
            .navigationTitle("宝石改造")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
