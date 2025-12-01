import Foundation

// MARK: - Story & Dungeon Unlocks
extension ProgressService {
    @discardableResult
    func markStoryNodeAsRead(_ nodeId: String) async throws -> StorySnapshot {
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
              snapshot.highestUnlockedDifficulty < maniaDifficultyRank else { return false }
        try await dungeon.unlockDifficulty(dungeonId: snapshot.dungeonId, difficulty: maniaDifficultyRank)
        return true
    }
}

// MARK: - Private Helpers
private extension ProgressService {
    enum StoryRequirement {
        case storyRead(String)
        case dungeonCleared(String)
    }

    enum DungeonRequirement {
        case storyRead(String)
        case dungeonCleared(String)
        case alwaysUnlocked
    }

    func synchronizeStoryUnlocks(definitions: [StoryNodeDefinition],
                                 readStoryIds: Set<String>,
                                 clearedDungeonIds: Set<String>) async throws {
        let sortedDefinitions = definitions.sorted { lhs, rhs in
            if lhs.chapter != rhs.chapter { return lhs.chapter < rhs.chapter }
            if lhs.section != rhs.section { return lhs.section < rhs.section }
            return lhs.id < rhs.id
        }

        for definition in sortedDefinitions {
            let requirements = definition.unlockRequirements
                .sorted { $0.orderIndex < $1.orderIndex }
                .compactMap { parseStoryRequirement($0.value) }

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
                                   readStoryIds: Set<String>,
                                   clearedDungeonIds: Set<String>) async throws {
        for definition in definitions {
            let rawConditions = definition.unlockConditions
                .sorted { $0.orderIndex < $1.orderIndex }

            let requirements = try rawConditions.map { try parseDungeonRequirement($0.value) }

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
            let id = String(truncatedRequirementValue(trimmed))
            return .dungeonCleared(id)
        }
        if trimmed.hasPrefix("story:") {
            let id = String(truncatedRequirementValue(trimmed))
            return .storyRead(id)
        }
        if trimmed.hasPrefix("storyRead:") {
            let id = String(truncatedRequirementValue(trimmed))
            return .storyRead(id)
        }
        return .storyRead(trimmed)
    }

    func parseDungeonRequirement(_ raw: String) throws -> DungeonRequirement {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .alwaysUnlocked }
        if trimmed.hasPrefix("storyRead:") {
            let id = String(truncatedRequirementValue(trimmed))
            return .storyRead(id)
        }
        if trimmed.hasPrefix("dungeonClear:") {
            let id = String(truncatedRequirementValue(trimmed))
            return .dungeonCleared(id)
        }
        throw ProgressError.invalidInput(description: "未知のダンジョン解放条件を検出しました: \(trimmed)")
    }

    func truncatedRequirementValue(_ raw: String) -> Substring {
        guard let separatorIndex = raw.firstIndex(of: ":") else { return raw[...] }
        return raw[raw.index(after: separatorIndex)...]
    }
}
