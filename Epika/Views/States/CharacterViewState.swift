import Foundation
import Observation

@MainActor
@Observable
final class CharacterViewState {
    @ObservationIgnored private var characterChangeTask: Task<Void, Never>?

    struct CharacterSummary: Identifiable, Sendable {
        let id: UInt8
        let name: String
        let level: Int
        let jobName: String
        let raceName: String
        let isAlive: Bool
        let createdAt: Date
        let jobId: UInt8
        let raceId: UInt8
        let gender: String
        let currentHP: Int
        let maxHP: Int
        let avatarId: UInt16

        /// 表示用のavatarId（0の場合はraceIdを使用）
        var resolvedAvatarId: UInt16 {
            avatarId == 0 ? UInt16(raceId) : avatarId
        }

        init(snapshot: CharacterSnapshot, job: JobDefinition?, race: RaceDefinition?) {
            self.id = snapshot.id
            self.name = snapshot.displayName
            self.level = snapshot.level
            self.jobName = job?.name ?? "職業\(snapshot.jobId)"
            self.raceName = race?.name ?? "種族\(snapshot.raceId)"
            self.isAlive = snapshot.hitPoints.current > 0
            self.createdAt = snapshot.createdAt
            self.jobId = snapshot.jobId
            self.raceId = snapshot.raceId
            self.gender = race?.genderDisplayName ?? "不明"
            self.currentHP = snapshot.hitPoints.current
            self.maxHP = snapshot.hitPoints.maximum
            self.avatarId = snapshot.avatarId
        }

    }

    var allCharacters: [RuntimeCharacter] = []
    var summaries: [CharacterSummary] = []
    var isLoadingAll: Bool = false
    var isLoadingSummaries: Bool = false

    deinit {
        characterChangeTask?.cancel()
    }

    func startObservingChanges(using appServices: AppServices) {
        guard characterChangeTask == nil else { return }
        characterChangeTask = Task { [weak self, appServices] in
            let center = NotificationCenter.default
            for await _ in center.notifications(named: .characterProgressDidChange) {
                if Task.isCancelled { break }
                guard let self else { break }
                await self.reloadAfterCharacterProgressChange(using: appServices)
            }
        }
    }

    func loadCharacterSummaries(using appServices: AppServices) async throws {
        if isLoadingSummaries { return }
        isLoadingSummaries = true
        defer { isLoadingSummaries = false }

        let snapshots = try await appServices.character.allCharacters()
        if snapshots.isEmpty {
            summaries = []
            return
        }

        let masterData = appServices.masterDataCache
        let jobMap = Dictionary(uniqueKeysWithValues: masterData.allJobs.map { ($0.id, $0) })
        let raceMap = Dictionary(uniqueKeysWithValues: masterData.allRaces.map { ($0.id, $0) })

        summaries = snapshots.map { snapshot in
            CharacterSummary(snapshot: snapshot,
                             job: jobMap[snapshot.jobId],
                             race: raceMap[snapshot.raceId])
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    func loadAllCharacters(using appServices: AppServices) async throws {
        if isLoadingAll { return }
        isLoadingAll = true
        defer { isLoadingAll = false }

        let characterService = appServices.character
        let snapshots = try await characterService.allCharacters()
        var buffer: [RuntimeCharacter] = []
        for snapshot in snapshots {
            let character = try await characterService.runtimeCharacter(from: snapshot)
            buffer.append(character)
        }
        allCharacters = buffer.sorted { lhs, rhs in
            lhs.id < rhs.id
        }
    }

    @MainActor
    private func reloadAfterCharacterProgressChange(using appServices: AppServices) async {
        do {
            try await loadAllCharacters(using: appServices)
            try await loadCharacterSummaries(using: appServices)
        } catch {
            assertionFailure("キャラクターデータの再読み込みに失敗しました: \(error)")
        }
    }
}
