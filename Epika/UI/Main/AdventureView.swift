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
    @State private var logsPartyId: UInt8?
    @State private var repeatSettingsByPartyId: [UInt8: RepeatDepartureSettings] = [:]
    @State private var bulkRepeatSettings: RepeatDepartureSettings?

    private var parties: [CachedParty] {
        partyState.parties.sorted { $0.id < $1.id }
    }

    private var massDepartureCandidates: [CachedParty] {
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
                    .contextMenu { bulkDepartureMenu }
                }
            }
            .onAppear { Task { await loadOnce() } }
            .onReceive(NotificationCenter.default.publisher(for: .progressUnlocksDidChange)) { _ in
                Task { await adventureState.reloadDungeonList(using: appServices) }
            }
            .sheet(item: $partyDetailContext, onDismiss: { Task { await reload() } }) { context in
                RuntimePartyDetailView(
                    partyId: context.partyId,
                    initialTargetFloor: context.initialTargetFloor,
                    initialLastSelectedDungeonId: context.initialLastSelectedDungeonId,
                    initialLastSelectedDifficulty: context.initialLastSelectedDifficulty,
                    selectedDungeonId: partyDetailSelectedDungeonBinding,
                    dungeons: adventureState.dungeons
                )
                .environment(adventureState)
                .environment(appServices.statChangeNotifications)
            }
            .sheet(item: logsPartySheetItem) { party in
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
    private func partySection(for party: CachedParty, index: Int) -> some View {
        let members = runtimeMembers(for: party)
        let memberSummaries = members.map { PartyMemberSummary(character: $0) }
        let bonuses = PartyDropBonuses(members: members)
        let runs = adventureState.explorationProgress
            .filter { $0.party.partyId == party.id }

        Section {
            PartySlotCardView(
                party: party,
                members: memberSummaries,
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
                primaryActionMenu: {
                    AnyView(repeatDepartureMenu(for: party))
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

    private func handleDeparture(for party: CachedParty) {
        if selectedDungeon(for: party) == nil {
            showPartyDetail(for: party)
            return
        }
        let settings = repeatSettingsByPartyId[party.id]
        Task { _ = await startExploration(for: party, settings: settings) }
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

    private func runtimeMembers(for party: CachedParty) -> [CachedCharacter] {
        appServices.userDataLoad.cachedCharacters(for: party.memberIds)
    }

    private func selectedDungeon(for party: CachedParty) -> CachedDungeonProgress? {
        guard let dungeonId = party.lastSelectedDungeonId else { return nil }
        return adventureState.dungeons.first { $0.dungeonId == dungeonId }
    }

    private func canStartExploration(for party: CachedParty) -> Bool {
        guard let dungeon = selectedDungeon(for: party) else { return false }
        guard dungeon.isUnlocked else { return false }
        guard party.lastSelectedDifficulty <= dungeon.highestUnlockedDifficulty else { return false }
        guard !runtimeMembers(for: party).isEmpty else { return false }
        return !adventureState.isExploring(partyId: party.id)
    }

    @MainActor
    private func startExploration(for party: CachedParty,
                                  settings: RepeatDepartureSettings?) async -> Bool {
        errorMessage = nil
        guard let dungeon = selectedDungeon(for: party) else {
            errorMessage = "ダンジョンを選択してください"
            return false
        }
        let repeatCount = settings?.repeatCount ?? 1
        let isImmediateReturn = settings?.isImmediateReturn ?? false
        do {
            try await adventureState.startExploration(party: party,
                                                      dungeon: dungeon,
                                                      repeatCount: repeatCount,
                                                      isImmediateReturn: isImmediateReturn,
                                                      using: appServices)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func selectParty(_ party: CachedParty) {
        if let partyIndex = parties.firstIndex(where: { $0.id == party.id }) {
            adventureState.selectParty(at: partyIndex)
        }
    }

    private func showPartyDetail(for party: CachedParty) {
        let selected = selectedDungeon(for: party)
        partyDetailContext = PartyDetailContext(partyId: party.id,
                                                initialTargetFloor: party.targetFloor,
                                                initialLastSelectedDungeonId: party.lastSelectedDungeonId,
                                                initialLastSelectedDifficulty: party.lastSelectedDifficulty,
                                                selectedDungeonId: selected?.dungeonId)
    }

    private func repeatSettings(for partyId: UInt8) -> RepeatDepartureSettings {
        repeatSettingsByPartyId[partyId] ?? RepeatDepartureSettings.defaultSettings
    }

    private func updateRepeatSettings(for partyId: UInt8,
                                      repeatCount: Int? = nil,
                                      isImmediateReturn: Bool? = nil) {
        let current = repeatSettings(for: partyId)
        let updated = RepeatDepartureSettings(repeatCount: repeatCount ?? current.repeatCount,
                                              isImmediateReturn: isImmediateReturn ?? current.isImmediateReturn)
        repeatSettingsByPartyId[partyId] = updated
    }

    private func updateBulkRepeatSettings(repeatCount: Int? = nil,
                                          isImmediateReturn: Bool? = nil) {
        let current = bulkRepeatSettings ?? RepeatDepartureSettings.defaultSettings
        let updated = RepeatDepartureSettings(repeatCount: repeatCount ?? current.repeatCount,
                                              isImmediateReturn: isImmediateReturn ?? current.isImmediateReturn)
        bulkRepeatSettings = updated
    }

    private var logsPartySheetItem: Binding<CachedParty?> {
        Binding(
            get: {
                guard let logsPartyId else { return nil }
                return parties.first { $0.id == logsPartyId }
            },
            set: { newValue in
                logsPartyId = newValue?.id
            }
        )
    }

    private var partyDetailSelectedDungeonBinding: Binding<UInt16?> {
        Binding(
            get: { partyDetailContext?.selectedDungeonId },
            set: { newValue in
                updatePartyDetailContext { $0.selectedDungeonId = newValue }
            }
        )
    }

    private func updatePartyDetailContext(_ update: (inout PartyDetailContext) -> Void) {
        guard var current = partyDetailContext else { return }
        update(&current)
        partyDetailContext = current
    }

    @ViewBuilder
    private func repeatDepartureMenu(for party: CachedParty) -> some View {
        let settings = repeatSettings(for: party.id)
        Menu("出撃回数") {
            ForEach(Array(RepeatDepartureSettings.repeatCountRange), id: \.self) { value in
                Button {
                    updateRepeatSettings(for: party.id, repeatCount: value)
                } label: {
                    if value == settings.repeatCount {
                        Label("\(value)回", systemImage: "checkmark")
                    } else {
                        Text("\(value)回")
                    }
                }
            }
        }

        Button {
            updateRepeatSettings(for: party.id, isImmediateReturn: !settings.isImmediateReturn)
        } label: {
            if settings.isImmediateReturn {
                Label("即時帰還", systemImage: "checkmark")
            } else {
                Text("即時帰還")
            }
        }

        Button("この設定で出撃") {
            updateRepeatSettings(for: party.id,
                                 repeatCount: settings.repeatCount,
                                 isImmediateReturn: settings.isImmediateReturn)
            selectParty(party)
            handleDeparture(for: party)
        }
        .disabled(!canStartExploration(for: party) || adventureState.isExploring(partyId: party.id))
    }

    @ViewBuilder
    private var bulkDepartureMenu: some View {
        let settings = bulkRepeatSettings ?? RepeatDepartureSettings.defaultSettings
        Menu("出撃回数") {
            ForEach(Array(RepeatDepartureSettings.repeatCountRange), id: \.self) { value in
                Button {
                    updateBulkRepeatSettings(repeatCount: value)
                } label: {
                    if value == settings.repeatCount {
                        Label("\(value)回", systemImage: "checkmark")
                    } else {
                        Text("\(value)回")
                    }
                }
            }
        }

        Button {
            updateBulkRepeatSettings(isImmediateReturn: !settings.isImmediateReturn)
        } label: {
            if settings.isImmediateReturn {
                Label("即時帰還", systemImage: "checkmark")
            } else {
                Text("即時帰還")
            }
        }

        Button("この設定で一斉出撃") {
            updateBulkRepeatSettings(repeatCount: settings.repeatCount,
                                     isImmediateReturn: settings.isImmediateReturn)
            Task { await startAllExplorations() }
        }
        .disabled(!canMassDepart)
    }

    @MainActor
    private func startAllExplorations() async {
        if isBulkDepartureInProgress { return }
        isBulkDepartureInProgress = true
        defer { isBulkDepartureInProgress = false }

        errorMessage = nil

        // パーティとダンジョンのペアを作成
        let batchParams: [AdventureViewState.BatchStartParams] = massDepartureCandidates.compactMap { party in
            guard let dungeon = selectedDungeon(for: party) else { return nil }
            return AdventureViewState.BatchStartParams(party: party, dungeon: dungeon)
        }

        guard !batchParams.isEmpty else { return }

        let settings = bulkRepeatSettings ?? RepeatDepartureSettings.defaultSettings
        do {
            let failures = try await adventureState.startExplorationsInBatch(batchParams,
                                                                             repeatCount: settings.repeatCount,
                                                                             isImmediateReturn: settings.isImmediateReturn,
                                                                             using: appServices)
            if !failures.isEmpty {
                errorMessage = failures.joined(separator: ", ") + " の探索開始に失敗しました"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}

private struct PartyDetailContext: Identifiable {
    var partyId: UInt8
    var initialTargetFloor: UInt8
    var initialLastSelectedDungeonId: UInt16?
    var initialLastSelectedDifficulty: UInt8
    var selectedDungeonId: UInt16?

    var id: UInt8 { partyId }
}

private struct RepeatDepartureSettings: Hashable {
    let repeatCount: Int
    let isImmediateReturn: Bool

    static let repeatCountRange = 1...100
    static let defaultSettings = RepeatDepartureSettings(repeatCount: 1, isImmediateReturn: false)
}
