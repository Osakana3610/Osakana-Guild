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
    nonisolated static func executePriestMagic(for side: ActorSide,
                                   casterIndex: Int,
                                   context: inout BattleContext,
                                   forcedTargets: BattleContext.SacrificeTargets) -> Bool {
        guard var caster = context.actor(for: side, index: casterIndex), caster.isAlive else { return false }

        let allies: [BattleActor] = side == .player ? context.players : context.enemies
        let opponents: [BattleActor] = side == .player ? context.enemies : context.players

        // 発動条件を満たす呪文をtier重みで抽選
        let available = caster.spells.priest.filter { caster.actionResources.hasAvailableCharges(for: $0.id) }
        guard let spell = selectSpellByTierWeight(in: available, matching: { canCastSpell($0, caster: caster, allies: allies, opponents: opponents) }, random: &context.random) else {
            return false
        }

        guard caster.actionResources.consume(spellId: spell.id) else { return false }
        context.updateActor(caster, side: side, index: casterIndex)

        switch spell.category {
        case .healing:
            // castConditionがtargetHalfHPの場合、HP半分以下の味方のみを対象にする
            let requireHalfHP = spell.castCondition.flatMap { SpellDefinition.CastCondition(rawValue: $0) } == .targetHalfHP
            guard let targetIndex = selectHealingTargetIndex(in: allies, requireHalfHP: requireHalfHP) else { return true }
            performPriestMagic(casterSide: side,
                               casterIndex: casterIndex,
                               targetIndex: targetIndex,
                               spell: spell,
                               context: &context)
        case .buff:
            performBuffSpell(casterSide: side,
                             casterIndex: casterIndex,
                             spell: spell,
                             context: &context)
        case .cleanse:
            _ = performCleanseSpell(casterSide: side,
                                    casterIndex: casterIndex,
                                    spell: spell,
                                    context: &context)
        case .damage, .status:
            // 僧侶はdamage/statusを持たない想定だが、念のため
            break
        }

        return true
    }

    nonisolated static func performPriestMagic(casterSide: ActorSide,
                                   casterIndex: Int,
                                   targetIndex: Int,
                                   spell: SpellDefinition,
                                   context: inout BattleContext) {
        guard let caster = context.actor(for: casterSide, index: casterIndex) else { return }
        guard var target = context.actor(for: casterSide, index: targetIndex) else { return }

        let healAmount: Int
        if let percent = spell.healPercentOfMaxHP {
            // 最大HPの割合で回復（フルヒールなど）
            healAmount = target.snapshot.maxHP * percent / 100
        } else {
            // 通常の回復計算 + healMultiplier
            let baseAmount = computeHealingAmount(caster: caster, target: target, spellId: spell.id, context: &context)
            let multiplier = spell.healMultiplier ?? 1.0
            healAmount = Int(Double(baseAmount) * multiplier)
        }
        let missing = target.snapshot.maxHP - target.currentHP
        let applied = min(healAmount, missing)
        target.currentHP += applied
        context.updateActor(target, side: casterSide, index: targetIndex)

        let casterIdx = context.actorIndex(for: casterSide, arrayIndex: casterIndex)
        let targetIdx = context.actorIndex(for: casterSide, arrayIndex: targetIndex)
        let entryBuilder = context.makeActionEntryBuilder(actorId: casterIdx,
                                                          kind: .priestMagic,
                                                          skillIndex: UInt16(spell.id))
        entryBuilder.addEffect(kind: .magicHeal, target: targetIdx, value: UInt32(applied))
        context.appendActionEntry(entryBuilder.build())
    }

    @discardableResult
    nonisolated static func executeMageMagic(for side: ActorSide,
                                 attackerIndex: Int,
                                 context: inout BattleContext,
                                 forcedTargets: BattleContext.SacrificeTargets) -> Bool {
        guard var attacker = context.actor(for: side, index: attackerIndex), attacker.isAlive else { return false }

        let allies: [BattleActor] = side == .player ? context.players : context.enemies
        let opponents: [BattleActor] = side == .player ? context.enemies : context.players

        // 発動条件を満たす呪文をtier重みで抽選
        let available = attacker.spells.mage.filter { attacker.actionResources.hasAvailableCharges(for: $0.id) }
        guard let spell = selectSpellByTierWeight(in: available, matching: { canCastSpell($0, caster: attacker, allies: allies, opponents: opponents) }, random: &context.random) else {
            return false
        }

        guard attacker.actionResources.consume(spellId: spell.id) else { return false }
        context.updateActor(attacker, side: side, index: attackerIndex)

        // 魔法名付きログを追加
        let attackerIdx = context.actorIndex(for: side, arrayIndex: attackerIndex)
        let entryBuilder = context.makeActionEntryBuilder(actorId: attackerIdx,
                                                          kind: .mageMagic,
                                                          skillIndex: UInt16(spell.id))

        // buffの場合は専用処理
        if spell.category == .buff {
            performBuffSpell(casterSide: side,
                             casterIndex: attackerIndex,
                             spell: spell,
                             context: &context)
            return true
        }

        // damage/statusの処理
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

            let targetIdx = context.actorIndex(for: targetRef.0, arrayIndex: targetRef.1)
            if spell.category == .damage {
                let damage = computeMagicalDamage(attacker: refreshedAttacker,
                                                  defender: &target,
                                                  spellId: spell.id,
                                                  context: &context)
                let applied = applyDamage(amount: damage, to: &target)
                applyMagicDegradation(to: &target, spellId: spell.id, caster: refreshedAttacker)

                context.updateActor(target, side: targetRef.0, index: targetRef.1)
                entryBuilder.addEffect(kind: .magicDamage,
                                       target: targetIdx,
                                       value: UInt32(applied),
                                       extra: UInt16(clamping: damage))

                if !target.isAlive {
                    appendDefeatLog(for: target,
                                    side: targetRef.0,
                                    index: targetRef.1,
                                    context: &context,
                                    entryBuilder: entryBuilder)
                    handleDefeatReactions(targetSide: targetRef.0,
                                          targetIndex: targetRef.1,
                                          killerSide: side,
                                          killerIndex: attackerIndex,
                                          context: &context)
                } else {
                    // 被ダメ時リアクション（魔法反撃）
                    let attackerRef = BattleContext.reference(for: side, index: attackerIndex)
                    context.reactionQueue.append(.init(
                        event: .selfDamagedMagical(side: targetRef.0,
                                                   actorIndex: targetRef.1,
                                                   attacker: attackerRef),
                        depth: 0
                    ))
                }
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
                    entryBuilder.addEffect(kind: .statusInflict, target: targetIdx, statusId: UInt16(statusId))
                } else {
                    entryBuilder.addEffect(kind: .statusResist, target: targetIdx, statusId: UInt16(statusId))
                }
            }
        }

        // 味方が魔法攻撃したイベントを発火（追撃用）
        context.reactionQueue.append(.init(
            event: .allyMagicAttack(side: side, casterIndex: attackerIndex),
            depth: 0
        ))

        context.appendActionEntry(entryBuilder.build())

        processReactionQueue(context: &context)

        return true
    }

    @discardableResult
    nonisolated static func executeBreath(for side: ActorSide,
                              attackerIndex: Int,
                              context: inout BattleContext,
                              forcedTargets: BattleContext.SacrificeTargets) -> Bool {
        guard var attacker = context.actor(for: side, index: attackerIndex), attacker.isAlive else { return false }
        guard attacker.actionResources.consume(.breath) else { return false }

        context.updateActor(attacker, side: side, index: attackerIndex)

        let attackerIdx = context.actorIndex(for: side, arrayIndex: attackerIndex)
        let entryBuilder = context.makeActionEntryBuilder(actorId: attackerIdx,
                                                          kind: .breath)

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

            let targetIdx = context.actorIndex(for: targetRef.0, arrayIndex: targetRef.1)
            entryBuilder.addEffect(kind: .breathDamage,
                                   target: targetIdx,
                                   value: UInt32(applied),
                                   extra: UInt16(clamping: damage))

            if !target.isAlive {
                appendDefeatLog(for: target,
                                side: targetRef.0,
                                index: targetRef.1,
                                context: &context,
                                entryBuilder: entryBuilder)
                handleDefeatReactions(targetSide: targetRef.0,
                                      targetIndex: targetRef.1,
                                      killerSide: side,
                                      killerIndex: attackerIndex,
                                      context: &context)
            }
        }

        context.appendActionEntry(entryBuilder.build())

        processReactionQueue(context: &context)

        return true
    }

    nonisolated static func selectMageSpell(for actor: BattleActor) -> SpellDefinition? {
        let available = actor.spells.mage.filter { actor.actionResources.hasAvailableCharges(for: $0.id) }
        guard !available.isEmpty else { return nil }
        return highestTierSpell(in: available)
    }

    nonisolated static func selectPriestSpell(for actor: BattleActor) -> SpellDefinition? {
        let available = actor.spells.priest.filter { actor.actionResources.hasAvailableCharges(for: $0.id) }
        guard !available.isEmpty else { return nil }
        return highestTierSpell(in: available)
    }

    /// 回復呪文のみを選択（救出処理用）
    nonisolated static func selectPriestHealingSpell(for actor: BattleActor) -> SpellDefinition? {
        let available = actor.spells.priest.filter { actor.actionResources.hasAvailableCharges(for: $0.id) }
        guard !available.isEmpty else { return nil }
        return highestTierSpell(in: available) { $0.category == .healing }
    }

    nonisolated static func highestTierSpell(in spells: [SpellDefinition],
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

    /// tierを重みとした抽選で呪文を選択（高tierほど選ばれやすい）
    nonisolated static func selectSpellByTierWeight(in spells: [SpellDefinition],
                                        matching predicate: ((SpellDefinition) -> Bool)? = nil,
                                        random: inout GameRandomSource) -> SpellDefinition? {
        let filtered: [SpellDefinition]
        if let predicate {
            filtered = spells.filter(predicate)
        } else {
            filtered = spells
        }
        guard !filtered.isEmpty else { return nil }
        if filtered.count == 1 { return filtered[0] }

        // tierを重みとして抽選
        let totalWeight = filtered.reduce(0) { $0 + $1.tier }
        guard totalWeight > 0 else { return filtered[0] }

        let roll = random.nextInt(in: 1...totalWeight)
        var cumulative = 0
        for spell in filtered {
            cumulative += spell.tier
            if roll <= cumulative {
                return spell
            }
        }
        return filtered.last
    }

    nonisolated static func statusTargetCount(for caster: BattleActor, spell: SpellDefinition) -> Int {
        let base = spell.maxTargetsBase ?? 1
        guard base > 0 else { return 1 }
        let extraPerLevel = spell.extraTargetsPerLevels ?? 0.0
        let level = Double(caster.level ?? 0)
        let total = Double(base) + level * extraPerLevel
        return max(1, Int(total.rounded(.down)))
    }

    nonisolated static func baseStatusChancePercent(spell: SpellDefinition, caster: BattleActor, target: BattleActor) -> Double {
        let magicAttack = max(0, caster.snapshot.magicalAttackScore)
        let magicDefense = max(1, target.snapshot.magicalDefenseScore)
        let ratio = Double(magicAttack) / Double(magicDefense)
        let base = min(95.0, 50.0 * ratio)
        let luckPenalty = max(0, target.luck - 10)
        let luckScalePercent = max(0.0, 100.0 - Double(luckPenalty * 2))
        return max(0.0, base * (luckScalePercent / 100.0))
    }

    nonisolated static func spellPowerModifier(for attacker: BattleActor, spellId: UInt8? = nil) -> Double {
        let percentScale = max(0.0, 1.0 + attacker.skillEffects.spell.power.percent / 100.0)
        var modifier = percentScale * attacker.skillEffects.spell.power.multiplier
        if let spellId,
           let specific = attacker.skillEffects.spell.specificMultipliers[spellId] {
            modifier *= specific
        }
        return modifier
    }

    // MARK: - Buff Spell

    /// バフ呪文を味方全体に適用
    nonisolated static func performBuffSpell(casterSide: ActorSide,
                                 casterIndex: Int,
                                 spell: SpellDefinition,
                                 context: inout BattleContext) {
        let allies: [BattleActor] = casterSide == .player ? context.players : context.enemies
        let casterIdx = context.actorIndex(for: casterSide, arrayIndex: casterIndex)
        let entryBuilder = context.makeActionEntryBuilder(actorId: casterIdx,
                                                          kind: spell.school == .mage ? .mageMagic : .priestMagic,
                                                          skillIndex: UInt16(spell.id))

        // spell.buffsからstatModifiersを構築
        var statModifiers: [String: Double] = [:]
        for buff in spell.buffs {
            let key = buff.type.identifier + "Multiplier"
            statModifiers[key] = buff.multiplier
        }

        // 戦闘中永続（戦闘は最大20ターンなので99で十分）
        let permanentDuration = BattleContext.maxTurns * 5
        let timedBuff = TimedBuff(
            id: "spell.\(spell.id)",
            baseDuration: permanentDuration,
            remainingTurns: permanentDuration,
            statModifiers: statModifiers
        )

        for index in allies.indices where allies[index].isAlive {
            var target = allies[index]
            upsert(buff: timedBuff, into: &target.timedBuffs)
            context.updateActor(target, side: casterSide, index: index)
            let targetIdx = context.actorIndex(for: casterSide, arrayIndex: index)
            entryBuilder.addEffect(kind: .buffApply, target: targetIdx)
        }

        context.appendActionEntry(entryBuilder.build())
    }

    // MARK: - Cleanse Spell

    /// 状態異常を持つ味方1人の状態異常を1つ除去
    /// - Returns: 対象がいなければfalse
    nonisolated static func performCleanseSpell(casterSide: ActorSide,
                                    casterIndex: Int,
                                    spell: SpellDefinition,
                                    context: inout BattleContext) -> Bool {
        let allies: [BattleActor] = casterSide == .player ? context.players : context.enemies

        // 状態異常を持つ味方のインデックスを収集
        var afflictedIndices: [Int] = []
        for index in allies.indices where allies[index].isAlive && !allies[index].statusEffects.isEmpty {
            afflictedIndices.append(index)
        }

        guard !afflictedIndices.isEmpty else { return false }

        // ランダムに1人選択
        let targetIndex = afflictedIndices[context.random.nextInt(in: 0...(afflictedIndices.count - 1))]
        var target = allies[targetIndex]

        // ランダムに1つの状態異常を除去
        let statusIndex = context.random.nextInt(in: 0...(target.statusEffects.count - 1))
        let removedStatus = target.statusEffects.remove(at: statusIndex)
        context.updateActor(target, side: casterSide, index: targetIndex)

        let casterIdx = context.actorIndex(for: casterSide, arrayIndex: casterIndex)
        let targetIdx = context.actorIndex(for: casterSide, arrayIndex: targetIndex)
        let entryBuilder = context.makeActionEntryBuilder(actorId: casterIdx,
                                                          kind: spell.school == .mage ? .mageMagic : .priestMagic,
                                                          skillIndex: UInt16(spell.id))
        entryBuilder.addEffect(kind: .statusRecover,
                               target: targetIdx,
                               statusId: UInt16(removedStatus.id))
        context.appendActionEntry(entryBuilder.build())
        return true
    }

    // MARK: - Spell Condition Checks

    /// 呪文の発動条件をチェック
    nonisolated static func canCastSpell(_ spell: SpellDefinition,
                             caster: BattleActor,
                             allies: [BattleActor],
                             opponents: [BattleActor]) -> Bool {
        switch spell.category {
        case .healing:
            // castConditionがtargetHalfHPの場合、HP半分以下の味方がいるかチェック
            if let conditionRaw = spell.castCondition,
               let condition = SpellDefinition.CastCondition(rawValue: conditionRaw),
               condition == .targetHalfHP {
                return selectHealingTargetIndex(in: allies, requireHalfHP: true) != nil
            }
            return selectHealingTargetIndex(in: allies) != nil
        case .cleanse:
            return allies.contains { $0.isAlive && !$0.statusEffects.isEmpty }
        case .buff:
            return shouldCastBuffSpell(spell: spell, allies: allies)
        case .damage, .status:
            return opponents.contains { $0.isAlive }
        }
    }

    private nonisolated static func shouldCastBuffSpell(spell: SpellDefinition,
                                            allies: [BattleActor]) -> Bool {
        guard spell.targeting == .partyAllies, !spell.buffs.isEmpty else { return true }
        let buffId = "spell.\(spell.id)"
        for ally in allies where ally.isAlive {
            if ally.timedBuffs.contains(where: { $0.id == buffId && $0.remainingTurns > 0 }) {
                return false
            }
        }
        return true
    }
}
