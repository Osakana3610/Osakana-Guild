// ==============================================================================
// RuntimePartyState.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 探索・戦闘で使用するランタイムパーティ状態の管理
//
// 【データ構造】
//   - RuntimePartyState: パーティスナップショットとランタイムキャラクターのセット
//
// 【使用箇所】
//   - BattleService（戦闘処理）
//   - DropService（ドロップ計算）
//   - ExplorationEngine（探索イベント処理）
//
// ==============================================================================

import Foundation

// MARK: - Runtime Party State

struct RuntimePartyState: Sendable {
    struct Member: Identifiable, Sendable {
        nonisolated var id: UInt8 { characterId }
        nonisolated let characterId: UInt8
        nonisolated let order: Int
        nonisolated var character: CachedCharacter
    }

    nonisolated let party: CachedParty
    nonisolated var members: [Member]
    /// 探索時間モディファイア（事前計算）
    nonisolated let explorationModifiers: SkillRuntimeEffects.ExplorationModifiers

    nonisolated init(party: CachedParty,
                     characters: [CachedCharacter],
                     explorationModifiers: SkillRuntimeEffects.ExplorationModifiers = .neutral) throws {
        self.party = party
        self.explorationModifiers = explorationModifiers
        let characterMap = Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0) })
        var mappedMembers: [Member] = []
        for (order, characterId) in party.memberIds.enumerated() {
            guard let character = characterMap[characterId] else {
                throw RuntimeError.missingProgressData(reason: "Party member \(characterId) のキャラクターデータが見つかりません")
            }
            mappedMembers.append(Member(characterId: characterId,
                                        order: order,
                                        character: character))
        }
        self.members = mappedMembers
    }

    /// 指定ダンジョンに対する探索時間倍率を取得
    nonisolated func explorationTimeMultiplier(forDungeon dungeon: DungeonDefinition) -> Double {
        max(0.0, explorationModifiers.multiplier(forDungeonId: dungeon.id, dungeonName: dungeon.name))
    }
}
