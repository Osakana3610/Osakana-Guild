// ==============================================================================
// ExplorationResultViews.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 探索結果のサマリーと履歴表示用のView群を提供
//
// 【View構成】
//   - ExplorationRunResultSummaryView: 探索結果の総合サマリー表示
//   - SimplifiedEventSummaryRowView: イベント・戦闘の簡易サマリー行
//   - FinalExplorationSummaryRowView: 探索完了時の最終サマリー行
//   - ExplorationDateFormatters: 日時フォーマッター群
//
// 【使用箇所】
//   - RecentExplorationLogsViewから参照
//   - パーティ画面での探索結果表示
//
// ==============================================================================

import SwiftUI

struct ExplorationRunResultSummaryView: View {
    let snapshot: ExplorationSnapshot
    let party: PartySnapshot

    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var appServices

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(snapshot.displayDungeonName)：\(ExplorationSnapshot.resultMessage(for: snapshot.status))")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let returnInfo {
                        Text("\(returnInfo.label)：\(returnInfo.value)")
                    }

                    Text("最終到達階層：\(snapshot.summary.floorNumber)F")

                    if snapshot.rewards.experience > 0 {
                        Text("獲得経験値：\(formatNumber(snapshot.rewards.experience))")
                    }

                    if snapshot.rewards.gold > 0 {
                        Text("獲得ゴールド：\(formatNumber(snapshot.rewards.gold))")
                    }

                    if snapshot.status == .completed {
                        if itemRows.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("入手アイテム：")
                                Text("なし")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("入手アイテム：")
                                ForEach(itemRows) { row in
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text("・\(row.displayName) x\(row.count)")
                                        if row.isSuperRare {
                                            Text("超レア")
                                                .font(.caption2)
                                                .foregroundStyle(.red)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(
                                                    Capsule()
                                                        .fill(Color.red.opacity(0.12))
                                                )
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("入手アイテム：")
                            Text("探索が完了していないためアイテムは持ち帰れません。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if shouldShowAutoSellSection {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("自動売却")
                                .font(.headline)
                            Text("以下のアイテムを自動売却しました。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if autoSellRows.isEmpty {
                                Text("自動売却アイテムの詳細を取得できませんでした。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(autoSellRows) { row in
                                    Text("・\(row.name) x\(formatNumber(row.quantity))")
                                }
                            }
                            Text("合計 \(formatNumber(snapshot.rewards.autoSellGold)) GP を入手しました。")
                                .padding(.top, 4)
                        }
                    }

                    Text("探索開始：\(ExplorationDateFormatters.timestamp.string(from: snapshot.startedAt))")

                    if let actual = actualReturnDate {
                        Text("探索終了：\(ExplorationDateFormatters.timestamp.string(from: actual))")
                        Text("所要時間：\(durationString(from: snapshot.startedAt, to: actual))")
                    }

                    Text("パーティ人数：\(party.memberIds.count)人")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .navigationTitle("探索サマリー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private var returnInfo: (label: String, value: String)? {
        let label = snapshot.summary.timingKind == .expected ? "帰還予定" : "帰還日時"
        let value = ExplorationDateFormatters.timestamp.string(from: snapshot.summary.timingDate)
        return (label, value)
    }

    private var actualReturnDate: Date? {
        snapshot.summary.timingKind == .actual ? snapshot.summary.timingDate : nil
    }

    private var itemRows: [DropRow] {
        guard snapshot.status == .completed else { return [] }
        let cache = appServices.masterDataCache
        return snapshot.rewards.itemDrops.compactMap { summary -> DropRow? in
            guard let definition = cache.item(summary.itemId) else { return nil }
            var name = ""
            if summary.superRareTitleId > 0,
               let title = cache.superRareTitle(summary.superRareTitleId)?.name,
               !title.isEmpty {
                name += title
            }
            if summary.normalTitleId > 0,
               let title = cache.title(summary.normalTitleId)?.name,
               !title.isEmpty {
                name += title
            }
            name += definition.name
            return DropRow(id: summary.id,
                           displayName: name,
                           count: formatNumber(summary.quantity),
                           isSuperRare: summary.isSuperRare)
        }
    }

    private var autoSellRows: [AutoSellRow] {
        guard !snapshot.rewards.autoSoldItems.isEmpty else { return [] }
        var rows: [AutoSellRow] = []
        rows.reserveCapacity(snapshot.rewards.autoSoldItems.count)
        let cache = appServices.masterDataCache
        for entry in snapshot.rewards.autoSoldItems where entry.quantity > 0 {
            guard let definition = cache.item(entry.itemId) else { continue }
            let name = autoSellDisplayName(for: entry, definition: definition)
            rows.append(AutoSellRow(itemId: entry.itemId,
                                    superRareTitleId: entry.superRareTitleId,
                                    normalTitleId: entry.normalTitleId,
                                    name: name,
                                    quantity: entry.quantity))
        }
        return rows
    }

    private var shouldShowAutoSellSection: Bool {
        !snapshot.rewards.autoSoldItems.isEmpty || snapshot.rewards.autoSellGold > 0
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.groupingSeparator = ","
        return formatter
    }()

    private func durationString(from start: Date, to end: Date) -> String {
        let interval = max(0, Int(end.timeIntervalSince(start)))
        let hours = interval / 3600
        let minutes = (interval % 3600) / 60
        let seconds = interval % 60
        if hours > 0 {
            return String(format: "%d時間 %d分 %d秒", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%d分 %d秒", minutes, seconds)
        } else {
            return String(format: "%d秒", seconds)
        }
    }

    private func formatNumber(_ value: Int) -> String {
        Self.numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func autoSellDisplayName(for entry: ExplorationSnapshot.Rewards.AutoSellEntry,
                                     definition: ItemDefinition) -> String {
        let cache = appServices.masterDataCache
        var result = ""
        if entry.superRareTitleId != 0,
           let title = cache.superRareTitle(entry.superRareTitleId)?.name,
           !title.isEmpty {
            result += title
        }
        if entry.normalTitleId != 0,
           let title = cache.title(entry.normalTitleId)?.name,
           !title.isEmpty {
            result += title
        }
        result += definition.name
        return result
    }
}

private struct AutoSellRow: Identifiable {
    let itemId: UInt16
    let superRareTitleId: UInt8
    let normalTitleId: UInt8
    let name: String
    let quantity: Int

    var id: String {
        "\(itemId)|\(superRareTitleId)|\(normalTitleId)"
    }
}

private struct DropRow: Identifiable {
    let id: String
    let displayName: String
    let count: String
    let isSuperRare: Bool
}

struct SimplifiedEventSummaryRowView: View {
    let encounter: ExplorationSnapshot.EncounterLog
    let runStatus: ExplorationSnapshot.Status

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                if let detail = subtitleText {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let result = resultText {
                Text(result)
                    .font(.caption)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var titleText: String {
        return ExplorationSnapshot.eventTitle(for: encounter, status: runStatus)
    }

    private var subtitleText: String? {
        if let drops = encounter.context.drops, !drops.isEmpty {
            return drops
        }
        if let exp = encounter.context.exp, !exp.isEmpty {
            return "経験値 \(exp)"
        }
        if let gold = encounter.context.gold, !gold.isEmpty {
            return "GP \(gold)"
        }
        if let effects = encounter.context.effects, !effects.isEmpty {
            return effects
        }
        return nil
    }

    private var resultText: String? {
        // 戦闘結果は CombatSummary から取得
        if let result = encounter.combatSummary?.result, !result.isEmpty {
            return ExplorationSnapshot.localizedCombatResult(result)
        }
        return nil
    }
}

struct FinalExplorationSummaryRowView: View {
    let summary: ExplorationSnapshot.Summary

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatSummaryHeader(summary))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Text(summary.body)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

func formatSummaryHeader(_ summary: ExplorationSnapshot.Summary) -> String {
    let label = summary.timingKind == .expected ? "帰還予定" : "帰還日時"
    let timestamp = ExplorationDateFormatters.short.string(from: summary.timingDate)
    return "[\(summary.floorNumber)F] \(label) \(timestamp)"
}

// MARK: - Date Formatters

enum ExplorationDateFormatters {
    static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    static let short: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "MM/dd HH:mm:ss"
        return formatter
    }()
}
