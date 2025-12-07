import Foundation

enum RuntimeError: Error, LocalizedError {
    case masterDataNotFound(entity: String, identifier: String)
    case invalidConfiguration(reason: String)
    case explorationAlreadyActive(dungeonId: UInt8)
    case missingProgressData(reason: String)

    var errorDescription: String? {
        switch self {
        case .masterDataNotFound(let entity, let identifier):
            return "マスターデータ \(entity) (ID: \(identifier)) が見つかりません"
        case .invalidConfiguration(let reason):
            return reason
        case .explorationAlreadyActive(let dungeonId):
            return "既にダンジョン (ID: \(dungeonId)) の探索が進行中です"
        case .missingProgressData(let reason):
            return reason
        }
    }
}
