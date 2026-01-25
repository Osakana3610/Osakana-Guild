// ==============================================================================
// SkillModifierKey.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - SkillEffectType + slot + param から補正キーを構成する
//   - ModifierKeyベースの集約結果（SkillModifierSnapshot）を保持する
//
// ==============================================================================

import Foundation

/// スキル補正キー
nonisolated struct SkillModifierKey: Sendable, Hashable {
    let rawValue: UInt32

    nonisolated static let paramAll: UInt16 = 0xFFFF

    init(kind: SkillEffectType, slot: UInt8 = 0, param: UInt16 = 0) {
        rawValue = (UInt32(kind.rawValue) << 24) | (UInt32(slot) << 16) | UInt32(param)
    }

    var kind: SkillEffectType? {
        SkillEffectType(rawValue: UInt8(truncatingIfNeeded: rawValue >> 24))
    }

    var slot: UInt8 {
        UInt8(truncatingIfNeeded: rawValue >> 16)
    }

    var param: UInt16 {
        UInt16(truncatingIfNeeded: rawValue)
    }
}

/// ModifierKeyベースの集約結果（簡易スナップショット）
nonisolated struct SkillModifierSnapshot: Sendable, Hashable {
    var additivePercents: [SkillModifierKey: Double]
    var multipliers: [SkillModifierKey: Double]
    var maxValues: [SkillModifierKey: Double]
    var minValues: [SkillModifierKey: Double]
    var intValues: [SkillModifierKey: Int]
    var flags: Set<SkillModifierKey>

    init(additivePercents: [SkillModifierKey: Double],
         multipliers: [SkillModifierKey: Double],
         maxValues: [SkillModifierKey: Double],
         minValues: [SkillModifierKey: Double],
         intValues: [SkillModifierKey: Int],
         flags: Set<SkillModifierKey>) {
        self.additivePercents = additivePercents
        self.multipliers = multipliers
        self.maxValues = maxValues
        self.minValues = minValues
        self.intValues = intValues
        self.flags = flags
    }

    init() {
        self.init(additivePercents: [:],
                  multipliers: [:],
                  maxValues: [:],
                  minValues: [:],
                  intValues: [:],
                  flags: [])
    }

    static let empty = SkillModifierSnapshot()
}
