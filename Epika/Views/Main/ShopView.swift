import SwiftUI

struct ShopView: View {
    var body: some View {
        NavigationStack {
            contentList
            .navigationTitle("商店")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var contentList: some View {
        List {
            Section("アイテムを装備") {
                ShopMenuRow(title: "アイテムを装備",
                           icon: "shield.fill",
                           tint: .blue) {
                    CharacterSelectionForEquipmentView()
                }

                ShopMenuRow(title: "パンドラボックスの管理",
                           icon: "shippingbox.fill",
                           tint: .purple) {
                    PandoraBoxView()
                }
            }

            Section("アイテムの売買") {
                ShopMenuRow(title: "アイテムの売却",
                           icon: "minus.circle.fill",
                           tint: .red) {
                    ItemSaleView()
                }

                ShopMenuRow(title: "アイテムの購入",
                           icon: "plus.circle.fill",
                           tint: .green) {
                    ItemPurchaseView()
                }

                ShopMenuRow(title: "日替わり商品",
                           icon: "calendar.circle.fill",
                           tint: .orange) {
                    Text("日替わり商品は準備中です")
                        .foregroundStyle(.secondary)
                        .padding()
                }

                ShopMenuRow(title: "掘り出し物を見る",
                           icon: "magnifyingglass.circle.fill",
                           tint: .cyan) {
                    PandoraBoxView()
                }

                ShopMenuRow(title: "神器交換",
                           icon: "star.circle.fill",
                           tint: .yellow) {
                    ArtifactExchangeView()
                }
            }

            Section("アイテムを加工") {
                ShopMenuRow(title: "アイテムを合成",
                           icon: "hammer.fill",
                           tint: .brown) {
                    ItemSynthesisView()
                }

                ShopMenuRow(title: "称号を継承",
                           icon: "crown.fill",
                           tint: .indigo) {
                    TitleInheritanceView()
                }

                ShopMenuRow(title: "宝石改造",
                           icon: "diamond.fill",
                           tint: .pink) {
                    GemModificationView()
                }
            }

            Section("在庫管理") {
                ShopMenuRow(title: "自動取引",
                           icon: "repeat.circle.fill",
                           tint: .teal) {
                    AutoTradeView()
                }

                ShopMenuRow(title: "在庫整理",
                           icon: "archivebox.fill",
                           tint: .gray) {
                    InventoryCleanupView()
                }
            }
        }
        .listStyle(.insetGrouped)
        .avoidBottomGameInfo()
    }
}

private struct ShopMenuRow<Destination: View>: View {
    let title: String
    let icon: String
    let tint: Color
    let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(tint)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .frame(height: AppConstants.UI.listRowHeight)
        }
    }
}
