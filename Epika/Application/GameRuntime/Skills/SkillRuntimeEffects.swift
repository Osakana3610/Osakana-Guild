// ==============================================================================
// SkillRuntimeEffects.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - スキル効果をコンパイルするユーティリティの名前空間定義
//   - 実際の実装は各extension fileに分割される
//
// 【公開API】
//   - enum SkillRuntimeEffectCompiler: 名前空間として使用
//     - Actor拡張: actorEffects(from:stats:)
//     - Equipment拡張: equipmentSlots(from:)
//     - Reward拡張: rewardComponents(from:)
//     - Exploration拡張: explorationModifiers(from:)
//     - Spell拡張: spellbook(from:), spellLoadout(from:definitions:)
//     - Validation拡張: decodePayload(from:skillId:), validatePayload(_:skillId:effectIndex:)
//
// 【使用箇所】
//   - キャラクター能力計算
//   - 戦闘システム
//   - 探索システム
//   - 報酬計算
//
// ==============================================================================

import Foundation

/// スキル効果をコンパイルするユーティリティ
/// 実際の実装は各extension fileに分割:
/// - SkillRuntimeEffectCompiler.Actor.swift: actorEffects
/// - SkillRuntimeEffectCompiler.Equipment.swift: equipmentSlots
/// - SkillRuntimeEffectCompiler.Reward.swift: rewardComponents
/// - SkillRuntimeEffectCompiler.Exploration.swift: explorationModifiers
/// - SkillRuntimeEffectCompiler.Spell.swift: spellbook, spellLoadout
/// - SkillRuntimeEffectCompiler.Validation.swift: decodePayload, validatePayload
enum SkillRuntimeEffectCompiler {}
