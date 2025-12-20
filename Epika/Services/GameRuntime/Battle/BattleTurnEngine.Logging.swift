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
