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
        case physicalAttackScore, magicalAttackScore
        case physicalDefenseScore, magicalDefenseScore
        case hitScore, evasionScore, criticalChancePercent
        case attackCount  // Double型
        case magicalHealingScore, trapRemovalScore
        case additionalDamageScore, breathDamageScore
        // isMartialEligibleはBoolなので除外

        var displayName: String {
            switch self {
            // 基本能力値
            case .strength: return L10n.BaseStat.strength
            case .wisdom: return L10n.BaseStat.wisdom
            case .spirit: return L10n.BaseStat.spirit
            case .vitality: return L10n.BaseStat.vitality
            case .agility: return L10n.BaseStat.agility
            case .luck: return L10n.BaseStat.luck
            // 戦闘ステータス
            case .maxHP: return L10n.CombatStat.maxHP
            case .physicalAttackScore: return L10n.CombatStat.physicalAttack
            case .magicalAttackScore: return L10n.CombatStat.magicalAttack
            case .physicalDefenseScore: return L10n.CombatStat.physicalDefense
            case .magicalDefenseScore: return L10n.CombatStat.magicalDefense
            case .hitScore: return L10n.CombatStat.hit
            case .evasionScore: return L10n.CombatStat.evasion
            case .criticalChancePercent: return L10n.CombatStat.criticalChancePercent
            case .attackCount: return L10n.CombatStat.attackCount
            case .magicalHealingScore: return L10n.CombatStat.magicalHealing
            case .trapRemovalScore: return L10n.CombatStat.trapRemoval
            case .additionalDamageScore: return L10n.CombatStat.additionalDamage
            case .breathDamageScore: return L10n.CombatStat.breathDamage
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
