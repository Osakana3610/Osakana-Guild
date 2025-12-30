// ==============================================================================
// BattleLogEffectInterpreter.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - BattleActionEntry.Effect からHP変動の意味を抽出するヘルパー
//   - ログ表示や状態復元で共通の判定ロジックを提供
//
// ==============================================================================

import Foundation

enum BattleLogEffectImpact {
    case damage(target: UInt16, amount: Int)
    case heal(target: UInt16, amount: Int)
    case setHP(target: UInt16, amount: Int)
}

struct BattleLogEffectInterpreter {
    static func impact(for effect: BattleActionEntry.Effect) -> BattleLogEffectImpact? {
        guard let target = effect.target else {
            return nil
        }

        switch effect.kind {
        case .physicalDamage,
             .magicDamage,
             .breathDamage,
             .statusTick,
             .enemySpecialDamage:
            guard let value = effect.value else { return nil }
            return .damage(target: target, amount: Int(value))
        case .statusRampage:
            guard let value = effect.value else { return nil }
            return .damage(target: target, amount: Int(value))
        case .damageSelf:
            guard let value = effect.value else { return nil }
            return .damage(target: target, amount: Int(value))
        case .magicHeal,
             .healParty,
             .healSelf,
             .healAbsorb,
             .healVampire,
             .enemySpecialHeal:
            guard let value = effect.value else { return nil }
            return .heal(target: target, amount: Int(value))
        case .resurrection,
             .necromancer,
             .rescue:
            guard let value = effect.value else { return nil }
            return .setHP(target: target, amount: Int(value))
        case .physicalKill:
            return .setHP(target: target, amount: 0)
        default:
            return nil
       }
   }
}
