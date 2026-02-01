// ==============================================================================
// SkillEffectHandler.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - スキルエフェクトを処理するハンドラのプロトコル定義
//   - SkillEffectType から対応ハンドラを取得するレジストリ管理
//   - スキルエフェクトコンテキスト（ActorStats含む）の提供
//
// 【公開API】
//   - SkillEffectHandler: 各ハンドラが実装すべきプロトコル
//   - SkillEffectHandlerRegistry: ハンドラレジストリ（型辞書ベース）
//   - SkillEffectContext: ハンドラに渡すスキル情報のコンテキスト
//   - ActorStats: コンパイル時に参照可能なアクターステータス
//
// 【使用箇所】
//   - SkillEffectHandlers.*.swift で各種ハンドラを実装
//   - SkillRuntimeEffectCompiler.Actor.actorEffects(from:stats:) でハンドラ取得・実行
//
// ==============================================================================

import Foundation

// MARK: - SkillEffectHandler Protocol

/// スキルエフェクトを処理するハンドラのプロトコル
/// 各 SkillEffectType に対応するハンドラが実装する
/// 静的メソッドのみで状態を持たないためSendable
protocol SkillEffectHandler: Sendable {
    /// このハンドラが処理する SkillEffectType
    nonisolated static var effectType: SkillEffectType { get }

    /// ペイロードを解析し、Accumulator に効果を適用する
    /// - Parameters:
    ///   - payload: デコード済みのペイロード
    ///   - accumulator: 効果を蓄積する Accumulator
    ///   - context: スキル情報を含むコンテキスト
    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws
}

/// ハンドラに渡すスキル情報のコンテキスト
struct SkillEffectContext: Sendable {
    nonisolated let skillId: UInt16
    nonisolated let skillName: String
    nonisolated let effectIndex: Int
    nonisolated let actorStats: ActorStats?
}

/// コンパイル時に参照可能なアクターのステータス
struct ActorStats: Sendable {
    nonisolated let strength: Int
    nonisolated let wisdom: Int
    nonisolated let spirit: Int
    nonisolated let vitality: Int
    nonisolated let agility: Int
    nonisolated let luck: Int

    /// EnumMappings.baseStat のrawValueでステータス値を取得
    /// strength=1, wisdom=2, spirit=3, vitality=4, agility=5, luck=6
    nonisolated func value(for statRawValue: Int) -> Int {
        switch statRawValue {
        case 1: return strength
        case 2: return wisdom
        case 3: return spirit
        case 4: return vitality
        case 5: return agility
        case 6: return luck
        default: return 0
        }
    }
}

/// statScaling計算のヘルパー
extension DecodedSkillEffectPayload {
    /// statScalingが指定されている場合、ステータス値×係数を返す
    nonisolated func scaledValue(from stats: ActorStats?) -> Double {
        SkillEffectInterpretation.scaledValue(self, stats: stats)
    }

    /// chancePercent / baseChancePercent(+scalingStat) から発動率(%)を解決する
    nonisolated func resolvedChancePercent(stats: ActorStats?, skillId: UInt16, effectIndex: Int) throws -> Double? {
        try SkillEffectInterpretation.resolvedChancePercent(self,
                                                            stats: stats,
                                                            skillId: skillId,
                                                            effectIndex: effectIndex)
    }
}

// MARK: - SkillEffectHandlerRegistry

/// SkillEffectType からハンドラを取得するレジストリ
/// 静的イミュータブル辞書として起動時に一度だけ構築される
/// ハンドラは静的メソッドのみでSendable、辞書もSendable
enum SkillEffectHandlerRegistry {
    /// 全ハンドラのテーブル（SkillEffectType.rawValue を添字に使用）
    nonisolated static let handlerTable: [((any SkillEffectHandler.Type)?)] = {
        let allHandlers: [any SkillEffectHandler.Type] = [
            // MARK: Damage Handlers (17)
            DamageDealtPercentHandler.self,
            DamageDealtMultiplierHandler.self,
            DamageTakenPercentHandler.self,
            DamageTakenMultiplierHandler.self,
            DamageDealtMultiplierAgainstHandler.self,
            CriticalDamagePercentHandler.self,
            CriticalDamageMultiplierHandler.self,
            CriticalDamageTakenMultiplierHandler.self,
            PenetrationDamageTakenMultiplierHandler.self,
            MartialBonusPercentHandler.self,
            MartialBonusMultiplierHandler.self,
            AdditionalDamageAdditiveHandler.self,
            AdditionalDamageMultiplierHandler.self,
            MinHitScaleHandler.self,
            MagicNullifyChancePercentHandler.self,
            LevelComparisonDamageTakenHandler.self,
            DamageDealtMultiplierByTargetHPHandler.self,

            // MARK: Spell Handlers (10)
            SpellPowerPercentHandler.self,
            SpellPowerMultiplierHandler.self,
            SpellSpecificMultiplierHandler.self,
            SpellSpecificTakenMultiplierHandler.self,
            SpellChargesHandler.self,
            SpellAccessHandler.self,
            SpellTierUnlockHandler.self,
            TacticSpellAmplifyHandler.self,
            MagicCriticalEnableHandler.self,
            SpellChargeRecoveryChanceHandler.self,

            // MARK: Combat Handlers (20)
            ProcMultiplierHandler.self,
            ProcRateHandler.self,
            ExtraActionHandler.self,
            ReactionNextTurnHandler.self,
            ActionOrderMultiplierHandler.self,
            ActionOrderShuffleHandler.self,
            CounterAttackEvasionMultiplierHandler.self,
            ReactionHandler.self,
            ParryHandler.self,
            ShieldBlockHandler.self,
            SpecialAttackHandler.self,
            BarrierHandler.self,
            BarrierOnGuardHandler.self,
            AttackCountAdditiveHandler.self,
            AttackCountMultiplierHandler.self,
            EnemyActionDebuffChanceHandler.self,
            CumulativeHitDamageBonusHandler.self,
            EnemySingleActionSkipChanceHandler.self,
            ActionOrderShuffleEnemyHandler.self,
            FirstStrikeHandler.self,
            StatDebuffHandler.self,

            // MARK: Status Handlers (8)
            StatusResistanceMultiplierHandler.self,
            StatusResistancePercentHandler.self,
            StatusInflictHandler.self,
            BerserkHandler.self,
            TimedBuffTriggerHandler.self,
            TimedMagicPowerAmplifyHandler.self,
            TimedBreathPowerAmplifyHandler.self,
            AutoStatusCureOnAllyHandler.self,

            // MARK: Resurrection Handlers (7)
            ResurrectionSaveHandler.self,
            ResurrectionActiveHandler.self,
            ResurrectionBuffHandler.self,
            ResurrectionVitalizeHandler.self,
            ResurrectionSummonHandler.self,
            ResurrectionPassiveHandler.self,
            SacrificeRiteHandler.self,

            // MARK: Misc Handlers
            RowProfileHandler.self,
            EndOfTurnHealingHandler.self,
            EndOfTurnSelfHPPercentHandler.self,
            PartyAttackFlagHandler.self,
            PartyAttackTargetHandler.self,
            ReverseHealingHandler.self,
            BreathVariantHandler.self,
            EquipmentStatMultiplierHandler.self,
            DodgeCapHandler.self,
            AbsorptionHandler.self,
            DegradationRepairHandler.self,
            DegradationRepairBoostHandler.self,
            AutoDegradationRepairHandler.self,
            RunawayMagicHandler.self,
            RunawayDamageHandler.self,
            RetreatAtTurnHandler.self,
            TargetingWeightHandler.self,
            CoverRowsBehindHandler.self,

            // MARK: Passthrough Handlers (Actor.swiftでは処理しないが登録は必要)
            CriticalChancePercentAdditiveHandler.self,
            CriticalChancePercentCapHandler.self,
            CriticalChancePercentMaxDeltaHandler.self,
            EquipmentSlotAdditiveHandler.self,
            EquipmentSlotMultiplierHandler.self,
            ExplorationTimeMultiplierHandler.self,
            GrowthMultiplierHandler.self,
            IncompetenceStatHandler.self,
            ItemStatMultiplierHandler.self,
            RewardExperienceMultiplierHandler.self,
            RewardExperiencePercentHandler.self,
            RewardGoldMultiplierHandler.self,
            RewardGoldPercentHandler.self,
            RewardItemMultiplierHandler.self,
            RewardItemPercentHandler.self,
            RewardTitleMultiplierHandler.self,
            RewardTitlePercentHandler.self,
            StatAdditiveHandler.self,
            StatConversionLinearHandler.self,
            StatConversionPercentHandler.self,
            StatFixedToOneHandler.self,
            StatMultiplierHandler.self,
            TalentStatHandler.self
        ]

        let maxRawValue = SkillEffectType.allCases.map { Int($0.rawValue) }.max() ?? 0
        var table: [((any SkillEffectHandler.Type)?)] = Array(repeating: nil, count: maxRawValue + 1)

        for handler in allHandlers {
            let index = Int(handler.effectType.rawValue)
            assert(table[index] == nil, "Duplicate handler for \(handler.effectType)")
            table[index] = handler
        }

        return table
    }()

    /// 指定された effectType に対応するハンドラを取得
    /// - Parameter effectType: 検索する SkillEffectType
    /// - Returns: 対応するハンドラ、未登録の場合は nil
    nonisolated static func handler(for effectType: SkillEffectType) -> (any SkillEffectHandler.Type)? {
        let index = Int(effectType.rawValue)
        guard index >= 0, index < handlerTable.count else { return nil }
        return handlerTable[index]
    }

    /// 登録済みのeffectType一覧（テスト/検証用）
    nonisolated static let registeredTypes: Set<SkillEffectType> = {
        var types: Set<SkillEffectType> = []
        for (index, handler) in handlerTable.enumerated() {
            guard handler != nil, let effectType = SkillEffectType(rawValue: UInt8(index)) else { continue }
            types.insert(effectType)
        }
        return types
    }()
}
