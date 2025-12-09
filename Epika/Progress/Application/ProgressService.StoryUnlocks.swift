import Foundation

// MARK: - Story & Dungeon Unlocks
extension ProgressService {
    @discardableResult
    func markStoryNodeAsRead(_ nodeId: UInt16) async throws -> StorySnapshot {
        let snapshot = try await story.markNodeAsRead(nodeId)
        try await synchronizeStoryAndDungeonUnlocks()
        return snapshot
    }

    func synchronizeStoryAndDungeonUnlocks() async throws {
        let storyDefinitions = try await environment.masterDataService.getAllStoryNodes()
        let dungeonDefinitions = try await environment.masterDataService.getAllDungeons()

        let storySnapshot = try await story.currentStorySnapshot()
        var dungeonSnapshots = try await dungeon.allDungeonSnapshots()

        var didUnlockDifficulty = false
        for snapshot in dungeonSnapshots {
            if try await unlockManiaDifficultyIfEligible(for: snapshot) {
                didUnlockDifficulty = true
            }
        }

        if didUnlockDifficulty {
            dungeonSnapshots = try await dungeon.allDungeonSnapshots()
        }

        let readStoryIds = storySnapshot.readNodeIds
        let clearedDungeonIds = Set(dungeonSnapshots.filter { $0.isCleared }.map { $0.dungeonId })

        try await synchronizeStoryUnlocks(definitions: storyDefinitions,
                                          readStoryIds: readStoryIds,
                                          clearedDungeonIds: clearedDungeonIds)

        try await synchronizeDungeonUnlocks(definitions: dungeonDefinitions,
                                            readStoryIds: readStoryIds,
                                            clearedDungeonIds: clearedDungeonIds)
        NotificationCenter.default.post(name: .progressUnlocksDidChange, object: nil)
    }

    @discardableResult
    func unlockManiaDifficultyIfEligible(for snapshot: DungeonSnapshot) async throws -> Bool {
        guard snapshot.isCleared,
              snapshot.highestUnlockedDifficulty < UInt8(maniaDifficultyRank) else { return false }
        try await dungeon.unlockDifficulty(dungeonId: snapshot.dungeonId, difficulty: UInt8(maniaDifficultyRank))
        return true
    }
}

// MARK: - Private Helpers
private extension ProgressService {
    enum StoryRequirement {
        case storyRead(UInt16)
        case dungeonCleared(UInt16)
    }

    enum DungeonRequirement {
        case storyRead(UInt16)
        case dungeonCleared(UInt16)
        case alwaysUnlocked
    }

    func synchronizeStoryUnlocks(definitions: [StoryNodeDefinition],
                                 readStoryIds: Set<UInt16>,
                                 clearedDungeonIds: Set<UInt16>) async throws {
        let sortedDefinitions = definitions.sorted { lhs, rhs in
            if lhs.chapter != rhs.chapter { return lhs.chapter < rhs.chapter }
            if lhs.section != rhs.section { return lhs.section < rhs.section }
            return lhs.id < rhs.id
        }

        for definition in sortedDefinitions {
            let requirements = definition.unlockRequirements
                .compactMap { parseStoryRequirement($0) }

            var shouldUnlock: Bool
            if requirements.isEmpty {
                shouldUnlock = true
            } else {
                shouldUnlock = requirements.allSatisfy { requirement in
                    switch requirement {
                    case .storyRead(let storyId):
                        return readStoryIds.contains(storyId)
                    case .dungeonCleared(let dungeonId):
                        return clearedDungeonIds.contains(dungeonId)
                    }
                }
            }
            if readStoryIds.contains(definition.id) {
                shouldUnlock = true
            }
            try await story.setUnlocked(shouldUnlock, nodeId: definition.id)
        }
    }

    func synchronizeDungeonUnlocks(definitions: [DungeonDefinition],
                                   readStoryIds: Set<UInt16>,
                                   clearedDungeonIds: Set<UInt16>) async throws {
        for definition in definitions {
            let requirements = try definition.unlockConditions.map { try parseDungeonRequirement($0) }

            var shouldUnlock: Bool
            if requirements.isEmpty {
                shouldUnlock = true
            } else {
                shouldUnlock = requirements.allSatisfy { requirement in
                    switch requirement {
                    case .alwaysUnlocked:
                        return true
                    case .storyRead(let storyId):
                        return readStoryIds.contains(storyId)
                    case .dungeonCleared(let dungeonId):
                        return clearedDungeonIds.contains(dungeonId)
                    }
                }
            }

            if clearedDungeonIds.contains(definition.id) {
                shouldUnlock = true
            }

            try await dungeon.setUnlocked(shouldUnlock, dungeonId: definition.id)
        }
    }

    func parseStoryRequirement(_ raw: String) -> StoryRequirement? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("dungeonClear:") {
            let idString = String(truncatedRequirementValue(trimmed))
            guard let id = UInt16(idString) else { return nil }
            return .dungeonCleared(id)
        }
        if trimmed.hasPrefix("story:") {
            let idString = String(truncatedRequirementValue(trimmed))
            guard let id = UInt16(idString) else { return nil }
            return .storyRead(id)
        }
        if trimmed.hasPrefix("storyRead:") {
            let idString = String(truncatedRequirementValue(trimmed))
            guard let id = UInt16(idString) else { return nil }
            return .storyRead(id)
        }
        guard let id = UInt16(trimmed) else { return nil }
        return .storyRead(id)
    }

    func parseDungeonRequirement(_ raw: String) throws -> DungeonRequirement {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .alwaysUnlocked }
        if trimmed.hasPrefix("storyRead:") {
            let idString = String(truncatedRequirementValue(trimmed))
            guard let id = UInt16(idString) else {
                throw ProgressError.invalidInput(description: "無効なstoryRead ID: \(idString)")
            }
            return .storyRead(id)
        }
        if trimmed.hasPrefix("dungeonClear:") {
            let idString = String(truncatedRequirementValue(trimmed))
            guard let id = UInt16(idString) else {
                throw ProgressError.invalidInput(description: "無効なdungeonClear ID: \(idString)")
            }
            return .dungeonCleared(id)
        }
        throw ProgressError.invalidInput(description: "未知のダンジョン解放条件を検出しました: \(trimmed)")
    }

    func truncatedRequirementValue(_ raw: String) -> Substring {
        guard let separatorIndex = raw.firstIndex(of: ":") else { return raw[...] }
        return raw[raw.index(after: separatorIndex)...]
    }
}
