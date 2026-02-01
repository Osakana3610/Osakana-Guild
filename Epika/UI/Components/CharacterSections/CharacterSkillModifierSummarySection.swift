// ==============================================================================
// CharacterSkillModifierSummarySection.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - スキル補正一覧を表示
//   - SkillModifierSummary の内容を人間向けラベルに変換して列挙
//
// 【View構成】
//   - LabeledContent を使用し、左に項目名、右に数値/条件付きタグを表示
//
// 【使用箇所】
//   - キャラクター詳細画面（CharacterDetailContent）
//
// ==============================================================================

import SwiftUI

@MainActor
struct CharacterSkillModifierSummarySection: View {
    let summary: SkillModifierSummary
    let masterData: MasterDataCache

    var body: some View {
        ForEach(summary.entries, id: \.key.rawValue) { entry in
            LabeledContent {
                HStack(spacing: 8) {
                    if let value = entry.value {
                        Text(format(value))
                            .font(.body)
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }
                    if entry.conditional {
                        Text(L10n.Modifier.conditional)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } label: {
                Text(label(for: entry.key))
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
    }
}

private extension CharacterSkillModifierSummarySection {
    func format(_ value: SkillModifierSummary.SkillModifierValue) -> String {
        switch value {
        case .percent(let percent):
            return formatSigned(percent, suffix: "%")
        case .multiplier(let multiplier):
            return String(format: "×%.2f", max(0.0, multiplier))
        case .additive(let additive):
            return formatSigned(additive, suffix: "")
        case .count(let count):
            let sign = count >= 0 ? "+" : ""
            return "\(sign)\(count)回"
        case .flag:
            return "有効"
        }
    }

    func formatSigned(_ value: Double, suffix: String) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(format: "%+.0f%@", rounded, suffix)
        }
        return String(format: "%+.1f%@", rounded, suffix)
    }

    func label(for key: SkillModifierKey) -> String {
        guard let kind = key.kind else { return "不明" }
        switch kind {
        case .damageDealtPercent, .damageDealtMultiplier:
            return "\(damageDealtLabel(param: key.param))"
        case .damageTakenPercent, .damageTakenMultiplier:
            return "\(damageTakenLabel(param: key.param))"
        case .damageDealtMultiplierAgainst:
            return "\(raceLabel(param: key.param))への攻撃で与えるダメージ"
        case .damageDealtMultiplierByTargetHP:
            return "対象HPに応じた与えるダメージ"
        case .criticalDamagePercent, .criticalDamageMultiplier:
            return "必殺ダメージ"
        case .criticalDamageTakenMultiplier:
            return "必殺ダメージを受ける倍率"
        case .penetrationDamageTakenMultiplier:
            return "貫通ダメージを受ける倍率"
        case .martialBonusPercent, .martialBonusMultiplier:
            return "格闘ボーナス"
        case .minHitScale:
            return "命中下限"
        case .magicNullifyChancePercent:
            return "魔法無効化"
        case .levelComparisonDamageTaken:
            return "低Lv敵から受けるダメージ"
        case .cumulativeHitDamageBonus:
            return "命中累積ボーナス"
        case .spellPowerPercent, .spellPowerMultiplier:
            return "魔法威力"
        case .spellSpecificMultiplier:
            return "\(spellLabel(param: key.param))威力"
        case .spellSpecificTakenMultiplier:
            return "\(spellLabel(param: key.param))を受ける倍率"
        case .spellCharges:
            return "\(spellChargeLabel(param: key.param))"
        case .spellChargeRecoveryChance:
            return "魔法の使用回数回復"
        case .magicCriticalEnable:
            return "魔法必殺"
        case .breathVariant:
            return "ブレスの使用回数"
        case .reverseHealing:
            return "回復反転"
        case .statusResistancePercent, .statusResistanceMultiplier:
            return "\(statusLabel(param: key.param))耐性"
        case .statusInflict:
            return "\(statusLabel(param: key.param))付与"
        case .berserk:
            return "暴走"
        case .parry:
            return key.slot == 1 ? "パリィ補正" : "パリィ"
        case .shieldBlock:
            return key.slot == 1 ? "盾防御補正" : "盾防御"
        case .barrier:
            return "\(damageTypeShortName(param: key.param))結界"
        case .barrierOnGuard:
            return "防御時\(damageTypeShortName(param: key.param))結界"
        case .autoStatusCureOnAlly:
            return "自動キュア"
        case .absorption:
            return key.slot == 1 ? "吸収上限" : "吸収"
        case .targetingWeight:
            return "狙われ率"
        case .partyAttackFlag:
            return partyAttackFlagLabel(slot: key.slot)
        case .partyAttackTarget:
            return partyAttackTargetLabel(slot: key.slot, param: key.param)
        case .coverRowsBehind:
            return key.slot == 1 ? "後列をかばう条件" : "後列をかばう"
        case .actionOrderMultiplier:
            return "行動順倍率"
        case .actionOrderShuffle:
            return "行動順シャッフル"
        case .actionOrderShuffleEnemy:
            return "敵行動順シャッフル"
        case .counterAttackEvasionMultiplier:
            return "反撃回避倍率"
        case .procRate:
            return "特殊効果発動率"
        case .procMultiplier:
            return "特殊効果発動率倍率"
        case .enemyActionDebuffChance:
            return "敵行動回数減少"
        case .enemySingleActionSkipChance:
            return "敵単体行動スキップ"
        case .firstStrike:
            return "先制攻撃"
        case .statDebuff:
            return "\(statLabel(param: key.param))弱体化"
        case .timedBuffTrigger:
            return "時限バフ"
        case .tacticSpellAmplify:
            return "魔法強化（\(spellLabel(param: key.param))）"
        case .timedMagicPowerAmplify:
            return "魔法威力強化（時限）"
        case .timedBreathPowerAmplify:
            return "ブレス威力強化（時限）"
        case .endOfTurnHealing:
            return "ターン終了時回復"
        case .endOfTurnSelfHPPercent:
            return "ターン終了時自己HP"
        case .runawayMagic:
            return "魔法暴走"
        case .runawayDamage:
            return "ダメージ暴走"
        case .retreatAtTurn:
            return key.slot == 1 ? "退却確率" : "退却ターン"
        case .statAdditive:
            return statLabel(param: key.param)
        case .statMultiplier:
            return statLabel(param: key.param)
        case .statConversionPercent:
            return statConversionLabel(param: key.param)
        case .statConversionLinear:
            return statConversionLabel(param: key.param)
        case .statFixedToOne:
            return "\(statLabel(param: key.param))固定"
        case .equipmentStatMultiplier:
            return "\(equipmentLabel(param: key.param))補正"
        case .itemStatMultiplier:
            return "装備補正: \(statLabel(param: key.param))"
        case .talentStat:
            return "\(statLabel(param: key.param))才能"
        case .incompetenceStat:
            return "\(statLabel(param: key.param))不向き"
        case .attackCountAdditive:
            return "攻撃回数"
        case .attackCountMultiplier:
            return "攻撃回数倍率"
        case .additionalDamageScoreAdditive:
            return "追加ダメージ"
        case .additionalDamageScoreMultiplier:
            return "追加ダメージ倍率"
        case .criticalChancePercentAdditive:
            return "必殺率"
        case .criticalChancePercentCap:
            return "必殺率上限"
        case .criticalChancePercentMaxDelta:
            return "必殺率上限補正"
        default:
            return kind.identifier
        }
    }

    func damageDealtLabel(param: UInt16) -> String {
        let type = damageTypeName(param: param)
        if type == "すべての攻撃" {
            return "すべての攻撃で与えるダメージ"
        }
        return "\(type)で与えるダメージ"
    }

    func damageTakenLabel(param: UInt16) -> String {
        let type = damageTypeName(param: param)
        if type == "すべての攻撃" {
            return "すべての攻撃で受けるダメージ"
        }
        return "\(type)で受けるダメージ"
    }

    func damageTypeName(param: UInt16) -> String {
        if param == SkillModifierKey.paramAll {
            return "すべての攻撃"
        }
        if let type = BattleDamageType(rawValue: UInt8(truncatingIfNeeded: param)) {
            switch type {
            case .physical: return "物理攻撃"
            case .magical: return "魔法攻撃"
            case .breath: return "ブレス攻撃"
            }
        }
        return "攻撃"
    }

    func damageTypeShortName(param: UInt16) -> String {
        if let type = BattleDamageType(rawValue: UInt8(truncatingIfNeeded: param)) {
            switch type {
            case .physical: return "物理"
            case .magical: return "魔法"
            case .breath: return "ブレス"
            }
        }
        return "攻撃"
    }

    func raceLabel(param: UInt16) -> String {
        masterData.enemyRaceName(for: UInt8(truncatingIfNeeded: param))
    }

    func statusLabel(param: UInt16) -> String {
        masterData.statusEffect(UInt8(truncatingIfNeeded: param))?.name ?? "状態ID:\(param)"
    }

    func spellLabel(param: UInt16) -> String {
        masterData.spellName(for: UInt8(truncatingIfNeeded: param))
    }

    func spellChargeLabel(param: UInt16) -> String {
        if param == SkillModifierKey.paramAll {
            return "魔法の使用回数（全て）"
        }
        return "魔法の使用回数（\(spellLabel(param: param))）"
    }

    func statLabel(param: UInt16) -> String {
        if let base = BaseStat(rawValue: UInt8(truncatingIfNeeded: param)) {
            return base.displayName
        }
        if let combat = CombatStat(rawValue: UInt8(truncatingIfNeeded: param)) {
            return combat.displayName
        }
        return "能力値\(param)"
    }

    func statConversionLabel(param: UInt16) -> String {
        let sourceRaw = UInt8(truncatingIfNeeded: param >> 8)
        let targetRaw = UInt8(truncatingIfNeeded: param & 0xFF)
        let source = CombatStat(rawValue: sourceRaw)?.displayName ?? "能力値\(sourceRaw)"
        let target = CombatStat(rawValue: targetRaw)?.displayName ?? "能力値\(targetRaw)"
        return "\(source)→\(target)変換"
    }

    func equipmentLabel(param: UInt16) -> String {
        let raw = UInt8(truncatingIfNeeded: param)
        return ItemSaleCategory(rawValue: raw)?.displayName ?? "装備種別\(raw)"
    }

    func partyAttackFlagLabel(slot: UInt8) -> String {
        switch slot {
        case 1: return "味方全員敵対"
        case 2: return "吸血衝動"
        case 3: return "吸血衝動抑制"
        default: return "敵対設定"
        }
    }

    func partyAttackTargetLabel(slot: UInt8, param: UInt16) -> String {
        let raceName = raceLabel(param: param)
        switch slot {
        case 1: return "敵対対象: \(raceName)"
        case 2: return "保護対象: \(raceName)"
        default: return "対象: \(raceName)"
        }
    }
}
