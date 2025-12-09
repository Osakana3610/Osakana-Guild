import SwiftUI

struct CharacterJobChangeView: View {
    let progressService: ProgressService
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var characters: [RuntimeCharacter] = []
    @State private var jobs: [JobDefinition] = []
    @State private var selectedCharacterId: UInt8?
    @State private var selectedJobIndex: UInt8?
    @State private var isLoading = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var didLoadOnce = false

    private let masterData = MasterDataRuntimeService.shared

    private var characterService: CharacterProgressService { progressService.character }

    var body: some View {
        NavigationStack {
            Form {
                Section("キャラクター") {
                    if characters.isEmpty {
                        ProgressView()
                    } else {
                        Picker("対象", selection: $selectedCharacterId) {
                            Text("未選択").tag(UInt8?.none)
                            ForEach(characters, id: \.id) { character in
                                Text("\(character.name) (Lv.\(character.level))").tag(UInt8?.some(character.id))
                            }
                        }
                    }
                }

                Section("職業") {
                    if jobs.isEmpty {
                        ProgressView()
                    } else {
                        Picker("新しい職業", selection: $selectedJobIndex) {
                            Text("未選択").tag(UInt8?.none)
                            ForEach(jobs) { job in
                                Text(job.name).tag(UInt8?.some(UInt8(job.id)))
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.primary)
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
            let progresses = try await characterService.allCharacters()
            var runtime: [RuntimeCharacter] = []
            for progress in progresses {
                let character = try await characterService.runtimeCharacter(from: progress)
                runtime.append(character)
            }
            characters = runtime.sorted { $0.id < $1.id }
            jobs = try await masterData.getAllJobs().sorted { $0.name < $1.name }
            if selectedCharacterId == nil {
                selectedCharacterId = characters.first?.id
            }
            if selectedJobIndex == nil {
                selectedJobIndex = jobs.first?.id
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
            let updated = try await characterService.updateCharacter(id: characterId) { snapshot in
                // 転職は1回のみ。previousJobIdが0（未転職）の場合のみ設定
                if snapshot.previousJobId == 0 && snapshot.jobId != jobIndex {
                    snapshot.previousJobId = snapshot.jobId
                }
                snapshot.jobId = jobIndex
            }
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
