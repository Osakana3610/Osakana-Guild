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
    @EnvironmentObject private var appServices: AppServices
    @Environment(\.sizeCategory) private var sizeCategory
    @State private var currentTime = Date()
    @State private var catTicketCount: Int = 0
    @State private var goldAmount: Int = 0
    @State private var currentPlayer: PlayerSnapshot?

    private let secondsTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

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

                    Text("\(catTicketCount)枚")
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
                    Text("\(formatGold(goldAmount))GP")
                        .font(.footnote)
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .padding(.vertical, 6)
        .modifier(BottomGameInfoStyleModifier())
        .onAppear { loadPlayerData() }
        .onReceive(secondsTimer) { _ in currentTime = Date() }
        .onReceive(minuteTimer) { _ in loadPlayerData() }
    }

    private func loadPlayerData() {
        Task { @MainActor in
            do {
                let player = try await appServices.gameState.currentPlayer()
                apply(player)
            } catch ProgressError.playerNotFound {
                do {
                    let player = try await appServices.gameState.loadCurrentPlayer()
                    apply(player)
                } catch {
                    clearPlayer()
                }
            } catch {
                clearPlayer()
            }
        }
    }

    @MainActor
    private func apply(_ snapshot: PlayerSnapshot) {
        currentPlayer = snapshot
        catTicketCount = Int(snapshot.catTickets)
        goldAmount = Int(snapshot.gold)
    }

    @MainActor
    private func clearPlayer() {
        currentPlayer = nil
        catTicketCount = 0
        goldAmount = 0
    }

    private func formatCurrentTime(_ date: Date) -> String {
        Self.ymdHmsFormatter.string(from: date)
    }

    private func formatGold(_ amount: Int) -> String {
        if amount >= 100_000_000 {
            return String(format: "%.0f,%03d,%03d",
                          Double(amount) / 1_000_000,
                          (amount / 1000) % 1000,
                          amount % 1000)
        } else if amount >= 1_000_000 {
            return String(format: "%.0f,%03d,%03d",
                          Double(amount) / 1_000_000,
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
