// ==============================================================================
// UnifiedSkillEffectCompiler.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - スキル定義から全種類のエフェクトを1回のループで集約
//   - 各用途向けのAccumulatorに振り分けて結果を構築
//
// 【公開API】
//   - init(skills:stats:) throws
//   - equipmentSlots: SkillRuntimeEffects.EquipmentSlots
//   - spellbook: SkillRuntimeEffects.Spellbook
//   - actorEffects: BattleActor.SkillEffects（戦闘用）
//
// 【設計方針】
//   - 1回のループで全エフェクトをデコード・振り分け
//   - 各Accumulatorは既存のロジックを維持
//   - State > Coupling > Complexity > Code の優先度に従う
//
// 【備考】
//   - CombatStatCalculator用のcombatEffectsは、CombatStatCalculatorが
//     内部でSkillEffectAggregatorを使用しているため、現状維持
//   - 将来的にCombatStatKeyをpublic化すれば統合可能
//
// ==============================================================================

import Foundation

/// スキル定義から全種類のエフェクトを1回のループで集約するコンパイラ
struct UnifiedSkillEffectCompiler: Sendable {
    // MARK: - Results

    let equipmentSlots: SkillRuntimeEffects.EquipmentSlots
    let spellbook: SkillRuntimeEffects.Spellbook
    let actorEffects: BattleActor.SkillEffects

    // MARK: - Initialization

    nonisolated init(skills: [SkillDefinition], stats: ActorStats? = nil) throws {
        guard !skills.isEmpty else {
            self.equipmentSlots = .neutral
            self.spellbook = SkillRuntimeEffects.emptySpellbook
            self.actorEffects = .neutral
            return
        }

        // 各用途向けのAccumulator
        var equipmentAccum = EquipmentSlotsAccumulator()
        var spellAccum = SpellbookAccumulator()
        var actorAccum = ActorEffectsAccumulator()

        // 1回のループで全エフェクトを振り分け
        for skill in skills {
            for effect in skill.effects {
                let payload = try SkillRuntimeEffectCompiler.decodePayload(from: effect, skillId: skill.id)
                try SkillRuntimeEffectCompiler.validatePayload(payload, skillId: skill.id, effectIndex: effect.index)

                let context = SkillEffectContext(
                    skillId: skill.id,
                    skillName: skill.name,
                    effectIndex: effect.index,
                    actorStats: stats
                )

                // エフェクトタイプに基づいて各Accumulatorに振り分け
                switch payload.effectType {
                // 装備スロット関連
                case .equipmentSlotAdditive:
                    equipmentAccum.addSlotAdditive(payload)
                case .equipmentSlotMultiplier:
                    equipmentAccum.addSlotMultiplier(payload)

                // スペルブック関連
                case .spellAccess:
                    try spellAccum.addSpellAccess(payload, skillId: skill.id, effectIndex: effect.index)
                case .spellTierUnlock:
                    try spellAccum.addTierUnlock(payload, skillId: skill.id, effectIndex: effect.index)

                // 戦闘用（BattleActor.SkillEffectsで使用）- ActorEffectsAccumulatorは既存のハンドラを使用
                default:
                    if let handler = SkillEffectHandlerRegistry.handler(for: payload.effectType) {
                        try handler.apply(payload: payload, to: &actorAccum, context: context)
                    }
                }
            }
        }

        // 結果を構築
        self.equipmentSlots = equipmentAccum.build()
        self.spellbook = spellAccum.build()
        self.actorEffects = actorAccum.build()
    }
}

// MARK: - Equipment Slots Accumulator

private struct EquipmentSlotsAccumulator {
    private var additive: Int = 0
    private var multiplier: Double = 1.0

    nonisolated init() {}

    nonisolated mutating func addSlotAdditive(_ payload: DecodedSkillEffectPayload) {
        if let value = payload.value[.add] {
            let intValue = Int(value.rounded(.towardZero))
            additive &+= max(0, intValue)
        }
    }

    nonisolated mutating func addSlotMultiplier(_ payload: DecodedSkillEffectPayload) {
        if let mult = payload.value[.multiplier] {
            multiplier *= mult
        }
    }

    nonisolated func build() -> SkillRuntimeEffects.EquipmentSlots {
        SkillRuntimeEffects.EquipmentSlots(additive: additive, multiplier: multiplier)
    }
}

// MARK: - Spellbook Accumulator

private struct SpellbookAccumulator {
    private var learnedSpellIds: Set<UInt8> = []
    private var forgottenSpellIds: Set<UInt8> = []
    private var tierUnlocks: [UInt8: Int] = [:]

    nonisolated init() {}

    nonisolated mutating func addSpellAccess(
        _ payload: DecodedSkillEffectPayload,
        skillId: UInt16,
        effectIndex: Int
    ) throws {
        let spellIdRaw = try payload.requireParam(.spellId, skillId: skillId, effectIndex: effectIndex)
        let spellId = UInt8(spellIdRaw)
        let actionRaw = payload.parameters[.action] ?? 1
        if actionRaw == 2 {
            forgottenSpellIds.insert(spellId)
        } else {
            learnedSpellIds.insert(spellId)
        }
    }

    nonisolated mutating func addTierUnlock(
        _ payload: DecodedSkillEffectPayload,
        skillId: UInt16,
        effectIndex: Int
    ) throws {
        let schoolRaw = try payload.requireParam(.school, skillId: skillId, effectIndex: effectIndex)
        guard let school = SpellDefinition.School(rawValue: UInt8(schoolRaw)) else { return }
        let tierValue = try payload.requireValue(.tier, skillId: skillId, effectIndex: effectIndex)
        let tier = max(0, Int(tierValue.rounded(FloatingPointRoundingRule.towardZero)))
        guard tier > 0 else { return }
        let schoolIndex = school.index
        let current = tierUnlocks[schoolIndex] ?? 0
        if tier > current {
            tierUnlocks[schoolIndex] = tier
        }
    }

    nonisolated func build() -> SkillRuntimeEffects.Spellbook {
        SkillRuntimeEffects.Spellbook(
            learnedSpellIds: learnedSpellIds,
            forgottenSpellIds: forgottenSpellIds,
            tierUnlocks: tierUnlocks
        )
    }
}
