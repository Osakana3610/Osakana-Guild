import SwiftUI

/// 現在の実装では自動取引機能を提供していないため、案内のみを表示するビュー。
struct AutoTradeView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("自動取引") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("自動取引機能は現在利用できません。")
                            .font(.body)
                        Text("今後のアップデートで商店の自動取引ルールを再設計する予定です。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .listStyle(.insetGrouped)
            .avoidBottomGameInfo()
            .navigationTitle("自動取引")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
