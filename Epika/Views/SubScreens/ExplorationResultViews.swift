import SwiftUI

struct ExplorationRunResultSummaryView: View {
    let snapshot: ExplorationSnapshot
    let party: RuntimeParty

    @Environment(\.dismiss) private var dismiss

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

                    if !itemRows.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("入手アイテム：")
                            ForEach(itemRows, id: \.name) { row in
                                Text("・\(row.name) x\(row.count)")
                            }
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
        switch snapshot.summary.timing {
        case .expectedReturn(let expected):
            return ("帰還予定", ExplorationDateFormatters.timestamp.string(from: expected))
        case .actualReturn(let actual):
            return ("帰還日時", ExplorationDateFormatters.timestamp.string(from: actual))
        }
    }

    private var actualReturnDate: Date? {
        switch snapshot.summary.timing {
        case .expectedReturn:
            return nil
        case .actualReturn(let date):
            return date
        }
    }

    private var itemRows: [(name: String, count: String)] {
        snapshot.rewards.itemDrops
            .sorted { lhs, rhs in lhs.key.localizedCompare(rhs.key) == .orderedAscending }
            .map { ($0.key, formatNumber($0.value)) }
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
        if let drops = encounter.context["drops"], !drops.isEmpty {
            return drops
        }
        if let exp = encounter.context["exp"], !exp.isEmpty {
            return "経験値 \(exp)"
        }
        if let gold = encounter.context["gold"], !gold.isEmpty {
            return "GP \(gold)"
        }
        if let effects = encounter.context["effects"], !effects.isEmpty {
            return effects
        }
        return nil
    }

    private var resultText: String? {
        if let raw = encounter.context["result"], !raw.isEmpty {
            return ExplorationSnapshot.localizedCombatResult(raw)
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
    let date: Date
    let label: String
    switch summary.timing {
    case .expectedReturn(let expected):
        date = expected
        label = "帰還予定"
    case .actualReturn(let actual):
        date = actual
        label = "帰還日時"
    }
    let timestamp = ExplorationDateFormatters.short.string(from: date)
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
