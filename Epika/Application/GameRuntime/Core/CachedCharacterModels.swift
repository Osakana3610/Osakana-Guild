// ==============================================================================
// CachedCharacterModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ランタイムキャラクターの型定義
//   - ゲームロジックで使用する完全なキャラクター表現
//
// 【データ構造】
//   - CachedCharacter: キャラクター完全表現
//     永続化データ:
//       - id, displayName, raceId, jobId, previousJobId, avatarId
//       - level, experience, currentHP
//       - equippedItems, primaryPersonalityId, secondaryPersonalityId
//       - actionRateAttack/PriestMagic/MageMagic/Breath
//       - updatedAt
//     計算結果:
//       - attributes (CoreAttributes): 基礎ステータス
//       - maxHP, combat (Combat): 戦闘ステータス
//       - equipmentCapacity: 装備可能数
//     マスターデータ:
//       - race, job, personalityPrimary/Secondary
//       - learnedSkills, loadout
//       - spellbook, spellLoadout
//
//   - Loadout: 装備関連マスターデータのキャッシュ
//     - items, titles, superRareTitles
//
// 【導出プロパティ】
//   - name, isAlive, raceName, jobName
//   - resolvedAvatarId: 有効なアバターID
//   - isMartialEligible: 格闘ボーナス適用可否
//   - actionPreferences, hitPoints: 互換用
//
// 【使用箇所】
//   - BattleContext: 戦闘中のキャラクター状態
//   - RuntimePartyState: パーティメンバー
//   - UI層: キャラクター表示
//
// ==============================================================================

import Foundation

// MARK: - 新CachedCharacter（フラット化）

/// ゲームロジックで使用するキャラクターの完全な表現。
/// CharacterInput + マスターデータ + 計算結果を統合。
struct CachedCharacter: Identifiable, Sendable, Hashable {
    // === 永続化データ（CharacterInputから） ===
    nonisolated let id: UInt8
    nonisolated var displayName: String
    nonisolated let raceId: UInt8
    nonisolated let jobId: UInt8
    nonisolated let previousJobId: UInt8
    nonisolated let avatarId: UInt16
    nonisolated let level: Int
    nonisolated let experience: Int
    nonisolated var currentHP: Int
    nonisolated let equippedItems: [CachedInventoryItem]
    nonisolated let primaryPersonalityId: UInt8
    nonisolated let secondaryPersonalityId: UInt8
    nonisolated let actionRateAttack: Int
    nonisolated let actionRatePriestMagic: Int
    nonisolated let actionRateMageMagic: Int
    nonisolated let actionRateBreath: Int
    nonisolated let updatedAt: Date
    nonisolated let displayOrder: UInt8

    // === 計算結果 ===
    nonisolated let attributes: CoreAttributes
    nonisolated let maxHP: Int
    nonisolated let combat: Combat
    nonisolated let equipmentCapacity: Int

    // isMartialEligibleはcombatから取得
    nonisolated var isMartialEligible: Bool { combat.isMartialEligible }

    // === マスターデータ ===
    nonisolated let race: RaceDefinition?
    nonisolated let job: JobDefinition?
    nonisolated let previousJob: JobDefinition?
    nonisolated let personalityPrimary: PersonalityPrimaryDefinition?
    nonisolated let personalitySecondary: PersonalitySecondaryDefinition?
    nonisolated let learnedSkills: [SkillDefinition]
    nonisolated let loadout: Loadout
    nonisolated let spellbook: SkillRuntimeEffects.Spellbook
    nonisolated let spellLoadout: SkillRuntimeEffects.SpellLoadout

    // === 導出プロパティ ===
    nonisolated var name: String { displayName }
    nonisolated var isAlive: Bool { currentHP > 0 }
    nonisolated var raceName: String { race?.name ?? "種族\(raceId)" }
    nonisolated var gender: String { race?.genderDisplayName ?? "不明" }
    nonisolated var jobName: String {
        let currentJobName = job?.name ?? "職業\(jobId)"
        // マスター職（ID 100以上）は前職表示不要
        if jobId < 100, let previousJobName = previousJob?.name {
            return "\(currentJobName)（\(previousJobName)）"
        }
        return currentJobName
    }
    /// 職業表示名（CharacterSummary互換）
    nonisolated var displayJobName: String { jobName }

    nonisolated var resolvedAvatarId: UInt16 {
        avatarId == 0 ? UInt16(raceId) : avatarId
    }

    /// 行動優先度
    nonisolated var actionPreferences: CharacterValues.ActionPreferences {
        CharacterValues.ActionPreferences(
            attack: actionRateAttack,
            priestMagic: actionRatePriestMagic,
            mageMagic: actionRateMageMagic,
            breath: actionRateBreath
        )
    }

    /// HP互換プロパティ
    nonisolated var hitPoints: CharacterValues.HitPoints {
        CharacterValues.HitPoints(current: currentHP, maximum: maxHP)
    }
}

extension CachedCharacter {
    typealias CoreAttributes = CharacterValues.CoreAttributes
    typealias Combat = CharacterValues.Combat

    struct Loadout: Sendable, Hashable {
        nonisolated var items: [ItemDefinition]
        nonisolated var titles: [TitleDefinition]
        nonisolated var superRareTitles: [SuperRareTitleDefinition]
    }
}
