// ==============================================================================
// StatChangeNotificationService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ステータス変動通知の管理
//   - 装備変更時のステータス差分をUI表示用に保持
//
// 【公開API】
//   - changes: [StatChangeNotification] - 現在の通知リスト
//   - publish(_:) - ステータス変動通知を設定（全置換）
//   - clear() - 全通知をクリア
//
// 【通知管理】
//   - publish()は毎回全置換（累積しない）
//   - タップで全クリア
//
// 【補助型】
//   - StatKind: ステータス種別（ゲーム内定義と一致）
//   - StatChangeNotification: 通知データ
//     - kind, newValue, delta
//     - displayText: 表示用テキスト
//
// ==============================================================================

import Foundation
import Observation

@MainActor
@Observable
final class StatChangeNotificationService {
    private(set) var changes: [StatChangeNotification] = []

    /// ステータス種別
    /// ゲーム内定義（CharacterValues.swift、CharacterCombatStatsSection.swift）と完全一致
    enum StatKind: String, CaseIterable {
        // 基本能力値（CoreAttributes）
        case strength, wisdom, spirit, vitality, agility, luck
        // 戦闘ステータス（Combat）
        case maxHP
        case physicalAttack, magicalAttack
        case physicalDefense, magicalDefense
        case hitRate, evasionRate, criticalRate
        case attackCount  // Double型
        case magicalHealing, trapRemoval
        case additionalDamage, breathDamage
        // isMartialEligibleはBoolなので除外

        var displayName: String {
            switch self {
            // 基本能力値
            case .strength: return "力"
            case .wisdom: return "知恵"
            case .spirit: return "精神"
            case .vitality: return "体力"
            case .agility: return "敏捷"
            case .luck: return "運"
            // 戦闘ステータス
            case .maxHP: return "最大HP"
            case .physicalAttack: return "物理攻撃"
            case .magicalAttack: return "魔法攻撃"
            case .physicalDefense: return "物理防御"
            case .magicalDefense: return "魔法防御"
            case .hitRate: return "命中"
            case .evasionRate: return "回避"
            case .criticalRate: return "必殺率"
            case .attackCount: return "攻撃回数"
            case .magicalHealing: return "魔法回復力"
            case .trapRemoval: return "罠解除"
            case .additionalDamage: return "追加ダメージ"
            case .breathDamage: return "ブレスダメージ"
            }
        }
    }

    struct StatChangeNotification: Identifiable, Equatable {
        let kind: StatKind
        let newValue: String
        let delta: String

        var id: StatKind { kind }

        var displayText: String {
            "\(kind.displayName) \(newValue)(\(delta))"
        }
    }

    func publish(_ changes: [StatChangeNotification]) {
        self.changes = changes
    }

    func clear() {
        changes.removeAll()
    }
}
