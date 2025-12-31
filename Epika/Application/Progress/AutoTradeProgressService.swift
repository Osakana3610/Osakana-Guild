// ==============================================================================
// AutoTradeProgressService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 自動売却ルールの管理
//   - 登録されたアイテムをドロップ時に自動で売却
//
// 【公開API】
//   - allRules() → [Rule] - 全ルールを取得
//   - addRule(...) → Rule - ルールを追加
//   - removeRule(id:) - ルールを削除
//   - registeredStackKeys() → Set<String> - 登録済みキーのセット
//
// 【データ構造】
//   - Rule: 自動売却ルール
//     - stackKey（id）: 称号+アイテムIDの組み合わせ
//     - superRareTitleId, normalTitleId, itemId
//     - socket系フィールド（宝石装着時用）
//
// 【使用箇所】
//   - AppServices.ExplorationRuntime: ドロップ時の自動売却判定
//   - AutoTradeView: ルール管理UI
//
// ==============================================================================

import Foundation
import SwiftData

actor AutoTradeProgressService {
    struct Rule: Sendable, Identifiable, Hashable {
        let id: String  // stackKey
        let superRareTitleId: UInt8
        let normalTitleId: UInt8
        let itemId: UInt16
        let socketSuperRareTitleId: UInt8
        let socketNormalTitleId: UInt8
        let socketItemId: UInt16
        let updatedAt: Date

        var stackKey: String { id }
    }

    private let contextProvider: SwiftDataContextProvider
    private let gameStateService: GameStateService
    private var cachedStackKeys: Set<String>?

    init(contextProvider: SwiftDataContextProvider, gameStateService: GameStateService) {
        self.contextProvider = contextProvider
        self.gameStateService = gameStateService
    }

    // MARK: - Public API

    func allRules() async throws -> [Rule] {
        let context = contextProvider.makeContext()
        var descriptor = FetchDescriptor<AutoTradeRuleRecord>()
        descriptor.sortBy = [SortDescriptor(\AutoTradeRuleRecord.updatedAt, order: .forward)]
        let records = try context.fetch(descriptor)
        return records.map(makeRule(_:))
    }

    func addRule(superRareTitleId: UInt8,
                 normalTitleId: UInt8,
                 itemId: UInt16,
                 socketSuperRareTitleId: UInt8 = 0,
                 socketNormalTitleId: UInt8 = 0,
                 socketItemId: UInt16 = 0) async throws -> Rule {
        let context = contextProvider.makeContext()
        let existing = try fetchRecord(
            superRareTitleId: superRareTitleId,
            normalTitleId: normalTitleId,
            itemId: itemId,
            socketSuperRareTitleId: socketSuperRareTitleId,
            socketNormalTitleId: socketNormalTitleId,
            socketItemId: socketItemId,
            context: context
        )
        if let existing {
            return makeRule(existing)
        }
        let now = Date()
        let record = AutoTradeRuleRecord(
            superRareTitleId: superRareTitleId,
            normalTitleId: normalTitleId,
            itemId: itemId,
            socketSuperRareTitleId: socketSuperRareTitleId,
            socketNormalTitleId: socketNormalTitleId,
            socketItemId: socketItemId,
            updatedAt: now
        )
        context.insert(record)
        try context.save()
        cachedStackKeys = nil
        return makeRule(record)
    }

    func removeRule(stackKey: String) async throws {
        guard let components = StackKeyComponents(stackKey: stackKey) else {
            throw ProgressError.invalidInput(description: "不正なstackKeyです: \(stackKey)")
        }
        let context = contextProvider.makeContext()
        guard let record = try fetchRecord(
            superRareTitleId: components.superRareTitleId,
            normalTitleId: components.normalTitleId,
            itemId: components.itemId,
            socketSuperRareTitleId: components.socketSuperRareTitleId,
            socketNormalTitleId: components.socketNormalTitleId,
            socketItemId: components.socketItemId,
            context: context
        ) else {
            throw ProgressError.invalidInput(description: "指定された自動売却ルールが見つかりません: \(stackKey)")
        }
        context.delete(record)
        try context.save()
        cachedStackKeys = nil
    }

    func shouldAutoSell(stackKey: String) async throws -> Bool {
        guard let components = StackKeyComponents(stackKey: stackKey) else {
            return false
        }
        let context = contextProvider.makeContext()
        let record = try fetchRecord(
            superRareTitleId: components.superRareTitleId,
            normalTitleId: components.normalTitleId,
            itemId: components.itemId,
            socketSuperRareTitleId: components.socketSuperRareTitleId,
            socketNormalTitleId: components.socketNormalTitleId,
            socketItemId: components.socketItemId,
            context: context
        )
        return record != nil
    }

    func registeredStackKeys() async throws -> Set<String> {
        if let cachedStackKeys {
            return cachedStackKeys
        }
        let context = contextProvider.makeContext()
        let descriptor = FetchDescriptor<AutoTradeRuleRecord>()
        let records = try context.fetch(descriptor)
        let keys = Set(records.map { $0.stackKey })
        cachedStackKeys = keys
        return keys
    }

    // MARK: - Private Helpers

    private func fetchRecord(superRareTitleId: UInt8,
                             normalTitleId: UInt8,
                             itemId: UInt16,
                             socketSuperRareTitleId: UInt8,
                             socketNormalTitleId: UInt8,
                             socketItemId: UInt16,
                             context: ModelContext) throws -> AutoTradeRuleRecord? {
        var descriptor = FetchDescriptor<AutoTradeRuleRecord>(predicate: #Predicate {
            $0.superRareTitleId == superRareTitleId &&
            $0.normalTitleId == normalTitleId &&
            $0.itemId == itemId &&
            $0.socketSuperRareTitleId == socketSuperRareTitleId &&
            $0.socketNormalTitleId == socketNormalTitleId &&
            $0.socketItemId == socketItemId
        })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func makeRule(_ record: AutoTradeRuleRecord) -> Rule {
        Rule(id: record.stackKey,
             superRareTitleId: record.superRareTitleId,
             normalTitleId: record.normalTitleId,
             itemId: record.itemId,
             socketSuperRareTitleId: record.socketSuperRareTitleId,
             socketNormalTitleId: record.socketNormalTitleId,
             socketItemId: record.socketItemId,
             updatedAt: record.updatedAt)
    }
}
