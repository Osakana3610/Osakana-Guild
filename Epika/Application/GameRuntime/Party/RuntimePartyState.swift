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
        var id: UInt8 { characterId }
        let characterId: UInt8
        let order: Int
        var character: RuntimeCharacter
    }

    let party: PartySnapshot
    var members: [Member]

    init(party: PartySnapshot, characters: [RuntimeCharacter]) throws {
        self.party = party
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
}
