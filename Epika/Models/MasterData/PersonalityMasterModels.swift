// ==============================================================================
// PersonalityMasterModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクターの性格（パーソナリティ）マスタデータ型定義
//
// 【データ構造】
//   - PersonalityPrimaryDefinition: 主性格
//     - id, name, description
//     - effects: 効果リスト（effectType, value, payloadJSON）
//   - PersonalitySecondaryDefinition: 副性格
//     - id, name
//     - positiveSkillId/negativeSkillId: 長所・短所スキル
//     - statBonuses: ステータス補正
//   - PersonalitySkillDefinition: 性格スキル
//     - id, name, description
//     - eventEffects: 戦闘イベント効果
//   - PersonalityCancellation: 性格打消し組み合わせ
//     - positiveSkillId/negativeSkillId: 打ち消し合うスキル
//   - PersonalityBattleEffect: 戦闘時効果
//     - id, payloadJSON: 効果定義（JSON形式）
//
// 【使用箇所】
//   - RuntimeCharacterFactory: キャラクター性格効果の適用
//   - BattleTurnEngine: 戦闘時の性格効果発動
//   - CharacterCreationView: 性格選択（将来実装）
//
// ==============================================================================

import Foundation

// MARK: - PersonalityPrimaryDefinition

struct PersonalityPrimaryDefinition: Identifiable, Sendable, Hashable {
    struct Effect: Sendable, Hashable {
        let effectType: String
        let value: Double?
        let payloadJSON: String
    }

    let id: UInt8
    let name: String
    let description: String
    let effects: [Effect]
}

struct PersonalitySecondaryDefinition: Identifiable, Sendable, Hashable {
    struct StatBonus: Sendable, Hashable {
        let stat: UInt8
        let value: Int
    }

    let id: UInt8
    let name: String
    let positiveSkillId: UInt8
    let negativeSkillId: UInt8
    let statBonuses: [StatBonus]
}

struct PersonalitySkillDefinition: Identifiable, Sendable {
    struct EventEffect: Sendable, Hashable {
        let effectId: UInt8
    }

    let id: UInt8
    let name: String
    let description: String
    let eventEffects: [EventEffect]
}

struct PersonalityCancellation: Sendable, Hashable {
    let positiveSkillId: UInt8
    let negativeSkillId: UInt8
}

struct PersonalityBattleEffect: Identifiable, Sendable {
    let id: UInt8
    let payloadJSON: String
}
