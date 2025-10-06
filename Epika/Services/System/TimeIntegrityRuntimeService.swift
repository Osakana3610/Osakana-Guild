import Foundation
import Observation

enum TimeIntegrityStatus: String, CaseIterable {
    case valid = "valid"
    case timeWentBackward = "time_went_backward"
    case suspiciousTimeJump = "suspicious_time_jump"
    case syncRequired = "sync_required"
}

enum OperationType: String, CaseIterable, Codable {
    case characterCreation = "character_creation"
    case characterDeletion = "character_deletion"
    case characterRevival = "character_revival"
    case jobChange = "job_change"
    case equipmentChange = "equipment_change"
    case explorationStart = "exploration_start"
    case explorationComplete = "exploration_complete"
    case itemPurchase = "item_purchase"
    case itemSale = "item_sale"
    case itemSynthesis = "item_synthesis"
    case dataSync = "data_sync"
    case appLaunch = "app_launch"
    case appTerminate = "app_terminate"
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
