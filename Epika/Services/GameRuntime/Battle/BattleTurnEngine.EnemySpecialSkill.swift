import Foundation

// MARK: - Enemy Special Skills
extension BattleTurnEngine {
    @discardableResult
    static func executeEnemySpecialSkill(for side: ActorSide,
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
        context.appendAction(kind: .enemySpecialSkill, actor: actorIdx, skillIndex: skillId)

        // スキルタイプに応じて実行
        switch skill.type {
        case .physical:
            executeEnemyPhysicalSkill(skill: skill,
                                      attackerSide: side,
                                      attackerIndex: actorIndex,
                                      context: &context)
        case .magical:
            executeEnemyMagicalSkill(skill: skill,
                                     attackerSide: side,
                                     attackerIndex: actorIndex,
                                     context: &context)
        case .breath:
            executeEnemyBreathSkill(skill: skill,
                                    attackerSide: side,
                                    attackerIndex: actorIndex,
                                    context: &context)
        case .status:
            executeEnemyStatusSkill(skill: skill,
                                    attackerSide: side,
                                    attackerIndex: actorIndex,
                                    context: &context)
        case .heal:
            executeEnemyHealSkill(skill: skill,
                                  casterSide: side,
                                  casterIndex: actorIndex,
                                  context: &context)
        case .buff:
            executeEnemyBuffSkill(skill: skill,
                                  casterSide: side,
                                  casterIndex: actorIndex,
                                  context: &context)
        }

        return true
    }

    // MARK: - Physical Skill

    private static func executeEnemyPhysicalSkill(skill: EnemySkillDefinition,
                                                  attackerSide: ActorSide,
                                                  attackerIndex: Int,
                                                  context: inout BattleContext) {
        guard let attacker = context.actor(for: attackerSide, index: attackerIndex), attacker.isAlive else { return }

        let targets = selectEnemySkillTargets(skill: skill,
                                              attackerSide: attackerSide,
                                              attackerIndex: attackerIndex,
                                              context: &context)

        let hitCount = skill.hitCount ?? 1
        let multiplier = skill.multiplier ?? 1.0

        for (targetSide, targetIndex) in targets {
            guard let refreshedAttacker = context.actor(for: attackerSide, index: attackerIndex),
                  refreshedAttacker.isAlive else { break }
            guard var target = context.actor(for: targetSide, index: targetIndex),
                  target.isAlive else { continue }

            var totalDamage = 0
            for _ in 0..<hitCount {
                guard target.isAlive else { break }

                let baseDamage = computeEnemySkillPhysicalDamage(attacker: refreshedAttacker,
                                                                 defender: target,
                                                                 multiplier: multiplier,
                                                                 ignoreDefense: skill.ignoreDefense,
                                                                 context: &context)
                let applied = applyDamage(amount: baseDamage, to: &target)
                totalDamage += applied
                context.updateActor(target, side: targetSide, index: targetIndex)

                // ターゲットを更新
                if let updated = context.actor(for: targetSide, index: targetIndex) {
                    target = updated
                }
            }

            let attackerIdx = context.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
            let targetIdx = context.actorIndex(for: targetSide, arrayIndex: targetIndex)
            context.appendAction(kind: .enemySpecialDamage, actor: attackerIdx, target: targetIdx, value: UInt32(totalDamage))

            handleEnemySkillDefeat(targetSide: targetSide,
                                   targetIndex: targetIndex,
                                   attackerSide: attackerSide,
                                   attackerIndex: attackerIndex,
                                   context: &context)

            // 状態異常付与
            if let statusId = skill.statusId, let statusChance = skill.statusChance {
                attemptEnemySkillStatusInflict(statusId: statusId,
                                               chancePercent: statusChance,
                                               targetSide: targetSide,
                                               targetIndex: targetIndex,
                                               context: &context)
            }
        }
    }

    // MARK: - Magical Skill

    private static func executeEnemyMagicalSkill(skill: EnemySkillDefinition,
                                                 attackerSide: ActorSide,
                                                 attackerIndex: Int,
                                                 context: inout BattleContext) {
        guard let attacker = context.actor(for: attackerSide, index: attackerIndex), attacker.isAlive else { return }

        let targets = selectEnemySkillTargets(skill: skill,
                                              attackerSide: attackerSide,
                                              attackerIndex: attackerIndex,
                                              context: &context)

        let hitCount = skill.hitCount ?? 1
        let multiplier = skill.multiplier ?? 1.0

        for (targetSide, targetIndex) in targets {
            guard let refreshedAttacker = context.actor(for: attackerSide, index: attackerIndex),
                  refreshedAttacker.isAlive else { break }
            guard var target = context.actor(for: targetSide, index: targetIndex),
                  target.isAlive else { continue }

            var totalDamage = 0
            for _ in 0..<hitCount {
                guard target.isAlive else { break }

                let baseDamage = computeEnemySkillMagicalDamage(attacker: refreshedAttacker,
                                                                defender: target,
                                                                multiplier: multiplier,
                                                                element: skill.element,
                                                                context: &context)
                let applied = applyDamage(amount: baseDamage, to: &target)
                totalDamage += applied
                context.updateActor(target, side: targetSide, index: targetIndex)

                if let updated = context.actor(for: targetSide, index: targetIndex) {
                    target = updated
                }
            }

            let attackerIdx = context.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
            let targetIdx = context.actorIndex(for: targetSide, arrayIndex: targetIndex)
            context.appendAction(kind: .enemySpecialDamage, actor: attackerIdx, target: targetIdx, value: UInt32(totalDamage))

            handleEnemySkillDefeat(targetSide: targetSide,
                                   targetIndex: targetIndex,
                                   attackerSide: attackerSide,
                                   attackerIndex: attackerIndex,
                                   context: &context)
        }
    }

    // MARK: - Breath Skill

    private static func executeEnemyBreathSkill(skill: EnemySkillDefinition,
                                                attackerSide: ActorSide,
                                                attackerIndex: Int,
                                                context: inout BattleContext) {
        guard let attacker = context.actor(for: attackerSide, index: attackerIndex), attacker.isAlive else { return }

        let targets = selectEnemySkillTargets(skill: skill,
                                              attackerSide: attackerSide,
                                              attackerIndex: attackerIndex,
                                              context: &context)

        let multiplier = skill.multiplier ?? 1.0

        for (targetSide, targetIndex) in targets {
            guard let refreshedAttacker = context.actor(for: attackerSide, index: attackerIndex),
                  refreshedAttacker.isAlive else { break }
            guard var target = context.actor(for: targetSide, index: targetIndex),
                  target.isAlive else { continue }

            let baseDamage = computeEnemySkillBreathDamage(attacker: refreshedAttacker,
                                                           defender: target,
                                                           multiplier: multiplier,
                                                           element: skill.element,
                                                           context: &context)
            let applied = applyDamage(amount: baseDamage, to: &target)
            context.updateActor(target, side: targetSide, index: targetIndex)

            let attackerIdx = context.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
            let targetIdx = context.actorIndex(for: targetSide, arrayIndex: targetIndex)
            context.appendAction(kind: .enemySpecialDamage, actor: attackerIdx, target: targetIdx, value: UInt32(applied))

            handleEnemySkillDefeat(targetSide: targetSide,
                                   targetIndex: targetIndex,
                                   attackerSide: attackerSide,
                                   attackerIndex: attackerIndex,
                                   context: &context)
        }
    }

    // MARK: - Status Skill

    private static func executeEnemyStatusSkill(skill: EnemySkillDefinition,
                                                attackerSide: ActorSide,
                                                attackerIndex: Int,
                                                context: inout BattleContext) {
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
                                           context: &context)
        }
    }

    // MARK: - Heal Skill

    private static func executeEnemyHealSkill(skill: EnemySkillDefinition,
                                              casterSide: ActorSide,
                                              casterIndex: Int,
                                              context: inout BattleContext) {
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

            let casterIdx = context.actorIndex(for: casterSide, arrayIndex: casterIndex)
            let targetIdx = context.actorIndex(for: targetSide, arrayIndex: targetIndex)
            context.appendAction(kind: .enemySpecialHeal, actor: casterIdx, target: targetIdx, value: UInt32(applied))
        }
    }

    // MARK: - Buff Skill

    private static func executeEnemyBuffSkill(skill: EnemySkillDefinition,
                                              casterSide: ActorSide,
                                              casterIndex: Int,
                                              context: inout BattleContext) {
        guard let _ = context.actor(for: casterSide, index: casterIndex) else { return }
        guard let buffType = skill.buffType else { return }

        let casterIdx = context.actorIndex(for: casterSide, arrayIndex: casterIndex)
        context.appendAction(kind: .enemySpecialBuff, actor: casterIdx, extra: UInt16(buffType.hashValue & 0xFFFF))

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
        }
    }

    // MARK: - Helper Functions

    private static func selectEnemySkillTargets(skill: EnemySkillDefinition,
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
                let idx = context.random.nextInt(in: 0...(alive.count - 1))
                let target = alive[idx]
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

    private static func computeEnemySkillPhysicalDamage(attacker: BattleActor,
                                                        defender: BattleActor,
                                                        multiplier: Double,
                                                        ignoreDefense: Bool,
                                                        context: inout BattleContext) -> Int {
        let baseAttack = Double(attacker.snapshot.physicalAttack)
        let baseDefense = ignoreDefense ? 0.0 : Double(defender.snapshot.physicalDefense)
        let rawDamage = max(1.0, baseAttack * multiplier - baseDefense * 0.5)

        let variance = context.random.nextDouble(in: 0.9...1.1)
        return max(1, Int(rawDamage * variance))
    }

    private static func computeEnemySkillMagicalDamage(attacker: BattleActor,
                                                       defender: BattleActor,
                                                       multiplier: Double,
                                                       element: String?,
                                                       context: inout BattleContext) -> Int {
        let baseAttack = Double(attacker.snapshot.magicalAttack)
        let baseDefense = Double(defender.snapshot.magicalDefense)
        let rawDamage = max(1.0, baseAttack * multiplier - baseDefense * 0.3)

        let variance = context.random.nextDouble(in: 0.9...1.1)
        return max(1, Int(rawDamage * variance))
    }

    private static func computeEnemySkillBreathDamage(attacker: BattleActor,
                                                      defender: BattleActor,
                                                      multiplier: Double,
                                                      element: String?,
                                                      context: inout BattleContext) -> Int {
        let baseBreath = Double(attacker.snapshot.breathDamage)
        let rawDamage = max(1.0, baseBreath * multiplier)

        let variance = context.random.nextDouble(in: 0.9...1.1)
        return max(1, Int(rawDamage * variance))
    }

    private static func handleEnemySkillDefeat(targetSide: ActorSide,
                                               targetIndex: Int,
                                               attackerSide: ActorSide,
                                               attackerIndex: Int,
                                               context: inout BattleContext) {
        guard let target = context.actor(for: targetSide, index: targetIndex),
              !target.isAlive else { return }

        appendDefeatLog(for: target, side: targetSide, index: targetIndex, context: &context)

        let killerRef = BattleContext.reference(for: attackerSide, index: attackerIndex)
        dispatchReactions(for: .allyDefeated(side: targetSide,
                                             fallenIndex: targetIndex,
                                             killer: killerRef),
                          depth: 0,
                          context: &context)

        _ = attemptInstantResurrectionIfNeeded(of: targetIndex,
                                               side: targetSide,
                                               context: &context)
            || attemptRescue(of: targetIndex,
                             side: targetSide,
                             context: &context)
    }

    private static func attemptEnemySkillStatusInflict(statusId: UInt8,
                                                       chancePercent: Int,
                                                       targetSide: ActorSide,
                                                       targetIndex: Int,
                                                       context: inout BattleContext) {
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
            context.appendAction(kind: .statusInflict, target: targetIdx, skillIndex: UInt16(statusId))
            // autoStatusCureOnAlly判定
            applyAutoStatusCureIfNeeded(for: targetSide, targetIndex: targetIndex, context: &context)
        } else {
            context.appendAction(kind: .statusResist, target: targetIdx, skillIndex: UInt16(statusId))
        }
    }

    private static func applyEnemyBuff(buffType: String, multiplier: Double, to actor: inout BattleActor) {
        switch buffType {
        case "attack":
            actor.snapshot.physicalAttack = Int(Double(actor.snapshot.physicalAttack) * multiplier)
        case "defense":
            actor.snapshot.physicalDefense = Int(Double(actor.snapshot.physicalDefense) * multiplier)
        case "magic":
            actor.snapshot.magicalAttack = Int(Double(actor.snapshot.magicalAttack) * multiplier)
        case "speed":
            // agilityは直接変更できないのでスキップ
            break
        default:
            break
        }
    }
}
