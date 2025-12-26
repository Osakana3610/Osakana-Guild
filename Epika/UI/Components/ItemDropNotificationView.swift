// ==============================================================================
// ItemDropNotificationView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アイテムドロップ時の通知を画面上部に表示
//   - GlassEffectを使用した視覚的な通知UI
//
// 【View構成】
//   - ItemDropNotificationServiceから通知リストを取得
//   - 各アイテムを行として表示（ItemDropRowView）
//   - iOS 26以降はglassEffect、それ以前はultraThinMaterial背景
//   - 超レアアイテムは白背景+赤tint、通常アイテムは濃いグレー
//   - イーズアウトアニメーション対応（挿入/削除）
//   - タップで全アイテムをクリア
//
// 【使用箇所】
//   - ゲーム画面上部（探索中・戦闘中）
//   - ダンジョン探索画面
//
// ==============================================================================

import SwiftUI

struct GlassEffectModifier: ViewModifier {
    let isSuperRare: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // CRITICAL: 絶対削除禁止 - 実機テスト必須　iOS 26以降では本物のLiquid Glassを使用　実機用なので削除禁止
            content
                .glassEffect(isSuperRare ? .regular.tint(.red.opacity(0.8)) : .regular)
        } else {
            // iOS 25以下ではブラー + 色オーバーレイ + 影で視認性確保
            content
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(backgroundColors.opacity(0.7))
                        )
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                )
        }
    }

    private var backgroundColors: Color {
        if isSuperRare {
            return Color.red
        } else {
            return Color(.systemBackground)
        }
    }
}

struct ItemDropNotificationView: View {
    @Environment(ItemDropNotificationService.self) private var dropService

    var body: some View {
        contentView
    }

    @ViewBuilder
    private var contentView: some View {
        if !dropService.droppedItems.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                itemsView
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
            .animation(.easeOut(duration: 0.3), value: dropService.droppedItems)
        } else {
            // アイテムがない時は何も表示しない
            EmptyView()
        }
    }

    @ViewBuilder
    private var itemsView: some View {
        ForEach(dropService.droppedItems) { item in
            ItemDropRowView(item: item) {
                clearAllItems()
            }
            .transition(
                .asymmetric(
                    insertion: AnyTransition.move(edge: .bottom).combined(with: .opacity),
                    removal: AnyTransition.move(edge: .top).combined(with: .opacity)
                )
            )
        }
    }

    private func clearAllItems() {
        dropService.clear()
    }

}

struct ItemDropRowView: View {
    let item: ItemDropNotificationService.DroppedItemNotification
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap, label: {
            // アイテム名に応じた幅調整
            Text(item.displayText)
                .font(.subheadline)
                .fontWeight(.regular)
                .foregroundColor(textColor(for: item))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .modifier(GlassEffectModifier(isSuperRare: item.isSuperRare))
        })
        .buttonStyle(PlainButtonStyle())
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Rectangle().inset(by: -2))
    }

    private func textColor(for item: ItemDropNotificationService.DroppedItemNotification) -> Color {
        if item.isSuperRare {
            // 超レア: ほぼ白でほんのり黒
            return Color.white.opacity(0.95)
        } else {
            // 通常: ラベル色でより確実なダークモード対応
            return Color(.label)
        }
    }
}
