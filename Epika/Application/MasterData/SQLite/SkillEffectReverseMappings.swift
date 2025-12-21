// ==============================================================================
// SkillEffectReverseMappings.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - SQLiteのスキルエフェクトテーブルに格納された整数値を文字列に逆変換
//   - param_type, value_type, array_type のマッピング定義を提供
//   - パラメータ値の型に応じた適切な文字列変換ロジック
//
// 【データ構造】
//   - Sendable structで全てのマッピングをstatic letで定義
//   - paramType: INT → String key（例: 1 → "action"）
//   - valueType: INT → String key（例: 1 → "accuracyMultiplier"）
//   - arrayType: INT → String key（例: 1 → "grantSkillIds"）
//   - 各種enumマッピング（damageType, baseStat, combatStat等）
//
// 【使用箇所】
//   - SQLiteMasterDataQueries.Skills.swift（fetchAllSkillsメソッド）
//
// ==============================================================================

import Foundation

/// skill_effect_params, skill_effect_values, skill_effect_array_values テーブルの
/// 整数値を文字列キー/値に逆変換するためのマッピング
struct SkillEffectReverseMappings: Sendable {
    private init() {}  // インスタンス化を禁止

    // MARK: - Param Type (INT → String key)

    nonisolated static let paramType: [Int: String] = [
        1: "action",
        2: "buffType",
        3: "condition",
        4: "damageType",
        5: "dungeonName",
        6: "equipmentCategory",
        7: "equipmentType",
        8: "farApt",
        9: "from",
        10: "mode",
        11: "nearApt",
        12: "preference",
        13: "procType",
        14: "profile",
        15: "requiresAllyBehind",
        16: "requiresMartial",
        17: "scalingStat",
        18: "school",
        19: "sourceStat",
        20: "specialAttackId",
        21: "spellId",
        22: "stacking",
        23: "stat",
        24: "statType",
        25: "status",
        26: "statusId",
        27: "statusType",
        28: "target",
        29: "targetId",
        30: "targetStat",
        31: "to",
        32: "trigger",
        33: "type",
        34: "variant",
        35: "hpScale",
        36: "targetStatus"
    ]

    // MARK: - Value Type (INT → String key)

    nonisolated static let valueType: [Int: String] = [
        1: "accuracyMultiplier",
        2: "add",
        3: "addPercent",
        4: "additive",
        5: "attackCountMultiplier",
        6: "attackCountPercentPerTurn",
        7: "attackPercentPerTurn",
        8: "baseChancePercent",
        9: "bonusPercent",
        10: "cap",
        11: "capPercent",
        12: "chancePercent",
        13: "charges",
        14: "count",
        15: "criticalRateMultiplier",
        16: "damageDealtPercent",
        17: "damagePercent",
        18: "defensePercentPerTurn",
        19: "deltaPercent",
        20: "duration",
        21: "enabled",
        22: "evasionRatePerTurn",
        23: "everyTurns",
        24: "extraCharges",
        25: "gainOnPhysicalHit",
        26: "guaranteed",
        27: "hitRatePerTurn",
        28: "hitRatePercent",
        29: "hostile",
        30: "hostileAll",
        31: "hpPercent",
        32: "hpThresholdPercent",
        33: "initialBonus",
        34: "initialCharges",
        35: "instant",
        36: "maxChancePercent",
        37: "maxCharges",
        38: "maxDodge",
        39: "maxPercent",
        40: "maxTriggers",
        41: "minHitScale",
        42: "minLevel",
        43: "minPercent",
        44: "multiplier",
        45: "percent",
        46: "points",
        47: "protect",
        48: "reduction",
        49: "regenAmount",
        50: "regenCap",
        51: "regenEveryTurns",
        52: "rememberSkills",
        53: "removePenalties",
        54: "scalingCoefficient",
        55: "thresholdPercent",
        56: "tier",
        57: "triggerTurn",
        58: "turn",
        59: "usesPriestMagic",
        60: "valuePerUnit",
        61: "valuePercent",
        62: "vampiricImpulse",
        63: "vampiricSuppression",
        64: "weight"
    ]

    // MARK: - Array Type (INT → String key)

    nonisolated static let arrayType: [Int: String] = [
        1: "grantSkillIds",
        2: "removeSkillIds",
        3: "targetRaceIds"
    ]

    // MARK: - Param Value Reverse Mappings

    /// damageType: INT → String
    nonisolated static let damageType: [Int: String] = [
        1: "physical",
        2: "magical",
        3: "breath",
        4: "penetration",
        5: "healing",
        99: "all"
    ]

    /// baseStat: INT → String
    nonisolated static let baseStat: [Int: String] = [
        1: "strength",
        2: "wisdom",
        3: "spirit",
        4: "vitality",
        5: "agility",
        6: "luck"
    ]

    /// combatStat: INT → String
    nonisolated static let combatStat: [Int: String] = [
        10: "maxHP",
        11: "physicalAttack",
        12: "magicalAttack",
        13: "physicalDefense",
        14: "magicalDefense",
        15: "hitRate",
        16: "evasionRate",
        17: "criticalRate",
        18: "attackCount",
        19: "magicalHealing",
        20: "trapRemoval",
        21: "additionalDamage",
        22: "breathDamage",
        99: "all"
    ]

    /// spellSchool: INT → String
    nonisolated static let spellSchool: [Int: String] = [
        1: "mage",
        2: "priest"
    ]

    /// spellBuffType: INT → String
    nonisolated static let spellBuffType: [Int: String] = [
        1: "physicalDamageDealt",
        2: "physicalDamageTaken",
        3: "magicalDamageTaken",
        4: "breathDamageTaken",
        5: "physicalAttack",
        6: "magicalAttack",
        7: "physicalDefense",
        8: "accuracy",
        9: "attackCount",
        10: "combat",
        11: "damage"
    ]

    /// itemCategory: INT → String
    nonisolated static let itemCategory: [Int: String] = [
        1: "thin_sword",
        2: "sword",
        3: "magic_sword",
        4: "advanced_magic_sword",
        5: "guardian_sword",
        6: "katana",
        7: "bow",
        8: "armor",
        9: "heavy_armor",
        10: "super_heavy_armor",
        11: "shield",
        12: "gauntlet",
        13: "accessory",
        14: "wand",
        15: "rod",
        16: "grimoire",
        17: "robe",
        18: "gem",
        19: "homunculus",
        20: "synthesis",
        21: "other",
        22: "race_specific",
        23: "for_synthesis",
        24: "mazo_material",
        25: "dagger"
    ]

    /// triggerType: INT → String
    nonisolated static let triggerType: [Int: String] = [
        1: "afterTurn8",
        2: "allyDamagedPhysical",
        3: "allyDefeated",
        4: "allyMagicAttack",
        5: "battleStart",
        6: "selfAttackNoKill",
        7: "selfDamagedMagical",
        8: "selfDamagedPhysical",
        9: "selfEvadePhysical",
        10: "selfKilledEnemy",
        11: "selfMagicAttack",
        12: "turnElapsed",
        13: "turnStart"
    ]

    /// effectModeType: INT → String
    nonisolated static let effectModeType: [Int: String] = [
        1: "preemptive"
    ]

    /// effectActionType: INT → String
    nonisolated static let effectActionType: [Int: String] = [
        1: "breathCounter",
        2: "counterAttack",
        3: "extraAttack",
        4: "forget",
        5: "learn",
        6: "magicCounter",
        7: "partyHeal",
        8: "physicalCounter",
        9: "physicalPursuit"
    ]

    /// stackingType: INT → String
    nonisolated static let stackingType: [Int: String] = [
        1: "add",
        2: "additive",
        3: "multiply"
    ]

    /// effectVariantType: INT → String
    nonisolated static let effectVariantType: [Int: String] = [
        1: "betweenFloors",
        2: "breath",
        3: "cold",
        4: "fire",
        5: "thunder"
    ]

    /// profileType: INT → String
    nonisolated static let profileType: [Int: String] = [
        1: "balanced",
        2: "melee",
        3: "mixed",
        4: "ranged"
    ]

    /// conditionType: INT → String
    nonisolated static let conditionType: [Int: String] = [
        1: "allyHPBelow50"
    ]

    /// preferenceType: INT → String
    nonisolated static let preferenceType: [Int: String] = [
        1: "backRow"
    ]

    /// procTypeValue: INT → String
    nonisolated static let procTypeValue: [Int: String] = [
        1: "counter",
        2: "counterOnEvade",
        3: "extraAction",
        4: "firstStrike",
        5: "parry",
        6: "pursuit"
    ]

    /// dungeonNameValue: INT → String
    nonisolated static let dungeonNameValue: [Int: String] = [
        1: "バベルの塔"
    ]

    /// hpScaleType: INT → String
    nonisolated static let hpScaleType: [Int: String] = [
        1: "magicalHealing"
    ]

    /// targetType: INT → String
    nonisolated static let targetType: [Int: String] = [
        1: "ally",
        2: "attacker",
        3: "breathCounter",
        4: "counter",
        5: "crisisEvasion",
        6: "criticalCombo",
        7: "enemy",
        8: "fightingSpirit",
        9: "instantResurrection",
        10: "killer",
        11: "magicCounter",
        12: "magicSupport",
        13: "manaDecomposition",
        14: "party",
        15: "pursuit",
        16: "reattack",
        17: "reflectionRecovery",
        18: "self"
    ]

    /// targetIdValue: INT → String
    nonisolated static let targetIdValue: [Int: String] = [
        1: "human",
        2: "special_a",
        3: "special_b",
        4: "special_c",
        5: "vampire"
    ]

    /// specialAttackIdValue: INT → String
    nonisolated static let specialAttackIdValue: [Int: String] = [
        1: "specialA",
        2: "specialB",
        3: "specialC",
        4: "specialD",
        5: "specialE"
    ]

    /// statusTypeValue: INT → String
    nonisolated static let statusTypeValue: [Int: String] = [
        1: "all",
        2: "instantDeath",
        3: "resurrection.active"
    ]

    // MARK: - Resolve Param Value

    /// パラメータタイプに応じて int_value を文字列に変換
    nonisolated static func resolveParamValue(paramType: String, intValue: Int) -> String {
        switch paramType {
        case "damageType":
            return damageType[intValue] ?? String(intValue)
        case "stat", "targetStat", "sourceStat", "scalingStat", "statType", "from", "to":
            return baseStat[intValue] ?? combatStat[intValue] ?? String(intValue)
        case "school":
            return spellSchool[intValue] ?? String(intValue)
        case "buffType":
            return spellBuffType[intValue] ?? String(intValue)
        case "equipmentCategory", "equipmentType":
            return itemCategory[intValue] ?? String(intValue)
        case "status", "statusId", "spellId":
            return String(intValue)
        case "statusType", "targetStatus":
            return statusTypeValue[intValue] ?? String(intValue)
        case "specialAttackId":
            return specialAttackIdValue[intValue] ?? String(intValue)
        case "targetId":
            return targetIdValue[intValue] ?? String(intValue)
        case "trigger":
            return triggerType[intValue] ?? String(intValue)
        case "procType":
            return procTypeValue[intValue] ?? String(intValue)
        case "action":
            return effectActionType[intValue] ?? String(intValue)
        case "mode":
            return effectModeType[intValue] ?? String(intValue)
        case "stacking":
            return stackingType[intValue] ?? String(intValue)
        case "type", "variant":
            return effectVariantType[intValue] ?? String(intValue)
        case "profile":
            return profileType[intValue] ?? String(intValue)
        case "condition":
            return conditionType[intValue] ?? String(intValue)
        case "preference":
            return preferenceType[intValue] ?? String(intValue)
        case "target":
            return targetType[intValue] ?? String(intValue)
        case "requiresAllyBehind", "requiresMartial", "farApt", "nearApt":
            return intValue == 1 ? "true" : "false"
        case "dungeonName":
            return dungeonNameValue[intValue] ?? String(intValue)
        case "hpScale":
            return hpScaleType[intValue] ?? String(intValue)
        default:
            return String(intValue)
        }
    }
}
