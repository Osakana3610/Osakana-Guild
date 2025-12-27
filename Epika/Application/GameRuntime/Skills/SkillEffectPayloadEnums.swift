// ==============================================================================
// SkillEffectPayloadEnums.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - スキルエフェクトのパラメータ・値・配列タイプの定義
//   - DBスキーマ（skill_effect_parameters, skill_effect_values, skill_effect_arrays）との対応
//
// 【データ構造】
//   - SkillEffectParamType: パラメータタイプ（42種類、UInt8）
//   - SkillEffectValueType: 数値タイプ（65種類、UInt8）
//   - SkillEffectArrayType: 配列タイプ（3種類、UInt8）
//
// 【使用箇所】
//   - ペイロードのデコード・バリデーション
//   - 文字列識別子との相互変換
//
// ==============================================================================

import Foundation

/// スキルエフェクトのパラメータタイプ（skill_effect_parameters.param_type）
enum SkillEffectParamType: UInt8, CaseIterable, Sendable, Hashable {
    case damageType = 1
    case scope = 2
    case trigger = 3
    case target = 4
    case statusId = 5
    case scalingStat = 6
    case school = 7
    case stat = 8
    case statType = 9
    case action = 10
    case buffType = 11
    case condition = 12
    case dungeonName = 13
    case equipmentCategory = 14
    case equipmentType = 15
    case farApt = 16
    case from = 17
    case mode = 18
    case nearApt = 19
    case preference = 20
    case procType = 21
    case profile = 22
    case requiresAllyBehind = 23
    case requiresMartial = 24
    case sourceStat = 25
    case specialAttackId = 26
    case spellId = 27
    case stacking = 28
    case status = 29
    case statusType = 30
    case targetId = 31
    case targetStat = 32
    case to = 33
    case type = 34
    case variant = 35
    case hpScale = 36
    case targetStatus = 37

    init?(identifier: String) {
        switch identifier {
        case "damageType": self = .damageType
        case "scope": self = .scope
        case "trigger": self = .trigger
        case "target": self = .target
        case "statusId": self = .statusId
        case "scalingStat": self = .scalingStat
        case "school": self = .school
        case "stat": self = .stat
        case "statType": self = .statType
        case "action": self = .action
        case "buffType": self = .buffType
        case "condition": self = .condition
        case "dungeonName": self = .dungeonName
        case "equipmentCategory": self = .equipmentCategory
        case "equipmentType": self = .equipmentType
        case "farApt": self = .farApt
        case "from": self = .from
        case "mode": self = .mode
        case "nearApt": self = .nearApt
        case "preference": self = .preference
        case "procType": self = .procType
        case "profile": self = .profile
        case "requiresAllyBehind": self = .requiresAllyBehind
        case "requiresMartial": self = .requiresMartial
        case "sourceStat": self = .sourceStat
        case "specialAttackId": self = .specialAttackId
        case "spellId": self = .spellId
        case "stacking": self = .stacking
        case "status": self = .status
        case "statusType": self = .statusType
        case "targetId": self = .targetId
        case "targetStat": self = .targetStat
        case "to": self = .to
        case "type": self = .type
        case "variant": self = .variant
        case "hpScale": self = .hpScale
        case "targetStatus": self = .targetStatus
        default: return nil
        }
    }

    var identifier: String {
        switch self {
        case .damageType: return "damageType"
        case .scope: return "scope"
        case .trigger: return "trigger"
        case .target: return "target"
        case .statusId: return "statusId"
        case .scalingStat: return "scalingStat"
        case .school: return "school"
        case .stat: return "stat"
        case .statType: return "statType"
        case .action: return "action"
        case .buffType: return "buffType"
        case .condition: return "condition"
        case .dungeonName: return "dungeonName"
        case .equipmentCategory: return "equipmentCategory"
        case .equipmentType: return "equipmentType"
        case .farApt: return "farApt"
        case .from: return "from"
        case .mode: return "mode"
        case .nearApt: return "nearApt"
        case .preference: return "preference"
        case .procType: return "procType"
        case .profile: return "profile"
        case .requiresAllyBehind: return "requiresAllyBehind"
        case .requiresMartial: return "requiresMartial"
        case .sourceStat: return "sourceStat"
        case .specialAttackId: return "specialAttackId"
        case .spellId: return "spellId"
        case .stacking: return "stacking"
        case .status: return "status"
        case .statusType: return "statusType"
        case .targetId: return "targetId"
        case .targetStat: return "targetStat"
        case .to: return "to"
        case .type: return "type"
        case .variant: return "variant"
        case .hpScale: return "hpScale"
        case .targetStatus: return "targetStatus"
        }
    }
}

/// スキルエフェクトの数値タイプ（skill_effect_values.value_type）
enum SkillEffectValueType: UInt8, CaseIterable, Sendable, Hashable {
    case valuePercent = 1
    case additive = 2
    case multiplier = 3
    case chancePercent = 4
    case count = 5
    case percent = 6
    case add = 7
    case addPercent = 8
    case cap = 9
    case capPercent = 10
    case deltaPercent = 11
    case maxPercent = 12
    case minPercent = 13
    case bonusPercent = 14
    case baseChancePercent = 15
    case maxChancePercent = 16
    // 17: hpPercent 削除済み
    case hpThresholdPercent = 18
    case thresholdPercent = 19
    case damagePercent = 20
    case damageDealtPercent = 21
    case duration = 22
    case turn = 23
    case triggerTurn = 24
    case everyTurns = 25
    case charges = 26
    case initialCharges = 27
    case extraCharges = 28
    case maxCharges = 29
    case maxTriggers = 30
    case tier = 31
    case points = 32
    case weight = 33
    case minLevel = 34
    case minHitScale = 35
    case maxDodge = 36
    case reduction = 37
    case protect = 38
    case enabled = 39
    case instant = 40
    case guaranteed = 41
    case hostile = 42
    case hostileAll = 43
    case rememberSkills = 44
    case removePenalties = 45
    case usesPriestMagic = 46
    case scalingCoefficient = 47
    case valuePerUnit = 48
    case initialBonus = 49
    case accuracyMultiplier = 50
    case attackCountMultiplier = 51
    case criticalRateMultiplier = 52
    case attackCountPercentPerTurn = 53
    case attackPercentPerTurn = 54
    case defensePercentPerTurn = 55
    case hitRatePerTurn = 56
    case evasionRatePerTurn = 57
    case hitRatePercent = 58
    case gainOnPhysicalHit = 59
    case regenAmount = 60
    case regenCap = 61
    case regenEveryTurns = 62
    case vampiricImpulse = 63
    case vampiricSuppression = 64

    init?(identifier: String) {
        switch identifier {
        case "valuePercent": self = .valuePercent
        case "additive": self = .additive
        case "multiplier": self = .multiplier
        case "chancePercent": self = .chancePercent
        case "count": self = .count
        case "percent": self = .percent
        case "add": self = .add
        case "addPercent": self = .addPercent
        case "cap": self = .cap
        case "capPercent": self = .capPercent
        case "deltaPercent": self = .deltaPercent
        case "maxPercent": self = .maxPercent
        case "minPercent": self = .minPercent
        case "bonusPercent": self = .bonusPercent
        case "baseChancePercent": self = .baseChancePercent
        case "maxChancePercent": self = .maxChancePercent
        case "hpThresholdPercent": self = .hpThresholdPercent
        case "thresholdPercent": self = .thresholdPercent
        case "damagePercent": self = .damagePercent
        case "damageDealtPercent": self = .damageDealtPercent
        case "duration": self = .duration
        case "turn": self = .turn
        case "triggerTurn": self = .triggerTurn
        case "everyTurns": self = .everyTurns
        case "charges": self = .charges
        case "initialCharges": self = .initialCharges
        case "extraCharges": self = .extraCharges
        case "maxCharges": self = .maxCharges
        case "maxTriggers": self = .maxTriggers
        case "tier": self = .tier
        case "points": self = .points
        case "weight": self = .weight
        case "minLevel": self = .minLevel
        case "minHitScale": self = .minHitScale
        case "maxDodge": self = .maxDodge
        case "reduction": self = .reduction
        case "protect": self = .protect
        case "enabled": self = .enabled
        case "instant": self = .instant
        case "guaranteed": self = .guaranteed
        case "hostile": self = .hostile
        case "hostileAll": self = .hostileAll
        case "rememberSkills": self = .rememberSkills
        case "removePenalties": self = .removePenalties
        case "usesPriestMagic": self = .usesPriestMagic
        case "scalingCoefficient": self = .scalingCoefficient
        case "valuePerUnit": self = .valuePerUnit
        case "initialBonus": self = .initialBonus
        case "accuracyMultiplier": self = .accuracyMultiplier
        case "attackCountMultiplier": self = .attackCountMultiplier
        case "criticalRateMultiplier": self = .criticalRateMultiplier
        case "attackCountPercentPerTurn": self = .attackCountPercentPerTurn
        case "attackPercentPerTurn": self = .attackPercentPerTurn
        case "defensePercentPerTurn": self = .defensePercentPerTurn
        case "hitRatePerTurn": self = .hitRatePerTurn
        case "evasionRatePerTurn": self = .evasionRatePerTurn
        case "hitRatePercent": self = .hitRatePercent
        case "gainOnPhysicalHit": self = .gainOnPhysicalHit
        case "regenAmount": self = .regenAmount
        case "regenCap": self = .regenCap
        case "regenEveryTurns": self = .regenEveryTurns
        case "vampiricImpulse": self = .vampiricImpulse
        case "vampiricSuppression": self = .vampiricSuppression
        default: return nil
        }
    }

    var identifier: String {
        switch self {
        case .valuePercent: return "valuePercent"
        case .additive: return "additive"
        case .multiplier: return "multiplier"
        case .chancePercent: return "chancePercent"
        case .count: return "count"
        case .percent: return "percent"
        case .add: return "add"
        case .addPercent: return "addPercent"
        case .cap: return "cap"
        case .capPercent: return "capPercent"
        case .deltaPercent: return "deltaPercent"
        case .maxPercent: return "maxPercent"
        case .minPercent: return "minPercent"
        case .bonusPercent: return "bonusPercent"
        case .baseChancePercent: return "baseChancePercent"
        case .maxChancePercent: return "maxChancePercent"
        case .hpThresholdPercent: return "hpThresholdPercent"
        case .thresholdPercent: return "thresholdPercent"
        case .damagePercent: return "damagePercent"
        case .damageDealtPercent: return "damageDealtPercent"
        case .duration: return "duration"
        case .turn: return "turn"
        case .triggerTurn: return "triggerTurn"
        case .everyTurns: return "everyTurns"
        case .charges: return "charges"
        case .initialCharges: return "initialCharges"
        case .extraCharges: return "extraCharges"
        case .maxCharges: return "maxCharges"
        case .maxTriggers: return "maxTriggers"
        case .tier: return "tier"
        case .points: return "points"
        case .weight: return "weight"
        case .minLevel: return "minLevel"
        case .minHitScale: return "minHitScale"
        case .maxDodge: return "maxDodge"
        case .reduction: return "reduction"
        case .protect: return "protect"
        case .enabled: return "enabled"
        case .instant: return "instant"
        case .guaranteed: return "guaranteed"
        case .hostile: return "hostile"
        case .hostileAll: return "hostileAll"
        case .rememberSkills: return "rememberSkills"
        case .removePenalties: return "removePenalties"
        case .usesPriestMagic: return "usesPriestMagic"
        case .scalingCoefficient: return "scalingCoefficient"
        case .valuePerUnit: return "valuePerUnit"
        case .initialBonus: return "initialBonus"
        case .accuracyMultiplier: return "accuracyMultiplier"
        case .attackCountMultiplier: return "attackCountMultiplier"
        case .criticalRateMultiplier: return "criticalRateMultiplier"
        case .attackCountPercentPerTurn: return "attackCountPercentPerTurn"
        case .attackPercentPerTurn: return "attackPercentPerTurn"
        case .defensePercentPerTurn: return "defensePercentPerTurn"
        case .hitRatePerTurn: return "hitRatePerTurn"
        case .evasionRatePerTurn: return "evasionRatePerTurn"
        case .hitRatePercent: return "hitRatePercent"
        case .gainOnPhysicalHit: return "gainOnPhysicalHit"
        case .regenAmount: return "regenAmount"
        case .regenCap: return "regenCap"
        case .regenEveryTurns: return "regenEveryTurns"
        case .vampiricImpulse: return "vampiricImpulse"
        case .vampiricSuppression: return "vampiricSuppression"
        }
    }
}

/// スキルエフェクトの配列タイプ（skill_effect_arrays.array_type）
enum SkillEffectArrayType: UInt8, CaseIterable, Sendable, Hashable {
    case removeSkillIds = 1
    case grantSkillIds = 2
    case targetRaceIds = 3

    init?(identifier: String) {
        switch identifier {
        case "removeSkillIds": self = .removeSkillIds
        case "grantSkillIds": self = .grantSkillIds
        case "targetRaceIds": self = .targetRaceIds
        default: return nil
        }
    }

    var identifier: String {
        switch self {
        case .removeSkillIds: return "removeSkillIds"
        case .grantSkillIds: return "grantSkillIds"
        case .targetRaceIds: return "targetRaceIds"
        }
    }
}
