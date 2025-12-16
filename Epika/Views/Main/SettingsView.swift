import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("図鑑") {
                    NavigationLink {
                        MonsterEncyclopediaView()
                    } label: {
                        Label("モンスター図鑑", systemImage: "pawprint.fill")
                    }
                    NavigationLink {
                        ItemEncyclopediaView()
                    } label: {
                        Label("アイテム図鑑", systemImage: "bag.fill")
                    }
                    NavigationLink {
                        SuperRareTitleEncyclopediaView()
                    } label: {
                        Label("超レア図鑑", systemImage: "sparkles")
                    }
                }
                Section("開発支援") {
                    NavigationLink("デバッグメニュー") {
                        DebugMenuView()
                    }
                }
            }
            .navigationTitle("その他")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
