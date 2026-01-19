// ==============================================================================
// BattleTurnEngine.EnemySpecialSkill.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 敵専用スキルの実行処理
//   - スキルタイプ別の処理分岐（物理、魔法、ブレス、状態異常、回復、バフ）
//   - 敵スキルのターゲット選択
//   - スキル使用回数管理
//
// 【本体との関係】
//   - BattleTurnEngineの拡張ファイル
//   - 敵の特殊行動に特化した機能を提供
//
// 【主要機能】
//   - executeEnemySpecialSkill: 敵専用技の実行
//   - スキルタイプ別実行関数（Physical、Magical、Breath、Status、Heal、Buff）
//   - スキルダメージ計算
//
// 【使用箇所】
//   - BattleTurnEngine.TurnLoop（行動選択時）
//
// ==============================================================================

import Foundation

// MARK: - Enemy Special Skills
extension BattleTurnEngine {
    @discardableResult
    nonisolated static func executeEnemySpecialSkill(for side: ActorSide,
                                         actorIndex: Int,
                                         context: inout BattleContext,
                                         forcedTargets: BattleContext.SacrificeTargets) -> Bool {
        guard side == .enemy else { return false }
        guard let actor = context.actor(for: side, index: actorIndex), actor.isAlive else { return false }

        let allies = context.enemies
        let opponents = context.players

        // スキルを再選択（selectActionと同じロジック）
        guard let skillId = selectEnemySpecialSkill(for: actor,
                                                    allies: allies,
                                                    opponents: opponents,
                                                    context: &context),
              let skill = context.enemySkillDefinition(for: skillId) else {
            return false
        }

        // 使用回数を記録
        context.incrementEnemySkillUsage(actorIdentifier: actor.identifier, skillId: skillId)

        // スキル発動ログ
        let actorIdx = context.actorIndex(for: side, arrayIndex: actorIndex)
        let entryBuilder = context.makeActionEntryBuilder(actorId: actorIdx,
                                                          kind: .enemySpecialSkill,
                                                          skillIndex: skillId)
        var defeatedTargets: [(ActorSide, Int)] = []
        var pendingSkillEffectLogs: [(kind: SkillEffectLogKind, actorId: UInt16, targetId: UInt16?)] = []
        var pendingBarrierLogs: [(actorId: UInt16, kind: SkillEffectLogKind)] = []

        // スキルタイプに応じて実行
        switch skill.type {
        case .physical:
            executeEnemyPhysicalSkill(skill: skill,
                                      attackerSide: side,
                                      attackerIndex: actorIndex,
                                      context: &context,
                                      entryBuilder: entryBuilder,
                                      defeatedTargets: &defeatedTargets,
                                      pendingBarrierLogs: &pendingBarrierLogs)
        case .magical:
            executeEnemyMagicalSkill(skill: skill,
                                     attackerSide: side,
                                     attackerIndex: actorIndex,
                                     context: &context,
                                     entryBuilder: entryBuilder,
                                     defeatedTargets: &defeatedTargets,
                                     pendingSkillEffectLogs: &pendingSkillEffectLogs,
                                     pendingBarrierLogs: &pendingBarrierLogs)
        case .breath:
            executeEnemyBreathSkill(skill: skill,
                                    attackerSide: side,
                                    attackerIndex: actorIndex,
                                    context: &context,
                                    entryBuilder: entryBuilder,
                                    defeatedTargets: &defeatedTargets,
                                    pendingBarrierLogs: &pendingBarrierLogs)
        case .status:
            executeEnemyStatusSkill(skill: skill,
                                    attackerSide: side,
                                    attackerIndex: actorIndex,
                                    context: &context,
                                    entryBuilder: entryBuilder)
        case .heal:
            executeEnemyHealSkill(skill: skill,
                                  casterSide: side,
                                  casterIndex: actorIndex,
                                  context: &context,
                                  entryBuilder: entryBuilder)
        case .buff:
            executeEnemyBuffSkill(skill: skill,
                                  casterSide: side,
                                  casterIndex: actorIndex,
                                  context: &context,
                                  entryBuilder: entryBuilder)
        }

        context.appendActionEntry(entryBuilder.build())
        if !pendingSkillEffectLogs.isEmpty {
            appendSkillEffectLogs(pendingSkillEffectLogs, context: &context, turnOverride: context.turn)
        }
        if !pendingBarrierLogs.isEmpty {
            let events = pendingBarrierLogs.map { (kind: $0.kind, actorId: $0.actorId, targetId: UInt16?.none) }
            appendSkillEffectLogs(events, context: &context, turnOverride: context.turn)
        }

        for targetRef in defeatedTargets {
            handleDefeatReactions(targetSide: targetRef.0,
                                  targetIndex: targetRef.1,
                                  killerSide: side,
                                  killerIndex: actorIndex,
                                  context: &context,
                                  reactionDepth: 0,
                                  allowsReactionEvents: true)
        }

        return true
    }

    // MARK: - Physical Skill

    private nonisolated static func executeEnemyPhysicalSkill(skill: EnemySkillDefinition,
                                                  attackerSide: ActorSide,
                                                  attackerIndex: Int,
                                                  context: inout BattleContext,
                                                  entryBuilder: BattleActionEntry.Builder,
                                                  defeatedTargets: inout [(ActorSide, Int)],
                                                  pendingBarrierLogs: inout [(actorId: UInt16, kind: SkillEffectLogKind)]) {
        guard var attacker = context.actor(for: attackerSide, index: attackerIndex), attacker.isAlive else { return }

        let targets = selectEnemySkillTargets(skill: skill,
                                              attackerSide: attackerSide,
                                              attackerIndex: attackerIndex,
                                              context: &context)

        let hitCount = skill.hitCount ?? 1
        let damageMultiplier = skill.damageDealtMultiplier ?? 1.0

        // damageDealtMultiplierを攻撃者のskillEffects.damage.dealtに適用
        attacker.skillEffects.damage.dealt.physical *= damageMultiplier

        for (targetSide, targetIndex) in targets {
            guard attacker.isAlive else { break }
            guard var target = context.actor(for: targetSide, index: targetIndex),
                  target.isAlive else { continue }

            var totalDamage = 0
            var totalRawDamage = 0

            for hitIndex in 1...hitCount {
                guard target.isAlive else { break }

                // 命中判定（通常物理攻撃と同じパイプライン）
                let hitChance = computeHitChance(attacker: attacker,
                                                 defender: target,
                                                 hitIndex: hitIndex,
                                                 accuracyMultiplier: 1.0,
                                                 context: &context)
                let roll = context.random.nextDouble()
                guard roll <= hitChance else {
                    let targetIdx = context.actorIndex(for: targetSide, arrayIndex: targetIndex)
                    entryBuilder.addEffect(kind: .physicalEvade, target: targetIdx)
                    continue
                }

                // ダメージ計算（通常物理攻撃と同じパイプライン）
                let barrierKey = barrierKey(for: .physical)
                let guardActive = target.guardActive
                let guardBefore = target.guardBarrierCharges[barrierKey] ?? 0
                let barrierBefore = target.barrierCharges[barrierKey] ?? 0

                let (rawDamage, _) = computePhysicalDamage(attacker: attacker,
                                                           defender: &target,
                                                           hitIndex: hitIndex,
                                                           context: &context)
                let guardAfter = target.guardBarrierCharges[barrierKey] ?? 0
                let barrierAfter = target.barrierCharges[barrierKey] ?? 0
                let targetIdx = context.actorIndex(for: targetSide, arrayIndex: targetIndex)
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
                context.updateActor(target, side: targetSide, index: targetIndex)

                // ターゲットを更新
                if let updated = context.actor(for: targetSide, index: targetIndex) {
                    target = updated
                }
            }

            if totalDamage > 0 {
                let targetIdx = context.actorIndex(for: targetSide, arrayIndex: targetIndex)
                entryBuilder.addEffect(kind: .enemySpecialDamage,
                                       target: targetIdx,
                                       value: UInt32(totalDamage),
                                       extra: UInt16(clamping: totalRawDamage))
            }

            if handleEnemySkillDefeat(targetSide: targetSide,
                                      targetIndex: targetIndex,
                                      context: &context,
                                      entryBuilder: entryBuilder) {
                defeatedTargets.append((targetSide, targetIndex))
            }

            // 状態異常付与
            if let statusId = skill.statusId, let statusChance = skill.statusChance {
                attemptEnemySkillStatusInflict(statusId: statusId,
                                               chancePercent: statusChance,
                                               targetSide: targetSide,
                                               targetIndex: targetIndex,
                                               context: &context,
                                               entryBuilder: entryBuilder)
            }
        }
    }

    // MARK: - Magical Skill

    private nonisolated static func executeEnemyMagicalSkill(skill: EnemySkillDefinition,
                                                 attackerSide: ActorSide,
                                                 attackerIndex: Int,
                                                 context: inout BattleContext,
                                                 entryBuilder: BattleActionEntry.Builder,
                                                 defeatedTargets: inout [(ActorSide, Int)],
                                                 pendingSkillEffectLogs: inout [(kind: SkillEffectLogKind, actorId: UInt16, targetId: UInt16?)],
                                                 pendingBarrierLogs: inout [(actorId: UInt16, kind: SkillEffectLogKind)]) {
        guard var attacker = context.actor(for: attackerSide, index: attackerIndex), attacker.isAlive else { return }

        let targets = selectEnemySkillTargets(skill: skill,
                                              attackerSide: attackerSide,
                                              attackerIndex: attackerIndex,
                                              context: &context)

        let hitCount = skill.hitCount ?? 1
        let damageMultiplier = skill.damageDealtMultiplier ?? 1.0

        // damageDealtMultiplierを攻撃者のskillEffects.damage.dealtに適用
        attacker.skillEffects.damage.dealt.magical *= damageMultiplier

        for (targetSide, targetIndex) in targets {
            guard attacker.isAlive else { break }
            guard var target = context.actor(for: targetSide, index: targetIndex),
                  target.isAlive else { continue }

            var totalDamage = 0
            var totalRawDamage = 0
            let attackerIdx = context.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
            let targetIdx = context.actorIndex(for: targetSide, arrayIndex: targetIndex)
            for _ in 0..<hitCount {
                guard target.isAlive else { break }

                // ダメージ計算（通常魔法攻撃と同じパイプライン）
                let result = computeMagicalDamage(attacker: attacker,
                                                  defender: &target,
                                                  spellId: nil,
                                                  context: &context)
                if result.wasNullified {
                    pendingSkillEffectLogs.append((kind: .magicNullify,
                                                   actorId: targetIdx,
                                                   targetId: attackerIdx))
                }
                if result.wasCritical {
                    entryBuilder.addEffect(kind: .skillEffect,
                                           target: targetIdx,
                                           extra: SkillEffectLogKind.magicCritical.rawValue)
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
                context.updateActor(target, side: targetSide, index: targetIndex)

                if let updated = context.actor(for: targetSide, index: targetIndex) {
                    target = updated
                }
            }

            if totalDamage > 0 {
                entryBuilder.addEffect(kind: .enemySpecialDamage,
                                       target: targetIdx,
                                       value: UInt32(totalDamage),
                                       extra: UInt16(clamping: totalRawDamage))
            }

            if handleEnemySkillDefeat(targetSide: targetSide,
                                      targetIndex: targetIndex,
                                      context: &context,
                                      entryBuilder: entryBuilder) {
                defeatedTargets.append((targetSide, targetIndex))
            }
        }
    }

    // MARK: - Breath Skill

    private nonisolated static func executeEnemyBreathSkill(skill: EnemySkillDefinition,
                                               attackerSide: ActorSide,
                                               attackerIndex: Int,
                                               context: inout BattleContext,
                                               entryBuilder: BattleActionEntry.Builder,
                                               defeatedTargets: inout [(ActorSide, Int)],
                                               pendingBarrierLogs: inout [(actorId: UInt16, kind: SkillEffectLogKind)]) {
        guard var attacker = context.actor(for: attackerSide, index: attackerIndex), attacker.isAlive else { return }

        let targets = selectEnemySkillTargets(skill: skill,
                                              attackerSide: attackerSide,
                                              attackerIndex: attackerIndex,
                                              context: &context)

        let damageMultiplier = skill.damageDealtMultiplier ?? 1.0

        // damageDealtMultiplierを攻撃者のskillEffects.damage.dealtに適用
        attacker.skillEffects.damage.dealt.breath *= damageMultiplier

        for (targetSide, targetIndex) in targets {
            guard attacker.isAlive else { break }
            guard var target = context.actor(for: targetSide, index: targetIndex),
                  target.isAlive else { continue }

            // ダメージ計算（通常ブレス攻撃と同じパイプライン）
            let result = computeBreathDamage(attacker: attacker,
                                             defender: &target,
                                             context: &context)
            let targetIdx = context.actorIndex(for: targetSide, arrayIndex: targetIndex)
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
            context.updateActor(target, side: targetSide, index: targetIndex)

            entryBuilder.addEffect(kind: .enemySpecialDamage,
                                   target: targetIdx,
                                   value: UInt32(applied),
                                   extra: UInt16(clamping: result.damage))

            if handleEnemySkillDefeat(targetSide: targetSide,
                                      targetIndex: targetIndex,
                                      context: &context,
                                      entryBuilder: entryBuilder) {
                defeatedTargets.append((targetSide, targetIndex))
            }
        }
    }

    // MARK: - Status Skill

    private nonisolated static func executeEnemyStatusSkill(skill: EnemySkillDefinition,
                                                attackerSide: ActorSide,
                                                attackerIndex: Int,
                                                context: inout BattleContext,
                                                entryBuilder: BattleActionEntry.Builder) {
        guard let _ = context.actor(for: attackerSide, index: attackerIndex) else { return }
        guard let statusId = skill.statusId else { return }

        let targets = selectEnemySkillTargets(skill: skill,
                                              attackerSide: attackerSide,
                                              attackerIndex: attackerIndex,
                                              context: &context)

        let chancePercent = skill.statusChance ?? skill.chancePercent

        for (targetSide, targetIndex) in targets {
            attemptEnemySkillStatusInflict(statusId: statusId,
                                           chancePercent: chancePercent,
                                           targetSide: targetSide,
                                           targetIndex: targetIndex,
                                           context: &context,
                                           entryBuilder: entryBuilder)
        }
    }

    // MARK: - Heal Skill

    private nonisolated static func executeEnemyHealSkill(skill: EnemySkillDefinition,
                                              casterSide: ActorSide,
                                              casterIndex: Int,
                                              context: inout BattleContext,
                                              entryBuilder: BattleActionEntry.Builder) {
        guard let caster = context.actor(for: casterSide, index: casterIndex), caster.isAlive else { return }
        guard let healPercent = skill.healPercent else { return }

        let targets: [(ActorSide, Int)]
        switch skill.targeting {
        case .`self`:
            targets = [(casterSide, casterIndex)]
        case .allAllies:
            targets = context.enemies.enumerated()
                .filter { $0.element.isAlive }
                .map { (ActorSide.enemy, $0.offset) }
        default:
            targets = [(casterSide, casterIndex)]
        }

        for (targetSide, targetIndex) in targets {
            guard var target = context.actor(for: targetSide, index: targetIndex),
                  target.isAlive else { continue }

            let healAmount = (target.snapshot.maxHP * healPercent) / 100
            let missing = target.snapshot.maxHP - target.currentHP
            let applied = min(healAmount, missing)
            target.currentHP += applied
            context.updateActor(target, side: targetSide, index: targetIndex)

            let targetIdx = context.actorIndex(for: targetSide, arrayIndex: targetIndex)
            entryBuilder.addEffect(kind: .enemySpecialHeal, target: targetIdx, value: UInt32(applied))
        }
    }

    // MARK: - Buff Skill

    private nonisolated static func executeEnemyBuffSkill(skill: EnemySkillDefinition,
                                              casterSide: ActorSide,
                                              casterIndex: Int,
                                              context: inout BattleContext,
                                              entryBuilder: BattleActionEntry.Builder) {
        guard let _ = context.actor(for: casterSide, index: casterIndex) else { return }
        guard let buffType = skill.buffType else { return }

        let targets: [(ActorSide, Int)]
        switch skill.targeting {
        case .`self`:
            targets = [(casterSide, casterIndex)]
        case .allAllies:
            targets = context.enemies.enumerated()
                .filter { $0.element.isAlive }
                .map { (ActorSide.enemy, $0.offset) }
        default:
            targets = [(casterSide, casterIndex)]
        }

        let multiplier = skill.buffMultiplier ?? 1.5

        for (targetSide, targetIndex) in targets {
            guard var target = context.actor(for: targetSide, index: targetIndex),
                  target.isAlive else { continue }

            applyEnemyBuff(buffType: buffType, multiplier: multiplier, to: &target)
            context.updateActor(target, side: targetSide, index: targetIndex)

            let targetIdx = context.actorIndex(for: targetSide, arrayIndex: targetIndex)
            entryBuilder.addEffect(kind: .enemySpecialBuff,
                                   target: targetIdx,
                                   extra: UInt16(buffType))
        }
    }

    // MARK: - Helper Functions

    private nonisolated static func selectEnemySkillTargets(skill: EnemySkillDefinition,
                                                attackerSide: ActorSide,
                                                attackerIndex: Int,
                                                context: inout BattleContext) -> [(ActorSide, Int)] {
        let opponentSide: ActorSide = attackerSide == .player ? .enemy : .player
        let opponents = attackerSide == .player ? context.enemies : context.players

        switch skill.targeting {
        case .single:
            let attacker = context.actor(for: attackerSide, index: attackerIndex)
            let forcedTargets = BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)
            if let (targetSide, targetIndex) = selectOffensiveTarget(attackerSide: attackerSide,
                                                                      context: &context,
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
                let randomIndex = context.random.nextInt(in: 0...(alive.count - 1))
                let target = alive[randomIndex]
                targets.append((opponentSide, target.offset))
            }
            return targets
        case .all:
            return opponents.enumerated()
                .filter { $0.element.isAlive }
                .map { (opponentSide, $0.offset) }
        case .`self`:
            return [(attackerSide, attackerIndex)]
        case .allAllies:
            let allies = attackerSide == .player ? context.players : context.enemies
            return allies.enumerated()
                .filter { $0.element.isAlive }
                .map { (attackerSide, $0.offset) }
        }
    }

    @discardableResult
    private nonisolated static func handleEnemySkillDefeat(targetSide: ActorSide,
                                               targetIndex: Int,
                                               context: inout BattleContext,
                                               entryBuilder: BattleActionEntry.Builder) -> Bool {
        guard let target = context.actor(for: targetSide, index: targetIndex),
              !target.isAlive else { return false }

        appendDefeatLog(for: target,
                        side: targetSide,
                        index: targetIndex,
                        context: &context,
                        entryBuilder: entryBuilder)
        return true
    }

    private nonisolated static func attemptEnemySkillStatusInflict(statusId: UInt8,
                                                       chancePercent: Int,
                                                       targetSide: ActorSide,
                                                       targetIndex: Int,
                                                       context: inout BattleContext,
                                                       entryBuilder: BattleActionEntry.Builder) {
        guard var target = context.actor(for: targetSide, index: targetIndex),
              target.isAlive else { return }
        guard let statusDef = context.statusDefinitions[statusId] else { return }

        let targetIdx = context.actorIndex(for: targetSide, arrayIndex: targetIndex)

        let applied = attemptApplyStatus(statusId: statusId,
                                         baseChancePercent: Double(chancePercent),
                                         durationTurns: statusDef.durationTurns,
                                         sourceId: nil,
                                         to: &target,
                                         context: &context)
        context.updateActor(target, side: targetSide, index: targetIndex)

        if applied {
            entryBuilder.addEffect(kind: .statusInflict, target: targetIdx, statusId: UInt16(statusId))
            // autoStatusCureOnAlly判定
            applyAutoStatusCureIfNeeded(for: targetSide, targetIndex: targetIndex, context: &context)
        } else {
            entryBuilder.addEffect(kind: .statusResist, target: targetIdx, statusId: UInt16(statusId))
        }
    }

    private nonisolated static func applyEnemyBuff(buffType: UInt8, multiplier: Double, to actor: inout BattleActor) {
        guard let type = SpellBuffType(rawValue: buffType) else { return }
        switch type {
        case .physicalDamageDealt, .combat, .damage:
            // 与ダメージ倍率は戦闘効果として後で適用されるため、ここでは物理攻撃力を上げる
            actor.snapshot.physicalAttackScore = Int(Double(actor.snapshot.physicalAttackScore) * multiplier)
        case .physicalDamageTaken:
            // 被物理ダメージ減少 = 防御力上昇
            actor.snapshot.physicalDefenseScore = Int(Double(actor.snapshot.physicalDefenseScore) * multiplier)
        case .magicalDamageTaken:
            // 被魔法ダメージ減少 = 魔法防御力上昇
            actor.snapshot.magicalDefenseScore = Int(Double(actor.snapshot.magicalDefenseScore) * multiplier)
        case .breathDamageTaken:
            // ブレス耐性は直接ステータスにないのでスキップ
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
