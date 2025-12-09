import Foundation

struct BattleLogEntry: Codable, Sendable, Hashable {
    nonisolated enum LogType: String, Codable, Sendable {
        case system
        case action
        case damage
        case heal
        case `guard`
        case defeat
        case victory
        case miss
        case status
        case retreat
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
