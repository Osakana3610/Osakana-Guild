// ==============================================================================
// PartySlotExpansionView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ギルド改造（パーティスロット拡張）機能を提供
//
// 【View構成】
//   - 現在の状況セクション（スロット数・所持ゴールド）
//   - ギルド改造セクション（次の改造内容・費用表示・実行ボタン）
//   - 改造計画セクション（全スロットの開放状況一覧）
//   - 改造完了メッセージ
//
// 【使用箇所】
//   - パーティ関連画面からシート表示
//
// ==============================================================================

import SwiftUI

struct PartySlotExpansionView: View {
    let appServices: AppServices
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var playerSnapshot: CachedPlayer?
    @State private var partySnapshots: [CachedParty] = []
    @State private var isLoading = false
    @State private var isExpanding = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var currentGold: Int { Int(playerSnapshot?.gold ?? 0) }
    private var currentSlots: Int { partySnapshots.count }
    private var nextSlot: Int { currentSlots + 1 }
    private var maxSlots: Int { AppConstants.Progress.maximumPartySlotsWithGold }
    private var canExpand: Bool { currentSlots < maxSlots }
    private var expansionCost: Int { AppConstants.Progress.partySlotExpansionCost(for: nextSlot) }
    private var hasEnoughGold: Bool { expansionCost == 0 || currentGold >= expansionCost }

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    ErrorView(message: errorMessage) {
                        Task { await loadState() }
                    }
                } else if isLoading && partySnapshots.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    content
                }
            }
            .navigationTitle("ギルド改造")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await loadState() }
        }
    }

    private var content: some View {
        VStack(spacing: 16) {
            List {
                statusSection
                if canExpand {
                    upgradeSection
                } else {
                    completedSection
                }
                planSection
            }
            .listStyle(.insetGrouped)
            .avoidBottomGameInfo()

            if let successMessage {
                Text(successMessage)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .transition(.opacity)
            }
        }
    }

    private var statusSection: some View {
        Section("現在の状況") {
            HStack {
                Image(systemName: "person.2")
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                Text("パーティスロット数")
                Spacer()
                Text("\(currentSlots)/\(maxSlots)")
                    .font(.headline)
            }
            .padding(.vertical, 4)

            HStack {
                Image(systemName: "dollarsign.circle")
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                Text("所持ゴールド")
                Spacer()
                Text("\(currentGold)G")
                    .font(.headline)
                    .foregroundColor(hasEnoughGold ? .primary : .secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var upgradeSection: some View {
        Section("ギルド改造") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "hammer")
                        .foregroundStyle(.tint)
                        .frame(width: 24)
                    Text("次の改造")
                    Spacer()
                    Text("\(currentSlots) → \(nextSlot)スロット")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                HStack {
                    Image(systemName: "bitcoinsign.circle")
                        .foregroundStyle(.tint)
                        .frame(width: 24)
                    Text("改造費用")
                    Spacer()
                    Text("\(expansionCost)G")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                Text("パーティスロットを1つ増やします。\n新しいパーティを編成できるようになります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.vertical, 4)

            Button {
                Task { await expandPartySlot() }
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.white)
                    Text("改造を実行する")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(hasEnoughGold ? Color.orange : Color.gray)
                .foregroundStyle(Color.white)
                .cornerRadius(8)
            }
            .disabled(!hasEnoughGold || isExpanding)
            .padding(.vertical, 4)
        }
    }

    private var completedSection: some View {
        Section("改造完了") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                        .frame(width: 24)
                    Text("ゴールドでの改造は完了しています")
                        .foregroundStyle(.primary)
                }

                Text("最大\(maxSlots)スロットまでゴールドで拡張できます。\nそれ以上の拡張は現在対応していません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
    }

    private var planSection: some View {
        Section("改造計画") {
            ForEach(1...maxSlots, id: \.self) { slotNumber in
                HStack {
                    let isUnlocked = slotNumber <= currentSlots
                    let isNext = slotNumber == nextSlot && canExpand

                    Image(systemName: iconName(isUnlocked: isUnlocked, isNext: isNext))
                        .foregroundStyle(.tint)
                        .frame(width: 24)

                    Text("パーティスロット \(slotNumber)")
                        .foregroundStyle(isUnlocked ? .primary : .secondary)

                    Spacer()

                    if isUnlocked {
                        Text("開放済み")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2), in: Capsule())
                    } else if isNext {
                        Text("次の改造")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                    } else {
                        let cost = AppConstants.Progress.partySlotExpansionCost(for: slotNumber)
                        Text("\(cost)G")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func iconName(isUnlocked: Bool, isNext: Bool) -> String {
        if isUnlocked { return "checkmark.circle.fill" }
        if isNext { return "circle.dotted" }
        return "circle"
    }

    private enum PartySlotExpansionError: LocalizedError {
        case rollbackFailed(original: Error, rollback: Error)

        var errorDescription: String? {
            switch self {
            case .rollbackFailed(let original, let rollback):
                return "パーティスロット拡張に失敗しました: \(original.localizedDescription)。さらにゴールドの払い戻しにも失敗しました: \(rollback.localizedDescription)"
            }
        }
    }

    @MainActor
    private func loadState() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            try await appServices.userDataLoad.loadParties()
            playerSnapshot = try await appServices.userDataLoad.refreshCachedPlayer()
            partySnapshots = appServices.userDataLoad.parties
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func expandPartySlot() async {
        guard canExpand else { return }
        if isExpanding { return }
        let previousSlots = currentSlots
        let cost = expansionCost
        isExpanding = true
        defer { isExpanding = false }
        errorMessage = nil
        successMessage = nil
        do {
            var spentSnapshot: CachedPlayer?
            if cost > 0 {
                spentSnapshot = try await appServices.gameState.spendGold(UInt32(cost))
                playerSnapshot = spentSnapshot
            }
            do {
                _ = try await appServices.party.ensurePartySlots(atLeast: previousSlots + 1)
                try await appServices.userDataLoad.loadParties()
                partySnapshots = appServices.userDataLoad.parties
                successMessage = "ギルド改造完了！パーティスロットが\(previousSlots)から\(partySnapshots.count)に増えました！"
                onComplete()
                return
            } catch {
                if cost > 0 {
                    do {
                        let refundSnapshot = try await appServices.gameState.addGold(UInt32(cost))
                        playerSnapshot = refundSnapshot
                    } catch let refundError {
                        throw PartySlotExpansionError.rollbackFailed(original: error, rollback: refundError)
                    }
                }
                throw error
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
