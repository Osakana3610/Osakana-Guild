// ==============================================================================
// RecentExplorationLogsView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - パーティの最近の探索ログ（最大2件）を表示
//
// 【View構成】
//   - 探索ログ行のリスト表示（ExplorationLogRowView）
//   - 詳細ボタンでログ詳細画面表示（ExplorationRunSummaryView）
//   - タップで結果サマリー画面表示（ExplorationRunResultSummaryView）
//   - 空状態の表示
//
// 【使用箇所】
//   - パーティ詳細画面内で使用
//
// ==============================================================================

import SwiftUI
import SwiftData

extension CachedExploration: Identifiable {}
extension CachedExploration.EncounterLog: Identifiable {}
extension CharacterSnapshot: Identifiable {}

struct RecentExplorationLogsView: View {
    let party: CachedParty
    let runs: [CachedExploration]

    @Environment(AppServices.self) private var appServices

    @State private var selectedRunForSummary: CachedExploration?
    @State private var selectedRunForResultSummary: CachedExploration?
    @State private var enrichedRuns: [Int64: CachedExploration] = [:]
    @State private var isFetchingDetail = false
    @State private var detailErrorMessage: String?

    private let maxDisplayCount = 2

    private var partyRuns: [CachedExploration] {
        runs
            .map { enrichedRuns[$0.id] ?? $0 }
            .filter { $0.party.partyId == party.id }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(maxDisplayCount)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let detailErrorMessage {
                statusBanner(text: detailErrorMessage, systemImage: "exclamationmark.triangle")
            }

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

    private func handleDetailButton(for run: CachedExploration) {
        Task { await presentSummary(for: run) }
    }

    private func handleRowTap(for run: CachedExploration) {
        Task {
            if run.status == .running {
                await presentSummary(for: run)
            } else {
                await presentResultSummary(for: run)
            }
        }
    }

    @MainActor
    private func presentSummary(for run: CachedExploration) async {
        guard let snapshot = await ensureDetailedSnapshot(for: run) else { return }
        selectedRunForSummary = snapshot
    }

    @MainActor
    private func presentResultSummary(for run: CachedExploration) async {
        if let enriched = enrichedRuns[run.id] {
            selectedRunForResultSummary = enriched
        } else {
            selectedRunForResultSummary = run
        }
    }

    @MainActor
    private func ensureDetailedSnapshot(for run: CachedExploration) async -> CachedExploration? {
        detailErrorMessage = nil
        let existing = enrichedRuns[run.id] ?? run
        guard needsDetailFetch(existing) else { return existing }

        isFetchingDetail = true
        defer { isFetchingDetail = false }

        do {
            guard let snapshot = try await appServices.exploration.explorationSnapshot(
                partyId: run.party.partyId,
                startedAt: run.startedAt
            ) else {
                detailErrorMessage = "探索ログを取得できませんでした。データが存在しません。"
                return nil
            }
            enrichedRuns[snapshot.id] = snapshot
            return snapshot
        } catch {
            detailErrorMessage = "探索ログの取得に失敗しました: \(error.localizedDescription)"
            return nil
        }
    }

    private func needsDetailFetch(_ run: CachedExploration) -> Bool {
        run.encounterLogs.isEmpty && run.status != .running
    }

    @ViewBuilder
    private func statusBanner(text: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
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

// MARK: - Run Summary View

private struct ExplorationRunSummaryView: View {
    let snapshot: CachedExploration
    let party: CachedParty

    @Environment(\.dismiss) private var dismiss
    @State private var selectedEncounter: CachedExploration.EncounterLog?
    @State private var showingResultSummary = false

    private var eventsByFloor: [(floor: Int, events: [CachedExploration.EncounterLog])] {
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
