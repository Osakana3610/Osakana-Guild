import Foundation
import SwiftData

actor ProgressMetadataService {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func resetAllProgress() async throws {
        let context = makeContext()
        try deleteAll(PlayerProfileRecord.self, context: context)
        try deleteAll(InventoryItemRecord.self, context: context)
        try deleteAll(CharacterRecord.self, context: context)
        try deleteAll(CharacterEquipmentRecord.self, context: context)
        try deleteAll(PartyRecord.self, context: context)
        try deleteAll(PartyMemberRecord.self, context: context)
        try deleteAll(StoryRecord.self, context: context)
        try deleteAll(StoryNodeProgressRecord.self, context: context)
        try deleteAll(DungeonRecord.self, context: context)
        try deleteAll(DungeonFloorRecord.self, context: context)
        try deleteAll(DungeonEncounterRecord.self, context: context)
        try deleteAll(ExplorationRunRecord.self, context: context)
        try deleteAll(ExplorationEventRecord.self, context: context)
        try deleteAll(ExplorationEventDropRecord.self, context: context)
        try deleteAll(ExplorationBattleLogRecord.self, context: context)
        try deleteAll(ShopRecord.self, context: context)
        try deleteAll(ShopStockRecord.self, context: context)
        try deleteAll(ProgressMetadataRecord.self, context: context)

        let metadata = ProgressMetadataRecord(createdAt: Date(), updatedAt: Date())
        context.insert(metadata)
        try saveIfNeeded(context)
    }

    func loadSuperRareDailyState(currentDate: Date = Date()) async throws -> SuperRareDailyState {
        let context = makeContext()
        let metadata = try ensureMetadata(context: context)
        let identifier = Self.jstDayIdentifier(for: currentDate)
        if metadata.superRareStateDateJST != identifier {
            metadata.superRareStateDateJST = identifier
            metadata.superRareTriggered = false
            metadata.updatedAt = Date()
            try saveIfNeeded(context)
        }
        return SuperRareDailyState(jstDayIdentifier: identifier,
                                   hasTriggered: metadata.superRareTriggered)
    }

    func updateSuperRareDailyState(_ state: SuperRareDailyState) async throws {
        let context = makeContext()
        let metadata = try ensureMetadata(context: context)
        metadata.superRareStateDateJST = state.jstDayIdentifier
        metadata.superRareTriggered = state.hasTriggered
        metadata.updatedAt = Date()
        try saveIfNeeded(context)
    }
}

private extension ProgressMetadataService {
    static let jstTimeZone = TimeZone(identifier: "Asia/Tokyo")!

    static func jstDayIdentifier(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jstTimeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    func ensureMetadata(context: ModelContext) throws -> ProgressMetadataRecord {
        let identifier = ProgressMetadataRecord.defaultIdentifier
        var descriptor = FetchDescriptor<ProgressMetadataRecord>(predicate: #Predicate { $0.identifier == identifier })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let now = Date()
        let metadata = ProgressMetadataRecord(createdAt: now, updatedAt: now)
        context.insert(metadata)
        return metadata
    }

    func deleteAll<T: PersistentModel>(_ type: T.Type, context: ModelContext) throws {
        let descriptor = FetchDescriptor<T>()
        let records = try context.fetch(descriptor)
        for record in records {
            context.delete(record)
        }
    }

    func saveIfNeeded(_ context: ModelContext) throws {
        guard context.hasChanges else { return }
        try context.save()
    }
}
