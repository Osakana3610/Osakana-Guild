import Foundation

// MARK: - Logging
extension BattleTurnEngine {
    // appendInitialStateLogs は削除（buildInitialHP で代替）

    static func appendActionLog(for actor: BattleActor,
                                side: ActorSide,
                                index: Int,
                                category: ActionKind,
                                context: inout BattleContext) {
        let actorIdx = context.actorIndex(for: side, arrayIndex: index)
        context.appendAction(kind: category, actor: actorIdx)
    }

    static func appendDefeatLog(for target: BattleActor,
                                side: ActorSide,
                                index: Int,
                                context: inout BattleContext) {
        let targetIdx = context.actorIndex(for: side, arrayIndex: index)
        context.appendAction(kind: .physicalKill, target: targetIdx)
    }

    static func appendStatusLockLog(for actor: BattleActor,
                                    side: ActorSide,
                                    index: Int,
                                    context: inout BattleContext) {
        let actorIdx = context.actorIndex(for: side, arrayIndex: index)
        context.appendAction(kind: .actionLocked, actor: actorIdx)
    }

    static func appendStatusExpireLog(for actor: BattleActor,
                                      side: ActorSide,
                                      index: Int,
                                      definition: StatusEffectDefinition,
                                      context: inout BattleContext) {
        let actorIdx = context.actorIndex(for: side, arrayIndex: index)
        context.appendAction(kind: .statusRecover, actor: actorIdx)
    }
}
