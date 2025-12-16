import SwiftUI

struct GuildView: View {
    @EnvironmentObject private var progressService: ProgressService
    @State private var characterState = CharacterViewState()
    @State private var maxCharacterSlots: Int = AppConstants.Progress.defaultCharacterSlotCount
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didLoadOnce = false

    private var aliveSummaries: [CharacterViewState.CharacterSummary] {
        characterState.summaries.filter { $0.isAlive }
    }

    private var fallenSummaries: [CharacterViewState.CharacterSummary] {
        characterState.summaries.filter { !$0.isAlive }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    errorState(message: errorMessage)
                } else if isLoading && characterState.summaries.isEmpty {
                    loadingState
                } else {
                    contentList
                }
            }
            .navigationTitle("ギルド")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                characterState.configureIfNeeded(with: progressService)
                Task { await loadOnce() }
            }
        }
    }

    private var contentList: some View {
        List {
            Section("ギルド機能") {
                NavigationLink {
                    CharacterCreationView(progressService: progressService) {
                        Task { await reload() }
                    }
                } label: {
                    GuildActionLabel(title: "求人を出す",
                                      icon: "person.badge.plus",
                                      tint: .blue)
                }

                NavigationLink {
                    CharacterReviveView(progressService: progressService) {
                        Task { await reload() }
                    }
                } label: {
                    GuildActionLabel(title: "キャラクターを蘇生させる",
                                      icon: "heart.fill",
                                      tint: .red,
                                      badgeCount: fallenSummaries.count)
                }

                NavigationLink {
                    CharacterJobChangeView(progressService: progressService) {
                        Task { await reload() }
                    }
                } label: {
                    GuildActionLabel(title: "キャラクターを転職させる",
                                      icon: "arrow.triangle.2.circlepath",
                                      tint: .green)
                }

                NavigationLink {
                    BattleStatsView(characters: characterState.allCharacters)
                } label: {
                    GuildActionLabel(title: "戦闘能力一覧",
                                      icon: "chart.bar",
                                      tint: .purple)
                }

                NavigationLink {
                    PartySlotExpansionView(progressService: progressService) {
                        Task { await reload() }
                    }
                } label: {
                    GuildActionLabel(title: "ギルドを改造する",
                                      icon: "house",
                                      tint: .orange)
                }

            }

            Section("登録キャラクター (\(characterState.summaries.count)/\(maxCharacterSlots))") {
                if aliveSummaries.isEmpty {
                    Text("在籍中のキャラクターがいません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(aliveSummaries) { summary in
                        NavigationLink {
                            LazyRuntimeCharacterDetailView(characterId: summary.id,
                                                            summary: summary,
                                                            progressService: progressService)
                        } label: {
                            GuildCharacterRow(summary: summary)
                        }
                    }
                }
            }

            if !fallenSummaries.isEmpty {
                Section("戦線離脱 (\(fallenSummaries.count))") {
                    ForEach(fallenSummaries) { summary in
                        GuildCharacterRow(summary: summary)
                            .opacity(0.6)
                    }
                }
            }

            Section {
                NavigationLink("キャラクターを解雇する") {
                    LazyDismissCharacterView {
                        Task { await reload() }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .avoidBottomGameInfo()
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("ギルド情報を読み込み中…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 44))
                .foregroundColor(.primary)
            Text("ギルド情報の取得に失敗しました")
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
        await loadData()
        didLoadOnce = true
    }

    private func loadData() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        do {
            async let summariesTask: Void = characterState.loadCharacterSummaries()
            async let allCharactersTask: Void = characterState.loadAllCharacters()
            _ = try await progressService.gameState.loadCurrentPlayer()
            try await summariesTask
            try await allCharactersTask
            maxCharacterSlots = AppConstants.Progress.defaultCharacterSlotCount
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func reload() async {
        await loadData()
    }
}

// MARK: - Action Row

private struct GuildActionLabel: View {
    let title: String
    let icon: String
    let tint: Color
    var badgeCount: Int?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24, height: 24)
                .foregroundStyle(tint)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            if let badgeCount, badgeCount > 0 {
                Text("(\(badgeCount))")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
        .frame(height: AppConstants.UI.listRowHeight)
    }
}

private struct GuildCharacterRow: View {
    let summary: CharacterViewState.CharacterSummary

    var body: some View {
        HStack(spacing: 12) {
            CharacterImageView(avatarIndex: summary.resolvedAvatarId, size: 55)
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.name)
                    .font(.headline)
                    .foregroundStyle(summary.isAlive ? .primary : .secondary)
                HStack(spacing: 8) {
                    Text("Lv.\(summary.level)")
                    Text(summary.raceName)
                    Text(summary.jobName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("HP")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(summary.currentHP)/\(summary.maxHP)")
                    .font(.caption)
                    .foregroundColor(summary.isAlive ? .primary : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Character Detail Loader

private struct LazyRuntimeCharacterDetailView: View {
    let characterId: UInt8
    let summary: CharacterViewState.CharacterSummary
    let progressService: ProgressService

    @State private var runtimeCharacter: RuntimeCharacter?
    @State private var errorMessage: String?
    @State private var isLoading = false

    private var characterService: CharacterProgressService { progressService.character }

    var body: some View {
        Group {
            if let runtimeCharacter {
                CharacterDetailContent(character: runtimeCharacter,
                                      onRename: { newName in
                                          try await renameCharacter(to: newName)
                                      },
                                      onAvatarChange: { identifier in
                                          try await changeAvatar(to: identifier)
                                      },
                                      onActionPreferencesChange: { preferences in
                                          try await updateActionPreferences(to: preferences)
                                      })
                    .navigationTitle(runtimeCharacter.name)
                    .navigationBarTitleDisplayMode(.inline)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    Button("再読み込み") { Task { await loadCharacter() } }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .navigationTitle(summary.name)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(summary.name)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task { await loadCharacter() }
    }

    @MainActor
    private func loadCharacter() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if let progress = try await characterService.character(withId: characterId) {
                runtimeCharacter = try await characterService.runtimeCharacter(from: progress)
            } else {
                throw RuntimeError.missingProgressData(reason: "Character not found")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func renameCharacter(to newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProgressError.invalidInput(description: "キャラクター名を入力してください")
        }
        if trimmed == runtimeCharacter?.name {
            return
        }
        let snapshot = try await characterService.updateCharacter(id: characterId) { snapshot in
            snapshot.displayName = trimmed
        }
        runtimeCharacter = try await characterService.runtimeCharacter(from: snapshot)
    }

    @MainActor
    private func changeAvatar(to avatarId: UInt16) async throws {
        if let current = runtimeCharacter, current.avatarId == avatarId {
            return
        }
        let snapshot = try await characterService.updateCharacter(id: characterId) { snapshot in
            snapshot.avatarId = avatarId
        }
        runtimeCharacter = try await characterService.runtimeCharacter(from: snapshot)
    }

    @MainActor
    private func updateActionPreferences(to newPreferences: CharacterSnapshot.ActionPreferences) async throws {
        let normalized = CharacterSnapshot.ActionPreferences.normalized(attack: newPreferences.attack,
                                                                        priestMagic: newPreferences.priestMagic,
                                                                        mageMagic: newPreferences.mageMagic,
                                                                        breath: newPreferences.breath)
        let snapshot = try await characterService.updateCharacter(id: characterId) { snapshot in
            snapshot.actionPreferences = normalized
        }
        runtimeCharacter = try await characterService.runtimeCharacter(from: snapshot)
    }
}
