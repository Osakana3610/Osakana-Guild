// ==============================================================================
// SkillRuntimeEffectCompiler.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - スキル効果をコンパイルするユーティリティの名前空間定義
//   - 実際の実装は各extension fileに分割される
//
// 【公開API】
//   - enum SkillRuntimeEffectCompiler: 名前空間として使用
//     - Actor拡張: BattleActor.SkillEffects.Reaction.make(...), RowProfile.applyParameters(...)
//     - Spell拡張: spellLoadout(from:definitions:characterLevel:)
//     - Validation拡張: decodePayload(from:skillId:), validatePayload(_:skillId:effectIndex:)
//
// 【使用箇所】
//   - キャラクター能力計算
//   - 戦闘システム
//   - SpellLoadout の構築
//
// ==============================================================================

import Foundation

/// スキル効果をコンパイルするユーティリティ
/// 実際の実装は各extension fileに分割:
/// - SkillRuntimeEffectCompiler.Spell.swift: spellLoadout
/// - SkillRuntimeEffectCompiler.Validation.swift: decodePayload, validatePayload
enum SkillRuntimeEffectCompiler {}
