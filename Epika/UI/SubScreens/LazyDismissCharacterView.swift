// ==============================================================================
// LazyDismissCharacterView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクター解雇画面の表示
//   - 解雇対象キャラクターの選択
//   - 解雇確認ダイアログと実行
//
// 【View構成】
//   - LazyDismissCharacterView: 解雇画面本体
//     - loadingView: 読み込み中表示
//     - emptyView: キャラクター不在時表示
//     - characterList: 解雇可能キャラクター一覧
//
// 【使用箇所】
//   - GuildView: ギルド画面から遷移
//
// ==============================================================================

import SwiftUI

/// キャラクター一覧を必要時に構築して解雇処理を行う画面。
struct LazyDismissCharacterView: View {
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var appServices

    @State private var fullCharacters: [CachedCharacter] = []
    @State private var exploringIds: Set<UInt8> = []
    @State private var selectedCharacter: CachedCharacter?
    @State private var showDeleteConfirmation = false
    @State private var isProcessing = false
    @State private var isLoading = true
    @State private var showError = false
    @State private var errorMessage = ""

    private var characterService: CharacterProgressService { appServices.character }

    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    loadingView
                } else if fullCharacters.isEmpty {
                    emptyView
                } else {
                    characterList
                }

                if showError {
                    Text(errorMessage)
                        .foregroundColor(.primary)
                        .font(.caption)
                        .padding(.bottom, 12)
                }
            }
            .navigationTitle("キャラクター解雇")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("キャラクター解雇", isPresented: $showDeleteConfirmation) {
                Button("キャンセル", role: .cancel) { selectedCharacter = nil }
                Button("解雇", role: .destructive) { Task { await dismissSelectedCharacter() } }
            } message: {
                if let character = selectedCharacter {
                    Text("「\(character.name)」を解雇しますか？この操作は取り消せません。")
                }
            }
            .task { await loadCharacters() }
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.2)
            Text("キャラクター情報を読み込み中...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.badge.minus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("解雇可能なキャラクターがいません")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var characterList: some View {
        List {
            ForEach(fullCharacters) { character in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(character.name)
                            .font(.body)
                            .foregroundStyle(character.isAlive ? .primary : .secondary)
                        HStack(spacing: 4) {
                            Text(character.raceName)
                            Text("Lv.\(character.level)")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        Text(character.jobName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("解雇") {
                        selectedCharacter = character
                        showDeleteConfirmation = true
                    }
                    .foregroundColor(.primary)
                    .disabled(isProcessing || exploringIds.contains(character.id))
                }
                .padding(.vertical, 4)
            }
        }
        .avoidBottomGameInfo()
    }

    // MARK: - Data Loading

    @MainActor
    private func loadCharacters() async {
        isLoading = true
        showError = false
        do {
            // キャッシュからキャラクターを取得（DB直接アクセスではなく）
            let characters = try await appServices.userDataLoad.getCharacters()
            fullCharacters = characters.sorted { $0.id < $1.id }
            exploringIds = try await appServices.userDataLoad.runningCharacterIds()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            fullCharacters = []
        }
        isLoading = false
    }

    @MainActor
    private func dismissSelectedCharacter() async {
        guard let character = selectedCharacter, !isProcessing else { return }
        isProcessing = true
        showError = false
        do {
            try await characterService.deleteCharacter(id: character.id)
            await loadCharacters()
            onComplete()
            if fullCharacters.isEmpty {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isProcessing = false
        selectedCharacter = nil
    }
}
