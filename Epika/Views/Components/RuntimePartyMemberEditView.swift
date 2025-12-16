import SwiftUI

struct RuntimePartyMemberEditView: View {
    var party: RuntimeParty
    let allCharacters: [RuntimeCharacter]
    @Environment(PartyViewState.self) private var partyState
    @EnvironmentObject private var progressService: ProgressService
    @State private var currentMemberIds: [UInt8?] = Array(repeating: nil, count: Self.maxSlots)
    @State private var selectedSlotIndex: Int? = nil
    @State private var searchText = ""
    @State private var characterIdsInOtherParties = Set<UInt8>()
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSaving = false

    private var availableCharacters: [RuntimeCharacter] {
        let filtered = allCharacters.filter { character in
            searchText.isEmpty || character.name.localizedCaseInsensitiveCompare(searchText) == .orderedSame || character.name.localizedCaseInsensitiveContains(searchText)
        }
        return filtered.filter { character in
            character.isAlive &&
            !currentMemberIds.contains(where: { $0 == character.id }) &&
            !characterIdsInOtherParties.contains(character.id)
        }
    }

    private var partyService: PartyProgressService { progressService.party }

    private func character(for id: UInt8?) -> RuntimeCharacter? {
        guard let id else { return nil }
        return allCharacters.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                partyMemberSection
                Divider()
                searchSection
                availableCharacterSection
            }
            .navigationTitle("メンバー編集")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await initialise() }
        .alert("エラー", isPresented: $showError) {
            Button("OK", role: .cancel) { showError = false }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Initialisation

    private func initialise() async {
        await MainActor.run { currentMemberIds = Self.initialSlots(from: party.memberIds) }
        await loadCharactersInOtherParties()
    }

    private func loadCharactersInOtherParties() async {
        do {
            let ids = try await partyService.characterIdsInOtherParties(excluding: party.persistentIdentifier)
            await MainActor.run { characterIdsInOtherParties = ids }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Sections

    private var partyMemberSection: some View {
        VStack(spacing: 0) {
            Text("パーティメンバー (最大6名)")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)

            VStack(spacing: 12) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 16) {
                        ForEach(0..<3, id: \.self) { col in
                            let index = row * 3 + col
                            let member = character(for: currentMemberIds[index])
                            RuntimePartyMemberSlotView(
                                character: member,
                                slotIndex: index,
                                isSelected: selectedSlotIndex == index,
                                onSlotTap: { handleSlotTap(index: index) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    private var searchSection: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("キャラクター名で検索", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button("クリア") { searchText = "" }
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var availableCharacterSection: some View {
        List {
            if availableCharacters.isEmpty {
                Text(searchText.isEmpty ? "利用可能なキャラクターがありません" : "検索結果がありません")
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(availableCharacters, id: \.id) { character in
                    RuntimeCharacterRowForPartyView(character: character) {
                        addCharacter(character)
                    }
                }
            }
        }
        .listStyle(.plain)
        .avoidBottomGameInfo()
    }

    // MARK: - Actions

    private func handleSlotTap(index: Int) {
        if selectedSlotIndex == index {
            removeCharacter(at: index)
        } else {
            selectedSlotIndex = index
        }
    }

    private func addCharacter(_ character: RuntimeCharacter) {
        if let selectedIndex = selectedSlotIndex {
            currentMemberIds[selectedIndex] = character.id
            selectedSlotIndex = nil
        } else if let emptyIndex = currentMemberIds.firstIndex(where: { $0 == nil }) {
            currentMemberIds[emptyIndex] = character.id
        }
        persistMembers()
    }

    private func removeCharacter(at index: Int) {
        guard currentMemberIds.indices.contains(index) else { return }
        currentMemberIds[index] = nil
        selectedSlotIndex = nil
        persistMembers()
    }

    private func persistMembers() {
        Task {
            guard !isSaving else { return }
            isSaving = true
            do {
                let memberIds = currentMemberIds.compactMap { $0 }
                try await partyState.updatePartyMembers(party: party, memberIds: memberIds)
                await loadCharactersInOtherParties()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
            isSaving = false
        }
    }
}

private extension RuntimePartyMemberEditView {
    static let maxSlots = 6

    static func initialSlots(from members: [UInt8]) -> [UInt8?] {
        var slots = Array<UInt8?>(repeating: nil, count: maxSlots)
        for (index, id) in members.enumerated() where index < slots.count {
            slots[index] = id
        }
        return slots
    }
}

// MARK: - Supporting Views remain unchanged below

struct RuntimePartyMemberSlotView: View {
    let character: RuntimeCharacter?
    let slotIndex: Int
    let isSelected: Bool
    let onSlotTap: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            if let character = character {
                Text("Lv\(character.level)")
                    .font(.caption)
                    .foregroundColor(.primary)

                CharacterImageView(avatarIndex: character.resolvedAvatarId, size: 55)

                Text("HP\(character.currentHP)")
                    .font(.caption)
                    .foregroundColor(character.currentHP == character.maxHP ? .primary : .secondary)

                Text(character.name)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if isSelected {
                    Text("再タップで削除")
                        .font(.caption2)
                        .foregroundColor(.primary)
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray4))
                    .frame(width: 50, height: 60)
                    .overlay(
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "plus")
                            .foregroundColor(isSelected ? .primary : .secondary)
                    )

                Text("---")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("スロット\(slotIndex)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSlotTap() }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

struct RuntimeCharacterRowForPartyView: View {
    let character: RuntimeCharacter
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                CharacterImageView(avatarIndex: character.resolvedAvatarId, size: 55)

                VStack(alignment: .leading, spacing: 4) {
                    Text(character.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack {
                        Text(character.raceName)
                        Text("•")
                        Text(character.jobName)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    HStack {
                        Text("Lv.\(character.level)")
                            .font(.caption)
                            .foregroundColor(.primary)

                        Spacer()

                        Text("HP: \(character.currentHP)/\(character.maxHP)")
                            .font(.caption)
                            .foregroundColor(character.currentHP == character.maxHP ? .primary : .secondary)
                    }
                }

                Spacer()

                Image(systemName: "plus.circle")
                    .foregroundColor(.primary)
                    .font(.title2)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
