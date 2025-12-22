// ==============================================================================
// MainTabView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アプリのメインタブバー構成
//   - 各タブ（物語・ギルド・冒険・商店・その他）の管理
//   - BottomGameInfoView と通知Viewの配置制御（アイテムドロップ、ステータス変動）
//
// 【View構成】
//   - TabView による5つのタブ管理
//   - iOS 26対応の Liquid Glass 風タブバースタイル
//   - 画面下部の固定UI（ゲーム情報、ドロップ通知）
//
// 【使用箇所】
//   - RootView
//
// ==============================================================================

import SwiftUI

// タブバーの実際の幅を取得するためのPreferenceKey
struct TabBarWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// BottomViewの位置を取得するためのPreferenceKey
struct BottomViewPositionPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var tabBarWidth: CGFloat = 0
    @State private var screenWidth: CGFloat = 0
    @State private var bottomViewTopPosition: CGFloat = 0

    // 計算されたpadding値
    private var calculatedHorizontalPadding: CGFloat {
        // UITabBarのlayoutMarginsを取得
        let tabBarMargin = UITabBar.appearance().layoutMargins.left
        return tabBarMargin > 0 ? tabBarMargin : 16 // フォールバック値
    }

    // タブバーとBottomViewの間隔（レイアウト統一用）
    private var tabBarBottomViewSpacing: CGFloat {
        return 9 // タブバーとBottomViewの間隔
    }

    // BottomViewのbottom padding計算（タブバー高さ + 間隔）
    private var bottomViewBottomPadding: CGFloat {
        return 49 + tabBarBottomViewSpacing // タブバー高さ(49) + 間隔
    }

    private func calculateDropNotificationPadding() -> CGFloat {
        if #available(iOS 26.0, *) {
            let bottomInfoHeight: CGFloat = 46
            let bottomInfoPadding = bottomViewBottomPadding
            return bottomInfoHeight + bottomInfoPadding + tabBarBottomViewSpacing
        } else {
            return 98
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedTab) {
                StoryView()
                    .tabItem {
                        Image(systemName: "book.fill")
                        Text("物語")
                    }
                    .tag(0)

                GuildView()
                    .tabItem {
                        Image(systemName: "person.3.fill")
                        Text("ギルド")
                    }
                    .tag(1)

                AdventureView()
                    .tabItem {
                        Image(systemName: "map.fill")
                        Text("冒険")
                    }
                    .tag(2)

                ShopView()
                    .tabItem {
                        Image(systemName: "bag.fill")
                        Text("商店")
                    }
                    .tag(3)

                SettingsView()
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("その他")
                    }
                    .tag(4)
            }
            .background(
                // タブバーの幅を測定
                GeometryReader { tabGeometry in
                    Color.clear
                        .preference(key: TabBarWidthPreferenceKey.self, value: tabGeometry.size.width)
                }
            )
            .onAppear {
                // 画面幅を取得
                screenWidth = geometry.size.width

                // タブバーの背景色を設定
                let tabBarAppearance = UITabBarAppearance()
                if #available(iOS 26.0, *) {
                    // iOS 26以降: より薄い透明スタイルでLiquid Glassに近づける
                    tabBarAppearance.configureWithTransparentBackground()
                    tabBarAppearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterial) // systemMaterial → systemThinMaterial

                    // タブアイテムの色調整
                    tabBarAppearance.stackedLayoutAppearance.selected.iconColor = .systemBlue
                    tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                        .foregroundColor: UIColor.systemBlue
                    ]
                } else {
                    // iOS 25以下: 従来通り
                    tabBarAppearance.configureWithOpaqueBackground()
                    tabBarAppearance.backgroundColor = UIColor.systemGray6
                }
                UITabBar.appearance().standardAppearance = tabBarAppearance
                UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
            }
            .onPreferenceChange(TabBarWidthPreferenceKey.self) { width in
                tabBarWidth = width
            }
            .onPreferenceChange(BottomViewPositionPreferenceKey.self) { position in
                bottomViewTopPosition = position
            }
        }
        .overlay(
            // BottomGameInfoViewを条件分岐で配置
            VStack {
                Spacer()
                if #available(iOS 26.0, *) {
                    // iOS 26以降: Apple Music風の浮遊レイアウト
                    BottomGameInfoView()
                        .padding(.horizontal, calculatedHorizontalPadding + 1) // タブバーより1pt左にずらす
                        .padding(.bottom, bottomViewBottomPadding) // 動的に計算されたpadding
                        .scaleEffect(0.98) // 微細なスケール調整で浮遊感
                        .background(
                            GeometryReader { bottomGeometry in
                                Color.clear
                                    .preference(key: BottomViewPositionPreferenceKey.self, value: bottomGeometry.frame(in: .global).minY)
                            }
                        )
                } else {
                    // iOS 25以下: 従来通りの配置
                    BottomGameInfoView()
                        .padding(.bottom, 49) // タブバーの高さ分
                }
            }
            .ignoresSafeArea(.keyboard)
        )
        .overlay(
            VStack(spacing: 0) {
                Spacer()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        ItemDropNotificationView()
                        StatChangeNotificationView()
                    }
                    Spacer()
                }
                .padding(.horizontal, calculatedHorizontalPadding - 1)
                .padding(.bottom, calculateDropNotificationPadding())
            }
        )
        }
    }
}

 
