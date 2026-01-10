// ==============================================================================
// SkillRuntimeEffectCompiler.Validation.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - スキルエフェクトペイロードのデコード・バリデーション処理
//   - 必須フィールドのチェックと代替パラメータ名のサポート
//
// 【公開API】
//   - decodePayload(from:skillId:): SkillDefinition.Effect から DecodedSkillEffectPayload を構築
//   - validatePayload(_:skillId:effectIndex:): ペイロードの必須フィールドをバリデーション
//
// 【データ構造】
//   - DecodedSkillEffectPayload: デコード済みペイロード
//     - requireParam(_:skillId:effectIndex:): 必須パラメータを取得
//     - requireValue(_:skillId:effectIndex:): 必須値を取得
//     - requireStringArray(_:skillId:effectIndex:): 必須配列を取得
//   - SkillEffectValidationRequirement: バリデーション要件
//   - requiredFields: エフェクトタイプ別の必須フィールド定義
//
// 【本体ファイルとの関係】
//   - SkillRuntimeEffectCompiler.swift で定義された enum を拡張
//   - 全てのCompiler拡張から共通で使用される
//
// ==============================================================================

import Foundation

// MARK: - Payload Decoding & Validation
extension SkillRuntimeEffectCompiler {
    nonisolated static func decodePayload(from effect: SkillDefinition.Effect, skillId: UInt16) throws -> DecodedSkillEffectPayload {
        return DecodedSkillEffectPayload(
            familyId: effect.familyId,
            effectType: effect.effectType,
            parameters: effect.parameters,
            value: effect.values,
            arrays: effect.arrayValues
        )
    }

    /// 代替パラメータ名のマッピング（キー: 主要名, 値: 代替名のリスト）
    private static let parameterAliases: [EffectParamKey: [EffectParamKey]] = [
        .statusType: [.status],
        .equipmentType: [.equipmentCategory]
    ]

    nonisolated static func validatePayload(_ payload: DecodedSkillEffectPayload,
                                           skillId: UInt16,
                                           effectIndex: Int) throws {
        // requiredFieldsはString baseのため、現時点ではバリデーションをスキップ
        // Int化完了後、requiredFieldsもEffectParamKey/EffectValueKey baseに変更予定

        switch payload.effectType {
        case .extraAction:
            // chancePercent/valuePercent/count のいずれかがあればOK（countのみの場合は100%発動）
            let hasChance = payload.value[.chancePercent] != nil || payload.value[.valuePercent] != nil
            let hasCount = payload.value[.count] != nil
            guard hasChance || hasCount else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId)#\(effectIndex) extraAction にchanceまたはcountがありません")
            }
        case .partyAttackFlag:
            let hasFlag = payload.value[.hostileAll] != nil
                || payload.value[.vampiricImpulse] != nil
                || payload.value[.vampiricSuppression] != nil
            guard hasFlag else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId)#\(effectIndex) partyAttackFlag が空です")
            }
        case .partyAttackTarget:
            let hasTargetFlag = payload.value[.hostile] != nil || payload.value[.protect] != nil
            guard hasTargetFlag else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId)#\(effectIndex) partyAttackTarget の種別指定がありません")
            }
        case .spellCharges:
            let hasField = payload.value[.maxCharges] != nil
                || payload.value[.initialCharges] != nil
                || payload.value[.initialBonus] != nil
                || payload.value[.regenEveryTurns] != nil
                || payload.value[.regenAmount] != nil
                || payload.value[.regenCap] != nil
                || payload.value[.gainOnPhysicalHit] != nil
            guard hasField else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId)#\(effectIndex) spellCharges に有効な指定がありません")
            }
        case .absorption:
            let hasValue = payload.value[.percent] != nil || payload.value[.capPercent] != nil
            guard hasValue else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId)#\(effectIndex) absorption が空です")
            }
        case .retreatAtTurn:
            let hasField = payload.value[.turn] != nil || payload.value[.chancePercent] != nil
            guard hasField else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId)#\(effectIndex) retreatAtTurn にturn/chanceがありません")
            }
        default:
            break
        }
    }
}

// MARK: - Validation Requirements
struct SkillEffectValidationRequirement {
    let params: [String]
    let values: [String]
}

let requiredFields: [SkillEffectType: SkillEffectValidationRequirement] = [
    .absorption: .init(params: [], values: []),
    .actionOrderMultiplier: .init(params: [], values: ["multiplier"]),
    .actionOrderShuffle: .init(params: [], values: []),
    .additionalDamageAdditive: .init(params: [], values: ["additive"]),
    .additionalDamageMultiplier: .init(params: [], values: ["multiplier"]),
    .antiHealing: .init(params: [], values: []),
    .barrier: .init(params: ["damageType"], values: ["charges"]),
    .barrierOnGuard: .init(params: ["damageType"], values: ["charges"]),
    .berserk: .init(params: [], values: ["chancePercent"]),
    .breathVariant: .init(params: [], values: ["extraCharges"]),
    .counterAttackEvasionMultiplier: .init(params: [], values: ["multiplier"]),
    .criticalDamageMultiplier: .init(params: [], values: ["multiplier"]),
    .criticalDamagePercent: .init(params: [], values: ["valuePercent"]),
    .criticalDamageTakenMultiplier: .init(params: [], values: ["multiplier"]),
    .damageDealtMultiplier: .init(params: ["damageType"], values: ["multiplier"]),
    .damageDealtMultiplierAgainst: .init(params: [], values: ["multiplier"]),
    .damageDealtPercent: .init(params: ["damageType"], values: []),  // valuePercent or statScale
    .damageTakenMultiplier: .init(params: ["damageType"], values: ["multiplier"]),
    .damageTakenPercent: .init(params: ["damageType"], values: ["valuePercent"]),
    .degradationRepair: .init(params: [], values: []),
    .degradationRepairBoost: .init(params: [], values: ["valuePercent"]),
    .endOfTurnHealing: .init(params: [], values: ["valuePercent"]),
    .endOfTurnSelfHPPercent: .init(params: [], values: ["valuePercent"]),
    .equipmentSlotAdditive: .init(params: [], values: []),
    .equipmentSlotMultiplier: .init(params: [], values: []),
    .equipmentStatMultiplier: .init(params: ["equipmentType"], values: ["multiplier"]),
    .itemStatMultiplier: .init(params: ["statType"], values: ["multiplier"]),
    .explorationTimeMultiplier: .init(params: [], values: ["multiplier"]),
    .martialBonusMultiplier: .init(params: [], values: ["multiplier"]),
    .martialBonusPercent: .init(params: [], values: ["valuePercent"]),
    .minHitScale: .init(params: [], values: ["minHitScale"]),
    .partyAttackFlag: .init(params: [], values: []),
    .partyAttackTarget: .init(params: ["targetId"], values: []),
    .penetrationDamageTakenMultiplier: .init(params: [], values: ["multiplier"]),
    .procMultiplier: .init(params: [], values: ["multiplier"]),
    .procRate: .init(params: ["target", "stacking"], values: []),
    .reaction: .init(params: ["trigger", "action"], values: []),
    .reactionNextTurn: .init(params: [], values: ["count"]),
    .resurrectionActive: .init(params: [], values: ["chancePercent"]),
    .resurrectionBuff: .init(params: [], values: ["guaranteed"]),
    .resurrectionPassive: .init(params: [], values: []),
    .resurrectionSummon: .init(params: [], values: ["everyTurns"]),
    .rewardExperienceMultiplier: .init(params: [], values: ["multiplier"]),
    .rewardExperiencePercent: .init(params: [], values: ["valuePercent"]),
    .rewardGoldMultiplier: .init(params: [], values: ["multiplier"]),
    .rewardGoldPercent: .init(params: [], values: ["valuePercent"]),
    .rewardItemMultiplier: .init(params: [], values: ["multiplier"]),
    .rewardItemPercent: .init(params: [], values: ["valuePercent"]),
    .rewardTitleMultiplier: .init(params: [], values: ["multiplier"]),
    .rewardTitlePercent: .init(params: [], values: ["valuePercent"]),
    .rowProfile: .init(params: ["profile"], values: []),
    .runawayDamage: .init(params: [], values: ["thresholdPercent", "chancePercent"]),
    .runawayMagic: .init(params: [], values: ["thresholdPercent", "chancePercent"]),
    .sacrificeRite: .init(params: [], values: ["everyTurns"]),
    .specialAttack: .init(params: [], values: []),  // specialAttackId or type - validated in handler
    .spellAccess: .init(params: ["spellId"], values: []),
    .spellPowerMultiplier: .init(params: [], values: ["multiplier"]),
    .spellPowerPercent: .init(params: [], values: ["valuePercent"]),
    .spellSpecificMultiplier: .init(params: ["spellId"], values: ["multiplier"]),
    .spellSpecificTakenMultiplier: .init(params: ["spellId"], values: ["multiplier"]),
    .spellTierUnlock: .init(params: ["school"], values: ["tier"]),
    .statusInflict: .init(params: ["statusId"], values: ["baseChancePercent"]),
    .statusResistanceMultiplier: .init(params: ["statusType"], values: ["multiplier"]),
    .statusResistancePercent: .init(params: ["statusType"], values: ["valuePercent"]),
    .tacticSpellAmplify: .init(params: ["spellId"], values: ["multiplier", "triggerTurn"]),
    .timedBreathPowerAmplify: .init(params: [], values: ["triggerTurn", "multiplier"]),
    .timedBuffTrigger: .init(params: [], values: []),
    .timedMagicPowerAmplify: .init(params: [], values: ["triggerTurn", "multiplier"]),
    // 職業スキル用（道化師）
    .enemySingleActionSkipChance: .init(params: [], values: ["chancePercent"]),
    .actionOrderShuffleEnemy: .init(params: [], values: []),
    .firstStrike: .init(params: [], values: []),
    // 職業スキル用（暗殺者）
    .damageDealtMultiplierByTargetHP: .init(params: [], values: ["hpThresholdPercent", "multiplier"]),
    // 職業スキル用（敵ステータス弱体化）
    .statDebuff: .init(params: ["stat", "target"], values: ["valuePercent"])
]

// MARK: - Decoded Payload
struct DecodedSkillEffectPayload: Sendable, Hashable {
    let familyId: UInt16?
    let effectType: SkillEffectType
    let parameters: [EffectParamKey: Int]
    let value: [EffectValueKey: Double]
    let arrays: [EffectArrayKey: [Int]]

    nonisolated func requireParam(_ key: EffectParamKey, skillId: UInt16, effectIndex: Int) throws -> Int {
        guard let value = parameters[key] else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId)#\(effectIndex) \(effectType.identifier) の必須パラメータ \(key) がありません")
        }
        return value
    }

    nonisolated func requireValue(_ key: EffectValueKey, skillId: UInt16, effectIndex: Int) throws -> Double {
        guard let value = self.value[key] else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId)#\(effectIndex) \(effectType.identifier) の必須値 \(key) がありません")
        }
        return value
    }

    nonisolated func requireArray(_ key: EffectArrayKey, skillId: UInt16, effectIndex: Int) throws -> [Int] {
        guard let array = self.arrays[key], !array.isEmpty else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId)#\(effectIndex) \(effectType.identifier) の必須配列 \(key) がありません")
        }
        return array
    }
}

