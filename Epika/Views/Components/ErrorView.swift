// ==============================================================================
// ErrorView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - エラー発生時の汎用エラー表示画面
//   - エラーメッセージと再試行機能を提供
//
// 【View構成】
//   - 三角アイコン（exclamationmark.triangle）
//   - エラータイトル「エラーが発生しました」
//   - エラーメッセージ（カスタマイズ可能）
//   - 再試行ボタン（オプション）
//
// 【使用箇所】
//   - データ読み込み失敗時
//   - ネットワークエラー時
//   - その他エラーハンドリング全般
//
// ==============================================================================

import SwiftUI

struct ErrorView: View {
    let message: String
    let onRetry: (() -> Void)?

    init(message: String, onRetry: (() -> Void)? = nil) {
        self.message = message
        self.onRetry = onRetry
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.primary)

            Text("エラーが発生しました")
                .font(.headline)
                .foregroundColor(.primary)

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let onRetry = onRetry {
                Button("再試行") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

 
