// ==============================================================================
// BattleEngine+EnemySpecialSkill.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 敵専用スキルの実行処理
//   - スキルタイプ別の処理分岐（物理、魔法、ブレス、状態異常、回復、バフ）
//   - 敵スキルのターゲット選択
//   - スキル使用回数管理
//
// ==============================================================================

import Foundation

// MARK: - Enemy Special Skills
extension BattleEngine {
    @discardableResult
    nonisolated static func executeEnemySpecialSkill(for side: ActorSide,
                                                     actorIndex: Int,
                                                     state: inout BattleState,
                                                     forcedTargets _: SacrificeTargets) -> Bool {
        guard side == .enemy else { return false }
        guard let actor = state.actor(for: side, index: actorIndex), actor.isAlive else { return false }

        let allies = state.enemies
        let opponents = state.players

        guard let skillId = selectEnemySpecialSkill(for: actor,
                                                    allies: allies,
                                                    opponents: opponents,
                                                    state: &state),
              let skill = state.enemySkillDefinition(for: skillId) else {
            return false
        }

        state.incrementEnemySkillUsage(actorIdentifier: actor.identifier, skillId: skillId)

        let actorIdx = state.actorIndex(for: side, arrayIndex: actorIndex)
        let entryBuilder = state.makeActionEntryBuilder(actorId: actorIdx,
                                                        kind: .enemySpecialSkill,
                                                        skillIndex: skillId)
        var defeatedTargets: [(ActorSide, Int)] = []
        var pendingSkillEffectLogs: [(kind: SkillEffectLogKind, actorId: UInt16, targetId: UInt16?)] = []
        var pendingBarrierLogs: [(actorId: UInt16, kind: SkillEffectLogKind)] = []

        switch skill.type {
        case .physical:
            executeEnemyPhysicalSkill(skill: skill,
                                      attackerSide: side,
                                      attackerIndex: actorIndex,
                                      state: &state,
                                      entryBuilder: entryBuilder,
                                      defeatedTargets: &defeatedTargets,
                                      pendingBarrierLogs: &pendingBarrierLogs)
        case .magical:
            executeEnemyMagicalSkill(skill: skill,
                                     attackerSide: side,
                                     attackerIndex: actorIndex,
                                     state: &state,
                                     entryBuilder: entryBuilder,
                                     defeatedTargets: &defeatedTargets,
                                     pendingSkillEffectLogs: &pendingSkillEffectLogs,
                                     pendingBarrierLogs: &pendingBarrierLogs)
        case .breath:
            executeEnemyBreathSkill(skill: skill,
                                    attackerSide: side,
                                    attackerIndex: actorIndex,
                                    state: &state,
                                    entryBuilder: entryBuilder,
                                    defeatedTargets: &defeatedTargets,
                                    pendingBarrierLogs: &pendingBarrierLogs)
        case .status:
            executeEnemyStatusSkill(skill: skill,
                                   attackerSide: side,
                                   attackerIndex: actorIndex,
                                   state: &state,
                                   entryBuilder: entryBuilder)
        case .heal:
            executeEnemyHealSkill(skill: skill,
                                 casterSide: side,
                                 casterIndex: actorIndex,
                                 state: &state,
                                 entryBuilder: entryBuilder)
        case .buff:
            executeEnemyBuffSkill(skill: skill,
                                 casterSide: side,
                                 casterIndex: actorIndex,
                                 state: &state,
                                 entryBuilder: entryBuilder)
        }

        state.appendActionEntry(entryBuilder.build())
        if !pendingSkillEffectLogs.isEmpty {
            appendSkillEffectLogs(pendingSkillEffectLogs, state: &state, turnOverride: state.turn)
        }
        if !pendingBarrierLogs.isEmpty {
            let events = pendingBarrierLogs.map { (kind: $0.kind, actorId: $0.actorId, targetId: UInt16?.none) }
            appendSkillEffectLogs(events, state: &state, turnOverride: state.turn)
        }

        for targetRef in defeatedTargets {
            handleDefeatReactions(targetSide: targetRef.0,
                                  targetIndex: targetRef.1,
                                  killerSide: side,
                                  killerIndex: actorIndex,
                                  state: &state,
                                  reactionDepth: 0,
                                  allowsReactionEvents: true)
        }

        return true
    }

    // MARK: - Physical Skill

    private nonisolated static func executeEnemyPhysicalSkill(skill: EnemySkillDefinition,
                                                              attackerSide: ActorSide,
                                                              attackerIndex: Int,
                                                              state: inout BattleState,
                                                              entryBuilder: BattleActionEntry.Builder,
                                                              defeatedTargets: inout [(ActorSide, Int)],
                                                              pendingBarrierLogs: inout [(actorId: UInt16, kind: SkillEffectLogKind)]) {
        guard var attacker = state.actor(for: attackerSide, index: attackerIndex), attacker.isAlive else { return }

        let targets = selectEnemySkillTargets(skill: skill,
                                              attackerSide: attackerSide,
                                              attackerIndex: attackerIndex,
                                              state: &state)

        let hitCount = skill.hitCount ?? 1
        let damageMultiplier = skill.damageDealtMultiplier ?? 1.0

        attacker.skillEffects.damage.dealt.physical *= damageMultiplier

        for (targetSide, targetIndex) in targets {
            guard attacker.isAlive else { break }
            guard var target = state.actor(for: targetSide, index: targetIndex),
                  target.isAlive else { continue }

            var totalDamage = 0
            var totalRawDamage = 0

            for hitIndex in 1...hitCount {
                guard target.isAlive else { break }

                let hitChance = computeHitChance(attacker: attacker,
                                                 defender: target,
                                                 hitIndex: hitIndex,
                                                 accuracyMultiplier: 1.0,
                                                 state: &state)
                let roll = state.random.nextDouble()
                guard roll <= hitChance else {
                    let targetIdx = state.actorIndex(for: targetSide, arrayIndex: targetIndex)
                    entryBuilder.addEffect(kind: .physicalEvade, target: targetIdx)
                    continue
                }

                let barrierKey = barrierKey(for: .physical)
                let guardActive = target.guardActive
                let guardBefore = target.guardBarrierCharges[barrierKey] ?? 0
                let barrierBefore = target.barrierCharges[barrierKey] ?? 0

                let (rawDamage, _) = computePhysicalDamage(attacker: attacker,
                                                           defender: &target,
                                                           hitIndex: hitIndex,
                                                           state: &state)
                let guardAfter = target.guardBarrierCharges[barrierKey] ?? 0
                let barrierAfter = target.barrierCharges[barrierKey] ?? 0
                let targetIdx = state.actorIndex(for: targetSide, arrayIndex: targetIndex)
                if guardActive && guardAfter < guardBefore {
                    let diff = guardBefore - guardAfter
                    for _ in 0..<diff {
                        pendingBarrierLogs.append((actorId: targetIdx, kind: .barrierGuardPhysical))
                    }
                } else if barrierAfter < barrierBefore {
                    let diff = barrierBefore - barrierAfter
                    for _ in 0..<diff {
                        pendingBarrierLogs.append((actorId: targetIdx, kind: .barrierPhysical))
                    }
                }
                totalRawDamage += rawDamage
                let applied = applyDamage(amount: rawDamage, to: &target)
                totalDamage += applied
                state.updateActor(target, side: targetSide, index: targetIndex)

                if let updated = state.actor(for: targetSide, index: targetIndex) {
                    target = updated
                }
            }

            if totalDamage > 0 {
                let targetIdx = state.actorIndex(for: targetSide, arrayIndex: targetIndex)
                entryBuilder.addEffect(kind: .enemySpecialDamage,
                                       target: targetIdx,
                                       value: UInt32(totalDamage),
                                       extra: UInt32(clamping: totalRawDamage))
            }

            if handleEnemySkillDefeat(targetSide: targetSide,
                                      targetIndex: targetIndex,
                                      state: &state,
                                      entryBuilder: entryBuilder) {
                defeatedTargets.append((targetSide, targetIndex))
            }

            if let statusId = skill.statusId, let statusChance = skill.statusChance {
                attemptEnemySkillStatusInflict(statusId: statusId,
                                               chancePercent: statusChance,
                                               targetSide: targetSide,
                                               targetIndex: targetIndex,
                                               state: &state,
                                               entryBuilder: entryBuilder)
            }
        }
    }

    // MARK: - Magical Skill

    private nonisolated static func executeEnemyMagicalSkill(skill: EnemySkillDefinition,
                                                             attackerSide: ActorSide,
                                                             attackerIndex: Int,
                                                             state: inout BattleState,
                                                             entryBuilder: BattleActionEntry.Builder,
                                                             defeatedTargets: inout [(ActorSide, Int)],
                                                             pendingSkillEffectLogs: inout [(kind: SkillEffectLogKind, actorId: UInt16, targetId: UInt16?)],
                                                             pendingBarrierLogs: inout [(actorId: UInt16, kind: SkillEffectLogKind)]) {
        guard var attacker = state.actor(for: attackerSide, index: attackerIndex), attacker.isAlive else { return }

        let targets = selectEnemySkillTargets(skill: skill,
                                              attackerSide: attackerSide,
                                              attackerIndex: attackerIndex,
                                              state: &state)

        let hitCount = skill.hitCount ?? 1
        let damageMultiplier = skill.damageDealtMultiplier ?? 1.0

        attacker.skillEffects.damage.dealt.magical *= damageMultiplier

        for (targetSide, targetIndex) in targets {
            guard attacker.isAlive else { break }
            guard var target = state.actor(for: targetSide, index: targetIndex),
                  target.isAlive else { continue }

            var totalDamage = 0
            var totalRawDamage = 0
            let attackerIdx = state.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
            let targetIdx = state.actorIndex(for: targetSide, arrayIndex: targetIndex)

            for _ in 0..<hitCount {
                guard target.isAlive else { break }

                let result = computeMagicalDamage(attacker: attacker,
                                                  defender: &target,
                                                  spellId: nil,
                                                  allowMagicCritical: false,
                                                  state: &state)
                if result.wasNullified {
                    pendingSkillEffectLogs.append((kind: .magicNullify,
                                                   actorId: targetIdx,
                                                   targetId: attackerIdx))
                }
                if result.wasCritical {
                    entryBuilder.addEffect(kind: .skillEffect,
                                           target: targetIdx,
                                           extra: UInt32(SkillEffectLogKind.magicCritical.rawValue))
                }
                if result.guardBarrierConsumed > 0 {
                    for _ in 0..<result.guardBarrierConsumed {
                        pendingBarrierLogs.append((actorId: targetIdx, kind: .barrierGuardMagical))
                    }
                } else if result.barrierConsumed > 0 {
                    for _ in 0..<result.barrierConsumed {
                        pendingBarrierLogs.append((actorId: targetIdx, kind: .barrierMagical))
                    }
                }

                totalRawDamage += result.damage
                let applied = applyDamage(amount: result.damage, to: &target)
                totalDamage += applied
                state.updateActor(target, side: targetSide, index: targetIndex)

                if let updated = state.actor(for: targetSide, index: targetIndex) {
                    target = updated
                }
            }

            if totalDamage > 0 {
                entryBuilder.addEffect(kind: .enemySpecialDamage,
                                       target: targetIdx,
                                       value: UInt32(totalDamage),
                                       extra: UInt32(clamping: totalRawDamage))
            }

            if handleEnemySkillDefeat(targetSide: targetSide,
                                      targetIndex: targetIndex,
                                      state: &state,
                                      entryBuilder: entryBuilder) {
                defeatedTargets.append((targetSide, targetIndex))
            }
        }
    }

    // MARK: - Breath Skill

    private nonisolated static func executeEnemyBreathSkill(skill: EnemySkillDefinition,
                                                            attackerSide: ActorSide,
                                                            attackerIndex: Int,
                                                            state: inout BattleState,
                                                            entryBuilder: BattleActionEntry.Builder,
                                                            defeatedTargets: inout [(ActorSide, Int)],
                                                            pendingBarrierLogs: inout [(actorId: UInt16, kind: SkillEffectLogKind)]) {
        guard var attacker = state.actor(for: attackerSide, index: attackerIndex), attacker.isAlive else { return }

        let targets = selectEnemySkillTargets(skill: skill,
                                              attackerSide: attackerSide,
                                              attackerIndex: attackerIndex,
                                              state: &state)

        let damageMultiplier = skill.damageDealtMultiplier ?? 1.0

        attacker.skillEffects.damage.dealt.breath *= damageMultiplier

        for (targetSide, targetIndex) in targets {
            guard attacker.isAlive else { break }
            guard var target = state.actor(for: targetSide, index: targetIndex),
                  target.isAlive else { continue }

            let result = computeBreathDamage(attacker: attacker,
                                             defender: &target,
                                             state: &state)
            let targetIdx = state.actorIndex(for: targetSide, arrayIndex: targetIndex)
            if result.guardBarrierConsumed > 0 {
                for _ in 0..<result.guardBarrierConsumed {
                    pendingBarrierLogs.append((actorId: targetIdx, kind: .barrierGuardBreath))
                }
            } else if result.barrierConsumed > 0 {
                for _ in 0..<result.barrierConsumed {
                    pendingBarrierLogs.append((actorId: targetIdx, kind: .barrierBreath))
                }
            }
            let applied = applyDamage(amount: result.damage, to: &target)
            state.updateActor(target, side: targetSide, index: targetIndex)

            entryBuilder.addEffect(kind: .enemySpecialDamage,
                                   target: targetIdx,
                                   value: UInt32(applied),
                                   extra: UInt32(clamping: result.damage))

            if handleEnemySkillDefeat(targetSide: targetSide,
                                      targetIndex: targetIndex,
                                      state: &state,
                                      entryBuilder: entryBuilder) {
                defeatedTargets.append((targetSide, targetIndex))
            }
        }
    }

    // MARK: - Status Skill

    private nonisolated static func executeEnemyStatusSkill(skill: EnemySkillDefinition,
                                                            attackerSide: ActorSide,
                                                            attackerIndex: Int,
                                                            state: inout BattleState,
                                                            entryBuilder: BattleActionEntry.Builder) {
        guard state.actor(for: attackerSide, index: attackerIndex) != nil else { return }
        guard let statusId = skill.statusId else { return }

        let targets = selectEnemySkillTargets(skill: skill,
                                              attackerSide: attackerSide,
                                              attackerIndex: attackerIndex,
                                              state: &state)

        let chancePercent = skill.statusChance ?? skill.chancePercent

        for (targetSide, targetIndex) in targets {
            attemptEnemySkillStatusInflict(statusId: statusId,
                                           chancePercent: chancePercent,
                                           targetSide: targetSide,
                                           targetIndex: targetIndex,
                                           state: &state,
                                           entryBuilder: entryBuilder)
        }
    }

    // MARK: - Heal Skill

    private nonisolated static func executeEnemyHealSkill(skill: EnemySkillDefinition,
                                                          casterSide: ActorSide,
                                                          casterIndex: Int,
                                                          state: inout BattleState,
                                                          entryBuilder: BattleActionEntry.Builder) {
        guard state.actor(for: casterSide, index: casterIndex)?.isAlive == true else { return }
        guard let healPercent = skill.healPercent else { return }

        let targets: [(ActorSide, Int)]
        switch skill.targeting {
        case .self:
            targets = [(casterSide, casterIndex)]
        case .allAllies:
            targets = state.enemies.enumerated()
                .filter { $0.element.isAlive }
                .map { (ActorSide.enemy, $0.offset) }
        default:
            targets = [(casterSide, casterIndex)]
        }

        for (targetSide, targetIndex) in targets {
            guard var target = state.actor(for: targetSide, index: targetIndex),
                  target.isAlive else { continue }

            let healAmount = (target.snapshot.maxHP * healPercent) / 100
            let missing = target.snapshot.maxHP - target.currentHP
            let applied = min(healAmount, missing)
            target.currentHP += applied
            state.updateActor(target, side: targetSide, index: targetIndex)

            let targetIdx = state.actorIndex(for: targetSide, arrayIndex: targetIndex)
            entryBuilder.addEffect(kind: .enemySpecialHeal, target: targetIdx, value: UInt32(applied))
        }
    }

    // MARK: - Buff Skill

    private nonisolated static func executeEnemyBuffSkill(skill: EnemySkillDefinition,
                                                          casterSide: ActorSide,
                                                          casterIndex: Int,
                                                          state: inout BattleState,
                                                          entryBuilder: BattleActionEntry.Builder) {
        guard state.actor(for: casterSide, index: casterIndex) != nil else { return }
        guard let buffType = skill.buffType else { return }

        let targets: [(ActorSide, Int)]
        switch skill.targeting {
        case .self:
            targets = [(casterSide, casterIndex)]
        case .allAllies:
            targets = state.enemies.enumerated()
                .filter { $0.element.isAlive }
                .map { (ActorSide.enemy, $0.offset) }
        default:
            targets = [(casterSide, casterIndex)]
        }

        let multiplier = skill.buffMultiplier ?? 1.5

        for (targetSide, targetIndex) in targets {
            guard var target = state.actor(for: targetSide, index: targetIndex),
                  target.isAlive else { continue }

            applyEnemyBuff(buffType: buffType, multiplier: multiplier, to: &target)
            state.updateActor(target, side: targetSide, index: targetIndex)

            let targetIdx = state.actorIndex(for: targetSide, arrayIndex: targetIndex)
            entryBuilder.addEffect(kind: .enemySpecialBuff,
                                   target: targetIdx,
                                   extra: UInt32(buffType))
        }
    }

    // MARK: - Helper Functions

    private nonisolated static func selectEnemySkillTargets(skill: EnemySkillDefinition,
                                                            attackerSide: ActorSide,
                                                            attackerIndex: Int,
                                                            state: inout BattleState) -> [(ActorSide, Int)] {
        let opponentSide: ActorSide = attackerSide == .player ? .enemy : .player
        let opponents = attackerSide == .player ? state.enemies : state.players

        switch skill.targeting {
        case .single:
            let attacker = state.actor(for: attackerSide, index: attackerIndex)
            let forcedTargets = SacrificeTargets()
            if let (targetSide, targetIndex) = selectOffensiveTarget(attackerSide: attackerSide,
                                                                     state: &state,
                                                                     allowFriendlyTargets: false,
                                                                     attacker: attacker,
                                                                     forcedTargets: forcedTargets) {
                return [(targetSide, targetIndex)]
            }
            return []
        case .random:
            let alive = opponents.enumerated().filter { $0.element.isAlive }
            guard !alive.isEmpty else { return [] }
            let hitCount = skill.hitCount ?? 1
            var targets: [(ActorSide, Int)] = []
            for _ in 0..<hitCount {
                let randomIndex = state.random.nextInt(in: 0...(alive.count - 1))
                let target = alive[randomIndex]
                targets.append((opponentSide, target.offset))
            }
            return targets
        case .all:
            return opponents.enumerated()
                .filter { $0.element.isAlive }
                .map { (opponentSide, $0.offset) }
        case .self:
            return [(attackerSide, attackerIndex)]
        case .allAllies:
            let allies = attackerSide == .player ? state.players : state.enemies
            return allies.enumerated()
                .filter { $0.element.isAlive }
                .map { (attackerSide, $0.offset) }
        }
    }

    @discardableResult
    private nonisolated static func handleEnemySkillDefeat(targetSide: ActorSide,
                                                          targetIndex: Int,
                                                          state: inout BattleState,
                                                          entryBuilder: BattleActionEntry.Builder) -> Bool {
        guard let target = state.actor(for: targetSide, index: targetIndex),
              !target.isAlive else { return false }

        appendDefeatLog(for: target,
                        side: targetSide,
                        index: targetIndex,
                        state: &state,
                        entryBuilder: entryBuilder)
        return true
    }

    private nonisolated static func attemptEnemySkillStatusInflict(statusId: UInt8,
                                                                   chancePercent: Int,
                                                                   targetSide: ActorSide,
                                                                   targetIndex: Int,
                                                                   state: inout BattleState,
                                                                   entryBuilder: BattleActionEntry.Builder) {
        guard var target = state.actor(for: targetSide, index: targetIndex),
              target.isAlive else { return }
        guard let statusDef = state.statusDefinitions[statusId] else { return }

        let targetIdx = state.actorIndex(for: targetSide, arrayIndex: targetIndex)

        let applied = attemptApplyStatus(statusId: statusId,
                                         baseChancePercent: Double(chancePercent),
                                         durationTurns: statusDef.durationTurns,
                                         sourceId: nil,
                                         to: &target,
                                         state: &state)
        state.updateActor(target, side: targetSide, index: targetIndex)

        if applied {
            entryBuilder.addEffect(kind: .statusInflict, target: targetIdx, statusId: UInt16(statusId))
            applyAutoStatusCureIfNeeded(for: targetSide, targetIndex: targetIndex, state: &state)
        } else {
            entryBuilder.addEffect(kind: .statusResist, target: targetIdx, statusId: UInt16(statusId))
        }
    }

    private nonisolated static func applyEnemyBuff(buffType: UInt8, multiplier: Double, to actor: inout BattleActor) {
        guard let type = SpellBuffType(rawValue: buffType) else { return }
        switch type {
        case .physicalDamageDealt, .combat, .damage:
            actor.snapshot.physicalAttackScore = Int(Double(actor.snapshot.physicalAttackScore) * multiplier)
        case .physicalDamageTaken:
            actor.snapshot.physicalDefenseScore = Int(Double(actor.snapshot.physicalDefenseScore) * multiplier)
        case .magicalDamageTaken:
            actor.snapshot.magicalDefenseScore = Int(Double(actor.snapshot.magicalDefenseScore) * multiplier)
        case .breathDamageTaken:
            break
        case .physicalAttackScore:
            actor.snapshot.physicalAttackScore = Int(Double(actor.snapshot.physicalAttackScore) * multiplier)
        case .magicalAttackScore:
            actor.snapshot.magicalAttackScore = Int(Double(actor.snapshot.magicalAttackScore) * multiplier)
        case .physicalDefenseScore:
            actor.snapshot.physicalDefenseScore = Int(Double(actor.snapshot.physicalDefenseScore) * multiplier)
        case .hitScore:
            actor.snapshot.hitScore = Int(Double(actor.snapshot.hitScore) * multiplier)
        case .attackCount:
            actor.snapshot.attackCount = actor.snapshot.attackCount * multiplier
        }
    }
}
