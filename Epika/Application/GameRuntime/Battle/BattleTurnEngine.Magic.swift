// ==============================================================================
// BattleTurnEngine.Magic.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 魔法攻撃と回復魔法の実行
//   - ブレス攻撃の実行
//   - 呪文の選択とチャージ消費
//   - 状態異常付与判定
//
// 【本体との関係】
//   - BattleTurnEngineの拡張ファイル
//   - 魔法系行動に特化した機能を提供
//
// 【主要機能】
//   - executePriestMagic: 僧侶魔法（回復）の実行
//   - executeMageMagic: 魔法使い魔法（攻撃）の実行
//   - executeBreath: ブレス攻撃の実行
//   - selectMageSpell、selectPriestHealingSpell: 呪文選択
//   - spellPowerModifier: 呪文威力修正
//
// 【使用箇所】
//   - BattleTurnEngine.TurnLoop（行動実行時）
//
// ==============================================================================

import Foundation

// MARK: - Magic (Priest & Mage)
extension BattleTurnEngine {
    @discardableResult
    static func executePriestMagic(for side: ActorSide,
                                   casterIndex: Int,
                                   context: inout BattleContext,
                                   forcedTargets: BattleContext.SacrificeTargets) -> Bool {
        guard var caster = context.actor(for: side, index: casterIndex), caster.isAlive else { return false }
        guard let spell = selectPriestHealingSpell(for: caster) else { return false }

        let allies: [BattleActor] = side == .player ? context.players : context.enemies
        guard let targetIndex = selectHealingTargetIndex(in: allies) else { return false }
        guard caster.actionResources.consume(spellId: spell.id) else { return false }

        context.updateActor(caster, side: side, index: casterIndex)

        // 呪文名付きログを追加
        let casterIdx = context.actorIndex(for: side, arrayIndex: casterIndex)
        context.appendAction(kind: .priestMagic, actor: casterIdx, skillIndex: UInt16(spell.id))

        performPriestMagic(casterSide: side,
                           casterIndex: casterIndex,
                           targetIndex: targetIndex,
                           spell: spell,
                           context: &context)
        return true
    }

    static func performPriestMagic(casterSide: ActorSide,
                                   casterIndex: Int,
                                   targetIndex: Int,
                                   spell: SpellDefinition,
                                   context: inout BattleContext) {
        guard let caster = context.actor(for: casterSide, index: casterIndex) else { return }
        guard var target = context.actor(for: casterSide, index: targetIndex) else { return }

        let healAmount = computeHealingAmount(caster: caster, target: target, spellId: spell.id, context: &context)
        let missing = target.snapshot.maxHP - target.currentHP
        let applied = min(healAmount, missing)
        target.currentHP += applied
        context.updateActor(target, side: casterSide, index: targetIndex)

        let casterIdx = context.actorIndex(for: casterSide, arrayIndex: casterIndex)
        let targetIdx = context.actorIndex(for: casterSide, arrayIndex: targetIndex)
        context.appendAction(kind: .magicHeal, actor: casterIdx, target: targetIdx, value: UInt32(applied))
    }

    @discardableResult
    static func executeMageMagic(for side: ActorSide,
                                 attackerIndex: Int,
                                 context: inout BattleContext,
                                 forcedTargets: BattleContext.SacrificeTargets) -> Bool {
        guard var attacker = context.actor(for: side, index: attackerIndex), attacker.isAlive else { return false }
        guard let spell = selectMageSpell(for: attacker) else { return false }
        guard attacker.actionResources.consume(spellId: spell.id) else { return false }

        context.updateActor(attacker, side: side, index: attackerIndex)

        // 魔法名付きログを追加
        let attackerIdx = context.actorIndex(for: side, arrayIndex: attackerIndex)
        context.appendAction(kind: .mageMagic, actor: attackerIdx, skillIndex: UInt16(spell.id))

        let allowFriendlyTargets = hasStatus(tag: statusTagConfusion, in: attacker, context: context)
        let targetCount = statusTargetCount(for: attacker, spell: spell)
        let targets = selectStatusTargets(attackerSide: side,
                                          context: &context,
                                          allowFriendlyTargets: allowFriendlyTargets,
                                          maxTargets: targetCount,
                                          distinct: true)

        for targetRef in targets {
            guard let refreshedAttacker = context.actor(for: side, index: attackerIndex),
                  refreshedAttacker.isAlive else { break }
            guard var target = context.actor(for: targetRef.0, index: targetRef.1),
                  target.isAlive else { continue }

            let damage = computeMagicalDamage(attacker: refreshedAttacker,
                                              defender: &target,
                                              spellId: spell.id,
                                              context: &context)
            let applied = applyDamage(amount: damage, to: &target)
            applyMagicDegradation(to: &target, spellId: spell.id, caster: refreshedAttacker)

            context.updateActor(target, side: targetRef.0, index: targetRef.1)

            let attackerIdx = context.actorIndex(for: side, arrayIndex: attackerIndex)
            let targetIdx = context.actorIndex(for: targetRef.0, arrayIndex: targetRef.1)
            context.appendAction(kind: .magicDamage, actor: attackerIdx, target: targetIdx, value: UInt32(applied))

            if !target.isAlive {
                appendDefeatLog(for: target, side: targetRef.0, index: targetRef.1, context: &context)
                let killerRef = BattleContext.reference(for: side, index: attackerIndex)
                dispatchReactions(for: .allyDefeated(side: targetRef.0,
                                                     fallenIndex: targetRef.1,
                                                     killer: killerRef),
                                  depth: 0,
                                  context: &context)
                // 敵を倒したキャラのリアクション
                let killedRef = BattleContext.reference(for: targetRef.0, index: targetRef.1)
                dispatchReactions(for: .selfKilledEnemy(side: side,
                                                        actorIndex: attackerIndex,
                                                        killedEnemy: killedRef),
                                  depth: 0,
                                  context: &context)
                if let _ = context.actor(for: targetRef.0, index: targetRef.1) {
                    _ = attemptInstantResurrectionIfNeeded(of: targetRef.1,
                                                          side: targetRef.0,
                                                          context: &context)
                        || attemptRescue(of: targetRef.1,
                                        side: targetRef.0,
                                        context: &context)
                }
            } else {
                let attackerRef = BattleContext.reference(for: side, index: attackerIndex)
                dispatchReactions(for: .selfDamagedMagical(side: targetRef.0,
                                                           actorIndex: targetRef.1,
                                                           attacker: attackerRef),
                                  depth: 0,
                                  context: &context)
            }

            // 呪文にステータスIDが設定されている場合は付与を試みる
            if let statusId = spell.statusId {
                guard var freshTarget = context.actor(for: targetRef.0, index: targetRef.1),
                      freshTarget.isAlive else { continue }
                let baseChance = baseStatusChancePercent(spell: spell, caster: refreshedAttacker, target: freshTarget)
                let statusApplied = attemptApplyStatus(statusId: statusId,
                                                       baseChancePercent: baseChance,
                                                       durationTurns: nil,
                                                       sourceId: refreshedAttacker.identifier,
                                                       to: &freshTarget,
                                                       context: &context,
                                                       sourceProcMultiplier: refreshedAttacker.skillEffects.combat.procChanceMultiplier)
                context.updateActor(freshTarget, side: targetRef.0, index: targetRef.1)

                // autoStatusCureOnAlly判定
                if statusApplied {
                    applyAutoStatusCureIfNeeded(for: targetRef.0, targetIndex: targetRef.1, context: &context)
                }
            }
        }

        // 味方が魔法攻撃したイベントを発火（追撃用）
        dispatchReactions(for: .allyMagicAttack(side: side, casterIndex: attackerIndex),
                          depth: 0,
                          context: &context)

        return true
    }

    @discardableResult
    static func executeBreath(for side: ActorSide,
                              attackerIndex: Int,
                              context: inout BattleContext,
                              forcedTargets: BattleContext.SacrificeTargets) -> Bool {
        guard var attacker = context.actor(for: side, index: attackerIndex), attacker.isAlive else { return false }
        guard attacker.actionResources.consume(.breath) else { return false }

        context.updateActor(attacker, side: side, index: attackerIndex)

        appendActionLog(for: attacker, side: side, index: attackerIndex, category: .breath, context: &context)

        let allowFriendlyTargets = hasStatus(tag: statusTagConfusion, in: attacker, context: context)
        let targets = selectStatusTargets(attackerSide: side,
                                          context: &context,
                                          allowFriendlyTargets: allowFriendlyTargets,
                                          maxTargets: 6,
                                          distinct: true)

        for targetRef in targets {
            guard let refreshedAttacker = context.actor(for: side, index: attackerIndex),
                  refreshedAttacker.isAlive else { break }
            guard var target = context.actor(for: targetRef.0, index: targetRef.1),
                  target.isAlive else { continue }

            let damage = computeBreathDamage(attacker: refreshedAttacker, defender: &target, context: &context)
            let applied = applyDamage(amount: damage, to: &target)

            context.updateActor(target, side: targetRef.0, index: targetRef.1)

            let attackerIdx = context.actorIndex(for: side, arrayIndex: attackerIndex)
            let targetIdx = context.actorIndex(for: targetRef.0, arrayIndex: targetRef.1)
            context.appendAction(kind: .breathDamage, actor: attackerIdx, target: targetIdx, value: UInt32(applied))

            if !target.isAlive {
                appendDefeatLog(for: target, side: targetRef.0, index: targetRef.1, context: &context)
                let killerRef = BattleContext.reference(for: side, index: attackerIndex)
                dispatchReactions(for: .allyDefeated(side: targetRef.0,
                                                     fallenIndex: targetRef.1,
                                                     killer: killerRef),
                                  depth: 0,
                                  context: &context)
                // 敵を倒したキャラのリアクション
                let killedRef = BattleContext.reference(for: targetRef.0, index: targetRef.1)
                dispatchReactions(for: .selfKilledEnemy(side: side,
                                                        actorIndex: attackerIndex,
                                                        killedEnemy: killedRef),
                                  depth: 0,
                                  context: &context)
                if let _ = context.actor(for: targetRef.0, index: targetRef.1) {
                    _ = attemptInstantResurrectionIfNeeded(of: targetRef.1,
                                                          side: targetRef.0,
                                                          context: &context)
                        || attemptRescue(of: targetRef.1,
                                        side: targetRef.0,
                                        context: &context)
                }
            } else {
                let attackerRef = BattleContext.reference(for: side, index: attackerIndex)
                dispatchReactions(for: .selfDamagedPhysical(side: targetRef.0,
                                                            actorIndex: targetRef.1,
                                                            attacker: attackerRef),
                                  depth: 0,
                                  context: &context)
            }
        }

        return true
    }

    static func selectMageSpell(for actor: BattleActor) -> SpellDefinition? {
        let available = actor.spells.mage.filter { actor.actionResources.hasAvailableCharges(for: $0.id) }
        guard !available.isEmpty else { return nil }
        return highestTierSpell(in: available) { spell in
            spell.category == .damage || spell.category == .status
        }
    }

    static func selectPriestHealingSpell(for actor: BattleActor) -> SpellDefinition? {
        let available = actor.spells.priest.filter { actor.actionResources.hasAvailableCharges(for: $0.id) }
        guard !available.isEmpty else { return nil }
        return highestTierSpell(in: available) { $0.category == .healing }
    }

    static func highestTierSpell(in spells: [SpellDefinition],
                                 matching predicate: ((SpellDefinition) -> Bool)? = nil) -> SpellDefinition? {
        let filtered: [SpellDefinition]
        if let predicate {
            filtered = spells.filter(predicate)
        } else {
            filtered = spells
        }
        guard !filtered.isEmpty else { return nil }
        return filtered.max { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            return lhs.id < rhs.id
        }
    }

    static func statusTargetCount(for caster: BattleActor, spell: SpellDefinition) -> Int {
        let base = spell.maxTargetsBase ?? 1
        guard base > 0 else { return 1 }
        let extraPerLevel = spell.extraTargetsPerLevels ?? 0.0
        let level = Double(caster.level ?? 0)
        let total = Double(base) + level * extraPerLevel
        return max(1, Int(total.rounded(.down)))
    }

    static func baseStatusChancePercent(spell: SpellDefinition, caster: BattleActor, target: BattleActor) -> Double {
        let magicAttack = max(0, caster.snapshot.magicalAttack)
        let magicDefense = max(1, target.snapshot.magicalDefense)
        let ratio = Double(magicAttack) / Double(magicDefense)
        let base = min(95.0, 50.0 * ratio)
        let luckPenalty = max(0, target.luck - 10)
        let luckScalePercent = max(0.0, 100.0 - Double(luckPenalty * 2))
        return max(0.0, base * (luckScalePercent / 100.0))
    }

    static func spellPowerModifier(for attacker: BattleActor, spellId: UInt8? = nil) -> Double {
        let percentScale = max(0.0, 1.0 + attacker.skillEffects.spell.power.percent / 100.0)
        var modifier = percentScale * attacker.skillEffects.spell.power.multiplier
        if let spellId,
           let specific = attacker.skillEffects.spell.specificMultipliers[spellId] {
            modifier *= specific
        }
        return modifier
    }
}
