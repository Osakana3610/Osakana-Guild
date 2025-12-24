// ==============================================================================
// CharacterReviveView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 戦闘不能キャラクター（HP 0）の蘇生
//   - 蘇生処理（HP を最大値の半分に回復）
//
// 【View構成】
//   - 戦闘不能キャラクターのリスト表示
//   - 各キャラクターごとの蘇生ボタン
//   - 空状態表示（蘇生が必要なキャラクターなし）
//
// 【使用箇所】
//   - GuildView（キャラクターを蘇生させる）
//
// ==============================================================================

import SwiftUI

struct CharacterReviveView: View {
    let appServices: AppServices
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var deadCharacters: [RuntimeCharacter] = []
    @State private var isLoading = false
    @State private var isProcessing = false
    @State private var errorMessage: String?

    private var characterService: CharacterProgressService { appServices.character }
    private var explorationService: ExplorationProgressService { appServices.exploration }

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        Button("再読み込み") {
                            Task { await loadDeadCharacters() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if deadCharacters.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.primary)
                        Text("蘇生が必要なキャラクターはいません")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(deadCharacters, id: \.id) { character in
                            HStack {
                                CharacterImageView(avatarIndex: character.resolvedAvatarId, size: 44)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(character.name)
                                        .font(.headline)
                                    Text("Lv.\(character.level) / \(character.jobName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("HP: 0/\(character.maxHP)")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                                Spacer()
                                Button("蘇生") {
                                    Task { await reviveCharacter(character) }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(isProcessing)
                            }
                        }
                    }
                    .avoidBottomGameInfo()
                }
            }
            .navigationTitle("キャラクター蘇生")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadDeadCharacters() }
        }
    }

    @MainActor
    private func loadDeadCharacters() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let exploringIds = try explorationService.runningPartyMemberIds()
            let progresses = try await characterService.allCharacters()
            // 探索中のキャラクターは除外（探索中は蘇生不可）
            let deceased = progresses.filter { $0.hitPoints.current <= 0 && !exploringIds.contains($0.id) }
            var runtime: [RuntimeCharacter] = []
            for progress in deceased {
                let character = try await characterService.runtimeCharacter(from: progress)
                runtime.append(character)
            }
            deadCharacters = runtime.sorted { $0.id < $1.id }
        } catch {
            errorMessage = error.localizedDescription
            deadCharacters = []
        }
    }

    @MainActor
    private func reviveCharacter(_ character: RuntimeCharacter) async {
        if isProcessing { return }
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }
        do {
            _ = try await characterService.updateCharacter(id: character.id) { progress in
                var hitPoints = progress.hitPoints
                hitPoints.current = max(1, hitPoints.maximum / 2)
                progress.hitPoints = hitPoints
            }
            await loadDeadCharacters()
            onComplete()
            if deadCharacters.isEmpty {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
