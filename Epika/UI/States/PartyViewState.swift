// ==============================================================================
// PartyViewState.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - パーティ一覧の管理
//   - パーティメンバーの更新処理
//
// 【状態管理】
//   - parties: 全パーティのスナップショット
//   - 重複読み込み防止（ongoingLoad による排他制御）
//
// 【使用箇所】
//   - AdventureView
//   - RootView（Environment として注入）
//
// ==============================================================================

import Foundation
import Observation

@MainActor
@Observable
final class PartyViewState {
    private let appServices: AppServices

    var parties: [PartySnapshot] = []
    var isLoading: Bool = false
    private var ongoingLoad: Task<Void, Error>? = nil

    init(appServices: AppServices) {
        self.appServices = appServices
    }

    private var partyService: PartyProgressService { appServices.party }

    func loadAllParties() async throws {
        if let task = ongoingLoad {
            try await task.value
            return
        }

        let task = Task { @MainActor in
            isLoading = true
            defer {
                isLoading = false
                ongoingLoad = nil
            }
            let partySnapshots = try await partyService.allParties()
            parties = partySnapshots.sorted { $0.id < $1.id }
        }
        ongoingLoad = task
        try await task.value
    }

    func refresh() async throws {
        try await loadAllParties()
    }

    func updatePartyMembers(party: PartySnapshot, memberIds: [UInt8]) async throws {
        _ = try await partyService.updatePartyMembers(persistentIdentifier: party.persistentIdentifier, memberIds: memberIds)
        try await refresh()
    }
}
