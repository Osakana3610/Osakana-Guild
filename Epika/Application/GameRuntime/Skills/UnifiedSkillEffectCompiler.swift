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
//   - 共通集計サービス（SkillEffectAggregationService）への薄いラッパー
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
        let sortedSkills = skills.sorted { $0.id < $1.id }
        let result = try SkillEffectAggregationService.aggregate(
            input: SkillEffectAggregationInput(skills: sortedSkills, actorStats: stats),
            options: []
        )
        self.equipmentSlots = result.equipmentSlots
        self.spellbook = result.spellbook
        self.actorEffects = result.battleEffects
    }
}
