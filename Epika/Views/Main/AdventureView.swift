import SwiftUI

struct AdventureView: View {
    @EnvironmentObject private var progressService: ProgressService
    @Environment(PartyViewState.self) private var partyState
    @State private var adventureState = AdventureViewState()
    @State private var characterState = CharacterViewState()

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isBulkDepartureInProgress = false
    @State private var didLoadOnce = false

    @State private var partyDetailContext: PartyDetailContext?
    @State private var logsContext: RuntimeParty?

    private var parties: [RuntimeParty] {
        partyState.parties.sorted { $0.id < $1.id }
    }

    private var massDepartureCandidates: [RuntimeParty] {
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
            .refreshable { await reload() }
            .sheet(item: $partyDetailContext, onDismiss: { Task { await reload() } }) { context in
                NavigationStack {
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
            }
            .sheet(item: $logsContext) { party in
                NavigationStack {
                    let runs = adventureState.explorationProgress
                        .filter { $0.party.partyId == party.id }
                    RecentExplorationLogsView(party: party, runs: runs)
                }
            }
        }
        .onAppear {
            adventureState.configureIfNeeded(with: progressService)
            characterState.configureIfNeeded(with: progressService)
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
    private func partySection(for party: RuntimeParty, index: Int) -> some View {
        let members = runtimeMembers(for: party)
        let bonuses = partyBonuses(for: members)
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
                        Task { await adventureState.cancelExploration(for: party) }
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

    private func partyBonuses(for members: [RuntimeCharacter]) -> PartySlotBonuses {
        guard !members.isEmpty else { return .zero }
        let luckSum = members.reduce(0) { $0 + $1.baseStats.luck }
        let spiritSum = members.reduce(0) { $0 + $1.baseStats.spirit }
        let gold = clampMultiplier(1.0 + Double(luckSum) * 0.001, limit: 250.0)
        let rare = clampMultiplier(1.0 + Double(luckSum + spiritSum) * 0.0005, limit: 99.9)
        let averageLuck = Double(luckSum) / Double(members.count)
        let title = clampMultiplier(1.0 + averageLuck * 0.002, limit: 99.9)
        let fortune = Int(averageLuck.rounded())
        return PartySlotBonuses(goldMultiplier: gold,
                                rareMultiplier: rare,
                                titleMultiplier: title,
                                fortune: fortune)
    }

    private func clampMultiplier(_ value: Double, limit: Double) -> Double {
        min(max(value, 0.0), limit)
    }

    private func handleDeparture(for party: RuntimeParty) {
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
            try await characterState.loadAllCharacters()
            try await characterState.loadCharacterSummaries()
            await adventureState.loadInitialData()
            await adventureState.ensurePartySlots()
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
            try await characterState.loadAllCharacters()
            try await characterState.loadCharacterSummaries()
            await adventureState.refreshAll()
            try await partyState.loadAllParties()
            if !parties.isEmpty {
                adventureState.selectParty(at: min(adventureState.selectedPartyIndex, parties.count - 1))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func runtimeMembers(for party: RuntimeParty) -> [RuntimeCharacter] {
        let map = Dictionary(uniqueKeysWithValues: characterState.allCharacters.map { ($0.id, $0) })
        return party.memberIds.compactMap { map[$0] }
    }

    private func selectedDungeon(for party: RuntimeParty) -> RuntimeDungeon? {
        guard party.lastSelectedDungeonId > 0 else { return nil }
        return adventureState.runtimeDungeons.first { $0.definition.id == party.lastSelectedDungeonId }
    }

    private func canStartExploration(for party: RuntimeParty) -> Bool {
        guard let dungeon = selectedDungeon(for: party), dungeon.id > 0 else { return false }
        guard dungeon.isUnlocked else { return false }
        guard party.lastSelectedDifficulty <= dungeon.highestUnlockedDifficulty else { return false }
        guard !runtimeMembers(for: party).isEmpty else { return false }
        return !adventureState.isExploring(partyId: party.id)
    }

    @MainActor
    private func startExploration(for party: RuntimeParty) async -> Bool {
        errorMessage = nil
        guard let dungeon = selectedDungeon(for: party) else {
            errorMessage = "ダンジョンを選択してください"
            return false
        }
        do {
            try await adventureState.startExploration(party: party, dungeon: dungeon)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func selectParty(_ party: RuntimeParty) {
        if let idx = parties.firstIndex(where: { $0.id == party.id }) {
            adventureState.selectParty(at: idx)
        }
    }

    private func showPartyDetail(for party: RuntimeParty) {
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
    var party: RuntimeParty
    var selectedDungeon: RuntimeDungeon?
    var id: UInt8 { party.id }
}
