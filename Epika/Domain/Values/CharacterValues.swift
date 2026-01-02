// ==============================================================================
// CharacterValues.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクター関連値型の名前空間
//   - CharacterSnapshot/RuntimeCharacterで共有される構造体の定義
//
// 【データ構造】
//   - CoreAttributes: 基礎ステータス（STR/WIS/SPI/VIT/AGI/LUK）
//   - HitPoints: HP情報（current/maximum）
//   - Combat: 戦闘ステータス
//     - maxHP, physicalAttack, magicalAttack
//     - physicalDefense, magicalDefense
//     - hitRate, evasionRate, criticalRate
//     - attackCount, magicalHealing, trapRemoval
//     - additionalDamage, breathDamage, isMartialEligible
//   - Personality: 性格設定（primary/secondary ID、0=なし）
//   - LearnedSkill: 習得スキル情報
//   - EquippedItem: 装備アイテム情報（称号・ソケット含む）
//   - AchievementCounters: 実績カウンター（戦闘数・勝利数・敗北数）
//   - ActionPreferences: 行動設定（攻撃/僧侶魔法/魔法使い魔法/ブレス）
//   - JobHistoryEntry: 転職履歴エントリ
//
// 【設計意図】
//   - enumとして定義（インスタンス化不可、名前空間として使用）
//   - すべての内部型はSendable/Hashable準拠
//
// 【使用箇所】
//   - CharacterSnapshot: 値型の型エイリアス元
//   - RuntimeCharacter: ランタイムキャラクター
//   - CharacterInput: 変換用中間型
//
// ==============================================================================

import Foundation

/// CharacterSnapshotとRuntimeCharacterで共有される値型の名前空間。
/// インスタンス化は意図しない（enumとして定義）。
enum CharacterValues {
    struct CoreAttributes: Sendable, Hashable {
        var strength: Int
        var wisdom: Int
        var spirit: Int
        var vitality: Int
        var agility: Int
        var luck: Int
    }

    struct HitPoints: Sendable, Hashable {
        var current: Int
        var maximum: Int
    }

    struct Combat: Sendable, Hashable {
        var maxHP: Int
        var physicalAttack: Int
        var magicalAttack: Int
        var physicalDefense: Int
        var magicalDefense: Int
        var hitRate: Int
        var evasionRate: Int
        var criticalRate: Int
        var attackCount: Double
        var magicalHealing: Int
        var trapRemoval: Int
        var additionalDamage: Int
        var breathDamage: Int
        var isMartialEligible: Bool
    }

    struct Personality: Sendable, Hashable {
        /// 0 = なし
        var primaryId: UInt8
        /// 0 = なし
        var secondaryId: UInt8
    }

    struct LearnedSkill: Sendable, Hashable {
        var id: UUID
        var skillId: UInt16
        var level: Int
        var isEquipped: Bool
        var createdAt: Date
        var updatedAt: Date
    }

    struct EquippedItem: Sendable, Hashable {
        // アイテム本体
        var superRareTitleId: UInt8
        var normalTitleId: UInt8
        var itemId: UInt16
        // ソケット（宝石改造）
        var socketSuperRareTitleId: UInt8
        var socketNormalTitleId: UInt8
        var socketItemId: UInt16
        // 数量（グループ化後）
        var quantity: Int

        /// スタック識別キー（文字列形式）
        var stackKey: String {
            "\(superRareTitleId)|\(normalTitleId)|\(itemId)|\(socketSuperRareTitleId)|\(socketNormalTitleId)|\(socketItemId)"
        }

        /// スタック識別キー（UInt64にパック、高速比較用）
        var packedStackKey: UInt64 {
            UInt64(superRareTitleId) << 56 |
            UInt64(normalTitleId) << 48 |
            UInt64(itemId) << 32 |
            UInt64(socketSuperRareTitleId) << 24 |
            UInt64(socketNormalTitleId) << 16 |
            UInt64(socketItemId)
        }
    }

    struct AchievementCounters: Sendable, Hashable {
        var totalBattles: Int
        var totalVictories: Int
        var defeatCount: Int
    }

    struct ActionPreferences: Sendable, Hashable {
        var attack: Int
        var priestMagic: Int
        var mageMagic: Int
        var breath: Int

        static func clamped(_ value: Int) -> Int {
            max(0, min(100, value))
        }

        static func normalized(attack: Int,
                               priestMagic: Int,
                               mageMagic: Int,
                               breath: Int) -> ActionPreferences {
            ActionPreferences(attack: clamped(attack),
                              priestMagic: clamped(priestMagic),
                              mageMagic: clamped(mageMagic),
                              breath: clamped(breath))
        }
    }

    struct JobHistoryEntry: Sendable, Hashable {
        var id: UUID
        var jobId: UInt8
        var achievedAt: Date
        var createdAt: Date
        var updatedAt: Date
    }
}
