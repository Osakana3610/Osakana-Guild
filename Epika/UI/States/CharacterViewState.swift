// ==============================================================================
// CharacterViewState.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクター一覧とサマリ情報の管理
//   - キャラクター変更通知の監視と自動更新
//
// 【状態管理】
//   - allCharacters: UserDataLoadServiceのキャッシュを参照
//   - summaries: キャラクターサマリ情報（RuntimeCharacterから派生）
//   - characterProgressDidChange 通知による自動リロード
//
// 【使用箇所】
//   - GuildView
//   - AdventureView
//
// ==============================================================================

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
        let displayOrder: UInt8
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

        init(from runtime: RuntimeCharacter) {
            self.id = runtime.id
            self.name = runtime.displayName
            self.level = runtime.level
            self.jobName = runtime.displayJobName
            self.raceName = runtime.raceName
            self.isAlive = runtime.currentHP > 0
            self.displayOrder = runtime.displayOrder
            self.jobId = runtime.jobId
            self.raceId = runtime.raceId
            self.gender = runtime.gender
            self.currentHP = runtime.currentHP
            self.maxHP = runtime.maxHP
            self.avatarId = runtime.avatarId
        }

    }

    var summaries: [CharacterSummary] = []
    private weak var appServicesRef: AppServices?

    /// キャッシュされたキャラクター一覧（同期アクセス用）
    var allCharacters: [RuntimeCharacter] {
        appServicesRef?.userDataLoad.characters ?? []
    }

    deinit {
        characterChangeTask?.cancel()
    }

    func startObservingChanges(using appServices: AppServices) {
        appServicesRef = appServices
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

    /// キャッシュからキャラクターをロード（キャッシュ済みならすぐ返る）
    func loadAllCharacters(using appServices: AppServices) async throws {
        _ = try await appServices.userDataLoad.getCharacters()
    }

    /// キャッシュからサマリーを更新
    func loadCharacterSummaries(using appServices: AppServices) async throws {
        let characters = try await appServices.userDataLoad.getCharacters()
        summaries = characters.map { CharacterSummary(from: $0) }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    @MainActor
    private func reloadAfterCharacterProgressChange(using appServices: AppServices) async {
        appServices.userDataLoad.invalidateCharacters()
        do {
            try await loadCharacterSummaries(using: appServices)
        } catch {
            assertionFailure("キャラクターデータの再読み込みに失敗しました: \(error)")
        }
    }
}
