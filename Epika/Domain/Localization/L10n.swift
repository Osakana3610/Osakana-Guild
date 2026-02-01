import Foundation

enum L10n {
    enum Key: String, CaseIterable {
        case baseStatStrength = "baseStat.strength"
        case baseStatWisdom = "baseStat.wisdom"
        case baseStatSpirit = "baseStat.spirit"
        case baseStatVitality = "baseStat.vitality"
        case baseStatAgility = "baseStat.agility"
        case baseStatLuck = "baseStat.luck"
        case baseStatStrengthShort = "baseStat.strength.short"
        case baseStatWisdomShort = "baseStat.wisdom.short"
        case baseStatSpiritShort = "baseStat.spirit.short"
        case baseStatVitalityShort = "baseStat.vitality.short"
        case baseStatAgilityShort = "baseStat.agility.short"
        case baseStatLuckShort = "baseStat.luck.short"
        case combatStatMaxHP = "combatStat.maxHP"
        case combatStatPhysicalAttack = "combatStat.physicalAttack"
        case combatStatPhysicalAttackMartial = "combatStat.physicalAttack.martial"
        case combatStatMagicalAttack = "combatStat.magicalAttack"
        case combatStatPhysicalDefense = "combatStat.physicalDefense"
        case combatStatMagicalDefense = "combatStat.magicalDefense"
        case combatStatHit = "combatStat.hit"
        case combatStatEvasion = "combatStat.evasion"
        case combatStatCriticalChancePercent = "combatStat.criticalChancePercent"
        case combatStatAttackCount = "combatStat.attackCount"
        case combatStatMagicalHealing = "combatStat.magicalHealing"
        case combatStatTrapRemoval = "combatStat.trapRemoval"
        case combatStatAdditionalDamage = "combatStat.additionalDamage"
        case combatStatBreathDamage = "combatStat.breathDamage"
        case combatStatMaxHPShort = "combatStat.maxHP.short"
        case combatStatPhysicalAttackShort = "combatStat.physicalAttack.short"
        case combatStatMagicalAttackShort = "combatStat.magicalAttack.short"
        case combatStatPhysicalDefenseShort = "combatStat.physicalDefense.short"
        case combatStatMagicalDefenseShort = "combatStat.magicalDefense.short"
        case combatStatHitShort = "combatStat.hit.short"
        case combatStatEvasionShort = "combatStat.evasion.short"
        case combatStatCriticalChancePercentShort = "combatStat.criticalChancePercent.short"
        case combatStatAttackCountShort = "combatStat.attackCount.short"
        case combatStatMagicalHealingShort = "combatStat.magicalHealing.short"
        case combatStatTrapRemovalShort = "combatStat.trapRemoval.short"
        case combatStatAdditionalDamageShort = "combatStat.additionalDamage.short"
        case combatStatBreathDamageShort = "combatStat.breathDamage.short"
        case actionPreferenceAttack = "actionPreference.attack"
        case actionPreferencePriestMagic = "actionPreference.priestMagic"
        case actionPreferenceMageMagic = "actionPreference.mageMagic"
        case actionPreferenceBreath = "actionPreference.breath"
        case modifierConditional = "modifier.conditional"
        case resistancePhysical = "resistance.physical"
        case resistancePiercing = "resistance.piercing"
        case resistanceCritical = "resistance.critical"
        case resistanceBreath = "resistance.breath"
        case damageModifierPhysicalDamageDealt = "damageModifier.physicalDamageDealt"
        case damageModifierPhysicalDamageTaken = "damageModifier.physicalDamageTaken"
        case damageModifierMagicalDamageTaken = "damageModifier.magicalDamageTaken"
        case damageModifierBreathDamageTaken = "damageModifier.breathDamageTaken"
        case battleTermReactionAttack = "battleTerm.reactionAttack"
        case battleTermFollowUp = "battleTerm.followUp"
        case battleTermRetaliation = "battleTerm.retaliation"
        case battleTermExtraAttack = "battleTerm.extraAttack"
        case battleTermMartialFollowUp = "battleTerm.martialFollowUp"
        case battleTermRescue = "battleTerm.rescue"

        nonisolated var defaultValue: String {
            switch self {
            case .baseStatStrength: return "力"
            case .baseStatWisdom: return "知恵"
            case .baseStatSpirit: return "精神"
            case .baseStatVitality: return "体力"
            case .baseStatAgility: return "敏捷"
            case .baseStatLuck: return "運"
            case .baseStatStrengthShort: return "力"
            case .baseStatWisdomShort: return "知"
            case .baseStatSpiritShort: return "精"
            case .baseStatVitalityShort: return "体"
            case .baseStatAgilityShort: return "速"
            case .baseStatLuckShort: return "運"
            case .combatStatMaxHP: return "最大HP"
            case .combatStatPhysicalAttack: return "物理攻撃"
            case .combatStatPhysicalAttackMartial: return "物理攻撃(格闘)"
            case .combatStatMagicalAttack: return "魔法攻撃"
            case .combatStatPhysicalDefense: return "物理防御"
            case .combatStatMagicalDefense: return "魔法防御"
            case .combatStatHit: return "命中"
            case .combatStatEvasion: return "回避"
            case .combatStatCriticalChancePercent: return "必殺率"
            case .combatStatAttackCount: return "攻撃回数"
            case .combatStatMagicalHealing: return "魔法回復力"
            case .combatStatTrapRemoval: return "罠解除"
            case .combatStatAdditionalDamage: return "追加ダメージ"
            case .combatStatBreathDamage: return "ブレスダメージ"
            case .combatStatMaxHPShort: return "HP"
            case .combatStatPhysicalAttackShort: return "物攻"
            case .combatStatMagicalAttackShort: return "魔攻"
            case .combatStatPhysicalDefenseShort: return "物防"
            case .combatStatMagicalDefenseShort: return "魔防"
            case .combatStatHitShort: return "命中"
            case .combatStatEvasionShort: return "回避"
            case .combatStatCriticalChancePercentShort: return "必殺率"
            case .combatStatAttackCountShort: return "攻撃回数"
            case .combatStatMagicalHealingShort: return "魔法回復力"
            case .combatStatTrapRemovalShort: return "罠解除"
            case .combatStatAdditionalDamageShort: return "追加ダメージ"
            case .combatStatBreathDamageShort: return "ブレスダメージ"
            case .actionPreferenceAttack: return "物理攻撃"
            case .actionPreferencePriestMagic: return "僧侶魔法"
            case .actionPreferenceMageMagic: return "魔法使い魔法"
            case .actionPreferenceBreath: return "ブレス"
            case .modifierConditional: return "条件付き"
            case .resistancePhysical: return "物理"
            case .resistancePiercing: return "貫通"
            case .resistanceCritical: return "必殺"
            case .resistanceBreath: return "ブレス"
            case .damageModifierPhysicalDamageDealt: return "与物理ダメージ"
            case .damageModifierPhysicalDamageTaken: return "被物理ダメージ"
            case .damageModifierMagicalDamageTaken: return "被魔法ダメージ"
            case .damageModifierBreathDamageTaken: return "被ブレスダメージ"
            case .battleTermReactionAttack: return "反撃"
            case .battleTermFollowUp: return "追撃"
            case .battleTermRetaliation: return "報復"
            case .battleTermExtraAttack: return "再攻撃"
            case .battleTermMartialFollowUp: return "格闘追撃"
            case .battleTermRescue: return "救出"
            }
        }
    }

    nonisolated private static func text(_ key: Key) -> String {
        NSLocalizedString(key.rawValue, tableName: nil, bundle: .main, value: key.defaultValue, comment: "")
    }

    nonisolated static func battleLog(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: "", comment: "")
    }

    enum BaseStat {
        nonisolated static var strength: String { L10n.text(.baseStatStrength) }
        nonisolated static var wisdom: String { L10n.text(.baseStatWisdom) }
        nonisolated static var spirit: String { L10n.text(.baseStatSpirit) }
        nonisolated static var vitality: String { L10n.text(.baseStatVitality) }
        nonisolated static var agility: String { L10n.text(.baseStatAgility) }
        nonisolated static var luck: String { L10n.text(.baseStatLuck) }

        nonisolated static var strengthShort: String { L10n.text(.baseStatStrengthShort) }
        nonisolated static var wisdomShort: String { L10n.text(.baseStatWisdomShort) }
        nonisolated static var spiritShort: String { L10n.text(.baseStatSpiritShort) }
        nonisolated static var vitalityShort: String { L10n.text(.baseStatVitalityShort) }
        nonisolated static var agilityShort: String { L10n.text(.baseStatAgilityShort) }
        nonisolated static var luckShort: String { L10n.text(.baseStatLuckShort) }
    }

    enum CombatStat {
        nonisolated static var maxHP: String { L10n.text(.combatStatMaxHP) }
        nonisolated static var physicalAttack: String { L10n.text(.combatStatPhysicalAttack) }
        nonisolated static var physicalAttackMartial: String { L10n.text(.combatStatPhysicalAttackMartial) }
        nonisolated static var magicalAttack: String { L10n.text(.combatStatMagicalAttack) }
        nonisolated static var physicalDefense: String { L10n.text(.combatStatPhysicalDefense) }
        nonisolated static var magicalDefense: String { L10n.text(.combatStatMagicalDefense) }
        nonisolated static var hit: String { L10n.text(.combatStatHit) }
        nonisolated static var evasion: String { L10n.text(.combatStatEvasion) }
        nonisolated static var criticalChancePercent: String { L10n.text(.combatStatCriticalChancePercent) }
        nonisolated static var attackCount: String { L10n.text(.combatStatAttackCount) }
        nonisolated static var magicalHealing: String { L10n.text(.combatStatMagicalHealing) }
        nonisolated static var trapRemoval: String { L10n.text(.combatStatTrapRemoval) }
        nonisolated static var additionalDamage: String { L10n.text(.combatStatAdditionalDamage) }
        nonisolated static var breathDamage: String { L10n.text(.combatStatBreathDamage) }

        nonisolated static var maxHPShort: String { L10n.text(.combatStatMaxHPShort) }
        nonisolated static var physicalAttackShort: String { L10n.text(.combatStatPhysicalAttackShort) }
        nonisolated static var magicalAttackShort: String { L10n.text(.combatStatMagicalAttackShort) }
        nonisolated static var physicalDefenseShort: String { L10n.text(.combatStatPhysicalDefenseShort) }
        nonisolated static var magicalDefenseShort: String { L10n.text(.combatStatMagicalDefenseShort) }
        nonisolated static var hitShort: String { L10n.text(.combatStatHitShort) }
        nonisolated static var evasionShort: String { L10n.text(.combatStatEvasionShort) }
        nonisolated static var criticalChancePercentShort: String { L10n.text(.combatStatCriticalChancePercentShort) }
        nonisolated static var attackCountShort: String { L10n.text(.combatStatAttackCountShort) }
        nonisolated static var magicalHealingShort: String { L10n.text(.combatStatMagicalHealingShort) }
        nonisolated static var trapRemovalShort: String { L10n.text(.combatStatTrapRemovalShort) }
        nonisolated static var additionalDamageShort: String { L10n.text(.combatStatAdditionalDamageShort) }
        nonisolated static var breathDamageShort: String { L10n.text(.combatStatBreathDamageShort) }
    }

    enum ActionPreference {
        nonisolated static var attack: String { L10n.text(.actionPreferenceAttack) }
        nonisolated static var priestMagic: String { L10n.text(.actionPreferencePriestMagic) }
        nonisolated static var mageMagic: String { L10n.text(.actionPreferenceMageMagic) }
        nonisolated static var breath: String { L10n.text(.actionPreferenceBreath) }
    }

    enum Modifier {
        nonisolated static var conditional: String { L10n.text(.modifierConditional) }
    }

    enum Resistance {
        nonisolated static var physical: String { L10n.text(.resistancePhysical) }
        nonisolated static var piercing: String { L10n.text(.resistancePiercing) }
        nonisolated static var critical: String { L10n.text(.resistanceCritical) }
        nonisolated static var breath: String { L10n.text(.resistanceBreath) }
    }

    enum DamageModifier {
        nonisolated static var physicalDamageDealt: String { L10n.text(.damageModifierPhysicalDamageDealt) }
        nonisolated static var physicalDamageTaken: String { L10n.text(.damageModifierPhysicalDamageTaken) }
        nonisolated static var magicalDamageTaken: String { L10n.text(.damageModifierMagicalDamageTaken) }
        nonisolated static var breathDamageTaken: String { L10n.text(.damageModifierBreathDamageTaken) }
    }

    enum BattleTerm {
        nonisolated static var reactionAttack: String { L10n.text(.battleTermReactionAttack) }
        nonisolated static var followUp: String { L10n.text(.battleTermFollowUp) }
        nonisolated static var retaliation: String { L10n.text(.battleTermRetaliation) }
        nonisolated static var extraAttack: String { L10n.text(.battleTermExtraAttack) }
        nonisolated static var martialFollowUp: String { L10n.text(.battleTermMartialFollowUp) }
        nonisolated static var rescue: String { L10n.text(.battleTermRescue) }
    }
}
