// ==============================================================================
// ExplorationSnapshot.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 探索セッションのイミュータブルスナップショット
//   - 探索状態・報酬・エンカウントログの表現
//
// 【データ構造】
//   - ExplorationSnapshot: 探索セッション全情報
//     - dungeonId, displayDungeonName, activeFloorNumber
//     - party (PartySummary): 参加パーティ情報
//     - startedAt, lastUpdatedAt, expectedReturnAt
//     - encounterLogs: エンカウント履歴
//     - rewards (Rewards): 獲得経験値・ゴールド・ドロップ
//     - summary (Summary): 表示用サマリー
//     - status (Status): 進行状態
//     - metadata (ProgressMetadata): 作成・更新日時
//
//   - Status: running/completed/cancelled/defeated
//   - Rewards: experience, gold, itemDrops
//   - PartySummary: partyId, memberCharacterIds, inventorySnapshotId
//   - EncounterLog: フロアごとのイベント記録
//     - Kind: nothing/enemyEncounter/scriptedEvent
//     - CombatSummary: 戦闘結果詳細
//     - Context: 表示用付加情報（exp/gold/drops/effects）
//   - Summary: 探索進行サマリー（タイミング・本文）
//
// 【ヘルパーメソッド】
//   - resultMessage(for:) → String: 終了ステータスのメッセージ
//   - makeSummary(...) → Summary: サマリー生成
//   - eventTitle(for:status:) → String: イベント表示タイトル
//   - localizedCombatResult(_:) → String: 戦闘結果のローカライズ
//
// 【使用箇所】
//   - ExplorationProgressService: 探索履歴の永続化・取得
//   - AdventureView: 探索状態の表示
//   - RecentExplorationLogsView: 過去の探索履歴表示
//
// ==============================================================================

import Foundation
import SwiftData

struct ExplorationSnapshot: Sendable, Hashable {
    enum Status: UInt8, Sendable, Hashable {
        case running = 1
        case completed = 2
        case cancelled = 3
        case defeated = 4

        nonisolated init?(identifier: String) {
            switch identifier {
            case "running": self = .running
            case "completed": self = .completed
            case "cancelled": self = .cancelled
            case "defeated": self = .defeated
            default: return nil
            }
        }

        nonisolated var identifier: String {
            switch self {
            case .running: return "running"
            case .completed: return "completed"
            case .cancelled: return "cancelled"
            case .defeated: return "defeated"
            }
        }
    }

    /// 探索報酬（経験値・ゴールド・アイテムドロップ）
    struct Rewards: Sendable, Hashable {
        struct AutoSellEntry: Sendable, Hashable {
            var itemId: UInt16
            var superRareTitleId: UInt8
            var normalTitleId: UInt8
            var quantity: Int
        }

        struct ItemDropSummary: Sendable, Hashable, Identifiable {
            var itemId: UInt16
            var superRareTitleId: UInt8
            var normalTitleId: UInt8
            var quantity: Int

            var id: String {
                "\(itemId)|\(superRareTitleId)|\(normalTitleId)"
            }

            var isSuperRare: Bool {
                superRareTitleId > 0
            }
        }

        var experience: Int = 0
        var gold: Int = 0
        var itemDrops: [ItemDropSummary] = []
        var autoSellGold: Int = 0
        var autoSoldItems: [AutoSellEntry] = []
    }

    struct PartySummary: Sendable, Hashable {
        var partyId: UInt8
        var memberCharacterIds: [UInt8]
        var inventorySnapshotId: UUID?
    }

    struct EncounterLog: Sendable, Hashable {
        enum Kind: UInt8, Sendable {
            case nothing = 1
            case enemyEncounter = 2
            case scriptedEvent = 3

            nonisolated init?(identifier: String) {
                switch identifier {
                case "nothing": self = .nothing
                case "enemyEncounter": self = .enemyEncounter
                case "scriptedEvent": self = .scriptedEvent
                default: return nil
                }
            }

            nonisolated var identifier: String {
                switch self {
                case .nothing: return "nothing"
                case .enemyEncounter: return "enemyEncounter"
                case .scriptedEvent: return "scriptedEvent"
                }
            }
        }

        struct CombatSummary: Sendable, Hashable {
            var enemyId: UInt16
            var enemyName: String
            var result: String
            var turns: Int
            var battleLogId: PersistentIdentifier?
        }

        /// イベントの付加情報（表示用）
        struct Context: Sendable, Hashable {
            var exp: String?
            var gold: String?
            var drops: String?
            var effects: String?
        }

        var id: UUID
        var floorNumber: Int
        var eventIndex: Int
        var kind: Kind
        var referenceId: String?
        var occurredAt: Date
        var context: Context
        var metadata: ProgressMetadata
        var combatSummary: CombatSummary?
    }

    struct Summary: Sendable, Hashable {
        /// iOS 17のAttributeGraphバグ回避のため、associated valueを持たないenumに変更
        enum TimingKind: UInt8, Sendable, Hashable {
            case expected = 1
            case actual = 2
        }

        var floorNumber: Int
        var timingKind: TimingKind
        var timingDate: Date
        var body: String
    }

    var dungeonId: UInt16
    var displayDungeonName: String
    var activeFloorNumber: Int
    var party: PartySummary
    var startedAt: Date
    var lastUpdatedAt: Date

    /// Identifiable用のID（startedAtのミリ秒タイムスタンプ）
    var id: Int64 {
        Int64(startedAt.timeIntervalSince1970 * 1000)
    }
    var expectedReturnAt: Date?
    var encounterLogs: [EncounterLog]
    var rewards: Rewards
    var summary: Summary
    var status: Status
    var metadata: ProgressMetadata
}

extension ExplorationSnapshot {
    static func resultMessage(for status: Status) -> String {
        switch status {
        case .completed:
            return "迷宮を制覇しました！"
        case .defeated:
            return "パーティは全滅しました……"
        case .cancelled:
            return "パーティは帰還しました。"
        case .running:
            return ""
        }
    }

    static func makeSummary(displayDungeonName: String,
                            status: Status,
                            activeFloorNumber: Int,
                            expectedReturnAt: Date?,
                            startedAt: Date,
                            lastUpdatedAt: Date,
                            logs: [EncounterLog]) -> Summary {
        let timingKind: Summary.TimingKind
        let timingDate: Date
        switch status {
        case .running:
            timingKind = .expected
            timingDate = expectedReturnAt ?? startedAt
        case .completed, .defeated, .cancelled:
            timingKind = .actual
            timingDate = lastUpdatedAt
        }

        let body: String
        switch status {
        case .running:
            let eventDescription: String
            if let last = logs.last {
                eventDescription = eventTitle(for: last, status: status)
            } else {
                eventDescription = "探索準備中..."
            }
            body = "\(displayDungeonName)：\(eventDescription)"
        case .completed, .defeated, .cancelled:
            body = "\(displayDungeonName)：\(resultMessage(for: status))"
        }

        return Summary(floorNumber: activeFloorNumber,
                       timingKind: timingKind,
                       timingDate: timingDate,
                       body: body)
    }

    static func eventTitle(for encounter: EncounterLog, status: Status) -> String {
        let base: String
        switch encounter.kind {
        case .nothing:
            base = status == .running ? "探索進行中" : "何も起こらなかった"
        case .enemyEncounter:
            if let enemyName = encounter.combatSummary?.enemyName, !enemyName.isEmpty {
                base = enemyName
            } else if let reference = encounter.referenceId, !reference.isEmpty {
                base = reference
            } else {
                base = "敵遭遇"
            }
        case .scriptedEvent:
            if let reference = encounter.referenceId, !reference.isEmpty {
                base = reference
            } else {
                base = "イベント"
            }
        }

        // 戦闘結果は CombatSummary から取得
        if let result = encounter.combatSummary?.result, !result.isEmpty {
            return "\(base)(\(localizedCombatResult(result)))"
        }
        return base
    }

    static func localizedCombatResult(_ raw: String) -> String {
        switch raw.lowercased() {
        case "victory":
            return "勝利"
        case "defeat":
            return "敗北"
        case "retreat":
            return "撤退"
        default:
            return raw
        }
    }
}

// MARK: - EncounterLog Conversion from Runtime Entry

extension ExplorationSnapshot.EncounterLog {
    /// ランタイムのイベントログエントリから EncounterLog を生成
    init(from entry: ExplorationEventLogEntry, battleLogId: PersistentIdentifier?, masterData: MasterDataCache) {
        let kind: Kind
        var referenceId: String?
        var combatSummary: CombatSummary?

        switch entry.kind {
        case .nothing:
            kind = .nothing

        case .combat(let combat):
            kind = .enemyEncounter
            referenceId = String(combat.enemy.id)
            combatSummary = CombatSummary(
                enemyId: combat.enemy.id,
                enemyName: combat.enemy.name,
                result: combat.result.identifier,
                turns: combat.turns,
                battleLogId: battleLogId
            )

        case .scripted(let scripted):
            kind = .scriptedEvent
            referenceId = scripted.name
        }

        // Context構造体を構築
        var context = Context()
        if entry.experienceGained > 0 {
            context.exp = "\(entry.experienceGained)"
        }
        if entry.goldGained > 0 {
            context.gold = "\(entry.goldGained)"
        }
        if !entry.drops.isEmpty {
            let dropStrings = entry.drops.map { drop in
                "\(drop.item.name)x\(drop.quantity)"
            }
            if !dropStrings.isEmpty {
                context.drops = dropStrings.joined(separator: ", ")
            }
        }

        self.init(
            id: UUID(),
            floorNumber: entry.floorNumber,
            eventIndex: entry.eventIndex,
            kind: kind,
            referenceId: referenceId,
            occurredAt: entry.occurredAt,
            context: context,
            metadata: ProgressMetadata(createdAt: entry.occurredAt, updatedAt: entry.occurredAt),
            combatSummary: combatSummary
        )
    }
}
