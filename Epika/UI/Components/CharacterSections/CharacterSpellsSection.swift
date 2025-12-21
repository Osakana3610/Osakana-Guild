// ==============================================================================
// CharacterSpellsSection.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクターの習得済み魔法一覧を表示
//   - 魔法使い魔法と僧侶魔法を分けて表示
//
// 【View構成】
//   - 魔法使い魔法セクション: spellLoadout.mage の魔法名リスト
//   - 僧侶魔法セクション: spellLoadout.priest の魔法名リスト
//   - 魔法がない場合は「魔法なし」テキスト
//
// 【使用箇所】
//   - キャラクター詳細画面（CharacterSectionType.mageMagic / priestMagic）
//
// ==============================================================================

import SwiftUI

/// 魔法使い魔法の一覧を表示するセクション
/// CharacterSectionType: mageMagic
@MainActor
struct CharacterMageSpellsSection: View {
    let character: RuntimeCharacter

    var body: some View {
        let spells = character.spellLoadout.mage
        Group {
            if spells.isEmpty {
                Text("魔法なし")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(spells, id: \.id) { spell in
                        Text("• \(spell.name)")
                    }
                }
            }
        }
    }
}

/// 僧侶魔法の一覧を表示するセクション
/// CharacterSectionType: priestMagic
@MainActor
struct CharacterPriestSpellsSection: View {
    let character: RuntimeCharacter

    var body: some View {
        let spells = character.spellLoadout.priest
        Group {
            if spells.isEmpty {
                Text("魔法なし")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(spells, id: \.id) { spell in
                        Text("• \(spell.name)")
                    }
                }
            }
        }
    }
}
