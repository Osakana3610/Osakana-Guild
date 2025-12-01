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
