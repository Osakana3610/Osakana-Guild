import Foundation

// MARK: - Payload Decoding & Validation
extension SkillRuntimeEffectCompiler {
    static func decodePayload(from effect: SkillDefinition.Effect, skillId: UInt16) throws -> DecodedSkillEffectPayload? {
        do {
            return try SkillEffectPayloadDecoder.decode(effect: effect, fallbackEffectType: effect.kind)
        } catch {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId) の payload を解析できません: \(error)")
        }
    }

    static func validatePayload(_ payload: DecodedSkillEffectPayload,
                                skillId: UInt16,
                                effectIndex: Int) throws {
        if let requirements = requiredFields[payload.effectType] {
            for key in requirements.params {
                guard let value = payload.parameters?[key], !value.isEmpty else {
                    throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId)#\(effectIndex) \(payload.effectType.rawValue) の必須パラメータ \(key) が不足しています")
                }
            }
            for key in requirements.values {
                guard payload.value[key] != nil else {
                    throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId)#\(effectIndex) \(payload.effectType.rawValue) の必須値 \(key) が不足しています")
                }
            }
        }

        switch payload.effectType {
        case .extraAction:
            let chance = payload.value["chancePercent"] ?? payload.value["valuePercent"]
            guard chance != nil else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId)#\(effectIndex) extraAction にchanceがありません")
            }
        case .partyAttackFlag:
            let hasFlag = payload.value["hostileAll"] != nil
                || payload.value["vampiricImpulse"] != nil
                || payload.value["vampiricSuppression"] != nil
            guard hasFlag else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId)#\(effectIndex) partyAttackFlag が空です")
            }
        case .partyAttackTarget:
            let hasTargetFlag = payload.value["hostile"] != nil || payload.value["protect"] != nil
            guard hasTargetFlag else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId)#\(effectIndex) partyAttackTarget の種別指定がありません")
            }
        case .spellCharges:
            let hasField = payload.value["maxCharges"] != nil
                || payload.value["initialCharges"] != nil
                || payload.value["initialBonus"] != nil
                || payload.value["regenEveryTurns"] != nil
                || payload.value["regenAmount"] != nil
                || payload.value["regenCap"] != nil
                || payload.value["gainOnPhysicalHit"] != nil
            guard hasField else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId)#\(effectIndex) spellCharges に有効な指定がありません")
            }
        case .absorption:
            let hasValue = payload.value["percent"] != nil || payload.value["capPercent"] != nil
            guard hasValue else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId)#\(effectIndex) absorption が空です")
            }
        case .retreatAtTurn:
            let hasField = payload.value["turn"] != nil || payload.value["chancePercent"] != nil
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
    .damageDealtMultiplierAgainst: .init(params: ["targetCategory"], values: ["multiplier"]),
    .damageDealtPercent: .init(params: ["damageType"], values: ["valuePercent"]),
    .damageTakenMultiplier: .init(params: ["damageType"], values: ["multiplier"]),
    .damageTakenPercent: .init(params: ["damageType"], values: ["valuePercent"]),
    .degradationRepair: .init(params: [], values: []),
    .degradationRepairBoost: .init(params: [], values: ["valuePercent"]),
    .endOfTurnHealing: .init(params: [], values: ["valuePercent"]),
    .endOfTurnSelfHPPercent: .init(params: [], values: ["valuePercent"]),
    .equipmentSlotAdditive: .init(params: [], values: []),
    .equipmentSlotMultiplier: .init(params: [], values: []),
    .equipmentStatMultiplier: .init(params: ["equipmentCategory"], values: ["multiplier"]),
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
    .specialAttack: .init(params: ["specialAttackId"], values: []),
    .spellAccess: .init(params: ["spellId"], values: []),
    .spellPowerMultiplier: .init(params: [], values: ["multiplier"]),
    .spellPowerPercent: .init(params: [], values: ["valuePercent"]),
    .spellSpecificMultiplier: .init(params: ["spellId"], values: ["multiplier"]),
    .spellSpecificTakenMultiplier: .init(params: ["spellId"], values: ["multiplier"]),
    .spellTierUnlock: .init(params: ["school"], values: ["tier"]),
    .statusInflict: .init(params: ["statusId"], values: ["baseChancePercent"]),
    .statusResistanceMultiplier: .init(params: ["status"], values: ["multiplier"]),
    .statusResistancePercent: .init(params: ["status"], values: ["valuePercent"]),
    .tacticSpellAmplify: .init(params: ["spellId"], values: ["multiplier", "triggerTurn"]),
    .timedBreathPowerAmplify: .init(params: [], values: ["triggerTurn", "multiplier"]),
    .timedBuffTrigger: .init(params: [], values: ["triggerTurn"]),
    .timedMagicPowerAmplify: .init(params: [], values: ["triggerTurn", "multiplier"])
]

// MARK: - Decoded Payload
struct DecodedSkillEffectPayload: Sendable, Hashable {
    let familyId: String?
    let effectType: SkillEffectType
    let parameters: [String: String]?
    let value: [String: Double]
    let stringValues: [String: String]
    let stringArrayValues: [String: [String]]

    func requireParam(_ key: String, skillId: UInt16, effectIndex: Int) throws -> String {
        guard let value = parameters?[key], !value.isEmpty else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId)#\(effectIndex) \(effectType.rawValue) の必須パラメータ \(key) がありません")
        }
        return value
    }

    func requireValue(_ key: String, skillId: UInt16, effectIndex: Int) throws -> Double {
        guard let value = self.value[key] else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId)#\(effectIndex) \(effectType.rawValue) の必須値 \(key) がありません")
        }
        return value
    }

    func requireStringArray(_ key: String, skillId: UInt16, effectIndex: Int) throws -> [String] {
        guard let array = self.stringArrayValues[key] else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId)#\(effectIndex) \(effectType.rawValue) の必須配列 \(key) がありません")
        }
        return array
    }
}

// MARK: - Payload Decoder
enum SkillEffectPayloadDecoder {
    static func decode(effect: SkillDefinition.Effect, fallbackEffectType: String) throws -> DecodedSkillEffectPayload? {
        guard !effect.payloadJSON.isEmpty,
              let data = effect.payloadJSON.data(using: .utf8) else {
            return nil
        }
        let raw = try decoder.decode(RawPayload.self, from: data)
        let resolvedEffectType = (raw.effectType ?? raw.type ?? fallbackEffectType).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedEffectType.isEmpty else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(fallbackEffectType) の effectType が不正です")
        }
        guard let effectType = SkillEffectType(rawValue: resolvedEffectType) else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(fallbackEffectType) の effectType \(resolvedEffectType) は未対応です")
        }

        let values = SkillEffectPayloadValues.from(rawValues: raw.value,
                                                   stringValues: raw.stringValues,
                                                   stringArrayValues: raw.stringArrayValues)
        return DecodedSkillEffectPayload(
            familyId: raw.familyId,
            effectType: effectType,
            parameters: raw.parameters,
            value: values.numericValues,
            stringValues: values.stringValues,
            stringArrayValues: values.stringArrayValues
        )
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private struct RawPayload: Decodable {
        let familyId: String?
        let effectType: String?
        let type: String?
        let parameters: [String: String]?
        let value: [String: SkillEffectFlexibleValue]?
        let stringValues: [String: String]?
        let stringArrayValues: [String: [String]]?
    }
}
