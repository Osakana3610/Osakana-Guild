import Foundation
import SwiftData

actor AutoTradeProgressService {
    struct Rule: Sendable, Identifiable {
        let id: UUID
        let compositeKey: String
        let displayName: String
        let createdAt: Date
    }

    private let container: ModelContainer
    private let playerService: PlayerProgressService
    private let environment: ProgressEnvironment

    init(container: ModelContainer,
         playerService: PlayerProgressService,
         environment: ProgressEnvironment) {
        self.container = container
        self.playerService = playerService
        self.environment = environment
    }

    // MARK: - Public API

    func allRules() async throws -> [Rule] {
        let context = makeContext()
        var descriptor = FetchDescriptor<AutoTradeRuleRecord>()
        descriptor.sortBy = [SortDescriptor(\AutoTradeRuleRecord.createdAt, order: .forward)]
        let records = try context.fetch(descriptor)
        return records.map(makeRule(_:))
    }

    func addRule(autoTradeKey: String, displayName: String) async throws -> Rule {
        let context = makeContext()
        let existing = try fetchRecord(compositeKey: autoTradeKey, context: context)
        if let existing {
            return makeRule(existing)
        }
        let now = Date()
        let record = AutoTradeRuleRecord(compositeKey: autoTradeKey,
                                          displayName: displayName,
                                          createdAt: now)
        context.insert(record)
        try context.save()
        return makeRule(record)
    }

    func removeRule(compositeKey: String) async throws {
        let context = makeContext()
        guard let record = try fetchRecord(compositeKey: compositeKey, context: context) else {
            throw ProgressError.invalidInput(description: "指定された自動売却ルールが見つかりません: \(compositeKey)")
        }
        context.delete(record)
        try context.save()
    }

    func removeRule(id: UUID) async throws {
        let context = makeContext()
        var descriptor = FetchDescriptor<AutoTradeRuleRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            throw ProgressError.invalidInput(description: "指定された自動売却ルールが見つかりません: \(id.uuidString)")
        }
        context.delete(record)
        try context.save()
    }

    func shouldAutoSell(compositeKey: String) async throws -> Bool {
        let context = makeContext()
        let record = try fetchRecord(compositeKey: compositeKey, context: context)
        return record != nil
    }

    func registeredCompositeKeys() async throws -> Set<String> {
        let context = makeContext()
        let descriptor = FetchDescriptor<AutoTradeRuleRecord>()
        let records = try context.fetch(descriptor)
        return Set(records.map { $0.compositeKey })
    }

    // MARK: - Private Helpers

    private func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func fetchRecord(compositeKey: String, context: ModelContext) throws -> AutoTradeRuleRecord? {
        var descriptor = FetchDescriptor<AutoTradeRuleRecord>(predicate: #Predicate { $0.compositeKey == compositeKey })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func makeRule(_ record: AutoTradeRuleRecord) -> Rule {
        Rule(id: record.id,
             compositeKey: record.compositeKey,
             displayName: record.displayName,
             createdAt: record.createdAt)
    }
}
