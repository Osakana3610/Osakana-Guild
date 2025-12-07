import Foundation
import SwiftData

struct ExplorationSnapshot: Sendable, Hashable {
    enum Status: String, Sendable, Hashable {
        case running
        case completed
        case cancelled
        case defeated
    }

    struct PartySummary: Sendable, Hashable {
        var partyId: UInt8
        var memberCharacterIds: [UInt8]
        var inventorySnapshotId: UUID?
    }

    struct EncounterLog: Sendable, Hashable {
        enum Kind: String, Sendable {
            case nothing
            case enemyEncounter
            case scriptedEvent
        }

        struct CombatSummary: Sendable, Hashable {
            var enemyId: UInt16
            var enemyName: String
            var result: String
            var turns: Int
            var battleLogData: Data?
        }

        var id: UUID
        var floorNumber: Int
        var eventIndex: Int
        var kind: Kind
        var referenceId: String?
        var occurredAt: Date
        var context: [String: String]
        var metadata: ProgressMetadata
        var combatSummary: CombatSummary?
    }

    struct Summary: Sendable, Hashable {
        enum Timing: Sendable, Hashable {
            case expectedReturn(Date)
            case actualReturn(Date)
        }

        var floorNumber: Int
        var timing: Timing
        var body: String
    }

    let persistentIdentifier: PersistentIdentifier
    var id: UUID
    var dungeonId: UInt16
    var displayDungeonName: String
    var activeFloorNumber: Int
    var party: PartySummary
    var startedAt: Date
    var lastUpdatedAt: Date
    var expectedReturnAt: Date?
    var encounterLogs: [EncounterLog]
    var rewards: [String: Int]
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
        let timing: Summary.Timing
        switch status {
        case .running:
            let reference = expectedReturnAt ?? startedAt
            timing = .expectedReturn(reference)
        case .completed, .defeated, .cancelled:
            timing = .actualReturn(lastUpdatedAt)
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
                       timing: timing,
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

        if let resultRaw = encounter.context["result"], !resultRaw.isEmpty {
            return "\(base)(\(localizedCombatResult(resultRaw)))"
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
