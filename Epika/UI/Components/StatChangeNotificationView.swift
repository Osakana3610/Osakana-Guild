// ==============================================================================
// StatChangeNotificationView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ステータス変動通知を画面上部に表示
//   - ガラスエフェクト（tintなし）を使用した視覚的な通知UI
//
// 【View構成】
//   - StatChangeNotificationServiceから通知リストを取得
//   - 各ステータス変動を行として表示（StatChangeRowView）
//   - iOS 26以降はglassEffect、それ以前はultraThinMaterial背景
//   - スプリングアニメーション対応（挿入/削除）
//   - タップで全通知をクリア
//
// 【使用箇所】
//   - MainTabView上部（装備変更時）
//
// ==============================================================================

import SwiftUI

struct StatChangeNotificationView: View {
    @Environment(StatChangeNotificationService.self) private var statChangeService

    var body: some View {
        contentView
    }

    @ViewBuilder
    private var contentView: some View {
        if !statChangeService.changes.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                itemsView
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: statChangeService.changes)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var itemsView: some View {
        ForEach(statChangeService.changes) { change in
            StatChangeRowView(change: change) {
                clearAllChanges()
            }
            .transition(
                .asymmetric(
                    insertion: AnyTransition.move(edge: .bottom).combined(with: .opacity),
                    removal: AnyTransition.move(edge: .top).combined(with: .opacity)
                )
            )
        }
    }

    private func clearAllChanges() {
        statChangeService.clear()
    }
}

struct StatChangeRowView: View {
    let change: StatChangeNotificationService.StatChangeNotification
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap, label: {
            Text(change.displayText)
                .font(.subheadline)
                .fontWeight(.regular)
                .foregroundColor(Color(.label))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .modifier(StatChangeGlassModifier())
        })
        .buttonStyle(PlainButtonStyle())
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Rectangle().inset(by: -2))
    }
}

private struct StatChangeGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // iOS 26以降では本物のLiquid Glassを使用（tintなし）
            content
                .glassEffect(.regular)
        } else {
            // iOS 25以下ではブラー + 影で視認性確保
            content
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                )
        }
    }
}
