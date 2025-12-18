import SwiftUI

struct GlassEffectModifier: ViewModifier {
    let isSuperRare: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // CRITICAL: 絶対削除禁止 - 実機テスト必須　iOS 26以降では本物のLiquid Glassを使用　実機用なので削除禁止
            content
                .glassEffect(isSuperRare ? .regular.tint(.red.opacity(0.8)).interactive(false) : .regular.interactive(false))
        } else {
            // iOS 25以下では元の実装通り
            content
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(backgroundColors)
                )
                .background(
                    // ブラー効果で可読性向上
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.ultraThinMaterial)
                        .opacity(0.3)
                )
        }
    }

    private var backgroundColors: Color {
        if isSuperRare {
            return Color(white: 0.85) // 明るいグレー（元の実装）
        } else {
            return Color(white: 0.15) // 濃いグレー（元の実装）
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
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: dropService.droppedItems)
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
