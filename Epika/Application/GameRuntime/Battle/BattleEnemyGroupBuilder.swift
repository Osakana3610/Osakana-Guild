// ==============================================================================
// BattleEnemyGroupBuilder.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 敵グループの生成と敵BattleActorの構築
//   - ダンジョン設定に基づく敵エンカウントの生成
//   - 敵のスキル効果キャッシュ管理
//
// 【データ構造】
//   - EncounteredEnemy: エンカウントした敵の定義とレベル
//
// 【公開API】
//   - makeEnemies: 敵グループとエンカウント情報を生成
//
// 【使用箇所】
//   - BattleService（戦闘開始時の敵グループ構築）
//
// ==============================================================================

import Foundation

struct BattleEnemyGroupBuilder {
    struct EncounteredEnemy {
        let definition: EnemyDefinition
        let level: Int
    }

    /// 敵グループを生成（複数種類の敵対応）
    /// nonisolated - 計算処理のためMainActorに縛られない
    nonisolated static func makeEnemies(specs: [EncounteredEnemySpec],
                            enemyDefinitions: [UInt16: EnemyDefinition],
                            skillDefinitions: [UInt16: SkillDefinition],
                            jobDefinitions: [UInt8: JobDefinition],
                            random: inout GameRandomSource) throws -> ([BattleActor], [EncounteredEnemy]) {
        var skillCache: [UInt16: BattleActor.SkillEffects] = [:]

        // specsを敵ID順、レベル降順でソート（同じ敵が連続するように）
        let sortedSpecs = specs.sorted { lhs, rhs in
            if lhs.enemyId != rhs.enemyId {
                return lhs.enemyId < rhs.enemyId
            }
            return lhs.level > rhs.level  // 同じ敵ならレベル高い順
        }

        var actors: [BattleActor] = []
        var encountered: [EncounteredEnemy] = []
        var slotIndex = 0

        for spec in sortedSpecs {
            guard let definition = enemyDefinitions[spec.enemyId] else { continue }

            for _ in 0..<spec.count {
                guard let slot = BattleContextBuilder.slot(for: slotIndex) else { break }

                let snapshot = try CombatSnapshotBuilder.makeEnemySnapshot(from: definition,
                                                                           levelOverride: spec.level,
                                                                           jobDefinitions: jobDefinitions,
                                                                           skillDefinitions: skillDefinitions)
                var resources = BattleActionResource.makeDefault(for: snapshot,
                                                                spellLoadout: .empty)
                let skillEffects = try cachedSkillEffects(for: definition,
                                                          cache: &skillCache,
                                                          skillDefinitions: skillDefinitions)
                if skillEffects.spell.breathExtraCharges > 0 {
                    let current = resources.charges(for: .breath)
                    resources.setCharges(for: .breath, value: current + skillEffects.spell.breathExtraCharges)
                }
                let identifier = "\(definition.id)_\(slotIndex)"
                let actor = BattleActor(identifier: identifier,
                                        displayName: definition.name,
                                        kind: .enemy,
                                        formationSlot: slot,
                                        strength: definition.strength,
                                        wisdom: definition.wisdom,
                                        spirit: definition.spirit,
                                        vitality: definition.vitality,
                                        agility: definition.agility,
                                        luck: definition.luck,
                                        partyMemberId: nil,
                                        level: spec.level,
                                        jobName: definition.jobId.flatMap { jobDefinitions[$0]?.name } ?? "敵",
                                        avatarIndex: nil,
                                        isMartialEligible: false,
                                        raceId: definition.raceId,
                                        enemyMasterIndex: definition.id,
                                        snapshot: snapshot,
                                        currentHP: snapshot.maxHP,
                                        actionRates: BattleActionRates(attack: definition.actionRates.attack,
                                                                       priestMagic: definition.actionRates.priestMagic,
                                                                       mageMagic: definition.actionRates.mageMagic,
                                                                       breath: definition.actionRates.breath),
                                        actionResources: resources,
                                        barrierCharges: skillEffects.combat.barrierCharges,
                                        skillEffects: skillEffects,
                                        spellbook: .empty,
                                        spells: .empty,
                                        baseSkillIds: Set(definition.specialSkillIds),
                                        innateResistances: BattleInnateResistances(from: definition.resistances))
                actors.append(actor)
                encountered.append(EncounteredEnemy(definition: definition, level: spec.level))
                slotIndex += 1
            }
        }

        return (actors, encountered)
    }

    nonisolated private static func makeActors(for definition: EnemyDefinition,
                                    levelOverride: Int?,
                                    count: Int,
                                    skillDefinitions: [UInt16: SkillDefinition],
                                    jobDefinitions: [UInt8: JobDefinition],
                                    cache: inout [UInt16: BattleActor.SkillEffects],
                                    random: inout GameRandomSource) throws -> [BattleActor] {
        var actors: [BattleActor] = []
        for index in 0..<count {
            guard let slot = BattleContextBuilder.slot(for: index) else { break }
            let level = levelOverride ?? 1
            let snapshot = try CombatSnapshotBuilder.makeEnemySnapshot(from: definition,
                                                                       levelOverride: level,
                                                                       jobDefinitions: jobDefinitions,
                                                                       skillDefinitions: skillDefinitions)
            var resources = BattleActionResource.makeDefault(for: snapshot,
                                                            spellLoadout: .empty)
            let skillEffects = try cachedSkillEffects(for: definition,
                                                      cache: &cache,
                                                      skillDefinitions: skillDefinitions)
            if skillEffects.spell.breathExtraCharges > 0 {
                let current = resources.charges(for: .breath)
                resources.setCharges(for: .breath, value: current + skillEffects.spell.breathExtraCharges)
            }
            let identifier = index == 0 ? String(definition.id) : "\(definition.id)_\(index)"
            let actor = BattleActor(identifier: identifier,
                                    displayName: definition.name,
                                    kind: .enemy,
                                    formationSlot: slot,
                                    strength: definition.strength,
                                    wisdom: definition.wisdom,
                                    spirit: definition.spirit,
                                    vitality: definition.vitality,
                                    agility: definition.agility,
                                    luck: definition.luck,
                                    partyMemberId: nil,
                                    level: level,
                                    jobName: definition.jobId.flatMap { jobDefinitions[$0]?.name } ?? "敵",
                                    avatarIndex: nil,
                                    isMartialEligible: false,
                                    raceId: definition.raceId,
                                    enemyMasterIndex: definition.id,
                                    snapshot: snapshot,
                                    currentHP: snapshot.maxHP,
                                    actionRates: BattleActionRates(attack: definition.actionRates.attack,
                                                                   priestMagic: definition.actionRates.priestMagic,
                                                                   mageMagic: definition.actionRates.mageMagic,
                                                                   breath: definition.actionRates.breath),
                                    actionResources: resources,
                                    barrierCharges: skillEffects.combat.barrierCharges,
                                    skillEffects: skillEffects,
                                    spellbook: .empty,
                                    spells: .empty,
                                    baseSkillIds: Set(definition.specialSkillIds),
                                    innateResistances: BattleInnateResistances(from: definition.resistances))
            actors.append(actor)
        }
        return actors
    }

    nonisolated private static func cachedSkillEffects(for definition: EnemyDefinition,
                                           cache: inout [UInt16: BattleActor.SkillEffects],
                                           skillDefinitions: [UInt16: SkillDefinition]) throws -> BattleActor.SkillEffects {
        if let cached = cache[definition.id] {
            return cached
        }
        let skills = definition.specialSkillIds.compactMap { skillDefinitions[$0] }
        let skillCompiler = try UnifiedSkillEffectCompiler(skills: skills)
        let effects = skillCompiler.actorEffects
        cache[definition.id] = effects
        return effects
    }
}
