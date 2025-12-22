// ==============================================================================
// RuntimeCharacterModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ランタイムキャラクターの型定義
//   - ゲームロジックで使用する完全なキャラクター表現
//
// 【データ構造】
//   - RuntimeCharacter: キャラクター完全表現
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

// MARK: - 新RuntimeCharacter（フラット化）

/// ゲームロジックで使用するキャラクターの完全な表現。
/// CharacterInput + マスターデータ + 計算結果を統合。
struct RuntimeCharacter: Identifiable, Sendable, Hashable {
    // === 永続化データ（CharacterInputから） ===
    let id: UInt8
    var displayName: String
    let raceId: UInt8
    let jobId: UInt8
    let previousJobId: UInt8
    let avatarId: UInt16
    let level: Int
    let experience: Int
    var currentHP: Int
    let equippedItems: [CharacterInput.EquippedItem]
    let primaryPersonalityId: UInt8
    let secondaryPersonalityId: UInt8
    let actionRateAttack: Int
    let actionRatePriestMagic: Int
    let actionRateMageMagic: Int
    let actionRateBreath: Int
    let updatedAt: Date

    // === 計算結果 ===
    let attributes: CoreAttributes
    let maxHP: Int
    let combat: Combat
    let equipmentCapacity: Int

    // isMartialEligibleはcombatから取得
    var isMartialEligible: Bool { combat.isMartialEligible }

    // === マスターデータ ===
    let race: RaceDefinition?
    let job: JobDefinition?
    let previousJob: JobDefinition?
    let personalityPrimary: PersonalityPrimaryDefinition?
    let personalitySecondary: PersonalitySecondaryDefinition?
    let learnedSkills: [SkillDefinition]
    let loadout: Loadout
    let spellbook: SkillRuntimeEffects.Spellbook
    let spellLoadout: SkillRuntimeEffects.SpellLoadout

    // === 導出プロパティ ===
    var name: String { displayName }
    var isAlive: Bool { currentHP > 0 }
    var raceName: String { race?.name ?? "種族\(raceId)" }
    var jobName: String {
        let currentJobName = job?.name ?? "職業\(jobId)"
        if let previousJobName = previousJob?.name {
            return "\(currentJobName)（\(previousJobName)）"
        }
        return currentJobName
    }

    var resolvedAvatarId: UInt16 {
        avatarId == 0 ? UInt16(raceId) : avatarId
    }

    /// 行動優先度（互換用）
    var actionPreferences: CharacterSnapshot.ActionPreferences {
        CharacterSnapshot.ActionPreferences(
            attack: actionRateAttack,
            priestMagic: actionRatePriestMagic,
            mageMagic: actionRateMageMagic,
            breath: actionRateBreath
        )
    }

    /// HP互換プロパティ
    var hitPoints: CharacterValues.HitPoints {
        CharacterValues.HitPoints(current: currentHP, maximum: maxHP)
    }
}

extension RuntimeCharacter {
    typealias CoreAttributes = CharacterValues.CoreAttributes
    typealias Combat = CharacterValues.Combat

    struct Loadout: Sendable, Hashable {
        var items: [ItemDefinition]
        var titles: [TitleDefinition]
        var superRareTitles: [SuperRareTitleDefinition]
    }
}
