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
    private static let jaJPDecimalStyle = IntegerFormatStyle<Int>.number.locale(Locale(identifier: "ja_JP"))

    private struct PhysicalSummary {
        var totalDamage: Int
        var defeated: Bool
        var attempts: Int
        var hits: Int

        init(totalDamage: Int = 0, defeated: Bool = false, attempts: Int = 0, hits: Int = 0) {
            self.totalDamage = totalDamage
            self.defeated = defeated
            self.attempts = attempts
            self.hits = hits
        }
    }

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
        skillNames: [UInt16: String] = [:],
        actorIdentifiers: [UInt16: String] = [:]
    ) -> [RenderedAction] {
        var rendered: [RenderedAction] = []
        var nextId = 0

        func appendRenderedAction(for entry: BattleActionEntry) {
            let actorIdString = entry.actor.flatMap { actorIdentifiers[$0] } ?? entry.actor.map { String($0) }
            let actorName = resolveName(index: entry.actor, allyNames: allyNames, enemyNames: enemyNames)

            let declaration = makeDeclarationEntry(turn: Int(entry.turn),
                                                   actorId: actorIdString,
                                                   actorName: actorName,
                                                   entry: entry,
                                                   spellNames: spellNames,
                                                   enemySkillNames: enemySkillNames,
                                                   skillNames: skillNames,
                                                   allyNames: allyNames,
                                                   enemyNames: enemyNames)

            let actionLabel = resolveActionLabel(entry: entry,
                                                 spellNames: spellNames,
                                                 enemySkillNames: enemySkillNames,
                                                 skillNames: skillNames)

            let shouldRenderEffects = rendersEffectLines(for: entry)
            var effectEntries: [BattleLogEntry] = []
            if shouldRenderEffects {
                effectEntries = renderEffectEntries(for: entry,
                                                    actorName: actorName,
                                                    actionLabel: actionLabel,
                                                    allyNames: allyNames,
                                                    enemyNames: enemyNames,
                                                    actorIdentifiers: actorIdentifiers)
            }

            rendered.append(RenderedAction(id: nextId,
                                           turn: Int(entry.turn),
                                           model: entry,
                                           declaration: declaration,
                                           results: effectEntries))
            nextId += 1
        }

        for entry in battleLog.entries {
            appendRenderedAction(for: entry)
        }

        return rendered
    }

    // MARK: - Helpers

    private static func renderEffectEntries(for entry: BattleActionEntry,
                                            actorName: String?,
                                            actionLabel: String?,
                                            allyNames: [UInt8: String],
                                            enemyNames: [UInt16: String],
                                            actorIdentifiers: [UInt16: String]) -> [BattleLogEntry] {
        if let buffSummary = renderBuffSummary(for: entry,
                                               actionLabel: actionLabel,
                                               allyNames: allyNames,
                                               enemyNames: enemyNames) {
            return buffSummary
        }

        if shouldAggregatePhysicalEffects(for: entry.declaration.kind) {
            return renderPhysicalEffects(for: entry,
                                         actorName: actorName,
                                         actionLabel: actionLabel,
                                         allyNames: allyNames,
                                         enemyNames: enemyNames,
                                         actorIdentifiers: actorIdentifiers)
        }

        return entry.effects.compactMap { effect in
            guard !shouldSkipEffectLine(for: entry.declaration.kind, effectKind: effect.kind) else { return nil }
            return makeEffectEntry(effect: effect,
                                   entry: entry,
                                   turn: Int(entry.turn),
                                   actorName: actorName,
                                   actionLabel: actionLabel,
                                   allyNames: allyNames,
                                   enemyNames: enemyNames,
                                   actorIdentifiers: actorIdentifiers)
        }
    }

    private static func makeDeclarationEntry(turn: Int,
                                             actorId: String?,
                                             actorName: String?,
                                             entry: BattleActionEntry,
                                             spellNames: [UInt8: String],
                                             enemySkillNames: [UInt16: String],
                                             skillNames: [UInt16: String],
                                             allyNames: [UInt8: String],
                                             enemyNames: [UInt16: String]) -> BattleLogEntry {
        let (message, type) = declarationMessage(kind: entry.declaration.kind,
                                                 actorName: actorName,
                                                 entry: entry,
                                                 spellNames: spellNames,
                                                 enemySkillNames: enemySkillNames,
                                                 skillNames: skillNames,
                                                 allyNames: allyNames,
                                                 enemyNames: enemyNames)
        return BattleLogEntry(turn: turn,
                              message: message,
                              type: type,
                              actorId: actorId,
                              targetId: nil)
    }

    private static func makeEffectEntry(effect: BattleActionEntry.Effect,
                                        entry: BattleActionEntry,
                                        turn: Int,
                                        actorName: String?,
                                        actionLabel: String?,
                                        allyNames: [UInt8: String],
                                        enemyNames: [UInt16: String],
                                        actorIdentifiers: [UInt16: String]) -> BattleLogEntry? {
        let targetName = resolveName(index: effect.target, allyNames: allyNames, enemyNames: enemyNames)
        let displayAmount = displayValue(for: effect)
        let (message, type) = effectMessage(kind: effect.kind,
                                            actorName: actorName,
                                            targetName: targetName,
                                            value: displayAmount,
                                            actionLabel: actionLabel)
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

    private static func resolveActionLabel(entry: BattleActionEntry,
                                           spellNames: [UInt8: String],
                                           enemySkillNames: [UInt16: String],
                                           skillNames: [UInt16: String]) -> String? {
        if let label = entry.declaration.label, !label.isEmpty {
            return localizedActionLabel(label)
        }

        guard let skillIndex = entry.declaration.skillIndex else { return nil }

        if entry.declaration.kind == .priestMagic || entry.declaration.kind == .mageMagic {
            if let spellId = UInt8(exactly: skillIndex), let name = spellNames[spellId] {
                return localizedActionLabel(name)
            }
        }

        if entry.declaration.kind == .enemySpecialSkill {
            if let name = enemySkillNames[skillIndex] {
                return localizedActionLabel(name)
            }
        }

        return localizedActionLabel(skillNames[skillIndex])
    }

    private static func localizedActionLabel(_ label: String?) -> String? {
        guard let label else { return nil }
        switch label {
        case L10n.Key.battleTermReactionAttack.defaultValue:
            return L10n.BattleTerm.reactionAttack
        case L10n.Key.battleTermFollowUp.defaultValue:
            return L10n.BattleTerm.followUp
        case L10n.Key.battleTermRetaliation.defaultValue:
            return L10n.BattleTerm.retaliation
        case L10n.Key.battleTermExtraAttack.defaultValue:
            return L10n.BattleTerm.extraAttack
        case L10n.Key.battleTermMartialFollowUp.defaultValue:
            return L10n.BattleTerm.martialFollowUp
        case L10n.Key.battleTermRescue.defaultValue:
            return L10n.BattleTerm.rescue
        default:
            return label
        }
    }

    private static func summarizeHits(for entry: BattleActionEntry,
                                      actionKind: ActionKind) -> String? {
        let attemptKinds: Set<BattleActionEntry.Effect.Kind>
        let hitKinds: Set<BattleActionEntry.Effect.Kind>

        switch actionKind {
        case .physicalAttack, .followUp, .reactionAttack:
            attemptKinds = [.physicalDamage, .physicalEvade, .physicalParry, .physicalBlock]
            hitKinds = [.physicalDamage]
        case .breath:
            attemptKinds = [.breathDamage]
            hitKinds = [.breathDamage]
        case .enemySpecialSkill:
            attemptKinds = [.enemySpecialDamage]
            hitKinds = [.enemySpecialDamage]
        default:
            return nil
        }

        let attempts = entry.effects.filter { attemptKinds.contains($0.kind) }.count
        guard attempts > 1 else { return nil }
        let hits = entry.effects.filter { hitKinds.contains($0.kind) }.count
        return "（\(attempts)回攻撃、\(hits)ヒット）"
    }

    private static func rendersEffectLines(for entry: BattleActionEntry) -> Bool {
        guard !entry.effects.isEmpty else { return false }
        switch entry.declaration.kind {
        case .battleStart,
             .turnStart,
             .victory,
             .defeat,
             .retreat,
             .enemyAppear:
            return false
        default:
            return true
        }
    }

    private static func shouldAggregatePhysicalEffects(for kind: ActionKind) -> Bool {
        switch kind {
        case .physicalAttack, .reactionAttack, .followUp:
            return true
        default:
            return false
        }
    }

    private static func renderBuffSummary(for entry: BattleActionEntry,
                                          actionLabel: String?,
                                          allyNames: [UInt8: String],
                                          enemyNames: [UInt16: String]) -> [BattleLogEntry]? {
        guard shouldSummarizeBuff(entry: entry) else { return nil }
        let targets = entry.effects.compactMap { $0.target }
        guard !targets.isEmpty else { return nil }
        let description = describeTargetGroup(for: targets,
                                              allyNames: allyNames,
                                              enemyNames: enemyNames)
        let label = actionLabel ?? "効果"
        let message = "\(description)に\(label)の効果が付与された！"
        let entryLine = BattleLogEntry(turn: Int(entry.turn),
                                       message: message,
                                       type: .status,
                                       actorId: nil,
                                       targetId: nil)
        return [entryLine]
    }

    private static func shouldSummarizeBuff(entry: BattleActionEntry) -> Bool {
        guard entry.declaration.kind == .mageMagic || entry.declaration.kind == .priestMagic else {
            return false
        }
        guard !entry.effects.isEmpty else { return false }
        return entry.effects.allSatisfy { $0.kind == .buffApply }
    }

    private static func shouldSkipEffectLine(for actionKind: ActionKind,
                                             effectKind: BattleActionEntry.Effect.Kind) -> Bool {
        switch actionKind {
        case .physicalAttack, .reactionAttack, .followUp:
            return effectKind == .physicalEvade
                || effectKind == .physicalParry
                || effectKind == .physicalBlock
                || effectKind == .reactionAttack
                || effectKind == .followUp
        default:
            return false
        }
    }

    private static func renderPhysicalEffects(for entry: BattleActionEntry,
                                              actorName: String?,
                                              actionLabel: String?,
                                              allyNames: [UInt8: String],
                                              enemyNames: [UInt16: String],
                                              actorIdentifiers: [UInt16: String]) -> [BattleLogEntry] {
        enum RenderToken {
            case physicalSummary(UInt16)
            case standard(BattleActionEntry.Effect)
        }

        var summaries: [UInt16: PhysicalSummary] = [:]
        var orderedTokens: [RenderToken] = []
        var insertedTargets: Set<UInt16> = []

        func ensureToken(for target: UInt16) {
            guard !insertedTargets.contains(target) else { return }
            insertedTargets.insert(target)
            orderedTokens.append(.physicalSummary(target))
        }

        for effect in entry.effects {
            switch effect.kind {
            case .physicalDamage:
                guard let target = effect.target, let displayAmount = displayValue(for: effect) else {
                    orderedTokens.append(.standard(effect))
                    continue
                }
                ensureToken(for: target)
                var summary = summaries[target] ?? PhysicalSummary()
                summary.totalDamage += displayAmount
                summary.attempts += 1
                summary.hits += 1
                summaries[target] = summary
            case .physicalKill:
                guard let target = effect.target else {
                    orderedTokens.append(.standard(effect))
                    continue
                }
                ensureToken(for: target)
                var summary = summaries[target] ?? PhysicalSummary()
                summary.defeated = true
                summaries[target] = summary
                orderedTokens.append(.standard(effect))
                continue
            case .physicalEvade, .physicalParry, .physicalBlock:
                guard let target = effect.target else { continue }
                ensureToken(for: target)
                var summary = summaries[target] ?? PhysicalSummary()
                summary.attempts += 1
                summaries[target] = summary
                continue
            default:
                orderedTokens.append(.standard(effect))
            }
        }

        return orderedTokens.compactMap { token -> BattleLogEntry? in
            switch token {
            case .physicalSummary(let target):
                guard let summary = summaries[target],
                      summary.attempts > 0 || summary.totalDamage > 0 || summary.defeated else {
                    return nil
                }
                return makePhysicalSummaryEntry(summary: summary,
                                                target: target,
                                                entry: entry,
                                                actorName: actorName,
                                                allyNames: allyNames,
                                                enemyNames: enemyNames,
                                                actorIdentifiers: actorIdentifiers)
            case .standard(let effect):
                guard !shouldSkipEffectLine(for: entry.declaration.kind, effectKind: effect.kind) else { return nil }
                return makeEffectEntry(effect: effect,
                                       entry: entry,
                                       turn: Int(entry.turn),
                                       actorName: actorName,
                                       actionLabel: actionLabel,
                                       allyNames: allyNames,
                                       enemyNames: enemyNames,
                                       actorIdentifiers: actorIdentifiers)
            }
        }
    }

    private static func makePhysicalSummaryEntry(summary: PhysicalSummary,
                                                 target: UInt16,
                                                 entry: BattleActionEntry,
                                                 actorName: String?,
                                                 allyNames: [UInt8: String],
                                                 enemyNames: [UInt16: String],
                                                 actorIdentifiers: [UInt16: String]) -> BattleLogEntry? {
        let actor = actorName ?? "不明"
        let targetName = resolveName(index: target, allyNames: allyNames, enemyNames: enemyNames) ?? "対象"
        var components: [String] = []

        if summary.totalDamage > 0 {
            components.append("\(actor)の攻撃！\(targetName)に\(formatAmount(summary.totalDamage))のダメージ！")
        } else {
            components.append("\(actor)の攻撃！")
        }

        if summary.totalDamage == 0 && !summary.defeated {
            guard summary.attempts > 0 else { return nil }
            let targetId = actorIdentifiers[target] ?? String(target)
            return BattleLogEntry(turn: Int(entry.turn),
                                  message: "\(targetName)は攻撃をかわした！",
                                  type: .miss,
                                  actorId: nil,
                                  targetId: targetId)
        } else {
            let targetId = actorIdentifiers[target] ?? String(target)
            let type: BattleLogEntry.LogType = summary.totalDamage > 0 ? .damage : .action
            return BattleLogEntry(turn: Int(entry.turn),
                                  message: components.joined(separator: " "),
                                  type: type,
                              actorId: nil,
                              targetId: targetId)
        }
    }

    private static func describeTargetGroup(for targets: [UInt16],
                                            allyNames: [UInt8: String],
                                            enemyNames: [UInt16: String]) -> String {
        let uniqueTargets = Array(Set(targets))
        guard let first = uniqueTargets.first else { return "対象" }
        let isEnemySide = first >= 1000
        if uniqueTargets.count == 1 {
            return resolveName(index: first, allyNames: allyNames, enemyNames: enemyNames) ?? (isEnemySide ? "敵" : "味方")
        }
        let descriptor = isEnemySide ? "敵" : "味方"
        return "\(descriptor)全体"
    }

    private static func declarationMessage(kind: ActionKind,
                                           actorName: String?,
                                           entry: BattleActionEntry,
                                           spellNames: [UInt8: String],
                                           enemySkillNames: [UInt16: String],
                                           skillNames: [UInt16: String],
                                           allyNames: [UInt8: String],
                                           enemyNames: [UInt16: String]) -> (String, BattleLogEntry.LogType) {
        let actor = actorName ?? "不明"
        let hitSummary = summarizeHits(for: entry, actionKind: kind)
        let actionLabel = resolveActionLabel(entry: entry,
                                             spellNames: spellNames,
                                             enemySkillNames: enemySkillNames,
                                             skillNames: skillNames)

        func appendDetails(to message: String) -> String {
            var result = message
            if let hitSummary {
                result += " \(hitSummary)"
            }
            return result
        }

        switch kind {
        case .defend:
            return ("\(actor)は防御態勢を取った", .guard)
        case .physicalAttack:
            return (appendDetails(to: "\(actor)の攻撃！"), .action)
        case .physicalKill:
            return ("戦闘不能が発生した", .status)
        case .priestMagic:
            let spellName = actionLabel
                ?? entry.declaration.skillIndex
                    .flatMap { UInt8(exactly: $0) }
                    .flatMap { spellNames[$0] }
                ?? "回復魔法"
            return (appendDetails(to: "\(actor)は\(spellName)を唱えた！"), .action)
        case .mageMagic:
            let spellName = actionLabel
                ?? entry.declaration.skillIndex
                    .flatMap { UInt8(exactly: $0) }
                    .flatMap { spellNames[$0] }
                ?? "攻撃魔法"
            return (appendDetails(to: "\(actor)は\(spellName)を唱えた！"), .action)
        case .breath:
            return (appendDetails(to: "\(actor)はブレスを吐いた！"), .action)
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
            let skillName = actionLabel
                ?? entry.declaration.skillIndex
                    .flatMap { enemySkillNames[$0] }
                ?? "特殊攻撃"
            return (appendDetails(to: "\(actor)の\(skillName)！"), .action)
        case .noAction:
            return ("\(actor)は何もしなかった", .action)
        case .withdraw:
            return ("\(actor)は戦線離脱した", .status)
        case .sacrifice:
            return ("古の儀：\(actor)が供儀対象になった", .status)
        case .vampireUrge:
            return ("\(actor)は吸血衝動に駆られた", .status)
        case .reactionAttack:
            let name = actionLabel ?? L10n.BattleTerm.reactionAttack
            return (appendDetails(to: "\(actor)の\(name)！"), .action)
        case .followUp:
            let name = actionLabel ?? L10n.BattleTerm.followUp
            return (appendDetails(to: "\(actor)の\(name)！"), .action)
        case .healParty:
            let name = actionLabel ?? "回復術"
            return (appendDetails(to: "\(actor)の\(name)！"), .heal)
        case .healSelf:
            let name = actionLabel ?? "回復"
            return ("\(actor)は\(name)で自分を癒やした", .heal)
        case .healAbsorb:
            let name = actionLabel ?? "吸収"
            return ("\(actor)は\(name)で回復した", .heal)
        case .healVampire:
            let name = actionLabel ?? "吸血"
            return ("\(actor)は\(name)で回復した", .heal)
        case .damageSelf:
            let name = actionLabel ?? "反動"
            return ("\(actor)は\(name)でダメージを受けた", .damage)
        case .statusTick:
            let name = actionLabel ?? "状態異常"
            return ("\(actor)は\(name)の影響を受けている", .status)
        case .statusRecover:
            let name = actionLabel ?? "状態異常"
            return ("\(actor)の\(name)が治った", .status)
        case .buffApply:
            if let label = actionLabel {
                return ("\(actor)に\(label)の効果が付与された", .status)
            } else {
                return ("\(actor)に効果が付与された", .status)
            }
        case .buffExpire:
            if let label = actionLabel {
                return ("\(actor)の\(label)が切れた", .status)
            } else {
                return ("\(actor)の効果が切れた", .status)
            }
        case .resurrection:
            let name = actionLabel ?? "蘇生の術"
            return (appendDetails(to: "\(actor)は\(name)を行った"), .status)
        case .necromancer:
            let name = actionLabel ?? "ネクロマンサー"
            return (appendDetails(to: "\(actor)は\(name)で死者を蘇らせた"), .status)
        case .rescue:
            let name = actionLabel ?? L10n.BattleTerm.rescue
            return (appendDetails(to: "\(actor)は\(name)を行った"), .status)
        case .actionLocked:
            let name = actionLabel ?? "行動不能"
            return ("\(actor)は\(name)だ", .status)
        case .spellChargeRecover:
            let name = actionLabel ?? "呪文"
            return ("\(actor)は\(name)を再装填した", .status)
        default:
            // 残りは効果メッセージに委ねる
            return ("", .system)
        }
    }

    private static func effectMessage(kind: BattleActionEntry.Effect.Kind,
                                      actorName: String?,
                                      targetName: String?,
                                      value: Int?,
                                      actionLabel: String?) -> (String, BattleLogEntry.LogType) {
        let actor = actorName ?? "不明"
        let target = targetName ?? "対象"
        let rawAmount = value ?? 0
        let amountText = formatAmount(rawAmount)

        switch kind {
        case .physicalDamage:
            return ("\(actor)の攻撃！\(target)に\(amountText)のダメージ！", .damage)
        case .physicalEvade:
            return ("\(actor)の攻撃！\(target)は攻撃をかわした！", .miss)
        case .physicalParry:
            return ("\(target)のパリィ！", .action)
        case .physicalBlock:
            return ("\(target)の盾防御！", .action)
        case .physicalKill:
            return ("\(target)を倒した！", .defeat)
        case .martial:
            return ("\(actor)の格闘戦！", .action)
        case .magicDamage:
            return ("\(actor)の魔法！\(target)に\(amountText)のダメージ！", .damage)
        case .magicHeal:
            return ("\(target)のHPが\(amountText)回復！", .heal)
        case .magicMiss:
            return ("しかし効かなかった", .miss)
        case .breathDamage:
            return ("\(actor)のブレス！\(target)に\(amountText)のダメージ！", .damage)
        case .statusInflict:
            return ("\(target)は状態異常になった！", .status)
        case .statusResist:
            return ("\(target)は抵抗した！", .status)
        case .statusRecover:
            return ("\(target)の状態異常が治った", .status)
        case .statusTick:
            return ("\(target)は継続ダメージで\(amountText)のダメージ！", .damage)
        case .statusConfusion:
            return ("\(actor)は暴走して混乱した！", .status)
        case .statusRampage:
            return ("\(actor)の暴走！\(target)に\(amountText)のダメージ！", .damage)
        case .reactionAttack:
            let name = actionLabel ?? L10n.BattleTerm.reactionAttack
            return ("\(actor)の\(name)！", .action)
        case .followUp:
            let name = actionLabel ?? L10n.BattleTerm.followUp
            return ("\(actor)の\(name)！", .action)
        case .healAbsorb:
            return ("\(actor)は吸収能力で\(amountText)回復", .heal)
        case .healVampire:
            return ("\(actor)は吸血で\(amountText)回復", .heal)
        case .healParty, .healSelf:
            return ("\(target)のHPが\(amountText)回復！", .heal)
        case .damageSelf:
            return ("\(target)は自身の効果で\(amountText)ダメージ", .damage)
        case .buffApply:
            if let label = actionLabel {
                return ("\(label)が\(target)に付与された", .status)
            } else {
                return ("効果が発動した", .status)
            }
        case .buffExpire:
            if let label = actionLabel {
                return ("\(target)の\(label)が切れた", .status)
            } else {
                return ("\(target)の効果が切れた", .status)
            }
        case .resurrection:
            return ("\(target)が蘇生した！", .heal)
        case .necromancer:
            return ("\(actor)のネクロマンサーで\(target)が蘇生した！", .heal)
        case .rescue:
            return ("\(actor)は\(target)を\(L10n.BattleTerm.rescue)した！", .heal)
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
            return ("\(target)に\(amountText)のダメージ！", .damage)
        case .enemySpecialHeal:
            return ("\(actor)は\(amountText)回復した！", .heal)
        case .enemySpecialBuff:
            return ("\(actor)は能力を強化した！", .status)
        case .spellChargeRecover:
            return ("\(actor)は魔法のチャージを回復した", .status)
        case .enemyAppear, .logOnly:
            return ("", .system)
        }
    }

    private static func displayValue(for effect: BattleActionEntry.Effect) -> Int? {
        let baseValue = effect.value.map { Int($0) }
        switch effect.kind {
        case .physicalDamage,
             .magicDamage,
             .breathDamage,
             .statusTick,
             .statusRampage,
             .damageSelf,
             .enemySpecialDamage:
            return effect.extra.map { Int($0) } ?? baseValue
        default:
            return baseValue
        }
    }

    private static func formatAmount(_ value: Int) -> String {
        value.formatted(jaJPDecimalStyle)
    }
}
