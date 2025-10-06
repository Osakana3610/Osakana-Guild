import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
#if DEBUG
                Section("開発支援") {
                    NavigationLink("デバッグメニュー") {
                        DebugMenuView()
                    }
                }
#endif
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
