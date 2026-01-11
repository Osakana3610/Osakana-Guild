// ==============================================================================
// SkillRuntimeEffectCompiler.Spell.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - Spellbook から SpellLoadout を構築
//
// 【公開API】
//   - spellLoadout(from:definitions:characterLevel:): Spellbook と SpellDefinition 配列から SpellLoadout を構築
//
// 【本体ファイルとの関係】
//   - SkillRuntimeEffectCompiler.swift で定義された enum を拡張
//   - SkillRuntimeEffects.SpellLoadout を戻り値として使用
//
// 【備考】
//   - Spellbook の構築は UnifiedSkillEffectCompiler で行う
//
// ==============================================================================

import Foundation

// MARK: - Spell Loadout Compilation
extension SkillRuntimeEffectCompiler {
    nonisolated static func spellLoadout(from spellbook: SkillRuntimeEffects.Spellbook,
                             definitions: [SpellDefinition],
                             characterLevel: Int) -> SkillRuntimeEffects.SpellLoadout {
        guard !definitions.isEmpty else { return SkillRuntimeEffects.emptySpellLoadout }

        var unlocks: [SpellDefinition.School: Int] = [:]
        for (schoolIndex, tier) in spellbook.tierUnlocks {
            guard let school = SpellDefinition.School(index: schoolIndex) else { continue }
            let clampedTier = max(0, tier)
            if let current = unlocks[school] {
                unlocks[school] = max(current, clampedTier)
            } else {
                unlocks[school] = clampedTier
            }
        }

        var allowedIds: Set<UInt8> = []
        for definition in definitions {
            guard !spellbook.forgottenSpellIds.contains(definition.id) else { continue }
            // 呪文解放条件: ティア解放スキルを持っている AND レベル条件を満たす
            if let unlockedTier = unlocks[definition.school],
               definition.tier <= unlockedTier,
               characterLevel >= definition.unlockLevel {
                allowedIds.insert(definition.id)
            }
        }

        allowedIds.formUnion(spellbook.learnedSpellIds)
        allowedIds.subtract(spellbook.forgottenSpellIds)

        guard !allowedIds.isEmpty else { return SkillRuntimeEffects.emptySpellLoadout }

        let filtered = definitions
            .filter { allowedIds.contains($0.id) }
            .sorted {
                if $0.tier != $1.tier { return $0.tier < $1.tier }
                return $0.id < $1.id
            }

        var mage: [SpellDefinition] = []
        var priest: [SpellDefinition] = []
        for definition in filtered {
            switch definition.school {
            case .mage:
                mage.append(definition)
            case .priest:
                priest.append(definition)
            }
        }

        return SkillRuntimeEffects.SpellLoadout(mage: mage, priest: priest)
    }
}
