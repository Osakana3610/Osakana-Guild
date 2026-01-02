// ==============================================================================
// ArtifactExchangeView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 所持している神器（アーティファクト）を他の神器と交換する機能を提供
//
// 【View構成】
//   - 機能準備中の表示（交換ルールが未定義のため）
//
// 【使用箇所】
//   - アイテム関連画面からナビゲーション
//
// 【ステータス】
//   - 現在は交換ルールが未定義のため機能準備中
//
// ==============================================================================

import SwiftUI

struct ArtifactExchangeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("神器交換")
                .font(.title2)
                .fontWeight(.bold)

            Text("この機能は準備中です")
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("神器交換")
        .navigationBarTitleDisplayMode(.inline)
    }
}
