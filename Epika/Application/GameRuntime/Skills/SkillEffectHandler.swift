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
protocol SkillEffectHandler {
    /// このハンドラが処理する SkillEffectType
    static var effectType: SkillEffectType { get }

    /// ペイロードを解析し、Accumulator に効果を適用する
    /// - Parameters:
    ///   - payload: デコード済みのペイロード
    ///   - accumulator: 効果を蓄積する Accumulator
    ///   - context: スキル情報を含むコンテキスト
    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws
}

/// ハンドラに渡すスキル情報のコンテキスト
struct SkillEffectContext: Sendable {
    let skillId: UInt16
    let skillName: String
    let effectIndex: Int
    let actorStats: ActorStats?
}

/// コンパイル時に参照可能なアクターのステータス
struct ActorStats: Sendable {
    let strength: Int
    let wisdom: Int
    let spirit: Int
    let vitality: Int
    let agility: Int
    let luck: Int

    /// EnumMappings.baseStat のrawValueでステータス値を取得
    /// strength=1, wisdom=2, spirit=3, vitality=4, agility=5, luck=6
    func value(for statRawValue: Int) -> Int {
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
    func scaledValue(from stats: ActorStats?) -> Double {
        guard let scalingStatInt = parameters[.scalingStat],
              let coefficient = value[.scalingCoefficient],
              let stats = stats else {
            return 0.0
        }
        return Double(stats.value(for: scalingStatInt)) * coefficient
    }
}

// MARK: - SkillEffectHandlerRegistry

/// SkillEffectType からハンドラを取得するレジストリ
/// 静的イミュータブル辞書として起動時に一度だけ構築される
@MainActor
enum SkillEffectHandlerRegistry {
    /// 全ハンドラの辞書（遅延初期化）
    static let handlers: [SkillEffectType: any SkillEffectHandler.Type] = {
        var dict: [SkillEffectType: any SkillEffectHandler.Type] = [:]

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
            MagicCriticalChancePercentHandler.self,
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
            AntiHealingHandler.self,
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
            CriticalRateAdditiveHandler.self,
            CriticalRateCapHandler.self,
            CriticalRateMaxAbsoluteHandler.self,
            CriticalRateMaxDeltaHandler.self,
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

        for handler in allHandlers {
            assert(dict[handler.effectType] == nil,
                   "Duplicate handler for \(handler.effectType)")
            dict[handler.effectType] = handler
        }

        return dict
    }()

    /// 指定された effectType に対応するハンドラを取得
    /// - Parameter effectType: 検索する SkillEffectType
    /// - Returns: 対応するハンドラ、未登録の場合は nil
    static func handler(for effectType: SkillEffectType) -> (any SkillEffectHandler.Type)? {
        handlers[effectType]
    }
}
