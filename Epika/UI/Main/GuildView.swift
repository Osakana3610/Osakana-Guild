// ==============================================================================
// GuildView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ギルド機能のハブ画面
//   - キャラクター管理機能へのナビゲーション
//   - 登録キャラクター一覧の表示
//
// 【View構成】
//   - ギルド機能メニュー（求人、蘇生、転職、戦闘能力一覧、改造）
//   - 在籍中のキャラクター一覧
//   - 戦線離脱キャラクター一覧
//   - キャラクター解雇機能へのリンク
//
// 【使用箇所】
//   - MainTabView（ギルドタブ）
//
// ==============================================================================

import SwiftUI

struct GuildView: View {
    @Environment(AppServices.self) private var appServices
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
            .toolbar {
                EditButton()
            }
            .onAppear {
                characterState.startObservingChanges(using: appServices)
                Task { await loadOnce() }
            }
        }
    }

    private var contentList: some View {
        List {
            Section("ギルド機能") {
                NavigationLink {
                    CharacterCreationView(appServices: appServices) {
                        Task { await reload() }
                    }
                } label: {
                    GuildActionLabel(title: "求人を出す",
                                      icon: "person.badge.plus",
                                      tint: .blue)
                }

                NavigationLink {
                    CharacterReviveView(appServices: appServices) {
                        Task { await reload() }
                    }
                } label: {
                    GuildActionLabel(title: "キャラクターを蘇生させる",
                                      icon: "heart.fill",
                                      tint: .red,
                                      badgeCount: fallenSummaries.count)
                }

                NavigationLink {
                    CharacterJobChangeView(appServices: appServices) {
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
                    PartySlotExpansionView(appServices: appServices) {
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
                                                            appServices: appServices)
                        } label: {
                            GuildCharacterRow(summary: summary)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onMove(perform: moveAliveCharacters)
                }
            }

            if !fallenSummaries.isEmpty {
                Section("戦線離脱 (\(fallenSummaries.count))") {
                    ForEach(fallenSummaries) { summary in
                        GuildCharacterRow(summary: summary)
                            .opacity(0.6)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
        // 初回のみ: 既存キャラクターにdisplayOrderを設定（EpikaApp起動時だとリリースビルドでハングするためここで実行）
        try? await appServices.character.migrateDisplayOrderIfNeeded()
        await loadData()
        didLoadOnce = true
    }

    private func loadData() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        do {
            async let summariesTask: Void = characterState.loadCharacterSummaries(using: appServices)
            async let allCharactersTask: Void = characterState.loadAllCharacters(using: appServices)
            _ = try await appServices.gameState.loadCurrentPlayer()
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

    private func moveAliveCharacters(from source: IndexSet, to destination: Int) {
        // aliveSummariesの並び順を更新
        var aliveIds = aliveSummaries.map(\.id)
        aliveIds.move(fromOffsets: source, toOffset: destination)

        // 戦線離脱キャラクターはaliveの後に配置
        let fallenIds = fallenSummaries.map(\.id)
        let orderedIds = aliveIds + fallenIds

        Task {
            do {
                try await appServices.character.reorderCharacters(orderedIds: orderedIds)
            } catch {
                errorMessage = "並び替えに失敗しました: \(error.localizedDescription)"
            }
        }
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
        HStack(spacing: 8) {
            CharacterImageView(avatarIndex: summary.resolvedAvatarId, size: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.name)
                    .font(.subheadline)
                    .foregroundStyle(summary.isAlive ? .primary : .secondary)
                HStack(spacing: 4) {
                    Text(summary.raceName)
                    Text("Lv.\(summary.level)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                Text(summary.jobName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Character Detail Loader

private struct LazyRuntimeCharacterDetailView: View {
    let characterId: UInt8
    let summary: CharacterViewState.CharacterSummary
    let appServices: AppServices

    @State private var runtimeCharacter: RuntimeCharacter?
    @State private var errorMessage: String?
    @State private var isLoading = false

    private var characterService: CharacterProgressService { appServices.character }

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
