// ==============================================================================
// RuntimePartyDetailView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - パーティの詳細情報と探索開始・管理機能を提供
//
// 【View構成】
//   - パーティスロットカード（メンバー表示・ボーナス情報・出撃ボタン）
//   - パーティスキル一覧への導線
//   - メンバー変更画面への導線
//   - 装備アイテム一覧への導線
//   - パーティ名変更への導線
//   - 出撃先迷宮選択（DungeonPickerView）
//   - 難易度選択（DifficultyPickerMenu）
//   - 目標階層選択（TargetFloorPickerMenu）
//
// 【使用箇所】
//   - パーティ一覧画面からナビゲーション
//
// ==============================================================================

import SwiftUI

struct RuntimePartyDetailView: View {
    @State private var currentParty: CachedParty
    @Binding private var selectedDungeon: CachedDungeonProgress?
    let dungeons: [CachedDungeonProgress]

    @Environment(PartyViewState.self) private var partyState
    @Environment(AdventureViewState.self) private var adventureState
    @Environment(AppServices.self) private var appServices

    @State private var allCharacters: [CachedCharacter] = []
    @State private var errorMessage: String?
    @State private var showDungeonPicker = false
    @State private var targetFloorSelection: Int
    @State private var selectedCharacter: CachedCharacter?

    init(party: CachedParty, selectedDungeon: Binding<CachedDungeonProgress?>, dungeons: [CachedDungeonProgress]) {
        _currentParty = State(initialValue: party)
        _selectedDungeon = selectedDungeon
        _targetFloorSelection = State(initialValue: Int(party.targetFloor))
        self.dungeons = dungeons
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PartySlotCardView(
                        party: currentParty,
                        members: membersOfCurrentParty,
                        bonuses: PartyDropBonuses(members: membersOfCurrentParty),
                        isExploring: adventureState.isExploring(partyId: currentParty.id),
                        canStartExploration: canStartExploration(for: currentParty),
                        onPrimaryAction: {
                            handlePrimaryAction(isExploring: adventureState.isExploring(partyId: currentParty.id),
                                                canDepart: canStartExploration(for: currentParty))
                        },
                        onMemberTap: { character in
                            selectedCharacter = character
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
                        Task { await refreshCachedParty() }
                    }
                } label: {
                    Text("メンバーを変更する (6名まで)")
                        .foregroundColor(.primary)
                        .frame(height: listRowHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(adventureState.isExploring(partyId: currentParty.id))

                NavigationLink {
                    PartyEquipmentListView(memberIds: currentParty.memberIds)
                } label: {
                    Text("装備アイテムの一覧")
                        .foregroundColor(.primary)
                        .frame(height: listRowHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                NavigationLink {
                    PartyNameEditorView(party: currentParty) {
                        await refreshCachedParty()
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
                    Button(action: { Task { await openDungeonPicker() } }) {
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
                        let displayedDifficulty = min(currentParty.lastSelectedDifficulty, dungeon.highestUnlockedDifficulty)
                        DifficultyPickerMenu(dungeon: dungeon,
                                             currentDifficulty: displayedDifficulty,
                                             onSelect: { await updateDifficultySelection($0) },
                                             rowHeight: listRowHeight)
                        .disabled(dungeon.availableDifficulties.count <= 1)
                    }

                    TargetFloorPickerMenu(selection: $targetFloorSelection,
                                          maxFloor: selectedDungeon?.floorCount ?? 1,
                                          rowHeight: listRowHeight)
                }
            }
            .listStyle(.insetGrouped)
            .avoidBottomGameInfo()
            .navigationTitle("パーティ詳細")
            .navigationBarTitleDisplayMode(.inline)
            .overlay { if let errorMessage { errorView(errorMessage) } }
            .task { await refreshData() }
            .onChange(of: currentParty.targetFloor) { _, newValue in
                let updatedValue = Int(newValue)
                if targetFloorSelection != updatedValue {
                    targetFloorSelection = updatedValue
                }
            }
            .onChange(of: targetFloorSelection) { _, newValue in
                if Int(currentParty.targetFloor) != newValue {
                    Task { await updateTargetFloor(newValue) }
                }
            }
            .sheet(isPresented: $showDungeonPicker) {
                DungeonPickerView(
                    dungeons: adventureState.dungeons,
                    currentSelection: selectedDungeon?.dungeonId ?? currentParty.lastSelectedDungeonId,
                    currentDifficulty: currentParty.lastSelectedDifficulty,
                    onSelectDungeon: { dungeon in
                        await updateDungeonSelection(dungeonId: dungeon.dungeonId)
                    },
                    onSelectDifficulty: { dungeon, difficulty in
                        await updateDifficultySelectionFromDungeonPicker(dungeon: dungeon, difficulty: difficulty)
                    }
                )
            }
            .sheet(isPresented: isCharacterDetailPresented) {
                if let character = selectedCharacter {
                    CachedCharacterDetailSheetView(character: character)
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            StatChangeNotificationView()
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    private var partyService: PartyProgressService { appServices.party }

    private var membersOfCurrentParty: [CachedCharacter] {
        currentParty.memberIds.compactMap { memberId in
            allCharacters.first { $0.id == memberId }
        }
    }

    private var activeDungeon: CachedDungeonProgress? {
        selectedDungeon ?? dungeons.first { $0.dungeonId == currentParty.lastSelectedDungeonId }
    }

    private var selectedDungeonName: String {
        if let dungeon = activeDungeon {
            let clampedDifficulty = min(currentParty.lastSelectedDifficulty, dungeon.highestUnlockedDifficulty)
            return formattedDifficultyLabel(for: dungeon, difficulty: clampedDifficulty, masterData: appServices.masterDataCache)
        }
        return "未選択"
    }

    private var listRowHeight: CGFloat? {
        let value = AppConstants.UI.listRowHeight
        return value > 0 ? value : nil
    }

    private var isCharacterDetailPresented: Binding<Bool> {
        Binding(
            get: { selectedCharacter != nil },
            set: { isPresented in
                if !isPresented { selectedCharacter = nil }
            }
        )
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

    // MARK: - Dungeon Picker

    @MainActor
    private func openDungeonPicker() async {
        await adventureState.reloadDungeonList(using: appServices)
        showDungeonPicker = true
    }

    // MARK: - Data Refresh

    @MainActor
    private func refreshData() async {
        errorMessage = nil
        do {
            // パーティメンバーのHP全回復（HP > 0 のキャラクターのみ）
            try await appServices.character.healToFull(characterIds: currentParty.memberIds)
            // HP変更後にキャッシュを無効化
            appServices.userDataLoad.invalidateCharacters()
            try await loadAllCharacters()
            await refreshCachedParty()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadAllCharacters() async throws {
        allCharacters = try await appServices.userDataLoad.getCharacters()
    }

    @MainActor
    private func refreshCachedParty() async {
        do {
            try await partyState.refresh()
            if let updated = partyState.parties.first(where: { $0.id == currentParty.id }) {
                currentParty = updated
                if let dungeon = dungeons.first(where: { $0.dungeonId == updated.lastSelectedDungeonId }) {
                    selectedDungeon = dungeon
                } else {
                    selectedDungeon = nil
                }
                if let dungeon = selectedDungeon,
                   updated.lastSelectedDifficulty > dungeon.highestUnlockedDifficulty {
                    do {
                        _ = try await partyService.setLastSelectedDifficulty(persistentIdentifier: updated.persistentIdentifier,
                                                                              difficulty: dungeon.highestUnlockedDifficulty)
                        try await partyState.refresh()
                        if let adjusted = partyState.parties.first(where: { $0.id == updated.id }) {
                            currentParty = adjusted
                            selectedDungeon = dungeons.first(where: { $0.dungeonId == adjusted.lastSelectedDungeonId })
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
            Task { await adventureState.cancelExploration(for: currentParty, using: appServices) }
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
            try await adventureState.startExploration(party: currentParty, dungeon: dungeon, using: appServices)
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func canStartExploration(for party: CachedParty) -> Bool {
        guard let dungeon = activeDungeon else { return false }
        guard dungeon.isUnlocked else { return false }
        guard party.lastSelectedDifficulty <= dungeon.highestUnlockedDifficulty else { return false }
        guard !membersOfCurrentParty.isEmpty else { return false }
        return !adventureState.isExploring(partyId: party.id)
    }

    // MARK: - Mutations

    private func updateDungeonSelection(dungeonId: UInt16) async -> Bool {
        do {
            _ = try await partyService.setLastSelectedDungeon(persistentIdentifier: currentParty.persistentIdentifier, dungeonId: dungeonId)
            await refreshCachedParty()
            return true
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
            return false
        }
    }

    private func updateTargetFloor(_ floor: Int) async {
        do {
            _ = try await partyService.setTargetFloor(persistentIdentifier: currentParty.persistentIdentifier, floor: UInt8(floor))
            await refreshCachedParty()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func updateDifficultySelection(_ difficulty: UInt8) async -> Bool {
        do {
            _ = try await partyService.setLastSelectedDifficulty(persistentIdentifier: currentParty.persistentIdentifier,
                                                                 difficulty: difficulty)
            await refreshCachedParty()
            return true
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
            return false
        }
    }

    private func updateDifficultySelectionFromDungeonPicker(dungeon: CachedDungeonProgress, difficulty: UInt8) async -> Bool {
        let success = await updateDifficultySelection(difficulty)
        return success
    }

}

private struct PartySkillsListView: View {
    let characters: [CachedCharacter]

    var body: some View {
        List {
            if characters.isEmpty {
                Text("メンバーがいません").foregroundColor(.secondary)
            } else {
                ForEach(characters) { character in
                    Section(character.name) {
                        let skills = character.learnedSkills
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
    let memberIds: [UInt8]
    @Environment(AppServices.self) private var appServices
    @State private var characters: [CachedCharacter] = []

    var body: some View {
        List {
            if characters.isEmpty {
                Text("メンバーがいません").foregroundColor(.secondary)
            } else {
                ForEach(characters, id: \.id) { character in
                    Section {
                        NavigationLink {
                            EquipmentEditorView(character: character)
                                .environment(appServices)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                CharacterImageView(avatarIndex: character.resolvedAvatarId, size: 44)
                                VStack(alignment: .leading, spacing: 4) {
                                    let equipment = character.equippedItems
                                    if equipment.isEmpty {
                                        Text("装備なし").foregroundColor(.secondary)
                                    } else {
                                        ForEach(equipment, id: \.stackKey) { item in
                                            let displayText = item.quantity > 1 ? "\(item.displayName) x\(item.quantity)" : item.displayName
                                            Text(displayText)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } header: {
                        HStack(spacing: 0) {
                            Text(character.name)
                                .fontWeight(.bold)
                            Text(characterSubHeaderText(for: character))
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .avoidBottomGameInfo()
        .navigationTitle("装備一覧")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCharacters() }
        .onAppear { Task { await loadCharacters() } }
    }

    @MainActor
    private func loadCharacters() async {
        do {
            let allCharacters = try await appServices.userDataLoad.getCharacters()
            characters = memberIds.compactMap { memberId in
                allCharacters.first { $0.id == memberId }
            }
        } catch {
            characters = []
        }
    }


    private func slotUsageText(for character: CachedCharacter) -> String {
        let usedSlots = character.equippedItems.reduce(into: 0) { result, item in
            result += max(0, item.quantity)
        }
        return "装備 \(usedSlots)/\(character.equipmentCapacity)"
    }

    private func characterSubHeaderText(for character: CachedCharacter) -> String {
        let masterData = appServices.masterDataCache
        let raceName = masterData.race(character.raceId)?.name ?? ""
        let jobName = masterData.job(character.jobId)?.name ?? ""
        let jobText: String
        if character.previousJobId > 0,
           let previousJobName = masterData.job(character.previousJobId)?.name {
            jobText = "\(jobName)（\(previousJobName)）"
        } else {
            jobText = jobName
        }
        return "　Lv\(character.level) / \(raceName) / \(jobText)"
    }
}

// MARK: - Inline Selection Menus

private struct DifficultyPickerMenu: View {
    @Environment(AppServices.self) private var appServices
    let dungeon: CachedDungeonProgress
    let currentDifficulty: UInt8
    let onSelect: (UInt8) async -> Bool
    let rowHeight: CGFloat?

    var body: some View {
        HStack {
            Text("探索難易度")
                .foregroundColor(.primary)
            Spacer(minLength: 12)
            Menu {
                ForEach(dungeon.availableDifficulties, id: \.self) { difficulty in
                    Button {
                        select(difficulty)
                    } label: {
                        HStack {
                            if currentDifficulty == difficulty {
                                Image(systemName: "checkmark")
                            }
                            Text(formattedDifficultyLabel(for: dungeon, difficulty: difficulty, masterData: appServices.masterDataCache))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(formattedDifficultyLabel(for: dungeon, difficulty: currentDifficulty, masterData: appServices.masterDataCache))
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

    private func select(_ difficulty: UInt8) {
        Task { _ = await onSelect(difficulty) }
    }
}

private struct TargetFloorPickerMenu: View {
    @Binding var selection: Int
    let maxFloor: Int
    let rowHeight: CGFloat?

    var body: some View {
        Picker(selection: $selection) {
            ForEach(floorRange, id: \.self) { floor in
                Text(floorDisplayName(floor)).tag(floor)
            }
        } label: {
            Text("目標階層")
                .foregroundColor(.primary)
        }
        .pickerStyle(.menu)
        .tint(Color(.secondaryLabel))
        .frame(height: rowHeight)
    }

    private var floorRange: [Int] { targetFloorRange(maxFloor: maxFloor) }
}


// MARK: - Sheet Components

private struct DungeonPickerView: View {
    @Environment(AppServices.self) private var appServices
    let dungeons: [CachedDungeonProgress]
    let currentSelection: UInt16?
    let currentDifficulty: UInt8
    let onSelectDungeon: (CachedDungeonProgress) async -> Bool
    let onSelectDifficulty: (CachedDungeonProgress, UInt8) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDungeonForDifficulty: CachedDungeonProgress?

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
                                        Text(formattedDifficultyLabel(for: dungeon, difficulty: dungeon.highestUnlockedDifficulty, masterData: appServices.masterDataCache))
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
                    onSelect: { difficulty in
                        await selectDifficulty(for: dungeon, difficulty: difficulty)
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

    private var groupedDungeons: [Int: [CachedDungeonProgress]] {
        Dictionary(grouping: dungeons) { $0.chapter }
    }

    private func chapterTitle(_ chapter: Int) -> String {
        chapter == 0 ? "バベルの塔" : "第\(chapter)章"
    }

    private func currentDifficulty(for dungeon: CachedDungeonProgress) -> UInt8 {
        if currentSelection == dungeon.dungeonId {
            return currentDifficulty
        }
        return min(currentDifficulty, dungeon.highestUnlockedDifficulty)
    }

    private func handleDungeonTap(_ dungeon: CachedDungeonProgress) {
        Task {
            let success = await onSelectDungeon(dungeon)
            if success {
                await MainActor.run {
                    selectedDungeonForDifficulty = dungeon
                }
            }
        }
    }

    private func selectDifficulty(for dungeon: CachedDungeonProgress, difficulty: UInt8) async -> Bool {
        let success = await onSelectDifficulty(dungeon, difficulty)
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
    let dungeon: CachedDungeonProgress
    let currentDifficulty: UInt8
    let onSelect: (UInt8) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var appServices

    var body: some View {
        List {
            ForEach(dungeon.availableDifficulties, id: \.self) { difficulty in
                Button(action: { choose(difficulty) }) {
                    HStack {
                        Text(formattedDifficultyLabel(for: dungeon, difficulty: difficulty, masterData: appServices.masterDataCache))
                            .foregroundColor(.primary)
                        Spacer()
                        if currentDifficulty == difficulty {
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

    private func choose(_ difficulty: UInt8) {
        Task {
            let success = await onSelect(difficulty)
            if success {
                dismiss()
            }
        }
    }
}

private struct PartyNameEditorView: View {
    let party: CachedParty
    let onComplete: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var appServices
    @State private var name: String = ""
    @State private var showError = false
    @State private var errorMessage = ""

    private var partyService: PartyProgressService { appServices.party }

    var body: some View {
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

private func formattedDifficultyLabel(for dungeon: CachedDungeonProgress, difficulty: UInt8, masterData: MasterDataCache) -> String {
    // 難易度プレフィックスを取得
    var name = dungeon.name
    if let prefix = DungeonDisplayNameFormatter.difficultyPrefix(for: difficulty, masterData: masterData) {
        name = "\(prefix)\(name)"
    }
    let status = dungeon.statusDescription(for: difficulty)
    return "\(name)\(status)"
}

private func targetFloorRange(maxFloor: Int) -> [Int] {
    let upperBound = max(1, maxFloor)
    return [0] + Array(1...upperBound)
}

private func floorDisplayName(_ floor: Int) -> String {
    floor == 0 ? "どこまでも進む" : "\(floor)階"
}
