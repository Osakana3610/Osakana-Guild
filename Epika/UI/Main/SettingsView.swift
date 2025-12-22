// ==============================================================================
// SettingsView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 図鑑とベータテスト用機能へのナビゲーション
//   - その他の設定・機能へのアクセスハブ
//
// 【View構成】
//   - 図鑑セクション（モンスター、アイテム、超レア）
//   - 開発支援セクション（ベータテスト用機能）
//
// 【使用箇所】
//   - MainTabView（その他タブ）
//
// ==============================================================================

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
                    NavigationLink("ベータテスト用機能") {
                        DebugMenuView()
                    }
                }
            }
            .navigationTitle("その他")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
