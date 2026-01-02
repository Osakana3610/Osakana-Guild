// ==============================================================================
// BottomGameInfoView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 画面下部に固定表示されるゲーム情報バーの表示
//   - キャット・チケット枚数、プレミアムタイム、現在時刻、ゴールド残高を表示
//
// 【View構成】
//   - 2行構成: 上段にキャット・チケット/プレミアム情報、下段に時刻/ゴールド
//   - iOS 26以降はglassEffect、それ以前はsystemGray6背景
//   - Dynamic Type対応（表示名を動的に短縮）
//   - Timer駆動で1秒ごとに時刻更新
//   - ゴールド/チケットはUserDataLoadServiceのキャッシュを参照（即時反映）
//
// 【使用箇所】
//   - アプリ全体の主要画面下部
//   - avoidBottomGameInfo()モディファイアと組み合わせて使用
//
// ==============================================================================

import SwiftUI
import Combine
import Foundation

/// BottomGameInfoView関連のレイアウトExtension
extension View {
    func avoidBottomGameInfo() -> some View {
        let bottomMargin: CGFloat = {
            if #available(iOS 26.0, *) { return 70 } else { return 49 }
        }()

        if #available(iOS 17.0, *) {
            return self
                .contentMargins(.bottom, bottomMargin, for: .scrollContent)
                .contentMargins(.bottom, bottomMargin * 0.8, for: .scrollIndicators)
        } else {
            return self.safeAreaInset(edge: .bottom) { Color.clear.frame(height: bottomMargin) }
        }
    }
}

struct BottomGameInfoStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .foregroundColor(.primary)
                .contentShape(Rectangle())
                .onTapGesture { }
                .glassEffect(.regular)
        } else {
            content
                .background(Color(.systemGray6))
                .foregroundColor(.primary)
        }
    }
}

struct BottomGameInfoView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.sizeCategory) private var sizeCategory
    @State private var currentTime = Date()

    private let secondsTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var catTicketDisplayName: String {
        sizeCategory > .large ? "キャット" : "キャット・チケット"
    }

    private var premiumTimeDisplayName: String {
        sizeCategory > .large ? "プレミアム" : "Premium Time"
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                HStack(spacing: 4) {
                    Text(catTicketDisplayName)
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    Text("\(appServices.userDataLoad.playerCatTickets)枚")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text(premiumTimeDisplayName)
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    Text("なし")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)

            HStack {
                Text(formatCurrentTime(currentTime))
                    .font(.footnote)
                    .foregroundColor(.primary)

                Spacer()

                HStack(spacing: 2) {
                    Text("\(formatGold(Int(appServices.userDataLoad.playerGold)))GP")
                        .font(.footnote)
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .padding(.vertical, 6)
        .modifier(BottomGameInfoStyleModifier())
        .onReceive(secondsTimer) { _ in currentTime = Date() }
    }

    private func formatCurrentTime(_ date: Date) -> String {
        Self.ymdHmsFormatter.string(from: date)
    }

    private func formatGold(_ amount: Int) -> String {
        if amount >= 10_000_000 {
            // 8〜9桁: XX,XXX,XXX
            return String(format: "%d,%03d,%03d",
                          amount / 1_000_000,
                          (amount / 1000) % 1000,
                          amount % 1000)
        } else if amount >= 1_000_000 {
            // 7桁: X,XXX,XXX
            return String(format: "%d,%03d,%03d",
                          amount / 1_000_000,
                          (amount / 1000) % 1000,
                          amount % 1000)
        } else if amount >= 1000 {
            return String(format: "%d,%03d", amount / 1000, amount % 1000)
        }
        return "\(amount)"
    }
}

private extension BottomGameInfoView {
    static let ymdHmsFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy/M/d HH:mm:ss"
        return formatter
    }()
}
