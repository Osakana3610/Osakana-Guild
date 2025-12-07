import SwiftUI

struct RuntimePartyDetailView: View {
    @State private var currentParty: RuntimeParty
    @Binding private var selectedDungeon: RuntimeDungeon?
    let dungeons: [RuntimeDungeon]

    @Environment(PartyViewState.self) private var partyState
    @Environment(AdventureViewState.self) private var adventureState
    @EnvironmentObject private var progressService: ProgressService

    @State private var allCharacters: [RuntimeCharacter] = []
    @State private var errorMessage: String?
    @State private var showDungeonPicker = false

    init(party: RuntimeParty, selectedDungeon: Binding<RuntimeDungeon?>, dungeons: [RuntimeDungeon]) {
        _currentParty = State(initialValue: party)
        _selectedDungeon = selectedDungeon
        self.dungeons = dungeons
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PartySlotCardView(
                        party: currentParty,
                        members: membersOfCurrentParty,
                        bonuses: partyBonuses(for: membersOfCurrentParty),
                        isExploring: adventureState.isExploring(partyId: currentParty.id),
                        canStartExploration: canStartExploration(for: currentParty),
                        onPrimaryAction: {
                            handlePrimaryAction(isExploring: adventureState.isExploring(partyId: currentParty.id),
                                                canDepart: canStartExploration(for: currentParty))
                        }
                    )
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(height: 0.5)
                            .padding(.horizontal, 16)
                    }

                NavigationLink {
                    PartySkillsListView(characters: membersOfCurrentParty)
                } label: {
                    Text("パーティーのスキルを見る")
                        .foregroundColor(.primary)
                        .frame(height: listRowHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                NavigationLink {
                    RuntimePartyMemberEditView(
                        party: currentParty,
                        allCharacters: allCharacters
                    )
                    .onDisappear {
                        Task { await refreshPartySnapshot() }
                    }
                } label: {
                    Text("メンバーを変更する (6名まで)")
                        .foregroundColor(.primary)
                        .frame(height: listRowHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                NavigationLink {
                    PartyEquipmentListView(characters: membersOfCurrentParty)
                } label: {
                    Text("装備アイテムの一覧")
                        .foregroundColor(.primary)
                        .frame(height: listRowHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                NavigationLink {
                    PartyNameEditorView(party: currentParty) {
                        await refreshPartySnapshot()
                    }
                } label: {
                    Text("パーティ名を変更する")
                        .foregroundColor(.primary)
                        .frame(height: listRowHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .contentMargins(.vertical, 8)

                Section("出撃先迷宮") {
                    Button(action: { showDungeonPicker = true }) {
                        HStack {
                            Text(selectedDungeonName)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Color(.tertiaryLabel))
                                .font(.footnote.weight(.semibold))
                        }
                        .frame(height: listRowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if let dungeon = activeDungeon {
                        let displayedDifficulty = min(Int(currentParty.lastSelectedDifficulty), dungeon.highestUnlockedDifficulty)
                        DifficultyPickerMenu(dungeon: dungeon,
                                             currentDifficulty: displayedDifficulty,
                                             onSelect: { await updateDifficultySelection($0) },
                                             rowHeight: listRowHeight)
                        .disabled(dungeon.availableDifficultyRanks.count <= 1)
                    }

                    TargetFloorPickerMenu(currentFloor: Int(currentParty.targetFloor),
                                          maxFloor: selectedDungeon?.definition.floorCount ?? 1,
                                          onSelect: { await updateTargetFloor($0) },
                                          rowHeight: listRowHeight)
                }
            }
            .listStyle(.insetGrouped)
            .avoidBottomGameInfo()
            .navigationTitle("パーティ詳細")
            .navigationBarTitleDisplayMode(.inline)
            .overlay { if let errorMessage { errorView(errorMessage) } }
            .task { await refreshData() }
            .sheet(isPresented: $showDungeonPicker) {
                DungeonPickerView(
                    dungeons: dungeons,
                    currentSelection: selectedDungeon?.definition.id ?? currentParty.lastSelectedDungeonId,
                    currentDifficulty: Int(currentParty.lastSelectedDifficulty),
                    onSelectDungeon: { dungeon in
                        await updateDungeonSelection(dungeonId: dungeon.definition.id)
                    },
                    onSelectDifficulty: { dungeon, difficulty in
                        await updateDifficultySelectionFromDungeonPicker(dungeon: dungeon, difficulty: difficulty)
                    }
                )
            }
        }
    }

    private var partyService: PartyProgressService { progressService.party }

    private var membersOfCurrentParty: [RuntimeCharacter] {
        currentParty.memberIds.compactMap { memberId in
            allCharacters.first { $0.id == memberId }
        }
    }

    private var activeDungeon: RuntimeDungeon? {
        selectedDungeon ?? dungeons.first { $0.definition.id == currentParty.lastSelectedDungeonId }
    }

    private var selectedDungeonName: String {
        if let dungeon = activeDungeon {
            let desiredRank = Int(currentParty.lastSelectedDifficulty)
            let clampedRank = min(desiredRank, dungeon.highestUnlockedDifficulty)
            return formattedDifficultyLabel(for: dungeon, rank: clampedRank)
        }
        return "未選択"
    }

    private var listRowHeight: CGFloat? {
        let value = AppConstants.UI.listRowHeight
        return value > 0 ? value : nil
    }

    private func errorView(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.caption)
                .foregroundColor(.primary)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Data Refresh

    @MainActor
    private func refreshData() async {
        errorMessage = nil
        do {
            try await loadAllCharacters()
            await refreshPartySnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadAllCharacters() async throws {
        let snapshots = try await progressService.character.allCharacters()
        guard !snapshots.isEmpty else {
            allCharacters = []
            return
        }

        var runtimeCharacters: [RuntimeCharacter] = []
        runtimeCharacters.reserveCapacity(snapshots.count)

        for snapshot in snapshots {
            let runtimeCharacter = try await progressService.character.runtimeCharacter(from: snapshot)
            runtimeCharacters.append(runtimeCharacter)
        }

        allCharacters = runtimeCharacters
    }

    @MainActor
    private func refreshPartySnapshot() async {
        do {
            try await partyState.refresh()
            if let updated = partyState.parties.first(where: { $0.id == currentParty.id }) {
                currentParty = updated
                if let dungeon = dungeons.first(where: { $0.definition.id == updated.lastSelectedDungeonId }) {
                    selectedDungeon = dungeon
                } else {
                    selectedDungeon = nil
                }
                if let dungeon = selectedDungeon,
                   Int(updated.lastSelectedDifficulty) > dungeon.highestUnlockedDifficulty {
                    do {
                        _ = try await partyService.setLastSelectedDifficulty(persistentIdentifier: updated.persistentIdentifier,
                                                                              difficulty: UInt8(dungeon.highestUnlockedDifficulty))
                        try await partyState.refresh()
                        if let adjusted = partyState.parties.first(where: { $0.id == updated.id }) {
                            currentParty = adjusted
                            selectedDungeon = dungeons.first(where: { $0.definition.id == adjusted.lastSelectedDungeonId })
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handlePrimaryAction(isExploring: Bool, canDepart: Bool) {
        if isExploring {
            Task { await adventureState.cancelExploration(for: currentParty) }
            return
        }

        guard canDepart else { return }

        Task {
            await startExplorationFromDetail()
        }
    }

    private func startExplorationFromDetail() async {
        guard let dungeon = activeDungeon else {
            await MainActor.run { showDungeonPicker = true }
            return
        }
        do {
            try await adventureState.startExploration(party: currentParty, dungeon: dungeon)
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func canStartExploration(for party: RuntimeParty) -> Bool {
        guard let dungeon = activeDungeon, dungeon.id > 0 else { return false }
        guard dungeon.isUnlocked else { return false }
        guard Int(party.lastSelectedDifficulty) <= dungeon.highestUnlockedDifficulty else { return false }
        guard !membersOfCurrentParty.isEmpty else { return false }
        return !adventureState.isExploring(partyId: party.id)
    }

    // MARK: - Mutations

    private func updateDungeonSelection(dungeonId: UInt16) async -> Bool {
        do {
            _ = try await partyService.setLastSelectedDungeon(persistentIdentifier: currentParty.persistentIdentifier, dungeonId: dungeonId)
            await refreshPartySnapshot()
            return true
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
            return false
        }
    }

    private func updateTargetFloor(_ floor: Int) async {
        do {
            _ = try await partyService.setTargetFloor(persistentIdentifier: currentParty.persistentIdentifier, floor: UInt8(floor))
            await refreshPartySnapshot()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func updateDifficultySelection(_ difficulty: Int) async -> Bool {
        do {
            _ = try await partyService.setLastSelectedDifficulty(persistentIdentifier: currentParty.persistentIdentifier,
                                                                 difficulty: UInt8(difficulty))
            await refreshPartySnapshot()
            return true
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
            return false
        }
    }

    private func updateDifficultySelectionFromDungeonPicker(dungeon: RuntimeDungeon, difficulty: Int) async -> Bool {
        let success = await updateDifficultySelection(difficulty)
        return success
    }

}

private struct PartySkillsListView: View {
    let characters: [RuntimeCharacter]

    var body: some View {
        List {
            if characters.isEmpty {
                Text("メンバーがいません").foregroundColor(.secondary)
            } else {
                ForEach(characters) { character in
                    Section(character.name) {
                        let skills = character.masteredSkills
                        if skills.isEmpty {
                            Text("習得スキルなし").foregroundColor(.secondary)
                        } else {
                            ForEach(skills, id: \.id) { skill in
                                Text(skill.name)
                            }
                        }
                    }
                }
            }
        }
        .avoidBottomGameInfo()
        .navigationTitle("パーティスキル")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PartyEquipmentListView: View {
    let characters: [RuntimeCharacter]

    var body: some View {
        List {
            if characters.isEmpty {
                Text("メンバーがいません").foregroundColor(.secondary)
            } else {
                ForEach(characters, id: \.id) { character in
                    Section(character.name) {
                        let equipment = character.progress.equippedItems
                        if equipment.isEmpty {
                            Text("装備なし").foregroundColor(.secondary)
                        } else {
                            let itemsById = Dictionary(uniqueKeysWithValues: character.loadout.items.map { ($0.id, $0) })
                            ForEach(equipment, id: \.stackKey) { entry in
                                let itemName = itemsById[entry.itemId]?.name ?? "不明なアイテム"
                                if entry.superRareTitleId > 0 || entry.normalTitleId > 0 {
                                    Text("\(itemName) x\(entry.quantity) (称号付き)")
                                } else {
                                    Text("\(itemName) x\(entry.quantity)")
                                }
                            }
                        }
                    }
                }
            }
        }
        .avoidBottomGameInfo()
        .navigationTitle("装備一覧")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Inline Selection Menus

private struct DifficultyPickerMenu: View {
    let dungeon: RuntimeDungeon
    let currentDifficulty: Int
    let onSelect: (Int) async -> Bool
    let rowHeight: CGFloat?

    var body: some View {
        HStack {
            Text("探索難易度")
                .foregroundColor(.primary)
            Spacer(minLength: 12)
            Menu {
                ForEach(dungeon.availableDifficultyRanks, id: \.self) { rank in
                    Button {
                        select(rank)
                    } label: {
                        HStack {
                            if currentDifficulty == rank {
                                Image(systemName: "checkmark")
                            }
                            Text(formattedDifficultyLabel(for: dungeon, rank: rank))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(formattedDifficultyLabel(for: dungeon, rank: currentDifficulty))
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(Color(.tertiaryLabel))
                        .font(.footnote.weight(.semibold))
                }
                .frame(height: rowHeight)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .menuStyle(.automatic)
        }
        .frame(height: rowHeight)
        .contentShape(Rectangle())
    }

    private func select(_ rank: Int) {
        Task { _ = await onSelect(rank) }
    }
}

private struct TargetFloorPickerMenu: View {
    let currentFloor: Int
    let maxFloor: Int
    let onSelect: (Int) async -> Void
    let rowHeight: CGFloat?

    var body: some View {
        HStack {
            Text("目標階層")
                .foregroundColor(.primary)
            Spacer(minLength: 12)
            Menu {
                ForEach(floorRange, id: \.self) { floor in
                    Button {
                        select(floor)
                    } label: {
                        HStack {
                            if currentFloor == floor {
                                Image(systemName: "checkmark")
                            }
                            Text("\(floor)階")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(currentFloor)階")
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(Color(.tertiaryLabel))
                        .font(.footnote.weight(.semibold))
                }
                .frame(height: rowHeight)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .menuStyle(.automatic)
        }
        .frame(height: rowHeight)
        .contentShape(Rectangle())
    }

    private var floorRange: [Int] {
        let upperBound = max(1, maxFloor)
        return Array(1...upperBound)
    }

    private func select(_ floor: Int) {
        Task { await onSelect(floor) }
    }
}

// MARK: - Bonus Calculation Helpers

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

// MARK: - Sheet Components

private struct DungeonPickerView: View {
    let dungeons: [RuntimeDungeon]
    let currentSelection: UInt16
    let currentDifficulty: Int
    let onSelectDungeon: (RuntimeDungeon) async -> Bool
    let onSelectDifficulty: (RuntimeDungeon, Int) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDungeonForDifficulty: RuntimeDungeon?

    var body: some View {
        NavigationStack {
            List {
                if dungeons.isEmpty {
                    Section {
                        Text("解放済みの迷宮がありません")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(groupedDungeons.keys.sorted(), id: \.self) { chapter in
                        Section(chapterTitle(chapter)) {
                            ForEach(groupedDungeons[chapter] ?? [], id: \.id) { dungeon in
                                Button(action: { handleDungeonTap(dungeon) }) {
                                    HStack(spacing: 8) {
                                        Text(formattedDifficultyLabel(for: dungeon, rank: dungeon.highestUnlockedDifficulty))
                                            .foregroundColor(.primary)
                                            .lineLimit(2)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                            }
                        }
                    }
                }
            }
            .avoidBottomGameInfo()
            .navigationTitle("迷宮を選択")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedDungeonForDifficulty) { dungeon in
                DifficultyPickerView(
                    dungeon: dungeon,
                    currentDifficulty: currentDifficulty(for: dungeon),
                    onSelect: { rank in
                        await selectDifficulty(for: dungeon, rank: rank)
                    }
                )
                .onDisappear {
                    if selectedDungeonForDifficulty?.id == dungeon.id {
                        selectedDungeonForDifficulty = nil
                    }
                }
            }
        }
    }

    private var groupedDungeons: [Int: [RuntimeDungeon]] {
        Dictionary(grouping: dungeons) { $0.definition.chapter }
    }

    private func chapterTitle(_ chapter: Int) -> String {
        "第\(chapter)章"
    }

    private func currentDifficulty(for dungeon: RuntimeDungeon) -> Int {
        if currentSelection == dungeon.definition.id {
            return currentDifficulty
        }
        return min(currentDifficulty, dungeon.highestUnlockedDifficulty)
    }

    private func handleDungeonTap(_ dungeon: RuntimeDungeon) {
        Task {
            let success = await onSelectDungeon(dungeon)
            if success {
                await MainActor.run {
                    selectedDungeonForDifficulty = dungeon
                }
            }
        }
    }

    private func selectDifficulty(for dungeon: RuntimeDungeon, rank: Int) async -> Bool {
        let success = await onSelectDifficulty(dungeon, rank)
        if success {
            await MainActor.run {
                selectedDungeonForDifficulty = nil
                dismiss()
            }
        }
        return success
    }
}

private struct DifficultyPickerView: View {
    let dungeon: RuntimeDungeon
    let currentDifficulty: Int
    let onSelect: (Int) async -> Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(dungeon.availableDifficultyRanks, id: \.self) { rank in
                Button(action: { choose(rank) }) {
                    HStack {
                        Text(formattedDifficultyLabel(for: dungeon, rank: rank))
                            .foregroundColor(.primary)
                        Spacer()
                        if currentDifficulty == rank {
                            Image(systemName: "checkmark")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
        }
        .avoidBottomGameInfo()
        .navigationTitle("探索難易度")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choose(_ rank: Int) {
        Task {
            let success = await onSelect(rank)
            if success {
                dismiss()
            }
        }
    }
}

private struct PartyNameEditorView: View {
    let party: RuntimeParty
    let onComplete: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var progressService: ProgressService
    @State private var name: String = ""
    @State private var showError = false
    @State private var errorMessage = ""

    private var partyService: PartyProgressService { progressService.party }

    var body: some View {
        NavigationStack {
            Form {
                Section("パーティ名") {
                    TextField("パーティ名を入力", text: $name)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
            }
            .avoidBottomGameInfo()
            .navigationTitle("パーティ名変更")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == party.name)
                }
            }
            .alert("エラー", isPresented: $showError) {
                Button("OK", role: .cancel) { showError = false }
            } message: {
                Text(errorMessage)
            }
            .onAppear { name = party.name }
        }
    }

    private func save() async {
        do {
            _ = try await partyService.updatePartyName(persistentIdentifier: party.persistentIdentifier, name: name.trimmingCharacters(in: .whitespaces))
            await onComplete()
            dismiss()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

private func formattedDifficultyLabel(for dungeon: RuntimeDungeon, rank: Int) -> String {
    let name = DungeonDisplayNameFormatter.displayName(for: dungeon.definition, difficultyRank: rank)
    let status = dungeon.statusDescription(for: rank)
    return "\(name)\(status)"
}
