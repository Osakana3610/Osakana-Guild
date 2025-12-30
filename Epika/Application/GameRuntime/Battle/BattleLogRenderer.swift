// ==============================================================================
// BattleLogRenderer.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - BattleLogEntryをアクション単位に描画するデータへ変換
//   - 旧ロジックのヒューリスティックを排除し、BattleActionEntryをそのまま使用
//
// ==============================================================================

import Foundation

/// BattleLog（ActionEntryベース）を UI 表示用にレンダリングする
struct BattleLogRenderer {
    struct RenderedAction: Sendable, Identifiable {
        let id: Int
        let turn: Int
        let model: BattleActionEntry
        let declaration: BattleLogEntry
        let results: [BattleLogEntry]

        var primaryEntry: BattleLogEntry { declaration }
    }

    static func render(
        battleLog: BattleLog,
        allyNames: [UInt8: String],
        enemyNames: [UInt16: String],
        spellNames: [UInt8: String] = [:],
        enemySkillNames: [UInt16: String] = [:],
        actorIdentifiers: [UInt16: String] = [:]
    ) -> [RenderedAction] {
        var rendered: [RenderedAction] = []

        for (index, entry) in battleLog.entries.enumerated() {
            let actorIdString = entry.actor.flatMap { actorIdentifiers[$0] } ?? entry.actor.map { String($0) }
            let actorName = resolveName(index: entry.actor, allyNames: allyNames, enemyNames: enemyNames)
            let declaration = makeDeclarationEntry(turn: Int(entry.turn),
                                                   actorId: actorIdString,
                                                   actorName: actorName,
                                                   entry: entry,
                                                   spellNames: spellNames,
                                                   enemySkillNames: enemySkillNames,
                                                   allyNames: allyNames,
                                                   enemyNames: enemyNames)

            let shouldRenderEffects = rendersEffectLines(for: entry.declaration.kind)
            let effectEntries: [BattleLogEntry]
            if shouldRenderEffects {
                effectEntries = entry.effects.compactMap { effect in
                    makeEffectEntry(effect: effect,
                                    turn: Int(entry.turn),
                                    actorName: actorName,
                                    allyNames: allyNames,
                                    enemyNames: enemyNames,
                                    actorIdentifiers: actorIdentifiers)
                }
            } else {
                effectEntries = []
            }

            rendered.append(RenderedAction(id: index,
                                           turn: Int(entry.turn),
                                           model: entry,
                                           declaration: declaration,
                                           results: effectEntries))
        }

        return rendered
    }

    // MARK: - Helpers

    private static func makeDeclarationEntry(turn: Int,
                                             actorId: String?,
                                             actorName: String?,
                                             entry: BattleActionEntry,
                                             spellNames: [UInt8: String],
                                             enemySkillNames: [UInt16: String],
                                             allyNames: [UInt8: String],
                                             enemyNames: [UInt16: String]) -> BattleLogEntry {
        let (message, type) = declarationMessage(kind: entry.declaration.kind,
                                                 actorName: actorName,
                                                 entry: entry,
                                                 spellNames: spellNames,
                                                 enemySkillNames: enemySkillNames)
        return BattleLogEntry(turn: turn,
                              message: message,
                              type: type,
                              actorId: actorId,
                              targetId: nil)
    }

    private static func makeEffectEntry(effect: BattleActionEntry.Effect,
                                        turn: Int,
                                        actorName: String?,
                                        allyNames: [UInt8: String],
                                        enemyNames: [UInt16: String],
                                        actorIdentifiers: [UInt16: String]) -> BattleLogEntry? {
        let targetName = resolveName(index: effect.target, allyNames: allyNames, enemyNames: enemyNames)
        let (message, type) = effectMessage(kind: effect.kind,
                                            actorName: actorName,
                                            targetName: targetName,
                                            value: effect.value.map { Int($0) })
        guard !message.isEmpty else { return nil }
        let targetId = effect.target.flatMap { actorIdentifiers[$0] } ?? effect.target.map { String($0) }
        return BattleLogEntry(turn: turn,
                              message: message,
                              type: type,
                              actorId: nil,
                              targetId: targetId)
    }

    private static func resolveName(index: UInt16?,
                                    allyNames: [UInt8: String],
                                    enemyNames: [UInt16: String]) -> String? {
        guard let index else { return nil }
        if index >= 1000 {
            return enemyNames[index] ?? "敵\(index)"
        } else {
            return allyNames[UInt8(index)] ?? "キャラ\(index)"
        }
    }

    private static func rendersEffectLines(for kind: ActionKind) -> Bool {
        switch kind {
        case .physicalAttack,
             .priestMagic,
             .mageMagic,
             .breath,
             .enemySpecialSkill,
             .reactionAttack,
             .followUp:
            return true
        default:
            return false
        }
    }

    private static func declarationMessage(kind: ActionKind,
                                           actorName: String?,
                                           entry: BattleActionEntry,
                                           spellNames: [UInt8: String],
                                           enemySkillNames: [UInt16: String]) -> (String, BattleLogEntry.LogType) {
        let actor = actorName ?? "不明"

        switch kind {
        case .defend:
            return ("\(actor)は防御態勢を取った", .guard)
        case .physicalAttack:
            return ("\(actor)の攻撃！", .action)
        case .priestMagic:
            let spellName = entry.declaration.skillIndex
                .flatMap { UInt8(exactly: $0) }
                .flatMap { spellNames[$0] } ?? "回復魔法"
            return ("\(actor)は\(spellName)を唱えた！", .action)
        case .mageMagic:
            let spellName = entry.declaration.skillIndex
                .flatMap { UInt8(exactly: $0) }
                .flatMap { spellNames[$0] } ?? "攻撃魔法"
            return ("\(actor)は\(spellName)を唱えた！", .action)
        case .breath:
            return ("\(actor)はブレスを吐いた！", .action)
        case .battleStart:
            return ("戦闘開始！", .system)
        case .turnStart:
            let turnNumber = Int(entry.declaration.extra ?? UInt16(entry.turn))
            return ("--- \(turnNumber)ターン目 ---", .system)
        case .victory:
            return ("勝利！ 敵を倒した！", .victory)
        case .defeat:
            return ("敗北… パーティは全滅した…", .defeat)
        case .retreat:
            return ("戦闘は長期化し、パーティは撤退を決断した", .retreat)
        case .enemyAppear:
            return ("敵が現れた！", .system)
        case .enemySpecialSkill:
            let skillName = entry.declaration.skillIndex
                .flatMap { enemySkillNames[$0] } ?? "特殊攻撃"
            return ("\(actor)の\(skillName)！", .action)
        case .noAction:
            return ("\(actor)は何もしなかった", .action)
        case .withdraw:
            return ("\(actor)は戦線離脱した", .status)
        case .sacrifice:
            return ("古の儀：\(actor)が供儀対象になった", .status)
        case .vampireUrge:
            return ("\(actor)は吸血衝動に駆られた", .status)
        default:
            // 残りは効果メッセージに委ねる
            return ("", .system)
        }
    }

    private static func effectMessage(kind: BattleActionEntry.Effect.Kind,
                                      actorName: String?,
                                      targetName: String?,
                                      value: Int?) -> (String, BattleLogEntry.LogType) {
        let actor = actorName ?? "不明"
        let target = targetName ?? "対象"
        let amount = value ?? 0

        switch kind {
        case .physicalDamage:
            return ("\(actor)の攻撃！\(target)に\(amount)のダメージ！", .damage)
        case .physicalEvade:
            return ("\(actor)の攻撃！\(target)は攻撃をかわした！", .miss)
        case .physicalParry:
            return ("\(target)の受け流し！", .action)
        case .physicalBlock:
            return ("\(target)は大盾で防いだ！", .action)
        case .physicalKill:
            return ("\(target)を倒した！", .defeat)
        case .martialArts:
            return ("\(actor)の格闘戦！", .action)
        case .magicDamage:
            return ("\(actor)の魔法！\(target)に\(amount)のダメージ！", .damage)
        case .magicHeal:
            return ("\(target)のHPが\(amount)回復！", .heal)
        case .magicMiss:
            return ("しかし効かなかった", .miss)
        case .breathDamage:
            return ("\(actor)のブレス！\(target)に\(amount)のダメージ！", .damage)
        case .statusInflict:
            return ("\(target)は状態異常になった！", .status)
        case .statusResist:
            return ("\(target)は抵抗した！", .status)
        case .statusRecover:
            return ("\(target)の状態異常が治った", .status)
        case .statusTick:
            return ("\(target)は継続ダメージで\(amount)のダメージ！", .damage)
        case .statusConfusion:
            return ("\(actor)は暴走して混乱した！", .status)
        case .statusRampage:
            return ("\(actor)の暴走！\(target)に\(amount)のダメージ！", .damage)
        case .reactionAttack:
            return ("\(actor)の反撃！", .action)
        case .followUp:
            return ("\(actor)の追加攻撃！", .action)
        case .healAbsorb:
            return ("\(actor)は吸収能力で\(amount)回復", .heal)
        case .healVampire:
            return ("\(actor)は吸血で\(amount)回復", .heal)
        case .healParty, .healSelf:
            return ("\(target)のHPが\(amount)回復！", .heal)
        case .damageSelf:
            return ("\(target)は自身の効果で\(amount)ダメージ", .damage)
        case .buffApply:
            return ("効果が発動した", .status)
        case .buffExpire:
            return ("\(target)の効果が切れた", .status)
        case .resurrection:
            return ("\(target)が蘇生した！", .heal)
        case .necromancer:
            return ("\(actor)のネクロマンサーで\(target)が蘇生した！", .heal)
        case .rescue:
            return ("\(actor)は\(target)を救出した！", .heal)
        case .actionLocked:
            return ("\(actor)は動けない", .status)
        case .noAction:
            return ("\(actor)は何もしなかった", .action)
        case .withdraw:
            return ("\(actor)は戦線離脱した", .status)
        case .sacrifice:
            return ("古の儀：\(target)が供儀対象になった", .status)
        case .vampireUrge:
            return ("\(actor)は吸血衝動に駆られた", .status)
        case .enemySpecialDamage:
            return ("\(target)に\(amount)のダメージ！", .damage)
        case .enemySpecialHeal:
            return ("\(actor)は\(amount)回復した！", .heal)
        case .enemySpecialBuff:
            return ("\(actor)は能力を強化した！", .status)
        case .spellChargeRecover:
            return ("\(actor)は魔法のチャージを回復した", .status)
        case .enemyAppear, .logOnly:
            return ("", .system)
        }
    }
}
