import SwiftUI
import SwiftData

extension ExplorationSnapshot: Identifiable {}
extension ExplorationSnapshot.EncounterLog: Identifiable {}
extension CharacterSnapshot: Identifiable {}

struct RecentExplorationLogsView: View {
    let party: RuntimeParty
    let runs: [ExplorationSnapshot]

    @State private var showingInProgressDetail = false
    @State private var activeRunForProgress: ExplorationSnapshot?
    @State private var selectedRunForSummary: ExplorationSnapshot?
    @State private var selectedRunForResultSummary: ExplorationSnapshot?

    private let maxDisplayCount = 2

    private var partyRuns: [ExplorationSnapshot] {
        runs
            .filter { $0.party.partyId == party.id }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(maxDisplayCount)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            if partyRuns.isEmpty {
                emptyState
            } else {
                ForEach(Array(partyRuns.enumerated()), id: \.element.id) { index, run in
                    if index > 0 {
                        Divider()
                            .padding(.horizontal, 0)
                    }

                    ExplorationLogRowView(
                        header: formatSummaryHeader(run.summary),
                        content: run.summary.body,
                        onShowDetail: {
                            handleDetailButton(for: run)
                        },
                        onRowTap: {
                            handleRowTap(for: run)
                        }
                    )
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingInProgressDetail, onDismiss: {
            activeRunForProgress = nil
        }) {
            InProgressStatusView(
                dungeonName: activeRunForProgress?.displayDungeonName ?? "",
                statusText: progressText(for: activeRunForProgress)
            )
        }
        .sheet(item: $selectedRunForSummary) { snapshot in
            ExplorationRunSummaryView(
                snapshot: snapshot,
                party: party
            )
        }
        .sheet(item: $selectedRunForResultSummary) { snapshot in
            ExplorationRunResultSummaryView(snapshot: snapshot,
                                             party: party)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("まだ探索ログがありません")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("出撃ボタンを押して探索を開始してください")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func progressText(for run: ExplorationSnapshot?) -> String {
        guard let run else {
            return "探索状況を取得できませんでした"
        }
        let referenceDate: Date
        let label: String
        switch run.summary.timing {
        case .expectedReturn(let expected):
            referenceDate = expected
            label = "帰還予定"
        case .actualReturn(let actual):
            referenceDate = actual
            label = "帰還日時"
        }
        let timestamp = ExplorationDateFormatters.timestamp.string(from: referenceDate)
        return "探索進行中...（\(run.activeFloorNumber)F到達・\(label) \(timestamp)）"
    }

    private func handleDetailButton(for run: ExplorationSnapshot) {
        if run.status == .running {
            activeRunForProgress = run
            showingInProgressDetail = true
            return
        }
        selectedRunForSummary = run
    }

    private func handleRowTap(for run: ExplorationSnapshot) {
        if run.status == .running {
            activeRunForProgress = run
            showingInProgressDetail = true
            return
        }
        selectedRunForResultSummary = run
    }

}

// MARK: - Row View

private struct ExplorationLogRowView: View {
    let header: String
    let content: String
    let onShowDetail: () -> Void
    let onRowTap: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                if !header.isEmpty {
                    Text(header)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Text(content)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onRowTap)

            Spacer()

            Button(action: onShowDetail) {
                Image(systemName: "info.circle")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - In Progress View

private struct InProgressStatusView: View {
    let dungeonName: String
    let statusText: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("探索進行中")
                    .font(.title2)
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: 8) {
                    Text("迷宮")
                        .font(.headline)
                    Text(dungeonName.isEmpty ? "不明な迷宮" : dungeonName)
                        .font(.body)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("現在の状況")
                        .font(.headline)
                    Text(statusText)
                        .font(.body)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("探索状況")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Run Summary View

private struct ExplorationRunSummaryView: View {
    let snapshot: ExplorationSnapshot
    let party: RuntimeParty

    @Environment(\.dismiss) private var dismiss
    @State private var selectedEncounter: ExplorationSnapshot.EncounterLog?
    @State private var showingResultSummary = false

    private var eventsByFloor: [(floor: Int, events: [ExplorationSnapshot.EncounterLog])] {
        let grouped = Dictionary(grouping: snapshot.encounterLogs) { $0.floorNumber }
        return grouped.keys.sorted().map { floor in
            let events = (grouped[floor] ?? []).sorted { lhs, rhs in
                lhs.eventIndex < rhs.eventIndex
            }
            return (floor, events)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                explorationLogSections
            }
            .avoidBottomGameInfo()
            .navigationTitle("冒険の記録")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedEncounter) { encounter in
                EncounterDetailView(snapshot: snapshot,
                                    party: party,
                                    encounter: encounter)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(isPresented: $showingResultSummary) {
                ExplorationRunResultSummaryView(snapshot: snapshot,
                                                 party: party)
            }
        }
    }

    private var explorationLogSections: some View {
        Group {
            if snapshot.encounterLogs.isEmpty {
                Section("探索ログ") {
                    VStack(spacing: 12) {
                        Text("詳細ログがありません")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("この探索ではイベント情報が記録されていません")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                finalSummaryRow
            } else {
                ForEach(eventsByFloor, id: \.floor) { floorData in
                    Section("\(floorData.floor)F") {
                        ForEach(floorData.events) { encounter in
                            Button {
                                selectedEncounter = encounter
                            } label: {
                                SimplifiedEventSummaryRowView(
                                    encounter: encounter,
                                    runStatus: snapshot.status
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                finalSummaryRow
            }
        }
    }

    @ViewBuilder
    private var finalSummaryRow: some View {
        if snapshot.status != .running {
            Button {
                showingResultSummary = true
            } label: {
                FinalExplorationSummaryRowView(summary: snapshot.summary)
            }
            .buttonStyle(.plain)
        }
    }
}
