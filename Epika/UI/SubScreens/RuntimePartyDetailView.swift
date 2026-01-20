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
    @State private var currentPartyId: UInt8
    @State private var lastSelectedDungeonId: UInt16?
    @State private var lastSelectedDifficulty: UInt8
    @Binding private var selectedDungeonId: UInt16?
    let dungeons: [CachedDungeonProgress]

    @Environment(PartyViewState.self) private var partyState
    @Environment(AdventureViewState.self) private var adventureState
    @Environment(AppServices.self) private var appServices

    @State private var partyMembers: [PartyMemberSummary] = []
    @State private var partyBonuses: PartyDropBonuses = .neutral
    @State private var errorMessage: String?
    @State private var showDungeonPicker = false
    @State private var targetFloorSelection: Int
    @State private var characterDetailContext: CharacterDetailContext?

    init(partyId: UInt8,
         initialTargetFloor: UInt8,
         initialLastSelectedDungeonId: UInt16?,
         initialLastSelectedDifficulty: UInt8,
         selectedDungeonId: Binding<UInt16?>,
         dungeons: [CachedDungeonProgress]) {
        _currentPartyId = State(initialValue: partyId)
        _lastSelectedDungeonId = State(initialValue: initialLastSelectedDungeonId)
        _lastSelectedDifficulty = State(initialValue: initialLastSelectedDifficulty)
        _selectedDungeonId = selectedDungeonId
        _targetFloorSelection = State(initialValue: Int(initialTargetFloor))
        self.dungeons = dungeons
    }

    var body: some View {
        NavigationStack {
            List {
                if let currentParty {
                    Section {
                        PartySlotCardView(
                            party: currentParty,
                            members: partyMembers,
                            bonuses: partyBonuses,
                            isExploring: adventureState.isExploring(partyId: currentParty.id),
                            canStartExploration: canStartExploration(for: currentParty),
                            onPrimaryAction: {
                                handlePrimaryAction(party: currentParty,
                                                    isExploring: adventureState.isExploring(partyId: currentParty.id),
                                                    canDepart: canStartExploration(for: currentParty))
                            },
                            onMemberTap: { memberId in
                                characterDetailContext = CharacterDetailContext(id: memberId)
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
                            PartySkillsListView(memberIds: currentParty.memberIds)
                        } label: {
                            Text("パーティーのスキルを見る")
                                .foregroundColor(.primary)
                                .frame(height: listRowHeight)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        NavigationLink {
                            RuntimePartyMemberEditView(
                                party: currentParty
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
                            PartyNameEditorView(party: currentParty) { completion in
                                Task {
                                    await refreshCachedParty()
                                    await MainActor.run { completion() }
                                }
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
                            let displayedDifficulty = min(resolvedLastSelectedDifficulty, dungeon.highestUnlockedDifficulty)
                            DifficultyPickerMenu(dungeon: dungeon,
                                                 currentDifficulty: displayedDifficulty,
                                                 onSelect: { difficulty in
                                                     Task { _ = await updateDifficultySelection(difficulty) }
                                                 },
                                                 rowHeight: listRowHeight)
                            .disabled(dungeon.availableDifficulties.count <= 1)
                        }

                        TargetFloorPickerMenu(selection: $targetFloorSelection,
                                              maxFloor: activeDungeon?.floorCount ?? 1,
                                              rowHeight: listRowHeight)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .avoidBottomGameInfo()
            .navigationTitle("パーティ詳細")
            .navigationBarTitleDisplayMode(.inline)
            .overlay { if let errorMessage { errorView(errorMessage) } }
            .task { await refreshData() }
            .onChange(of: currentPartyTargetFloor) { _, newValue in
                guard let newValue else { return }
                let updatedValue = Int(newValue)
                if targetFloorSelection != updatedValue {
                    targetFloorSelection = updatedValue
                }
            }
            .onChange(of: targetFloorSelection) { _, newValue in
                guard let currentParty else { return }
                if Int(currentParty.targetFloor) != newValue {
                    Task { await updateTargetFloor(newValue) }
                }
            }
            .sheet(isPresented: $showDungeonPicker) {
                DungeonPickerView(
                    dungeons: adventureState.dungeons,
                    currentSelection: selectedDungeonId ?? resolvedLastSelectedDungeonId,
                    currentDifficulty: resolvedLastSelectedDifficulty,
                    onSelectDungeon: { dungeon, completion in
                        Task {
                            let success = await updateDungeonSelection(dungeonId: dungeon.dungeonId)
                            await MainActor.run { completion(success) }
                        }
                    },
                    onSelectDifficulty: { dungeon, difficulty, completion in
                        Task {
                            let success = await updateDifficultySelectionFromDungeonPicker(dungeon: dungeon, difficulty: difficulty)
                            await MainActor.run { completion(success) }
                        }
                    }
                )
            }
            .sheet(item: $characterDetailContext) { context in
                CharacterDetailSheetLoader(characterId: context.id)
            }
        }
        .overlay(alignment: .bottomLeading) {
            StatChangeNotificationView()
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    private var partyService: PartyProgressService { appServices.party }

    private var currentParty: CachedParty? {
        partyState.parties.first { $0.id == currentPartyId }
    }

    private var resolvedLastSelectedDungeonId: UInt16? {
        currentParty?.lastSelectedDungeonId ?? lastSelectedDungeonId
    }

    private var resolvedLastSelectedDifficulty: UInt8 {
        currentParty?.lastSelectedDifficulty ?? lastSelectedDifficulty
    }

    private var currentPartyTargetFloor: UInt8? {
        currentParty?.targetFloor
    }

    private var activeDungeon: CachedDungeonProgress? {
        let resolvedId = selectedDungeonId ?? resolvedLastSelectedDungeonId
        guard let dungeonId = resolvedId else { return nil }
        return dungeons.first { $0.dungeonId == dungeonId }
    }

    private var selectedDungeonName: String {
        if let dungeon = activeDungeon {
            let clampedDifficulty = min(resolvedLastSelectedDifficulty, dungeon.highestUnlockedDifficulty)
            return formattedDifficultyLabel(for: dungeon, difficulty: clampedDifficulty, masterData: appServices.masterDataCache)
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
            if partyState.parties.isEmpty {
                try await partyState.loadAllParties()
            }
            guard let currentParty else { return }
            // パーティメンバーのHP全回復（HP > 0 のキャラクターのみ）
            try await appServices.character.healToFull(characterIds: currentParty.memberIds)
            // HP変更後にキャッシュを無効化
            appServices.userDataLoad.invalidateCharacters()
            await refreshCachedParty()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadPartyMembers(memberIds: [UInt8]) async throws {
        guard !memberIds.isEmpty else {
            partyMembers = []
            partyBonuses = .neutral
            return
        }
        let allCharacters = try await appServices.userDataLoad.getCharacters()
        let map = Dictionary(uniqueKeysWithValues: allCharacters.map { ($0.id, $0) })
        let members = memberIds.compactMap { map[$0] }
        partyMembers = members.map { PartyMemberSummary(character: $0) }
        partyBonuses = PartyDropBonuses(members: members)
    }

    @MainActor
    private func refreshCachedParty() async {
        do {
            try await partyState.refresh()
            guard let updated = partyState.parties.first(where: { $0.id == currentPartyId }) else {
                partyMembers = []
                partyBonuses = .neutral
                return
            }
            try await loadPartyMembers(memberIds: updated.memberIds)
            lastSelectedDungeonId = updated.lastSelectedDungeonId
            lastSelectedDifficulty = updated.lastSelectedDifficulty
            let updatedTargetFloor = Int(updated.targetFloor)
            if targetFloorSelection != updatedTargetFloor {
                targetFloorSelection = updatedTargetFloor
            }
            if let dungeonId = updated.lastSelectedDungeonId,
               dungeons.contains(where: { $0.dungeonId == dungeonId }) {
                selectedDungeonId = dungeonId
            } else {
                selectedDungeonId = nil
            }
            if let dungeonId = selectedDungeonId,
               let dungeon = dungeons.first(where: { $0.dungeonId == dungeonId }),
               updated.lastSelectedDifficulty > dungeon.highestUnlockedDifficulty {
                do {
                    _ = try await partyService.setLastSelectedDifficulty(partyId: updated.id,
                                                                        difficulty: dungeon.highestUnlockedDifficulty)
                    try await partyState.refresh()
                    if let adjusted = partyState.parties.first(where: { $0.id == updated.id }) {
                        lastSelectedDungeonId = adjusted.lastSelectedDungeonId
                        lastSelectedDifficulty = adjusted.lastSelectedDifficulty
                        let adjustedTargetFloor = Int(adjusted.targetFloor)
                        if targetFloorSelection != adjustedTargetFloor {
                            targetFloorSelection = adjustedTargetFloor
                        }
                        if let adjustedDungeonId = adjusted.lastSelectedDungeonId,
                           dungeons.contains(where: { $0.dungeonId == adjustedDungeonId }) {
                            selectedDungeonId = adjustedDungeonId
                        } else {
                            selectedDungeonId = nil
                        }
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handlePrimaryAction(party: CachedParty, isExploring: Bool, canDepart: Bool) {
        if isExploring {
            Task { await adventureState.cancelExploration(for: party, using: appServices) }
            return
        }

        guard canDepart else { return }

        Task {
            await startExplorationFromDetail(party: party)
        }
    }

    private func startExplorationFromDetail(party: CachedParty) async {
        guard let dungeon = activeDungeon else {
            await MainActor.run { showDungeonPicker = true }
            return
        }
        do {
            try await adventureState.startExploration(party: party,
                                                      dungeon: dungeon,
                                                      repeatCount: 1,
                                                      isImmediateReturn: false,
                                                      using: appServices)
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func canStartExploration(for party: CachedParty) -> Bool {
        guard let dungeon = activeDungeon else { return false }
        guard dungeon.isUnlocked else { return false }
        guard party.lastSelectedDifficulty <= dungeon.highestUnlockedDifficulty else { return false }
        guard !partyMembers.isEmpty else { return false }
        return !adventureState.isExploring(partyId: party.id)
    }

    // MARK: - Mutations

    private func updateDungeonSelection(dungeonId: UInt16) async -> Bool {
        do {
            _ = try await partyService.setLastSelectedDungeon(partyId: currentPartyId, dungeonId: dungeonId)
            await refreshCachedParty()
            return true
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
            return false
        }
    }

    private func updateTargetFloor(_ floor: Int) async {
        do {
            _ = try await partyService.setTargetFloor(partyId: currentPartyId, floor: UInt8(floor))
            await refreshCachedParty()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func updateDifficultySelection(_ difficulty: UInt8) async -> Bool {
        do {
            _ = try await partyService.setLastSelectedDifficulty(partyId: currentPartyId,
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

private struct CharacterDetailContext: Identifiable {
    let id: UInt8
}

private struct CharacterDetailSheetLoader: View {
    let characterId: UInt8
    @Environment(AppServices.self) private var appServices
    @State private var character: CachedCharacter?
    @State private var errorMessage: String?

    private var characterService: CharacterProgressService { appServices.character }

    var body: some View {
        Group {
            if let character {
                CachedCharacterDetailSheetView(character: character,
                                               onActionPreferencesChange: { preferences, completion in
                                                   Task {
                                                       do {
                                                           try await updateActionPreferences(to: preferences)
                                                           await MainActor.run { completion(.success(())) }
                                                       } catch {
                                                           await MainActor.run { completion(.failure(error)) }
                                                       }
                                                   }
                                               })
            } else if let errorMessage {
                VStack {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await loadCharacter() }
    }

    @MainActor
    private func loadCharacter() async {
        errorMessage = nil
        do {
            let allCharacters = try await appServices.userDataLoad.getCharacters()
            guard let found = allCharacters.first(where: { $0.id == characterId }) else {
                errorMessage = "キャラクターが見つかりません"
                return
            }
            character = found
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func updateActionPreferences(to newPreferences: CharacterValues.ActionPreferences) async throws {
        let updated = try await characterService.updateActionPreferences(
            characterId: characterId,
            attack: newPreferences.attack,
            priestMagic: newPreferences.priestMagic,
            mageMagic: newPreferences.mageMagic,
            breath: newPreferences.breath
        )
        character = updated
        appServices.userDataLoad.updateCharacter(updated)
    }
}

private struct PartySkillsListView: View {
    let memberIds: [UInt8]
    @Environment(AppServices.self) private var appServices
    @State private var members: [PartyMemberSkillSummary] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.secondary)
            } else if members.isEmpty {
                Text("メンバーがいません").foregroundColor(.secondary)
            } else {
                ForEach(members) { member in
                    Section(member.name) {
                        if member.skills.isEmpty {
                            Text("習得スキルなし").foregroundColor(.secondary)
                        } else {
                            ForEach(member.skills) { skill in
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
        .task { await loadMembers() }
    }

    @MainActor
    private func loadMembers() async {
        errorMessage = nil
        guard !memberIds.isEmpty else {
            members = []
            return
        }
        do {
            let allCharacters = try await appServices.userDataLoad.getCharacters()
            let map = Dictionary(uniqueKeysWithValues: allCharacters.map { ($0.id, $0) })
            let summaries = memberIds.compactMap { map[$0] }.map { PartyMemberSkillSummary(character: $0) }
            members = summaries
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PartyMemberSkillSummary: Identifiable, Hashable {
    let id: UInt8
    let name: String
    let skills: [PartySkillSummary]

    init(character: CachedCharacter) {
        id = character.id
        name = character.name
        skills = character.learnedSkills.map { PartySkillSummary(id: $0.id, name: $0.name) }
    }
}

private struct PartySkillSummary: Identifiable, Hashable {
    let id: UInt16
    let name: String
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
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 0) {
                                Text(character.name)
                                    .font(.subheadline.bold())
                                Text("　\(slotUsageText(for: character))")
                                    .font(.subheadline)
                            }
                            Text(characterDetailText(for: character))
                                .font(.caption)
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

    private func characterDetailText(for character: CachedCharacter) -> String {
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
        return "Lv\(character.level) / \(raceName) / \(jobText)"
    }
}

// MARK: - Inline Selection Menus
// iOS 17のAttributeGraphクラッシュ回避のため、Viewがasyncクロージャを保持しない（commit: 535a42b）。

private struct DifficultyPickerMenu: View {
    @Environment(AppServices.self) private var appServices
    let dungeon: CachedDungeonProgress
    let currentDifficulty: UInt8
    let onSelect: (UInt8) -> Void
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
        onSelect(difficulty)
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
    let onSelectDungeon: (CachedDungeonProgress, @escaping (Bool) -> Void) -> Void
    let onSelectDifficulty: (CachedDungeonProgress, UInt8, @escaping (Bool) -> Void) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDungeonIdForDifficulty: UInt16?

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
            .navigationDestination(isPresented: isDifficultyPickerPresented) {
                if let dungeonId = selectedDungeonIdForDifficulty,
                   let dungeon = dungeons.first(where: { $0.dungeonId == dungeonId }) {
                    DifficultyPickerView(
                        dungeon: dungeon,
                        currentDifficulty: currentDifficulty(for: dungeon),
                        onSelect: { difficulty, completion in
                            selectDifficulty(for: dungeon, difficulty: difficulty, completion: completion)
                        }
                    )
                    .onDisappear {
                        if selectedDungeonIdForDifficulty == dungeonId {
                            selectedDungeonIdForDifficulty = nil
                        }
                    }
                }
            }
        }
    }

    private var isDifficultyPickerPresented: Binding<Bool> {
        Binding(
            get: { selectedDungeonIdForDifficulty != nil },
            set: { isPresented in
                if !isPresented { selectedDungeonIdForDifficulty = nil }
            }
        )
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
        onSelectDungeon(dungeon) { success in
            if success {
                selectedDungeonIdForDifficulty = dungeon.dungeonId
            }
        }
    }

    private func selectDifficulty(for dungeon: CachedDungeonProgress, difficulty: UInt8, completion: @escaping (Bool) -> Void) {
        onSelectDifficulty(dungeon, difficulty) { success in
            if success {
                selectedDungeonIdForDifficulty = nil
                dismiss()
            }
            completion(success)
        }
    }
}

private struct DifficultyPickerView: View {
    let dungeon: CachedDungeonProgress
    let currentDifficulty: UInt8
    let onSelect: (UInt8, @escaping (Bool) -> Void) -> Void
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
        onSelect(difficulty) { success in
            if success {
                dismiss()
            }
        }
    }
}

private struct PartyNameEditorView: View {
    let party: CachedParty
    let onComplete: (@escaping () -> Void) -> Void
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
            _ = try await partyService.updatePartyName(partyId: party.id, name: name.trimmingCharacters(in: .whitespaces))
            onComplete {
                dismiss()
            }
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
