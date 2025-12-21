// ==============================================================================
// AdventureView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - パーティ一覧の表示とダンジョン探索の管理
//   - 各パーティの探索開始・停止・進捗表示
//   - 一斉出撃による複数パーティの同時探索開始
//
// 【View構成】
//   - パーティごとにカード形式で表示（編成・装備・探索状況）
//   - ダンジョン選択用のシート表示
//   - 探索ログの確認機能
//
// 【使用箇所】
//   - MainTabView（冒険タブ）
//
// ==============================================================================

import SwiftUI

struct AdventureView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(PartyViewState.self) private var partyState
    @State private var adventureState = AdventureViewState()
    @State private var characterState = CharacterViewState()

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isBulkDepartureInProgress = false
    @State private var didLoadOnce = false

    @State private var partyDetailContext: PartyDetailContext?
    @State private var logsContext: PartySnapshot?

    private var parties: [PartySnapshot] {
        partyState.parties.sorted { $0.id < $1.id }
    }

    private var massDepartureCandidates: [PartySnapshot] {
        parties.filter { canStartExploration(for: $0) }
    }

    private var canMassDepart: Bool {
        !massDepartureCandidates.isEmpty && !isBulkDepartureInProgress
    }

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    errorState(message: errorMessage)
                } else if isLoading && parties.isEmpty {
                    loadingState
                } else {
                    contentList
                }
            }
            .navigationTitle("冒険")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button("一斉出撃") {
                        Task { await startAllExplorations() }
                    }
                    .disabled(!canMassDepart)
                }
            }
            .onAppear { Task { await loadOnce() } }
            .onReceive(NotificationCenter.default.publisher(for: .progressUnlocksDidChange)) { _ in
                Task { await adventureState.reloadDungeonList(using: appServices) }
            }
            .sheet(item: $partyDetailContext, onDismiss: { Task { await reload() } }) { context in
                RuntimePartyDetailView(
                    party: context.party,
                    selectedDungeon: Binding(
                        get: { partyDetailContext?.selectedDungeon },
                        set: { newValue in
                            if var current = partyDetailContext {
                                current.selectedDungeon = newValue
                                partyDetailContext = current
                            }
                        }
                    ),
                    dungeons: adventureState.runtimeDungeons
                )
                .environment(adventureState)
            }
            .sheet(item: $logsContext) { party in
                let runs = adventureState.explorationProgress
                    .filter { $0.party.partyId == party.id }
                RecentExplorationLogsView(party: party, runs: runs)
            }
        }
        .onAppear {
            characterState.startObservingChanges(using: appServices)
        }
    }

    private var contentList: some View {
        List {
            ForEach(Array(parties.enumerated()), id: \.element.id) { index, party in
                partySection(for: party, index: index)
                    .id(party.id)
            }
        }
        .listStyle(.insetGrouped)
        .avoidBottomGameInfo()
    }

    @ViewBuilder
    private func partySection(for party: PartySnapshot, index: Int) -> some View {
        let members = runtimeMembers(for: party)
        let bonuses = PartySlotBonuses(members: members)
        let runs = adventureState.explorationProgress
            .filter { $0.party.partyId == party.id }

        Section {
            PartySlotCardView(
                party: party,
                members: members,
                bonuses: bonuses,
                isExploring: adventureState.isExploring(partyId: party.id),
                canStartExploration: canStartExploration(for: party),
                onPrimaryAction: {
                    if adventureState.isExploring(partyId: party.id) {
                        Task { await adventureState.cancelExploration(for: party, using: appServices) }
                    } else {
                        selectParty(party)
                        handleDeparture(for: party)
                    }
                },
                onMembersTap: {
                    adventureState.selectParty(at: index)
                    showPartyDetail(for: party)
                },
                footer: {
                    RecentExplorationLogsView(party: party, runs: runs)
                }
            )
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
        .contentMargins(.vertical, 8)
    }

    private func handleDeparture(for party: PartySnapshot) {
        if selectedDungeon(for: party) == nil {
            showPartyDetail(for: party)
            return
        }
        Task { _ = await startExploration(for: party) }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("パーティ情報を読み込み中…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 44))
                .foregroundColor(.primary)
            Text("冒険情報の取得に失敗しました")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("再試行") {
                Task { await reload() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func loadOnce() async {
        if didLoadOnce { return }
        await loadInitial()
        didLoadOnce = true
    }

    private func loadInitial() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        adventureState.setPartyState(partyState)
        do {
            try await partyState.loadAllParties()
            try await characterState.loadAllCharacters(using: appServices)
            try await characterState.loadCharacterSummaries(using: appServices)
            await adventureState.loadInitialData(using: appServices)
            await adventureState.ensurePartySlots(using: appServices)
            try await partyState.loadAllParties()
            if !parties.isEmpty {
                adventureState.selectParty(at: min(adventureState.selectedPartyIndex, parties.count - 1))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func reload() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        do {
            try await partyState.refresh()
            try await characterState.loadAllCharacters(using: appServices)
            try await characterState.loadCharacterSummaries(using: appServices)
            await adventureState.refreshAll(using: appServices)
            try await partyState.loadAllParties()
            if !parties.isEmpty {
                adventureState.selectParty(at: min(adventureState.selectedPartyIndex, parties.count - 1))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func runtimeMembers(for party: PartySnapshot) -> [RuntimeCharacter] {
        let map = Dictionary(uniqueKeysWithValues: characterState.allCharacters.map { ($0.id, $0) })
        return party.memberIds.compactMap { map[$0] }
    }

    private func selectedDungeon(for party: PartySnapshot) -> RuntimeDungeon? {
        guard let dungeonId = party.lastSelectedDungeonId else { return nil }
        return adventureState.runtimeDungeons.first { $0.definition.id == dungeonId }
    }

    private func canStartExploration(for party: PartySnapshot) -> Bool {
        guard let dungeon = selectedDungeon(for: party) else { return false }
        guard dungeon.isUnlocked else { return false }
        guard party.lastSelectedDifficulty <= dungeon.highestUnlockedDifficulty else { return false }
        guard !runtimeMembers(for: party).isEmpty else { return false }
        return !adventureState.isExploring(partyId: party.id)
    }

    @MainActor
    private func startExploration(for party: PartySnapshot) async -> Bool {
        errorMessage = nil
        guard let dungeon = selectedDungeon(for: party) else {
            errorMessage = "ダンジョンを選択してください"
            return false
        }
        do {
            try await adventureState.startExploration(party: party, dungeon: dungeon, using: appServices)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func selectParty(_ party: PartySnapshot) {
        if let idx = parties.firstIndex(where: { $0.id == party.id }) {
            adventureState.selectParty(at: idx)
        }
    }

    private func showPartyDetail(for party: PartySnapshot) {
        let selected = selectedDungeon(for: party)
        partyDetailContext = PartyDetailContext(party: party, selectedDungeon: selected)
    }

    @MainActor
    private func startAllExplorations() async {
        if isBulkDepartureInProgress { return }
        isBulkDepartureInProgress = true
        defer { isBulkDepartureInProgress = false }

        errorMessage = nil
        var failures: [String] = []
        for party in massDepartureCandidates {
            let success = await startExploration(for: party)
            if !success {
                failures.append(party.name)
            }
        }

        if !failures.isEmpty {
            errorMessage = failures.joined(separator: ", ") + " の探索開始に失敗しました"
        }
    }
}

private struct PartyDetailContext: Identifiable {
    var party: PartySnapshot
    var selectedDungeon: RuntimeDungeon?
    var id: UInt8 { party.id }
}
