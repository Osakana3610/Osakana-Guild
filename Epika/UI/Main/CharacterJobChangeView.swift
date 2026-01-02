// ==============================================================================
// CharacterJobChangeView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクターの転職処理
//   - 転職可能なキャラクターの絞り込み（未転職・非探索中）
//   - マスター職業への転職条件チェック（Lv50以上、対応職業）
//
// 【View構成】
//   - キャラクター選択ピッカー
//   - 職業選択ピッカー（条件に応じた職業フィルタリング）
//   - 転職実行ボタン
//
// 【使用箇所】
//   - GuildView（キャラクターを転職させる）
//
// ==============================================================================

import SwiftUI

struct CharacterJobChangeView: View {
    let appServices: AppServices
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var characters: [CachedCharacter] = []
    @State private var jobs: [JobDefinition] = []
    @State private var exploringCharacterIds: Set<UInt8> = []
    @State private var selectedCharacterId: UInt8?
    @State private var selectedJobIndex: UInt8?
    @State private var isLoading = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var didLoadOnce = false

    private var characterService: CharacterProgressService { appServices.character }
    private var masterData: MasterDataCache { appServices.masterDataCache }

    /// 転職可能なキャラクター（未転職かつ探索中でない）
    private var eligibleCharacters: [CachedCharacter] {
        characters.filter { $0.previousJobId == 0 && !exploringCharacterIds.contains($0.id) }
    }

    /// 選択中のキャラクター
    private var selectedCharacter: CachedCharacter? {
        guard let id = selectedCharacterId else { return nil }
        return characters.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("キャラクター") {
                    if characters.isEmpty {
                        ProgressView()
                    } else if eligibleCharacters.isEmpty {
                        Text("転職可能なキャラクターがいません")
                            .foregroundColor(.secondary)
                    } else {
                        Picker("対象", selection: $selectedCharacterId) {
                            Text("未選択").tag(UInt8?.none)
                            ForEach(eligibleCharacters, id: \.id) { character in
                                Text("\(character.name) (Lv.\(character.level) \(character.job?.name ?? ""))").tag(UInt8?.some(character.id))
                            }
                        }
                    }
                }

                if let character = selectedCharacter {
                    Section("職業") {
                        if jobs.isEmpty {
                            ProgressView()
                        } else {
                            Picker("新しい職業", selection: $selectedJobIndex) {
                                Text("未選択").tag(UInt8?.none)
                                ForEach(jobs) { job in
                                    let jobId = UInt8(job.id)
                                    let isCurrentJob = character.jobId == jobId
                                    let isMasterJob = jobId >= 101 && jobId <= 116
                                    let masterBaseJobId = isMasterJob ? jobId - 100 : 0

                                    if isMasterJob {
                                        if character.jobId == masterBaseJobId {
                                            // 対応する基本職の場合、Lv50条件を表示
                                            if character.level >= 50 {
                                                Text(job.name).tag(UInt8?.some(jobId))
                                            } else {
                                                Text("\(job.name) (Lv50必要)").tag(UInt8?.none)
                                            }
                                        }
                                        // 対応しない職業の場合は表示しない
                                    } else if !isCurrentJob {
                                        Text(job.name).tag(UInt8?.some(jobId))
                                    }
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button("転職する") {
                        Task { await changeJob() }
                    }
                    .disabled(!canSubmit || isProcessing)
                }
            }
            .avoidBottomGameInfo()
            .navigationTitle("キャラクター転職")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { Task { await loadOnce() } }
        }
    }

    private var canSubmit: Bool {
        selectedCharacterId != nil && selectedJobIndex != nil
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
        defer { isLoading = false }
        do {
            exploringCharacterIds = try await appServices.exploration.runningPartyMemberIds()
            // キャッシュからキャラクターを取得（DB直接アクセスではなく）
            let cachedCharacters = try await appServices.userDataLoad.getCharacters()
            characters = cachedCharacters.sorted { $0.id < $1.id }
            jobs = masterData.allJobs.sorted { $0.id < $1.id }
            if selectedCharacterId == nil {
                selectedCharacterId = eligibleCharacters.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
            characters = []
            jobs = []
        }
    }

    @MainActor
    private func changeJob() async {
        guard let characterId = selectedCharacterId, let jobIndex = selectedJobIndex else { return }
        if isProcessing { return }
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }
        do {
            let updated = try await characterService.changeJob(characterId: characterId, newJobId: jobIndex)
            let runtime = try await characterService.runtimeCharacter(from: updated)
            if let index = characters.firstIndex(where: { $0.id == runtime.id }) {
                characters[index] = runtime
            }
            onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
