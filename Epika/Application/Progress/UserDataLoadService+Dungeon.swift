// ==============================================================================
// UserDataLoadService+Dungeon.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ダンジョン進行データのロードとキャッシュ管理
//   - ダンジョン進行変更通知の購読
//
// ==============================================================================

import Foundation

// MARK: - Dungeon Change Notification

extension UserDataLoadService {
    /// ダンジョン進行変更通知用の構造体
    /// - Note: DungeonProgressServiceがsave()成功後に送信する
    struct DungeonChange: Sendable {
        let dungeonIds: [UInt16]

        static let fullReload = DungeonChange(dungeonIds: [])
    }
}

// MARK: - Dungeon Loading

extension UserDataLoadService {
    func loadDungeonSnapshots() async throws {
        let snapshots = try await appServices?.dungeon.allDungeonSnapshots() ?? []
        await MainActor.run {
            self.dungeonSnapshots = snapshots
            self.isDungeonSnapshotsLoaded = true
        }
    }
}

// MARK: - Dungeon Cache API

extension UserDataLoadService {
    /// 指定されたdungeonIdの進行情報を取得
    @MainActor
    func dungeonSnapshot(dungeonId: UInt16) -> DungeonSnapshot? {
        dungeonSnapshots.first { $0.dungeonId == dungeonId }
    }

    /// 解放済みダンジョン一覧
    @MainActor
    func unlockedDungeonSnapshots() -> [DungeonSnapshot] {
        dungeonSnapshots.filter { $0.isUnlocked }
    }

    /// クリア済みダンジョン一覧
    @MainActor
    func clearedDungeonSnapshots() -> [DungeonSnapshot] {
        dungeonSnapshots.filter { $0.highestClearedDifficulty != nil }
    }
}

// MARK: - Dungeon Change Notification Handling

extension UserDataLoadService {
    /// ダンジョン進行変更通知を購読開始
    @MainActor
    func subscribeDungeonChanges() {
        Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .dungeonProgressDidChange) {
                guard let self else { continue }

                if let dungeonIds = notification.userInfo?["dungeonIds"] as? [UInt16],
                   !dungeonIds.isEmpty {
                    await self.applyDungeonChange(dungeonIds: dungeonIds)
                } else {
                    // 後方互換性: ペイロードなしの通知は全件リロード
                    try? await self.loadDungeonSnapshots()
                }
            }
        }
    }

    /// ダンジョン進行変更をキャッシュへ適用（差分更新）
    @MainActor
    private func applyDungeonChange(dungeonIds: [UInt16]) async {
        guard let dungeon = appServices?.dungeon else { return }
        do {
            // 変更されたダンジョンのスナップショットを取得
            var snapshotMap = Dictionary(uniqueKeysWithValues: dungeonSnapshots.map { ($0.dungeonId, $0) })
            for dungeonId in dungeonIds {
                let snapshot = try await dungeon.ensureDungeonSnapshot(for: dungeonId)
                snapshotMap[dungeonId] = snapshot
            }
            dungeonSnapshots = Array(snapshotMap.values).sorted { $0.dungeonId < $1.dungeonId }
        } catch {
            #if DEBUG
            print("[UserDataLoadService] Failed to update dungeon snapshots: \(error)")
            #endif
        }
    }
}
