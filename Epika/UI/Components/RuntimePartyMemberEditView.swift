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
    @State private var selectedMemberId: UInt8?
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
    private var emptySlotCount: Int { Self.maxSlots - currentMemberIds.count }

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
                            isSelected: selectedMemberId == memberId,
                            onTap: { handleMemberTap(id: memberId) }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }
                .onMove(perform: moveMembers)
                ForEach(0..<emptySlotCount, id: \.self) { _ in
                    EmptySlotRow()
                        .moveDisabled(true)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
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
                        AvailableCharacterRow(character: character) {
                            addCharacter(character)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
        persistMembers(reloadOtherParties: false)
    }

    private func handleMemberTap(id: UInt8) {
        if selectedMemberId == id {
            // 2回目のタップで削除
            currentMemberIds.removeAll { $0 == id }
            selectedMemberId = nil
            persistMembers(reloadOtherParties: true)
        } else {
            selectedMemberId = id
        }
    }

    private func addCharacter(_ character: RuntimeCharacter) {
        guard currentMemberIds.count < Self.maxSlots else { return }
        currentMemberIds.append(character.id)
        selectedMemberId = nil
        persistMembers(reloadOtherParties: true)
    }

    private func persistMembers(reloadOtherParties: Bool) {
        Task {
            guard !isSaving else { return }
            isSaving = true
            do {
                try await partyState.updatePartyMembers(party: party, memberIds: currentMemberIds)
                if reloadOtherParties {
                    await loadCharactersInOtherParties()
                }
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
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                CharacterImageView(avatarIndex: character.resolvedAvatarId, size: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(character.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        Text("Lv.\(character.level)")
                        Text(character.jobName)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Text("再タップで削除")
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("HP")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(character.currentHP)/\(character.maxHP)")
                            .font(.caption2)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.red.opacity(0.1) : Color(.systemBackground))
    }
}

private struct EmptySlotRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Spacer()
                .frame(width: 50, height: 50)
        }
    }
}

private struct AvailableCharacterRow: View {
    let character: RuntimeCharacter
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                CharacterImageView(avatarIndex: character.resolvedAvatarId, size: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(character.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        Text("Lv.\(character.level)")
                        Text(character.jobName)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("HP")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(character.currentHP)/\(character.maxHP)")
                        .font(.caption2)
                        .foregroundStyle(.primary)
                }
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

