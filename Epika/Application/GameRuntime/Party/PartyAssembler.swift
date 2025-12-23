// ==============================================================================
// PartyAssembler.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - パーティスナップショットとキャラクターデータからランタイムパーティ状態を組み立て
//
// 【公開API】
//   - assembleState(): パーティとキャラクター入力からRuntimePartyStateを構築
//
// 【使用箇所】
//   - ExplorationService（探索開始時のパーティ準備）
//
// ==============================================================================

import Foundation

enum PartyAssembler {
    @MainActor
    static func assembleState(masterData: MasterDataCache,
                              party: PartySnapshot,
                              characters: [CharacterInput]) throws -> RuntimePartyState {
        let characterMap = Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0) })
        var assembled: [RuntimeCharacter] = []
        for characterId in party.memberIds {
            guard let input = characterMap[characterId] else { continue }
            let runtimeCharacter = try RuntimeCharacterFactory.make(
                from: input,
                masterData: masterData
            )
            assembled.append(runtimeCharacter)
        }

        // 探索時間モディファイアを事前計算
        var explorationModifiers = SkillRuntimeEffects.ExplorationModifiers.neutral
        for character in assembled {
            let modifiers = try SkillRuntimeEffectCompiler.explorationModifiers(from: character.learnedSkills)
            explorationModifiers.merge(modifiers)
        }

        return try RuntimePartyState(party: party,
                                     characters: assembled,
                                     explorationModifiers: explorationModifiers)
    }
}
