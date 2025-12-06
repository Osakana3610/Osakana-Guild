import Foundation
import Observation

@MainActor
@Observable
final class CharacterViewState {
    private var progressService: ProgressService?
    @ObservationIgnored private var characterChangeTask: Task<Void, Never>?

    struct CharacterSummary: Identifiable, Sendable {
        let id: UInt8
        let name: String
        let level: Int
        let jobName: String
        let raceName: String
        let isAlive: Bool
        let createdAt: Date
        let jobIndex: UInt8
        let raceIndex: UInt8
        let gender: String
        let currentHP: Int
        let maxHP: Int
        let avatarIndex: UInt16

        /// 表示用のavatarIndex（0の場合はraceIndexを使用）
        var resolvedAvatarIndex: UInt16 {
            avatarIndex == 0 ? UInt16(raceIndex) : avatarIndex
        }

        init(snapshot: CharacterSnapshot, job: JobDefinition?, race: RaceDefinition?) {
            self.id = snapshot.id
            self.name = snapshot.displayName
            self.level = snapshot.level
            self.jobName = job?.name ?? "職業\(snapshot.jobIndex)"
            self.raceName = race?.name ?? "種族\(snapshot.raceIndex)"
            self.isAlive = snapshot.hitPoints.current > 0
            self.createdAt = snapshot.createdAt
            self.jobIndex = snapshot.jobIndex
            self.raceIndex = snapshot.raceIndex
            self.gender = race?.gender ?? "不明"
            self.currentHP = snapshot.hitPoints.current
            self.maxHP = snapshot.hitPoints.maximum
            self.avatarIndex = snapshot.avatarIndex
        }

    }

    private let masterDataService = MasterDataRuntimeService.shared

    var allCharacters: [RuntimeCharacter] = []
    var summaries: [CharacterSummary] = []
    var isLoadingAll: Bool = false
    var isLoadingSummaries: Bool = false

    init(progressService: ProgressService? = nil) {
        self.progressService = progressService
        if progressService != nil {
            observeCharacterChanges()
        }
    }

    func configureIfNeeded(with progressService: ProgressService) {
        if self.progressService == nil {
            self.progressService = progressService
            observeCharacterChanges()
        }
    }

    deinit {
        characterChangeTask?.cancel()
    }

    private var characterService: CharacterProgressService {
        guard let progressService else {
            fatalError("CharacterViewState requires ProgressService configuration before use")
        }
        return progressService.character
    }

    func loadCharacterSummaries() async throws {
        if isLoadingSummaries { return }
        isLoadingSummaries = true
        defer { isLoadingSummaries = false }

        let snapshots = try await characterService.allCharacters()
        if snapshots.isEmpty {
            summaries = []
            return
        }

        async let jobsTask = masterDataService.getAllJobs()
        async let racesTask = masterDataService.getAllRaces()
        let (jobs, races) = try await (jobsTask, racesTask)
        let jobMap = Dictionary(uniqueKeysWithValues: jobs.map { (UInt8($0.index), $0) })
        let raceMap = Dictionary(uniqueKeysWithValues: races.map { (UInt8($0.index), $0) })

        summaries = snapshots.map { snapshot in
            CharacterSummary(snapshot: snapshot,
                             job: jobMap[snapshot.jobIndex],
                             race: raceMap[snapshot.raceIndex])
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    func loadAllCharacters() async throws {
        if isLoadingAll { return }
        isLoadingAll = true
        defer { isLoadingAll = false }

        let snapshots = try await characterService.allCharacters()
        var buffer: [RuntimeCharacter] = []
        for snapshot in snapshots {
            let character = try await characterService.runtimeCharacter(from: snapshot)
            buffer.append(character)
        }
        allCharacters = buffer.sorted { lhs, rhs in
            lhs.progress.createdAt < rhs.progress.createdAt
        }
    }

    private func observeCharacterChanges() {
        guard characterChangeTask == nil else { return }
        characterChangeTask = Task { [weak self] in
            let center = NotificationCenter.default
            for await _ in center.notifications(named: .characterProgressDidChange) {
                if Task.isCancelled { break }
                guard let self else { break }
                await self.reloadAfterCharacterProgressChange()
            }
        }
    }

    @MainActor
    private func reloadAfterCharacterProgressChange() async {
        do {
            try await loadAllCharacters()
            try await loadCharacterSummaries()
        } catch {
            assertionFailure("キャラクターデータの再読み込みに失敗しました: \(error)")
        }
    }
}
