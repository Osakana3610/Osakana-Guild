// ==============================================================================
// AppServices.StoryUnlocks.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ストーリー・ダンジョンの解放状態管理
//   - 難易度解放処理
//
// 【公開API】
//   - markStoryNodeAsRead(_:) → CachedStoryProgress
//     ストーリーを既読にし、関連モジュール（ダンジョン等）を解放
//   - unlockStoryForDungeonClear(_:)
//     ダンジョンクリア時に次のストーリーを解放
//   - unlockNextDifficultyIfEligible(for:clearedDifficulty:) → Bool
//     次の難易度を解放（無称号→魔性の→宿った→伝説の）
//
// 【解放フロー】
//   - ストーリー既読 → unlockModulesでダンジョン解放
//   - ダンジョンクリア → 次のストーリーを解放
//
// 【補助型】
//   - UnlockTarget: 解放対象（現在はdungeonのみ）
//
// ==============================================================================

import Foundation

// MARK: - Unlock Target Type

extension AppServices {
    enum UnlockTarget {
        case dungeon(UInt16)
    }
}

// MARK: - Next Difficulty Unlock

extension AppServices {
    /// 難易度クリア時に次の難易度を解放する
    /// - 無称号(2)クリア → 魔性の(4)解放
    /// - 魔性の(4)クリア → 宿った(5)解放
    /// - 宿った(5)クリア → 伝説の(6)解放
    @discardableResult
    func unlockNextDifficultyIfEligible(for snapshot: CachedDungeonProgress, clearedDifficulty: UInt8) async throws -> Bool {
        guard let nextDifficulty = DungeonDisplayNameFormatter.nextDifficulty(after: clearedDifficulty),
              snapshot.highestUnlockedDifficulty < nextDifficulty else { return false }
        return try await dungeon.unlockDifficulty(dungeonId: snapshot.dungeonId, difficulty: nextDifficulty)
    }
}

// MARK: - Initial Unlock

extension AppServices {
    /// 解放条件がないストーリーを初期解放する
    /// - Note: unlockRequirements: [] のストーリーは最初から解放済みとする
    func ensureInitialStoriesUnlocked() async throws {
        let definitions = masterDataCache.allStoryNodes
        var didChange = false

        for definition in definitions where definition.unlockRequirements.isEmpty {
            let changed = try await story.setUnlocked(true, nodeId: definition.id)
            didChange = didChange || changed
        }

        if didChange {
            await notifyProgressUnlocksDidChange()
        }
    }

    /// 解放条件がないダンジョンを初期解放する
    /// - Note: unlockConditions: [] のダンジョンは最初から解放済みとする
    func ensureInitialDungeonsUnlocked() async throws {
        let definitions = masterDataCache.allDungeons
        var didChange = false

        for definition in definitions where definition.unlockConditions.isEmpty {
            let changed = try await unlockDungeonIfNeeded(definition.id)
            didChange = didChange || changed
        }

        if didChange {
            await notifyProgressUnlocksDidChange()
        }
    }
}

// MARK: - Dungeon Clear → Story Unlock (Push型)

extension AppServices {
    /// ダンジョンクリア時に次のストーリーを解放する
    /// - Parameter dungeonId: クリアしたダンジョンID
    /// - Note: ダンジョンNをクリア → ストーリーN+1を解放
    func unlockStoryForDungeonClear(_ dungeonId: UInt16) async throws {
        let nextStoryId = dungeonId + 1

        // ストーリーが存在しなければ何もしない
        guard masterDataCache.storyNode(nextStoryId) != nil else { return }

        let didChange = try await story.setUnlocked(true, nodeId: nextStoryId)
        if didChange {
            await notifyProgressUnlocksDidChange()
        }
    }
}

// MARK: - Story Read → Dungeon Unlock (Push型)

extension AppServices {
    /// ストーリーノードを既読にし、同一トランザクション内で解放対象を処理する
    @discardableResult
    func markStoryNodeAsRead(_ nodeId: UInt16) async throws -> CachedStoryProgress {
        guard let definition = masterDataCache.storyNode(nodeId) else {
            throw ProgressError.invalidInput(description: "ストーリーノードが見つかりません: \(nodeId)")
        }

        let snapshot = try await story.markNodeAsRead(nodeId)

        for module in definition.unlockModules {
            switch module.type {
            case 0: // dungeon
                let dungeonId = UInt16(module.value)
                _ = try await unlockDungeonIfNeeded(dungeonId)
            default:
                break
            }
        }
        await notifyProgressUnlocksDidChange()
        return snapshot
    }
}


// MARK: - Helpers

private extension AppServices {
    func notifyProgressUnlocksDidChange() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .progressUnlocksDidChange, object: nil)
        }
    }

    func unlockDungeonIfNeeded(_ dungeonId: UInt16) async throws -> Bool {
        let unlocked = try await dungeon.setUnlocked(true, dungeonId: dungeonId)
        let difficultyChanged = try await dungeon.unlockDifficulty(
            dungeonId: dungeonId,
            difficulty: DungeonDisplayNameFormatter.initialDifficulty
        )
        return unlocked || difficultyChanged
    }
}
