import Foundation
import Observation

enum TimeIntegrityStatus: UInt8, CaseIterable {
    case valid = 1
    case timeWentBackward = 2
    case suspiciousTimeJump = 3
    case syncRequired = 4

    nonisolated init?(identifier: String) {
        switch identifier {
        case "valid": self = .valid
        case "time_went_backward": self = .timeWentBackward
        case "suspicious_time_jump": self = .suspiciousTimeJump
        case "sync_required": self = .syncRequired
        default: return nil
        }
    }

    nonisolated var identifier: String {
        switch self {
        case .valid: return "valid"
        case .timeWentBackward: return "time_went_backward"
        case .suspiciousTimeJump: return "suspicious_time_jump"
        case .syncRequired: return "sync_required"
        }
    }
}

enum OperationType: UInt8, CaseIterable, Codable {
    case characterCreation = 1
    case characterDeletion = 2
    case characterRevival = 3
    case jobChange = 4
    case equipmentChange = 5
    case explorationStart = 6
    case explorationComplete = 7
    case itemPurchase = 8
    case itemSale = 9
    case itemSynthesis = 10
    case dataSync = 11
    case appLaunch = 12
    case appTerminate = 13

    nonisolated init?(identifier: String) {
        switch identifier {
        case "character_creation": self = .characterCreation
        case "character_deletion": self = .characterDeletion
        case "character_revival": self = .characterRevival
        case "job_change": self = .jobChange
        case "equipment_change": self = .equipmentChange
        case "exploration_start": self = .explorationStart
        case "exploration_complete": self = .explorationComplete
        case "item_purchase": self = .itemPurchase
        case "item_sale": self = .itemSale
        case "item_synthesis": self = .itemSynthesis
        case "data_sync": self = .dataSync
        case "app_launch": self = .appLaunch
        case "app_terminate": self = .appTerminate
        default: return nil
        }
    }

    nonisolated var identifier: String {
        switch self {
        case .characterCreation: return "character_creation"
        case .characterDeletion: return "character_deletion"
        case .characterRevival: return "character_revival"
        case .jobChange: return "job_change"
        case .equipmentChange: return "equipment_change"
        case .explorationStart: return "exploration_start"
        case .explorationComplete: return "exploration_complete"
        case .itemPurchase: return "item_purchase"
        case .itemSale: return "item_sale"
        case .itemSynthesis: return "item_synthesis"
        case .dataSync: return "data_sync"
        case .appLaunch: return "app_launch"
        case .appTerminate: return "app_terminate"
        }
    }
}

@MainActor
@Observable
class TimeIntegrityRuntimeService {
    static let shared = TimeIntegrityRuntimeService()

    var timeIntegrityStatus: TimeIntegrityStatus = .valid
    var lastValidatedTime: Date?

    private let maxTimeDrift: TimeInterval = 300 // 5分
    private var lastKnownValidTime: Date = Date()
    

    private init() {}

    func validateTimeIntegrity() -> Bool {
        let currentTime = Date()

        // 時間の逆行チェック
        if currentTime < lastKnownValidTime {
            timeIntegrityStatus = .timeWentBackward
            return false
        }

        // 急激な時間進行チェック
        let timeDiff = currentTime.timeIntervalSince(lastKnownValidTime)
        if timeDiff > maxTimeDrift {
            timeIntegrityStatus = .suspiciousTimeJump
            return false
        }

        lastKnownValidTime = currentTime
        lastValidatedTime = currentTime
        timeIntegrityStatus = .valid
        return true
    }

}


@MainActor
class OperationHistoryManager {
    static let shared = OperationHistoryManager()

    private var operationLog: [OperationEntry] = []
    private let maxLogSize = 10000

    struct OperationEntry: Codable, Identifiable {
        let id: String
        let timestamp: Date
        let operation: OperationType
        let metadata: [String: String]
    }

    private init() {}

    func logOperation(
        _ type: OperationType,
        metadata: [String: String] = [:]
    ) async {
        let entry = OperationEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            operation: type,
            metadata: metadata
        )

        operationLog.append(entry)

        // ログサイズ制限
        if operationLog.count > maxLogSize {
            operationLog.removeFirst(operationLog.count - maxLogSize)
        }

        // 時間整合性チェック
        _ = TimeIntegrityRuntimeService.shared.validateTimeIntegrity()
    }

}
