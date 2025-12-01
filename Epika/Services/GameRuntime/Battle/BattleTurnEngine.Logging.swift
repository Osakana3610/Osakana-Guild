import Foundation

// MARK: - Logging
extension BattleTurnEngine {
    static func appendInitialStateLogs(_ context: inout BattleContext) {
        for (index, player) in context.players.enumerated() {
            context.appendLog(initialStateEntry(for: player, role: "player", order: index))
        }
        for (index, enemy) in context.enemies.enumerated() {
            context.appendLog(initialStateEntry(for: enemy, role: "enemy", order: index))
        }
    }

    static func initialStateEntry(for actor: BattleActor,
                                  role: String,
                                  order: Int) -> BattleLogEntry {
        var metadata: [String: String] = [
            "category": "initialState",
            "role": role,
            "order": "\(order)",
            "currentHP": "\(actor.currentHP)",
            "maxHP": "\(actor.snapshot.maxHP)",
            "name": actor.displayName
        ]
        if let level = actor.level {
            metadata["level"] = "\(level)"
        }
        if let job = actor.jobName, !job.isEmpty {
            metadata["job"] = job
        }
        if let partyId = actor.partyMemberId {
            metadata["partyMemberId"] = partyId.uuidString
        }
        metadata["identifier"] = actor.identifier

        return BattleLogEntry(turn: 0,
                              message: "",
                              type: .system,
                              actorId: actor.identifier,
                              targetId: nil,
                              metadata: metadata)
    }

    static func appendActionLog(for actor: BattleActor,
                                category: ActionCategory,
                                remainingUses: Int?,
                                spellId: String? = nil,
                                context: inout BattleContext) {
        var metadata = ["category": category.logIdentifier]
        if let remainingUses {
            metadata["remainingUses"] = "\(remainingUses)"
        }
        if let spellId {
            metadata["spellId"] = spellId
        }
        context.appendLog(message: category.actionMessage(for: actor.displayName),
                          type: category.logType,
                          actorId: actor.identifier,
                          metadata: metadata)
    }

    static func appendDefeatLog(for target: BattleActor, context: inout BattleContext) {
        context.appendLog(message: "\(target.displayName)は倒れた…",
                          type: .defeat,
                          actorId: target.identifier)
    }

    static func appendStatusLockLog(for actor: BattleActor, context: inout BattleContext) {
        guard let effect = actor.statusEffects.first(where: { isActionLocked(effect: $0, context: context) }) else {
            context.appendLog(message: "\(actor.displayName)は動けない",
                              type: .status,
                              actorId: actor.identifier)
            return
        }
        if let definition = context.statusDefinition(for: effect) {
            let message = "\(actor.displayName)は\(definition.name)で動けない"
            var metadata: [String: String] = ["statusId": effect.id]
            if effect.remainingTurns > 0 {
                metadata["remainingTurns"] = "\(effect.remainingTurns)"
            }
            context.appendLog(message: message, type: .status, actorId: actor.identifier, metadata: metadata)
            return
        }
        var metadata: [String: String] = ["statusId": effect.id]
        if effect.remainingTurns > 0 {
            metadata["remainingTurns"] = "\(effect.remainingTurns)"
        }
        context.appendLog(message: "\(actor.displayName)は動けない",
                          type: .status,
                          actorId: actor.identifier,
                          metadata: metadata)
    }

    static func appendStatusExpireLog(for actor: BattleActor,
                                      definition: StatusEffectDefinition,
                                      context: inout BattleContext) {
        let message = definition.expireMessage ?? "\(actor.displayName)の\(definition.name)が解除された"
        context.appendLog(message: message,
                          type: .status,
                          actorId: actor.identifier,
                          metadata: ["statusId": definition.id])
    }
}
