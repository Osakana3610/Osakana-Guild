// ==============================================================================
// RuntimePartyMemberEditView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - パーティメンバーの編集画面（最大6名）
//   - キャラクター検索・選択・追加・削除機能を提供
//
// 【View構成】
//   - パーティメンバーセクション: 2行3列グリッド（6枠）
//   - 検索セクション: キャラクター名での絞り込み
//   - 利用可能キャラクターリスト: List表示
//   - スロット選択 → キャラクター選択で追加
//   - 配置済みスロットを再タップで削除
//   - 他パーティ所属キャラクターは除外表示
//
// 【使用箇所】
//   - パーティ編成画面（メンバー編集モーダル）
//
// ==============================================================================

import SwiftUI

struct RuntimePartyMemberEditView: View {
    var party: PartySnapshot
    let allCharacters: [RuntimeCharacter]
    @Environment(PartyViewState.self) private var partyState
    @Environment(AppServices.self) private var appServices
    @State private var currentMemberIds: [UInt8] = []
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
            !currentMemberIds.contains(character.id) &&
            !characterIdsInOtherParties.contains(character.id)
        }
    }

    private var partyService: PartyProgressService { appServices.party }

    private func character(for id: UInt8) -> RuntimeCharacter? {
        allCharacters.first { $0.id == id }
    }

    var body: some View {
        List {
            Section {
                ForEach(currentMemberIds, id: \.self) { memberId in
                    if let member = character(for: memberId) {
                        PartyMemberRow(
                            character: member,
                            onRemove: { removeCharacter(id: memberId) }
                        )
                    }
                }
                .onMove(perform: moveMembers)
            } header: {
                Text("パーティメンバー (\(currentMemberIds.count)/\(Self.maxSlots))")
            }

            Section {
                searchField
                if availableCharacters.isEmpty {
                    Text(searchText.isEmpty ? "利用可能なキャラクターがありません" : "検索結果がありません")
                        .foregroundStyle(.secondary)
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
            } header: {
                Text("控え")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("メンバー編集")
        .navigationBarTitleDisplayMode(.inline)
        .avoidBottomGameInfo()
        .task { await initialise() }
        .alert("エラー", isPresented: $showError) {
            Button("OK", role: .cancel) { showError = false }
        } message: {
            Text(errorMessage)
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("キャラクター名で検索", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button("クリア") { searchText = "" }
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Initialisation

    private func initialise() async {
        await MainActor.run { currentMemberIds = party.memberIds }
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

    // MARK: - Actions

    private func moveMembers(from source: IndexSet, to destination: Int) {
        currentMemberIds.move(fromOffsets: source, toOffset: destination)
        persistMembers()
    }

    private func addCharacter(_ character: RuntimeCharacter) {
        guard currentMemberIds.count < Self.maxSlots else { return }
        currentMemberIds.append(character.id)
        persistMembers()
    }

    private func removeCharacter(id: UInt8) {
        currentMemberIds.removeAll { $0 == id }
        persistMembers()
    }

    private func persistMembers() {
        Task {
            guard !isSaving else { return }
            isSaving = true
            do {
                try await partyState.updatePartyMembers(party: party, memberIds: currentMemberIds)
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
}

// MARK: - Supporting Views

private struct PartyMemberRow: View {
    let character: RuntimeCharacter
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CharacterImageView(avatarIndex: character.resolvedAvatarId, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(character.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text("Lv.\(character.level)")
                    Text(character.jobName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

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
