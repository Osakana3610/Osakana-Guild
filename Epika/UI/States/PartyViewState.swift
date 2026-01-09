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
//   - parties: UserDataLoadServiceのキャッシュを参照
//   - 更新時はキャッシュを無効化して再読み込み
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

    var isLoading: Bool = false

    init(appServices: AppServices) {
        self.appServices = appServices
    }

    /// キャッシュからパーティ一覧を取得
    var parties: [CachedParty] {
        appServices.userDataLoad.parties
    }

    /// キャッシュからパーティを読み込み（キャッシュ済みならすぐ返る）
    func loadAllParties() async throws {
        isLoading = true
        defer { isLoading = false }
        _ = try await appServices.userDataLoad.getParties()
    }

    /// キャッシュを無効化して再読み込み
    func refresh() async throws {
        appServices.userDataLoad.invalidateParties()
        try await loadAllParties()
    }

    func updatePartyMembers(party: CachedParty, memberIds: [UInt8]) async throws {
        _ = try await appServices.party.updatePartyMembers(partyId: party.id, memberIds: memberIds)
        try await refresh()
    }
}
