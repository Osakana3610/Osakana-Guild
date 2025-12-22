// ==============================================================================
// DropModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ドロップシステムで使用するモデル型の定義
//   - パーティのドロップ補正値の計算ロジック
//
// 【データ構造】
//   - DropItemCategory: アイテムのドロップカテゴリ（normal/good/rare/gem）
//   - PartyDropBonuses: パーティのドロップ系補正値を集計した構造体
//   - DropRollResult: 1回のドロップ判定結果
//   - SuperRareDailyState: 日次で共有する超レアドロップ状態
//   - SuperRareSessionState: 1バトル内の超レア判定セッション情報
//   - DropOutcome: ドロップ処理の最終結果
//
// 【使用箇所】
//   - DropService（ドロップ計算のメインロジック）
//   - ItemDropRateCalculator（ドロップ率計算）
//   - TitleAssignmentEngine（称号付与処理）
//
// ==============================================================================

import Foundation

/// 旧ランタイムで使用していたドロップカテゴリを非決定論向けに再定義。
enum DropItemCategory: UInt8, Sendable {
    case normal = 1
    case good = 2
    case rare = 3
    case gem = 4

    nonisolated init?(identifier: String) {
        switch identifier {
        case "normal": self = .normal
        case "good": self = .good
        case "rare": self = .rare
        case "gem": self = .gem
        default: return nil
        }
    }

    nonisolated var identifier: String {
        switch self {
        case .normal: return "normal"
        case .good: return "good"
        case .rare: return "rare"
        case .gem: return "gem"
        }
    }
}

/// パーティのドロップ系補正値を集計したもの。
struct PartyDropBonuses: Sendable {
    let goldMultiplier: Double
    let rareDropMultiplier: Double
    let titleGrantRateMultiplier: Double
    let averageLuck: Double
    let fortune: Int

    static let neutral = PartyDropBonuses(goldMultiplier: 1.0,
                                          rareDropMultiplier: 1.0,
                                          titleGrantRateMultiplier: 1.0,
                                          averageLuck: 0.0,
                                          fortune: 0)

    /// RuntimeCharacter配列からボーナスを計算する。
    init(members: [RuntimeCharacter]) {
        guard !members.isEmpty else {
            self = .neutral
            return
        }

        var luckSum = 0
        var spiritSum = 0
        for member in members {
            luckSum += member.attributes.luck
            spiritSum += member.attributes.spirit
        }

        let count = Double(members.count)
        let averageLuck = Double(luckSum) / count

        // 旧仕様準拠: Luck合計でゴールド倍率を底上げ
        let goldBase = 1.0 + Double(luckSum) * 0.001
        // 旧仕様準拠: (Luck + Spirit) 合計でレア倍率を底上げ
        let rareBase = 1.0 + (Double(luckSum + spiritSum) * 0.0005)
        // 旧仕様準拠: 平均Luckに比例して称号付与率を上げる
        let titleBase = 1.0 + (averageLuck * 0.002)

        // 報酬系スキルはパーティ全体でID単位の重複無効
        let allSkills = members.flatMap { $0.learnedSkills }
        let uniqueSkills = Array(Dictionary(allSkills.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values)
        let rewardComponents = (try? SkillRuntimeEffectCompiler.rewardComponents(from: uniqueSkills)) ?? .neutral

        self.goldMultiplier = goldBase * rewardComponents.goldScale()
        self.rareDropMultiplier = rareBase * rewardComponents.itemDropScale()
        self.titleGrantRateMultiplier = titleBase * rewardComponents.titleScale()
        self.averageLuck = averageLuck
        self.fortune = Int(averageLuck.rounded())
    }

    private init(goldMultiplier: Double, rareDropMultiplier: Double, titleGrantRateMultiplier: Double, averageLuck: Double, fortune: Int) {
        self.goldMultiplier = goldMultiplier
        self.rareDropMultiplier = rareDropMultiplier
        self.titleGrantRateMultiplier = titleGrantRateMultiplier
        self.averageLuck = averageLuck
        self.fortune = fortune
    }
}

/// 1回のドロップ判定結果。
struct DropRollResult: Sendable {
    let willDrop: Bool
    let luckRoll: Double
    let baseThreshold: Double
    let finalThreshold: Double
}

/// 日次で共有する超レアドロップ状態。
struct SuperRareDailyState: Sendable, Codable {
    /// JST日付 (YYYYMMDD形式のUInt32)
    var jstDate: UInt32
    var hasTriggered: Bool
}

/// 1バトル内の超レア判定に利用するセッション情報。
struct SuperRareSessionState {
    var normalItemTriggered: Bool = false
}

struct DropOutcome: Sendable {
    let results: [ItemDropResult]
    let superRareState: SuperRareDailyState
    /// 今回の戦闘で新たにドロップしたアイテムID
    let newlyDroppedItemIds: Set<UInt16>
}

extension RuntimePartyState {
    /// パーティメンバーのステータスからドロップ倍率を集計する。
    func makeDropBonuses() -> PartyDropBonuses {
        PartyDropBonuses(members: members.map(\.character))
    }
}
