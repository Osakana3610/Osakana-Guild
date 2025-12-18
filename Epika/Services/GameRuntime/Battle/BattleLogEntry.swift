import Foundation

struct BattleLogEntry: Codable, Sendable, Hashable {
    nonisolated enum LogType: UInt8, Codable, Sendable {
        case system = 1
        case action = 2
        case damage = 3
        case heal = 4
        case `guard` = 5
        case defeat = 6
        case victory = 7
        case miss = 8
        case status = 9
        case retreat = 10

        nonisolated init?(identifier: String) {
            switch identifier {
            case "system": self = .system
            case "action": self = .action
            case "damage": self = .damage
            case "heal": self = .heal
            case "guard": self = .guard
            case "defeat": self = .defeat
            case "victory": self = .victory
            case "miss": self = .miss
            case "status": self = .status
            case "retreat": self = .retreat
            default: return nil
            }
        }

        nonisolated var identifier: String {
            switch self {
            case .system: return "system"
            case .action: return "action"
            case .damage: return "damage"
            case .heal: return "heal"
            case .guard: return "guard"
            case .defeat: return "defeat"
            case .victory: return "victory"
            case .miss: return "miss"
            case .status: return "status"
            case .retreat: return "retreat"
            }
        }
    }

    let turn: Int
    let message: String
    let type: LogType
    let actorId: String?
    let targetId: String?

    nonisolated init(turn: Int,
                     message: String,
                     type: LogType,
                     actorId: String? = nil,
                     targetId: String? = nil) {
        self.turn = turn
        self.message = message
        self.type = type
        self.actorId = actorId
        self.targetId = targetId
    }
}
