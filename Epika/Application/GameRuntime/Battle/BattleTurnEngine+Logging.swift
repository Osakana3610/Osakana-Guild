// ==============================================================================
// BattleTurnEngine.Logging.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 戦闘ログ出力のヘルパー関数
//   - 各種行動・結果のログ記録
//
// 【本体との関係】
//   - BattleTurnEngineの拡張ファイル
//   - ログ出力に特化した機能を提供
//
// 【主要機能】
//   - appendActionLog: 行動ログの追加
//   - appendDefeatLog: 戦闘不能ログの追加
//   - appendStatusLockLog: 行動不能ログの追加
//   - appendStatusExpireLog: 状態異常解除ログの追加
//
// 【使用箇所】
//   - BattleTurnEngine各拡張ファイル（各種処理からログ出力）
//
// ==============================================================================

import Foundation

// MARK: - Logging
extension BattleTurnEngine {
    // appendInitialStateLogs は削除（buildInitialHP で代替）

    nonisolated static func appendActionLog(for actor: BattleActor,
                                side: ActorSide,
                                index: Int,
                                category: ActionKind,
                                context: inout BattleContext) {
        let actorIdx = context.actorIndex(for: side, arrayIndex: index)
        context.appendSimpleEntry(kind: category,
                                  actorId: actorIdx,
                                  effectKind: .logOnly)
    }

    nonisolated static func appendDefeatLog(for target: BattleActor,
                                side: ActorSide,
                                index: Int,
                                context: inout BattleContext,
                                entryBuilder: BattleActionEntry.Builder? = nil) {
        let targetIdx = context.actorIndex(for: side, arrayIndex: index)
        if let entryBuilder {
            entryBuilder.addEffect(kind: .physicalKill, target: targetIdx)
            return
        }
        context.appendSimpleEntry(kind: .physicalKill,
                                  targetId: targetIdx,
                                  effectKind: .physicalKill)
    }

    nonisolated static func appendStatusLockLog(for actor: BattleActor,
                                    side: ActorSide,
                                    index: Int,
                                    context: inout BattleContext) {
        let actorIdx = context.actorIndex(for: side, arrayIndex: index)
        context.appendSimpleEntry(kind: .actionLocked,
                                  actorId: actorIdx,
                                  targetId: actorIdx,
                                  effectKind: .actionLocked)
    }

    nonisolated static func appendStatusExpireLog(for actor: BattleActor,
                                      side: ActorSide,
                                      index: Int,
                                      definition: StatusEffectDefinition,
                                      context: inout BattleContext) {
        let actorIdx = context.actorIndex(for: side, arrayIndex: index)
        context.appendSimpleEntry(kind: .statusRecover,
                                  actorId: actorIdx,
                                  targetId: actorIdx,
                                  statusId: UInt16(definition.id),
                                  effectKind: .statusRecover)
    }
}
