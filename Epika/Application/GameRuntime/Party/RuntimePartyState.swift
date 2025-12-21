// ==============================================================================
// RuntimePartyState.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 探索・戦闘で使用するランタイムパーティ状態の管理
//   - パーティメンバーのステータスに基づく補正値の計算
//
// 【データ構造】
//   - PartySlotBonuses: パーティのゴールド/レア/称号倍率と幸運値
//   - RuntimePartyState: パーティスナップショットとランタイムキャラクターのセット
//
// 【使用箇所】
//   - BattleService（戦闘処理）
//   - DropService（ドロップ計算）
//   - ExplorationEngine（探索イベント処理）
//
// ==============================================================================

import Foundation

// MARK: - Party Slot Bonuses

struct PartySlotBonuses: Sendable {
    let goldMultiplier: Double
    let rareMultiplier: Double
    let titleMultiplier: Double
    let fortune: Int

    static let zero = PartySlotBonuses(goldMultiplier: 0.0,
                                       rareMultiplier: 0.0,
                                       titleMultiplier: 0.0,
                                       fortune: 0)

    init(goldMultiplier: Double, rareMultiplier: Double, titleMultiplier: Double, fortune: Int) {
        self.goldMultiplier = goldMultiplier
        self.rareMultiplier = rareMultiplier
        self.titleMultiplier = titleMultiplier
        self.fortune = fortune
    }

    init(members: [RuntimeCharacter]) {
        guard !members.isEmpty else {
            self = .zero
            return
        }
        let luckSum = members.reduce(0) { $0 + $1.attributes.luck }
        let spiritSum = members.reduce(0) { $0 + $1.attributes.spirit }
        let gold = Self.clampMultiplier(1.0 + Double(luckSum) * 0.001, limit: 250.0)
        let rare = Self.clampMultiplier(1.0 + Double(luckSum + spiritSum) * 0.0005, limit: 99.9)
        let averageLuck = Double(luckSum) / Double(members.count)
        let title = Self.clampMultiplier(1.0 + averageLuck * 0.002, limit: 99.9)
        let fortune = Int(averageLuck.rounded())
        self.goldMultiplier = gold
        self.rareMultiplier = rare
        self.titleMultiplier = title
        self.fortune = fortune
    }

    private static func clampMultiplier(_ value: Double, limit: Double) -> Double {
        min(max(value, 0.0), limit)
    }
}

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
