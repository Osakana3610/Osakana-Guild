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
        var criticalHits: Int

        init(totalDamage: Int = 0,
             defeated: Bool = false,
             attempts: Int = 0,
             hits: Int = 0,
             criticalHits: Int = 0) {
            self.totalDamage = totalDamage
            self.defeated = defeated
            self.attempts = attempts
            self.hits = hits
            self.criticalHits = criticalHits
        }
    }

    private static func reportMissing(_ message: String, location: String) {
#if DEBUG
        assertionFailure("\(location): \(message)")
#else
        Task { await AppLogCollector.shared.logError(message, location: location) }
#endif
    }

    private static func templateValue(for key: String, location: String) -> String? {
        let value = L10n.battleLog(key)
        if value.isEmpty || value == key {
            reportMissing("Missing localized template: \(key)", location: location)
            return nil
        }
        return value
    }

    private static func termValue(for key: String, location: String) -> String? {
        templateValue(for: key, location: location)
    }

    private static func renderTemplate(key: String,
                                       placeholders: [String: String?],
                                       location: String) -> String? {
        guard let template = templateValue(for: key, location: location) else { return nil }
        for (token, value) in placeholders {
            let placeholder = "{\(token)}"
            if template.contains(placeholder), value == nil {
                reportMissing("Missing placeholder value: \(token) for \(key)", location: location)
                return nil
            }
        }

        var result = template
        for (token, value) in placeholders {
            guard let value else { continue }
            result = result.replacingOccurrences(of: "{\(token)}", with: value)
        }
        return result
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
        statusNames: [UInt16: String] = [:],
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
                                                   statusNames: statusNames,
                                                   allyNames: allyNames,
                                                   enemyNames: enemyNames)

            let actionLabel = resolveActionLabel(entry: entry,
                                                 spellNames: spellNames,
                                                 enemySkillNames: enemySkillNames,
                                                 skillNames: skillNames,
                                                 statusNames: statusNames)

            let shouldRenderEffects = rendersEffectLines(for: entry)
            var effectEntries: [BattleLogEntry] = []
            if shouldRenderEffects {
                effectEntries = renderEffectEntries(for: entry,
                                                    actorName: actorName,
                                                    actionLabel: actionLabel,
                                                    allyNames: allyNames,
                                                    enemyNames: enemyNames,
                                                    statusNames: statusNames,
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
                                            statusNames: [UInt16: String],
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
                                         statusNames: statusNames,
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
                                   statusNames: statusNames,
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
                                             statusNames: [UInt16: String],
                                             allyNames: [UInt8: String],
                                             enemyNames: [UInt16: String]) -> BattleLogEntry {
        let (message, type) = declarationMessage(kind: entry.declaration.kind,
                                                 actorName: actorName,
                                                 entry: entry,
                                                 spellNames: spellNames,
                                                 enemySkillNames: enemySkillNames,
                                                 skillNames: skillNames,
                                                 statusNames: statusNames,
                                                 allyNames: allyNames,
                                                 enemyNames: enemyNames)
        return BattleLogEntry(turn: turn,
                              message: message ?? "",
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
                                        statusNames: [UInt16: String],
                                        actorIdentifiers: [UInt16: String]) -> BattleLogEntry? {
        let targetName = resolveName(index: effect.target, allyNames: allyNames, enemyNames: enemyNames)
        let displayAmount = displayValue(for: effect)
        let effectLabel = resolveEffectLabel(effect: effect,
                                             entry: entry,
                                             actionLabel: actionLabel,
                                             statusNames: statusNames)
        let (message, type) = effectMessage(kind: effect.kind,
                                            actorName: actorName,
                                            targetName: targetName,
                                            value: displayAmount,
                                            actionLabel: effectLabel)
        guard let message, !message.isEmpty else { return nil }
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
            guard let name = enemyNames[index] else {
                reportMissing("Enemy name not found for actorIndex=\(index)", location: "BattleLogRenderer.resolveName")
                return nil
            }
            return name
        } else {
            guard let name = allyNames[UInt8(index)] else {
                reportMissing("Ally name not found for actorIndex=\(index)", location: "BattleLogRenderer.resolveName")
                return nil
            }
            return name
        }
    }

    private static func resolveActionLabel(entry: BattleActionEntry,
                                           spellNames: [UInt8: String],
                                           enemySkillNames: [UInt16: String],
                                           skillNames: [UInt16: String],
                                           statusNames: [UInt16: String]) -> String? {
        switch entry.declaration.kind {
        case .skillEffect:
            return resolveSkillEffectLabel(extra: entry.declaration.extra,
                                           location: "BattleLogRenderer.resolveActionLabel")
        case .priestMagic, .mageMagic:
            guard let skillIndex = entry.declaration.skillIndex,
                  let spellId = UInt8(exactly: skillIndex),
                  let name = spellNames[spellId] else {
                reportMissing("Spell name not found for skillIndex=\(String(describing: entry.declaration.skillIndex))",
                              location: "BattleLogRenderer.resolveActionLabel")
                return nil
            }
            return name
        case .enemySpecialSkill:
            guard let skillIndex = entry.declaration.skillIndex,
                  let name = enemySkillNames[skillIndex] else {
                reportMissing("Enemy skill name not found for skillIndex=\(String(describing: entry.declaration.skillIndex))",
                              location: "BattleLogRenderer.resolveActionLabel")
                return nil
            }
            return name
        case .buffApply, .buffExpire:
            guard let skillIndex = entry.declaration.skillIndex,
                  let name = skillNames[skillIndex] else {
                reportMissing("Skill name not found for skillIndex=\(String(describing: entry.declaration.skillIndex))",
                              location: "BattleLogRenderer.resolveActionLabel")
                return nil
            }
            return name
        case .reactionAttack:
            if let skillIndex = entry.declaration.skillIndex, let name = skillNames[skillIndex] {
                return name
            }
            return termValue(for: "battleLog.term.reactionAttack", location: "BattleLogRenderer.resolveActionLabel")
        case .followUp:
            if let skillIndex = entry.declaration.skillIndex, let name = skillNames[skillIndex] {
                return name
            }
            return termValue(for: "battleLog.term.martialFollowUp", location: "BattleLogRenderer.resolveActionLabel")
        case .statusTick:
            guard let statusId = entry.effects.first(where: { $0.kind == .statusTick })?.statusId,
                  let name = statusNames[statusId] else {
                reportMissing("Status name not found for statusId in statusTick",
                              location: "BattleLogRenderer.resolveActionLabel")
                return nil
            }
            return name
        case .statusRecover:
            guard let statusId = entry.effects.first(where: { $0.kind == .statusRecover })?.statusId,
                  let name = statusNames[statusId] else {
                reportMissing("Status name not found for statusId in statusRecover",
                              location: "BattleLogRenderer.resolveActionLabel")
                return nil
            }
            return name
        case .spellChargeRecover:
            guard let rawSpellId = entry.effects.first(where: { $0.kind == .spellChargeRecover })?.value,
                  let spellId = UInt8(exactly: rawSpellId),
                  let name = spellNames[spellId] else {
                reportMissing("Spell name not found for spellChargeRecover",
                              location: "BattleLogRenderer.resolveActionLabel")
                return nil
            }
            return name
        case .actionLocked:
            return termValue(for: "battleLog.term.actionLocked", location: "BattleLogRenderer.resolveActionLabel")
        case .resurrection:
            return termValue(for: "battleLog.term.resurrection", location: "BattleLogRenderer.resolveActionLabel")
        case .necromancer:
            return termValue(for: "battleLog.term.necromancer", location: "BattleLogRenderer.resolveActionLabel")
        case .rescue:
            return termValue(for: "battleLog.term.rescue", location: "BattleLogRenderer.resolveActionLabel")
        case .healParty:
            return termValue(for: "battleLog.term.healParty", location: "BattleLogRenderer.resolveActionLabel")
        case .healSelf:
            return termValue(for: "battleLog.term.healSelf", location: "BattleLogRenderer.resolveActionLabel")
        case .healAbsorb:
            return termValue(for: "battleLog.term.healAbsorb", location: "BattleLogRenderer.resolveActionLabel")
        case .healVampire:
            return termValue(for: "battleLog.term.healVampire", location: "BattleLogRenderer.resolveActionLabel")
        case .damageSelf:
            return termValue(for: "battleLog.term.damageSelf", location: "BattleLogRenderer.resolveActionLabel")
        default:
            return nil
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
        return renderTemplate(
            key: "battleLog.summary.hit",
            placeholders: [
                "attempts": formatAmount(attempts),
                "hits": formatAmount(hits)
            ],
            location: "BattleLogRenderer.summarizeHits"
        )
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
        guard let label = actionLabel else {
            reportMissing("Missing action label for buff summary", location: "BattleLogRenderer.renderBuffSummary")
            return nil
        }
        guard let description = describeTargetGroup(for: targets,
                                                    allyNames: allyNames,
                                                    enemyNames: enemyNames) else {
            return nil
        }
        guard let message = renderTemplate(
            key: "battleLog.summary.buffGroup",
            placeholders: [
                "group": description,
                "label": label
            ],
            location: "BattleLogRenderer.renderBuffSummary"
        ) else {
            return nil
        }
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
                                              statusNames: [UInt16: String],
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
            case .skillEffect:
                guard let target = effect.target,
                      let extra = effect.extra,
                      extra == SkillEffectLogKind.physicalCritical.rawValue else {
                    orderedTokens.append(.standard(effect))
                    continue
                }
                ensureToken(for: target)
                var summary = summaries[target] ?? PhysicalSummary()
                summary.criticalHits += 1
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
                                       statusNames: statusNames,
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
        guard let targetName = resolveName(index: target, allyNames: allyNames, enemyNames: enemyNames) else {
            return nil
        }
        let actor = actorName
        let targetId = actorIdentifiers[target] ?? String(target)

        if summary.totalDamage == 0 && !summary.defeated {
            guard summary.attempts > 0 else { return nil }
            guard let message = renderTemplate(
                key: "battleLog.effect.physicalEvade",
                placeholders: [
                    "actor": actor,
                    "target": targetName
                ],
                location: "BattleLogRenderer.makePhysicalSummaryEntry"
            ) else {
                return nil
            }
            return BattleLogEntry(turn: Int(entry.turn),
                                  message: message,
                                  type: .miss,
                                  actorId: nil,
                                  targetId: targetId)
        }

        let amountText = formatAmount(summary.totalDamage)
        let templateKey = summary.criticalHits > 0
            ? "battleLog.effect.physicalCriticalDamage"
            : "battleLog.effect.physicalDamage"
        guard let message = renderTemplate(
            key: templateKey,
            placeholders: [
                "actor": actor,
                "target": targetName,
                "amount": amountText
            ],
            location: "BattleLogRenderer.makePhysicalSummaryEntry"
        ) else {
            return nil
        }

        let type: BattleLogEntry.LogType = summary.totalDamage > 0 ? .damage : .action
        return BattleLogEntry(turn: Int(entry.turn),
                              message: message,
                              type: type,
                              actorId: nil,
                              targetId: targetId)
    }

    private static func describeTargetGroup(for targets: [UInt16],
                                            allyNames: [UInt8: String],
                                            enemyNames: [UInt16: String]) -> String? {
        let uniqueTargets = Array(Set(targets))
        guard let first = uniqueTargets.first else {
            reportMissing("Buff summary targets are empty", location: "BattleLogRenderer.describeTargetGroup")
            return nil
        }
        let isEnemySide = first >= 1000
        if uniqueTargets.count == 1 {
            return resolveName(index: first, allyNames: allyNames, enemyNames: enemyNames)
        }
        let key = isEnemySide ? "battleLog.term.enemiesGroup" : "battleLog.term.alliesGroup"
        return termValue(for: key, location: "BattleLogRenderer.describeTargetGroup")
    }

    private static func resolveEffectLabel(effect: BattleActionEntry.Effect,
                                           entry: BattleActionEntry,
                                           actionLabel: String?,
                                           statusNames: [UInt16: String]) -> String? {
        switch effect.kind {
        case .skillEffect:
            return resolveSkillEffectLabel(extra: effect.extra ?? entry.declaration.extra,
                                           location: "BattleLogRenderer.resolveEffectLabel")
        case .statusInflict, .statusResist, .statusRecover, .statusTick:
            guard let statusId = effect.statusId,
                  let name = statusNames[statusId] else {
                reportMissing("Status name not found for statusId=\(String(describing: effect.statusId))",
                              location: "BattleLogRenderer.resolveEffectLabel")
                return nil
            }
            return name
        case .buffApply, .buffExpire, .reactionAttack, .followUp:
            guard let actionLabel else {
                reportMissing("Missing action label for effect kind \(effect.kind)",
                              location: "BattleLogRenderer.resolveEffectLabel")
                return nil
            }
            return actionLabel
        default:
            return nil
        }
    }

    private static func declarationKey(for kind: ActionKind) -> String? {
        switch kind {
        case .skillEffect,
             .defend,
             .physicalAttack,
             .priestMagic,
             .mageMagic,
             .breath,
             .battleStart,
             .turnStart,
             .victory,
             .defeat,
             .retreat,
             .physicalKill,
             .statusRecover,
             .statusTick,
             .reactionAttack,
             .followUp,
             .healAbsorb,
             .healVampire,
             .healParty,
             .healSelf,
             .damageSelf,
             .buffApply,
             .buffExpire,
             .resurrection,
             .necromancer,
             .rescue,
             .actionLocked,
             .noAction,
             .withdraw,
             .sacrifice,
             .vampireUrge,
             .enemyAppear,
             .enemySpecialSkill,
             .spellChargeRecover:
            return "battleLog.declaration.\(kind)"
        default:
            return nil
        }
    }

    private static func effectKey(for kind: BattleActionEntry.Effect.Kind) -> String? {
        switch kind {
        case .enemyAppear, .logOnly:
            return nil
        default:
            return "battleLog.effect.\(kind)"
        }
    }

    private static func declarationLogType(for kind: ActionKind) -> BattleLogEntry.LogType {
        switch kind {
        case .skillEffect:
            return .status
        case .defend: return .guard
        case .physicalAttack, .priestMagic, .mageMagic, .breath, .reactionAttack, .followUp, .noAction: return .action
        case .battleStart, .turnStart, .enemyAppear: return .system
        case .victory: return .victory
        case .defeat: return .defeat
        case .retreat: return .retreat
        case .physicalKill,
             .statusRecover,
             .statusTick,
             .buffApply,
             .buffExpire,
             .resurrection,
             .necromancer,
             .rescue,
             .actionLocked,
             .withdraw,
             .sacrifice,
             .vampireUrge:
            return .status
        case .healAbsorb, .healVampire, .healParty, .healSelf:
            return .heal
        case .damageSelf:
            return .damage
        case .enemySpecialSkill:
            return .action
        case .spellChargeRecover:
            return .status
        default:
            return .system
        }
    }

    private static func effectLogType(for kind: BattleActionEntry.Effect.Kind) -> BattleLogEntry.LogType {
        switch kind {
        case .skillEffect:
            return .status
        case .physicalDamage,
             .magicDamage,
             .breathDamage,
             .statusTick,
             .statusRampage,
             .damageSelf,
             .enemySpecialDamage:
            return .damage
        case .physicalEvade,
             .magicMiss:
            return .miss
        case .physicalParry,
             .physicalBlock,
             .martial,
             .reactionAttack,
             .followUp,
             .noAction:
            return .action
        case .magicHeal,
             .healParty,
             .healSelf,
             .healAbsorb,
             .healVampire,
             .enemySpecialHeal,
             .resurrection,
             .necromancer,
             .rescue:
            return .heal
        case .physicalKill:
            return .defeat
        case .statusInflict,
             .statusResist,
             .statusRecover,
             .statusConfusion,
             .buffApply,
             .buffExpire,
             .actionLocked,
             .withdraw,
             .sacrifice,
             .vampireUrge,
             .enemySpecialBuff,
             .spellChargeRecover:
            return .status
        case .enemyAppear, .logOnly:
            return .system
        }
    }

    private static func resolveSkillEffectLabel(extra: UInt16?, location: String) -> String? {
        guard let extra,
              let kind = SkillEffectLogKind(rawValue: extra) else {
            reportMissing("SkillEffectLogKind missing/invalid: \(String(describing: extra))", location: location)
            return nil
        }
        return termValue(for: kind.termKey, location: location)
    }

    private static func placeholderMap(actor: String?,
                                       target: String?,
                                       amount: String?,
                                       label: String?,
                                       turn: String? = nil,
                                       attempts: String? = nil,
                                       hits: String? = nil) -> [String: String?] {
        [
            "actor": actor,
            "target": target,
            "amount": amount,
            "label": label,
            "spell": label,
            "skill": label,
            "reaction": label,
            "followUp": label,
            "turn": turn,
            "attempts": attempts,
            "hits": hits
        ]
    }

    private static func declarationMessage(kind: ActionKind,
                                           actorName: String?,
                                           entry: BattleActionEntry,
                                           spellNames: [UInt8: String],
                                           enemySkillNames: [UInt16: String],
                                           skillNames: [UInt16: String],
                                           statusNames: [UInt16: String],
                                           allyNames: [UInt8: String],
                                           enemyNames: [UInt16: String]) -> (String?, BattleLogEntry.LogType) {
        let type = declarationLogType(for: kind)
        guard let key = declarationKey(for: kind) else {
            return ("", type)
        }

        let actionLabel = resolveActionLabel(entry: entry,
                                             spellNames: spellNames,
                                             enemySkillNames: enemySkillNames,
                                             skillNames: skillNames,
                                             statusNames: statusNames)

        let turnText: String?
        if kind == .turnStart {
            guard let extra = entry.declaration.extra else {
                reportMissing("Missing extra for turnStart", location: "BattleLogRenderer.declarationMessage")
                return (nil, type)
            }
            turnText = formatAmount(Int(extra))
        } else {
            turnText = nil
        }

        var message = renderTemplate(
            key: key,
            placeholders: placeholderMap(actor: actorName,
                                         target: nil,
                                         amount: nil,
                                         label: actionLabel,
                                         turn: turnText),
            location: "BattleLogRenderer.declarationMessage"
        )

        if let hitSummary = summarizeHits(for: entry, actionKind: kind),
           let base = message {
            message = "\(base) \(hitSummary)"
        }

        return (message, type)
    }

    private static func effectMessage(kind: BattleActionEntry.Effect.Kind,
                                      actorName: String?,
                                      targetName: String?,
                                      value: Int?,
                                      actionLabel: String?) -> (String?, BattleLogEntry.LogType) {
        let type = effectLogType(for: kind)
        guard let key = effectKey(for: kind) else {
            return ("", type)
        }
        let amountText = value.map { formatAmount($0) }
        let message = renderTemplate(
            key: key,
            placeholders: placeholderMap(actor: actorName,
                                         target: targetName,
                                         amount: amountText,
                                         label: actionLabel),
            location: "BattleLogRenderer.effectMessage"
        )
        return (message, type)
    }

    private static func displayValue(for effect: BattleActionEntry.Effect) -> Int? {
        switch effect.kind {
        case .physicalDamage,
             .magicDamage,
             .breathDamage,
             .statusTick,
             .statusRampage,
             .enemySpecialDamage,
             .damageSelf:
            if let raw = effect.extra {
                return Int(raw)
            }
        default:
            break
        }
        return effect.value.map { Int($0) }
    }

    private static func formatAmount(_ value: Int) -> String {
        value.formatted(jaJPDecimalStyle)
    }
}
