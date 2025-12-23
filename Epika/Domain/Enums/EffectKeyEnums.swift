import Foundation

// MARK: - EffectParamKey

/// スキルエフェクトのパラメータキー
/// rawValue: EnumMappings.skillEffectParamType
enum EffectParamKey: Int, Sendable, Hashable, CaseIterable {
    case action = 1
    case buffType = 2
    case condition = 3
    case damageType = 4
    case dungeonName = 5
    case equipmentCategory = 6
    case equipmentType = 7
    case farApt = 8
    case from = 9
    case mode = 10
    case nearApt = 11
    case preference = 12
    case procType = 13
    case profile = 14
    case requiresAllyBehind = 15
    case requiresMartial = 16
    case scalingStat = 17
    case school = 18
    case sourceStat = 19
    case specialAttackId = 20
    case spellId = 21
    case stacking = 22
    case stat = 23
    case statType = 24
    case status = 25
    case statusId = 26
    case statusType = 27
    case target = 28
    case targetId = 29
    case targetStat = 30
    case to = 31
    case trigger = 32
    case type = 33
    case variant = 34
    case hpScale = 35
    case targetStatus = 36
}

// MARK: - EffectValueKey

/// スキルエフェクトの値キー
/// rawValue: EnumMappings.skillEffectValueType
enum EffectValueKey: Int, Sendable, Hashable, CaseIterable {
    case accuracyMultiplier = 1
    case add = 2
    case addPercent = 3
    case additive = 4
    case attackCountMultiplier = 5
    case attackCountPercentPerTurn = 6
    case attackPercentPerTurn = 7
    case baseChancePercent = 8
    case bonusPercent = 9
    case cap = 10
    case capPercent = 11
    case chancePercent = 12
    case charges = 13
    case count = 14
    case criticalRateMultiplier = 15
    case damageDealtPercent = 16
    case damagePercent = 17
    case defensePercentPerTurn = 18
    case deltaPercent = 19
    case duration = 20
    case enabled = 21
    case evasionRatePerTurn = 22
    case everyTurns = 23
    case extraCharges = 24
    case gainOnPhysicalHit = 25
    case guaranteed = 26
    case hitRatePerTurn = 27
    case hitRatePercent = 28
    case hostile = 29
    case hostileAll = 30
    case hpPercent = 31
    case hpThresholdPercent = 32
    case initialBonus = 33
    case initialCharges = 34
    case instant = 35
    case maxChancePercent = 36
    case maxCharges = 37
    case maxDodge = 38
    case maxPercent = 39
    case maxTriggers = 40
    case minHitScale = 41
    case minLevel = 42
    case minPercent = 43
    case multiplier = 44
    case percent = 45
    case points = 46
    case protect = 47
    case reduction = 48
    case regenAmount = 49
    case regenCap = 50
    case regenEveryTurns = 51
    case rememberSkills = 52
    case removePenalties = 53
    case scalingCoefficient = 54
    case thresholdPercent = 55
    case tier = 56
    case triggerTurn = 57
    case turn = 58
    case usesPriestMagic = 59
    case valuePerUnit = 60
    case valuePercent = 61
    case vampiricImpulse = 62
    case vampiricSuppression = 63
    case weight = 64
}

// MARK: - EffectArrayKey

/// スキルエフェクトの配列キー
/// rawValue: EnumMappings.skillEffectArrayType
enum EffectArrayKey: Int, Sendable, Hashable, CaseIterable {
    case grantSkillIds = 1
    case removeSkillIds = 2
    case targetRaceIds = 3
}
