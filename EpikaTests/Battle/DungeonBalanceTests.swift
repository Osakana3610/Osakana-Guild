import XCTest
@testable import Epika

/// 迷宮バランステスト（16パーティ版）
/// 各迷宮のボス戦を16パーティ×100回実行し、勝率を計算する
@MainActor
final class DungeonBalanceTests: XCTestCase {

    // MARK: - Test Configuration

    /// 1迷宮あたりの戦闘回数
    private static let battleCount = 100

    /// 並列実行するパーティ数
    private static let parallelPartyCount = 8

    /// 結果出力先ディレクトリ
    private static let outputDirectory = "/Users/licht/Development/Epika/Documents/DungeonBalanceResults"

    // MARK: - Party Member Configuration

    private struct PartyMemberConfig {
        let raceId: UInt8
        let previousJobId: UInt8
        let currentJobId: UInt8
        let actionRates: BattleActionRates

        /// 侍かどうか（武器装備判定用）
        var isSamurai: Bool { currentJobId == 10 || currentJobId == 110 }

        /// アタッカーかどうか（細剣装備判定用）
        var isAttacker: Bool {
            let attackerJobs: Set<UInt8> = [2, 8, 10, 11, 14, 102, 108, 110, 111, 114] // 剣士,狩人,侍,剣聖,忍者 + マスター
            return attackerJobs.contains(currentJobId)
        }

        /// 後衛かどうか
        var isBackline: Bool {
            let backlineJobs: Set<UInt8> = [6, 7, 13, 106, 107, 113] // 僧侶,魔法使い,賢者 + マスター
            return backlineJobs.contains(currentJobId)
        }
    }

    private struct PartyConfig {
        let name: String
        let members: [PartyMemberConfig]
    }

    // MARK: - 16 Party Definitions

    private static let partyConfigs: [PartyConfig] = [
        // Party 1: 標準バランス
        PartyConfig(name: "標準バランス", members: [
            PartyMemberConfig(raceId: 15, previousJobId: 6, currentJobId: 1,   actionRates: BattleActionRates(attack: 80, priestMagic: 20, mageMagic: 0, breath: 0)),  // 巨人 僧侶→戦士
            PartyMemberConfig(raceId: 4,  previousJobId: 9, currentJobId: 6,   actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)), // ノーム 修道者→僧侶
            PartyMemberConfig(raceId: 9,  previousJobId: 7, currentJobId: 107, actionRates: BattleActionRates(attack: 0, priestMagic: 0, mageMagic: 100, breath: 0)), // サイキック 魔法使い→魔法使いM
            PartyMemberConfig(raceId: 17, previousJobId: 14, currentJobId: 10, actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // 鬼 忍者→侍
            PartyMemberConfig(raceId: 3,  previousJobId: 3, currentJobId: 103, actionRates: BattleActionRates(attack: 60, priestMagic: 0, mageMagic: 0, breath: 0)),  // ピグミー 盗賊→盗賊M
            PartyMemberConfig(raceId: 8,  previousJobId: 6, currentJobId: 13,  actionRates: BattleActionRates(attack: 0, priestMagic: 50, mageMagic: 50, breath: 0)), // エルフ 僧侶→賢者
        ]),

        // Party 2: 物理特化
        PartyConfig(name: "物理特化", members: [
            PartyMemberConfig(raceId: 17, previousJobId: 9, currentJobId: 10,  actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // 鬼 修道者→侍
            PartyMemberConfig(raceId: 15, previousJobId: 9, currentJobId: 10,  actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // 巨人 修道者→侍
            PartyMemberConfig(raceId: 11, previousJobId: 14, currentJobId: 2,  actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // ドラゴニュート 忍者→剣士
            PartyMemberConfig(raceId: 7,  previousJobId: 14, currentJobId: 11, actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // 吸血鬼 忍者→剣聖
            PartyMemberConfig(raceId: 4,  previousJobId: 6, currentJobId: 106, actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)), // ノーム 僧侶→僧侶M
            PartyMemberConfig(raceId: 3,  previousJobId: 6, currentJobId: 3,   actionRates: BattleActionRates(attack: 60, priestMagic: 40, mageMagic: 0, breath: 0)), // ピグミー 僧侶→盗賊
        ]),

        // Party 3: 魔法特化
        PartyConfig(name: "魔法特化", members: [
            PartyMemberConfig(raceId: 5,  previousJobId: 6, currentJobId: 1,   actionRates: BattleActionRates(attack: 80, priestMagic: 20, mageMagic: 0, breath: 0)), // ドワーフ 僧侶→戦士
            PartyMemberConfig(raceId: 9,  previousJobId: 7, currentJobId: 107, actionRates: BattleActionRates(attack: 0, priestMagic: 0, mageMagic: 100, breath: 0)), // サイキック 魔法使い→魔法使いM
            PartyMemberConfig(raceId: 6,  previousJobId: 7, currentJobId: 107, actionRates: BattleActionRates(attack: 0, priestMagic: 0, mageMagic: 100, breath: 0)), // ダークエルフ 魔法使い→魔法使いM
            PartyMemberConfig(raceId: 4,  previousJobId: 9, currentJobId: 13,  actionRates: BattleActionRates(attack: 0, priestMagic: 50, mageMagic: 50, breath: 0)), // ノーム 修道者→賢者
            PartyMemberConfig(raceId: 8,  previousJobId: 6, currentJobId: 106, actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)), // エルフ 僧侶→僧侶M
            PartyMemberConfig(raceId: 16, previousJobId: 3, currentJobId: 14,  actionRates: BattleActionRates(attack: 80, priestMagic: 0, mageMagic: 0, breath: 0)),  // 天狗 盗賊→忍者
        ]),

        // Party 4: 耐久重視
        PartyConfig(name: "耐久重視", members: [
            PartyMemberConfig(raceId: 5,  previousJobId: 6, currentJobId: 1,   actionRates: BattleActionRates(attack: 80, priestMagic: 20, mageMagic: 0, breath: 0)), // ドワーフ 僧侶→戦士
            PartyMemberConfig(raceId: 14, previousJobId: 6, currentJobId: 15,  actionRates: BattleActionRates(attack: 50, priestMagic: 50, mageMagic: 0, breath: 0)), // アンデッド 僧侶→君主
            PartyMemberConfig(raceId: 15, previousJobId: 1, currentJobId: 101, actionRates: BattleActionRates(attack: 80, priestMagic: 0, mageMagic: 0, breath: 0)),  // 巨人 戦士→戦士M
            PartyMemberConfig(raceId: 4,  previousJobId: 6, currentJobId: 106, actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)), // ノーム 僧侶→僧侶M
            PartyMemberConfig(raceId: 8,  previousJobId: 9, currentJobId: 6,   actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)), // エルフ 修道者→僧侶
            PartyMemberConfig(raceId: 4,  previousJobId: 6, currentJobId: 13,  actionRates: BattleActionRates(attack: 0, priestMagic: 50, mageMagic: 50, breath: 0)), // ノーム 僧侶→賢者
        ]),

        // Party 5: 速攻型
        PartyConfig(name: "速攻型", members: [
            PartyMemberConfig(raceId: 18, previousJobId: 3, currentJobId: 14,  actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // サイボーグ 盗賊→忍者
            PartyMemberConfig(raceId: 16, previousJobId: 3, currentJobId: 14,  actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // 天狗 盗賊→忍者
            PartyMemberConfig(raceId: 10, previousJobId: 14, currentJobId: 8,  actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // ワーキャット 忍者→狩人
            PartyMemberConfig(raceId: 18, previousJobId: 14, currentJobId: 8,  actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // サイボーグ 忍者→狩人
            PartyMemberConfig(raceId: 4,  previousJobId: 6, currentJobId: 106, actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)), // ノーム 僧侶→僧侶M
            PartyMemberConfig(raceId: 9,  previousJobId: 7, currentJobId: 107, actionRates: BattleActionRates(attack: 0, priestMagic: 0, mageMagic: 100, breath: 0)), // サイキック 魔法使い→魔法使いM
        ]),

        // Party 6: 回避型
        PartyConfig(name: "回避型", members: [
            PartyMemberConfig(raceId: 8,  previousJobId: 14, currentJobId: 11, actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // エルフ 忍者→剣聖
            PartyMemberConfig(raceId: 16, previousJobId: 3, currentJobId: 14,  actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // 天狗 盗賊→忍者
            PartyMemberConfig(raceId: 18, previousJobId: 3, currentJobId: 14,  actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // サイボーグ 盗賊→忍者
            PartyMemberConfig(raceId: 3,  previousJobId: 6, currentJobId: 3,   actionRates: BattleActionRates(attack: 60, priestMagic: 40, mageMagic: 0, breath: 0)), // ピグミー 僧侶→盗賊
            PartyMemberConfig(raceId: 8,  previousJobId: 9, currentJobId: 6,   actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)), // エルフ 修道者→僧侶
            PartyMemberConfig(raceId: 4,  previousJobId: 6, currentJobId: 13,  actionRates: BattleActionRates(attack: 0, priestMagic: 50, mageMagic: 50, breath: 0)), // ノーム 僧侶→賢者
        ]),

        // Party 7: 多段攻撃
        PartyConfig(name: "多段攻撃", members: [
            PartyMemberConfig(raceId: 7,  previousJobId: 14, currentJobId: 2,  actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // 吸血鬼 忍者→剣士
            PartyMemberConfig(raceId: 11, previousJobId: 14, currentJobId: 2,  actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // ドラゴニュート 忍者→剣士
            PartyMemberConfig(raceId: 10, previousJobId: 3, currentJobId: 8,   actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // ワーキャット 盗賊→狩人
            PartyMemberConfig(raceId: 18, previousJobId: 3, currentJobId: 8,   actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // サイボーグ 盗賊→狩人
            PartyMemberConfig(raceId: 4,  previousJobId: 6, currentJobId: 106, actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)), // ノーム 僧侶→僧侶M
            PartyMemberConfig(raceId: 3,  previousJobId: 6, currentJobId: 3,   actionRates: BattleActionRates(attack: 60, priestMagic: 40, mageMagic: 0, breath: 0)), // ピグミー 僧侶→盗賊
        ]),

        // Party 8: 単発火力
        PartyConfig(name: "単発火力", members: [
            PartyMemberConfig(raceId: 17, previousJobId: 9, currentJobId: 10,  actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // 鬼 修道者→侍
            PartyMemberConfig(raceId: 15, previousJobId: 9, currentJobId: 10,  actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // 巨人 修道者→侍
            PartyMemberConfig(raceId: 17, previousJobId: 14, currentJobId: 11, actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // 鬼 忍者→剣聖
            PartyMemberConfig(raceId: 5,  previousJobId: 6, currentJobId: 1,   actionRates: BattleActionRates(attack: 80, priestMagic: 20, mageMagic: 0, breath: 0)), // ドワーフ 僧侶→戦士
            PartyMemberConfig(raceId: 4,  previousJobId: 6, currentJobId: 106, actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)), // ノーム 僧侶→僧侶M
            PartyMemberConfig(raceId: 8,  previousJobId: 6, currentJobId: 13,  actionRates: BattleActionRates(attack: 0, priestMagic: 50, mageMagic: 50, breath: 0)), // エルフ 僧侶→賢者
        ]),

        // Party 9: 回復厚め
        PartyConfig(name: "回復厚め", members: [
            PartyMemberConfig(raceId: 5,  previousJobId: 6, currentJobId: 1,   actionRates: BattleActionRates(attack: 80, priestMagic: 20, mageMagic: 0, breath: 0)), // ドワーフ 僧侶→戦士
            PartyMemberConfig(raceId: 15, previousJobId: 6, currentJobId: 15,  actionRates: BattleActionRates(attack: 50, priestMagic: 50, mageMagic: 0, breath: 0)), // 巨人 僧侶→君主
            PartyMemberConfig(raceId: 4,  previousJobId: 6, currentJobId: 106, actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)), // ノーム 僧侶→僧侶M
            PartyMemberConfig(raceId: 8,  previousJobId: 9, currentJobId: 6,   actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)), // エルフ 修道者→僧侶
            PartyMemberConfig(raceId: 4,  previousJobId: 9, currentJobId: 13,  actionRates: BattleActionRates(attack: 0, priestMagic: 50, mageMagic: 50, breath: 0)), // ノーム 修道者→賢者
            PartyMemberConfig(raceId: 8,  previousJobId: 6, currentJobId: 13,  actionRates: BattleActionRates(attack: 0, priestMagic: 50, mageMagic: 50, breath: 0)), // エルフ 僧侶→賢者
        ]),

        // Party 10: ハイブリッド
        PartyConfig(name: "ハイブリッド", members: [
            PartyMemberConfig(raceId: 5,  previousJobId: 7, currentJobId: 12,  actionRates: BattleActionRates(attack: 50, priestMagic: 0, mageMagic: 50, breath: 0)), // ドワーフ 魔法使い→秘法剣士
            PartyMemberConfig(raceId: 8,  previousJobId: 7, currentJobId: 12,  actionRates: BattleActionRates(attack: 50, priestMagic: 0, mageMagic: 50, breath: 0)), // エルフ 魔法使い→秘法剣士
            PartyMemberConfig(raceId: 16, previousJobId: 3, currentJobId: 14,  actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // 天狗 盗賊→忍者
            PartyMemberConfig(raceId: 4,  previousJobId: 6, currentJobId: 106, actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)), // ノーム 僧侶→僧侶M
            PartyMemberConfig(raceId: 9,  previousJobId: 7, currentJobId: 13,  actionRates: BattleActionRates(attack: 0, priestMagic: 50, mageMagic: 50, breath: 0)), // サイキック 魔法使い→賢者
            PartyMemberConfig(raceId: 3,  previousJobId: 6, currentJobId: 3,   actionRates: BattleActionRates(attack: 60, priestMagic: 40, mageMagic: 0, breath: 0)), // ピグミー 僧侶→盗賊
        ]),

        // Party 11: 前衛厚め
        PartyConfig(name: "前衛厚め", members: [
            PartyMemberConfig(raceId: 5,  previousJobId: 6, currentJobId: 1,   actionRates: BattleActionRates(attack: 80, priestMagic: 20, mageMagic: 0, breath: 0)), // ドワーフ 僧侶→戦士
            PartyMemberConfig(raceId: 15, previousJobId: 6, currentJobId: 1,   actionRates: BattleActionRates(attack: 80, priestMagic: 20, mageMagic: 0, breath: 0)), // 巨人 僧侶→戦士
            PartyMemberConfig(raceId: 14, previousJobId: 1, currentJobId: 15,  actionRates: BattleActionRates(attack: 50, priestMagic: 50, mageMagic: 0, breath: 0)), // アンデッド 戦士→君主
            PartyMemberConfig(raceId: 17, previousJobId: 9, currentJobId: 10,  actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // 鬼 修道者→侍
            PartyMemberConfig(raceId: 4,  previousJobId: 6, currentJobId: 106, actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)), // ノーム 僧侶→僧侶M
            PartyMemberConfig(raceId: 8,  previousJobId: 6, currentJobId: 106, actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)), // エルフ 僧侶→僧侶M
        ]),

        // Party 12: 後衛厚め
        PartyConfig(name: "後衛厚め", members: [
            PartyMemberConfig(raceId: 5,  previousJobId: 6, currentJobId: 1,   actionRates: BattleActionRates(attack: 80, priestMagic: 20, mageMagic: 0, breath: 0)), // ドワーフ 僧侶→戦士
            PartyMemberConfig(raceId: 9,  previousJobId: 7, currentJobId: 107, actionRates: BattleActionRates(attack: 0, priestMagic: 0, mageMagic: 100, breath: 0)), // サイキック 魔法使い→魔法使いM
            PartyMemberConfig(raceId: 6,  previousJobId: 7, currentJobId: 107, actionRates: BattleActionRates(attack: 0, priestMagic: 0, mageMagic: 100, breath: 0)), // ダークエルフ 魔法使い→魔法使いM
            PartyMemberConfig(raceId: 4,  previousJobId: 6, currentJobId: 106, actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)), // ノーム 僧侶→僧侶M
            PartyMemberConfig(raceId: 4,  previousJobId: 9, currentJobId: 13,  actionRates: BattleActionRates(attack: 0, priestMagic: 50, mageMagic: 50, breath: 0)), // ノーム 修道者→賢者
            PartyMemberConfig(raceId: 8,  previousJobId: 6, currentJobId: 13,  actionRates: BattleActionRates(attack: 0, priestMagic: 50, mageMagic: 50, breath: 0)), // エルフ 僧侶→賢者
        ]),

        // Party 13: クリ特化
        PartyConfig(name: "クリ特化", members: [
            PartyMemberConfig(raceId: 18, previousJobId: 3, currentJobId: 14,  actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // サイボーグ 盗賊→忍者
            PartyMemberConfig(raceId: 16, previousJobId: 3, currentJobId: 14,  actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // 天狗 盗賊→忍者
            PartyMemberConfig(raceId: 10, previousJobId: 14, currentJobId: 8,  actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // ワーキャット 忍者→狩人
            PartyMemberConfig(raceId: 3,  previousJobId: 6, currentJobId: 3,   actionRates: BattleActionRates(attack: 60, priestMagic: 40, mageMagic: 0, breath: 0)), // ピグミー 僧侶→盗賊
            PartyMemberConfig(raceId: 4,  previousJobId: 6, currentJobId: 106, actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)), // ノーム 僧侶→僧侶M
            PartyMemberConfig(raceId: 9,  previousJobId: 7, currentJobId: 107, actionRates: BattleActionRates(attack: 0, priestMagic: 0, mageMagic: 100, breath: 0)), // サイキック 魔法使い→魔法使いM
        ]),

        // Party 14: マスター揃い
        PartyConfig(name: "マスター揃い", members: [
            PartyMemberConfig(raceId: 5,  previousJobId: 1, currentJobId: 101, actionRates: BattleActionRates(attack: 80, priestMagic: 0, mageMagic: 0, breath: 0)),  // ドワーフ 戦士→戦士M
            PartyMemberConfig(raceId: 17, previousJobId: 10, currentJobId: 110, actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // 鬼 侍→侍M
            PartyMemberConfig(raceId: 18, previousJobId: 14, currentJobId: 114, actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // サイボーグ 忍者→忍者M
            PartyMemberConfig(raceId: 4,  previousJobId: 6, currentJobId: 106, actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)), // ノーム 僧侶→僧侶M
            PartyMemberConfig(raceId: 9,  previousJobId: 7, currentJobId: 107, actionRates: BattleActionRates(attack: 0, priestMagic: 0, mageMagic: 100, breath: 0)), // サイキック 魔法使い→魔法使いM
            PartyMemberConfig(raceId: 3,  previousJobId: 3, currentJobId: 103, actionRates: BattleActionRates(attack: 60, priestMagic: 0, mageMagic: 0, breath: 0)),  // ピグミー 盗賊→盗賊M
        ]),

        // Party 15: 異色転職A
        PartyConfig(name: "異色転職A", members: [
            PartyMemberConfig(raceId: 7,  previousJobId: 6, currentJobId: 2,   actionRates: BattleActionRates(attack: 80, priestMagic: 20, mageMagic: 0, breath: 0)), // 吸血鬼 僧侶→剣士
            PartyMemberConfig(raceId: 11, previousJobId: 9, currentJobId: 2,   actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // ドラゴニュート 修道者→剣士
            PartyMemberConfig(raceId: 16, previousJobId: 7, currentJobId: 14,  actionRates: BattleActionRates(attack: 80, priestMagic: 0, mageMagic: 20, breath: 0)), // 天狗 魔法使い→忍者
            PartyMemberConfig(raceId: 4,  previousJobId: 6, currentJobId: 13,  actionRates: BattleActionRates(attack: 0, priestMagic: 50, mageMagic: 50, breath: 0)), // ノーム 僧侶→賢者
            PartyMemberConfig(raceId: 8,  previousJobId: 6, currentJobId: 106, actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)), // エルフ 僧侶→僧侶M
            PartyMemberConfig(raceId: 3,  previousJobId: 6, currentJobId: 3,   actionRates: BattleActionRates(attack: 60, priestMagic: 40, mageMagic: 0, breath: 0)), // ピグミー 僧侶→盗賊
        ]),

        // Party 16: 異色転職B
        PartyConfig(name: "異色転職B", members: [
            PartyMemberConfig(raceId: 12, previousJobId: 14, currentJobId: 10, actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)), // アマゾネス 忍者→侍
            PartyMemberConfig(raceId: 15, previousJobId: 3, currentJobId: 1,   actionRates: BattleActionRates(attack: 80, priestMagic: 0, mageMagic: 0, breath: 0)),  // 巨人 盗賊→戦士
            PartyMemberConfig(raceId: 6,  previousJobId: 9, currentJobId: 7,   actionRates: BattleActionRates(attack: 0, priestMagic: 0, mageMagic: 100, breath: 0)), // ダークエルフ 修道者→魔法使い
            PartyMemberConfig(raceId: 4,  previousJobId: 6, currentJobId: 106, actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)), // ノーム 僧侶→僧侶M
            PartyMemberConfig(raceId: 8,  previousJobId: 6, currentJobId: 13,  actionRates: BattleActionRates(attack: 0, priestMagic: 50, mageMagic: 50, breath: 0)), // エルフ 僧侶→賢者
            PartyMemberConfig(raceId: 5,  previousJobId: 6, currentJobId: 15,  actionRates: BattleActionRates(attack: 50, priestMagic: 50, mageMagic: 0, breath: 0)), // ドワーフ 僧侶→君主
        ]),
    ]

    // MARK: - Equipment Grade Configuration

    /// 装備グレード（ダンジョンレベルに応じて選択）
    private enum EquipmentGrade: CaseIterable {
        case early    // Lv 1-30
        case mid      // Lv 31-80
        case late     // Lv 81-150
        case endgame  // Lv 151+

        static func from(level: Int) -> EquipmentGrade {
            switch level {
            case 0...30: return .early
            case 31...80: return .mid
            case 81...150: return .late
            default: return .endgame
            }
        }
    }

    // MARK: - Cached Data

    private var repository: MasterDataRepository!
    private var dungeons: [DungeonDefinition] = []
    private var floors: [DungeonFloorDefinition] = []
    private var encounterTables: [String: EncounterTableDefinition] = [:]
    private var enemies: [UInt16: EnemyDefinition] = [:]
    private var skills: [UInt16: SkillDefinition] = [:]
    private var enemySkills: [UInt16: EnemySkillDefinition] = [:]
    private var jobs: [UInt8: JobDefinition] = [:]
    private var races: [UInt8: RaceDefinition] = [:]
    private var statusEffects: [UInt8: StatusEffectDefinition] = [:]
    private var racePassiveSkills: [UInt8: [UInt16]] = [:]
    private var items: [UInt16: ItemDefinition] = [:]

    // 装備グレード別アイテムID
    private var equipmentByGrade: [EquipmentGrade: GradeEquipment] = [:]

    private struct GradeEquipment: Sendable {
        let katana: UInt16      // 侍用
        let thinSword: UInt16   // 格闘アタッカー用
        let rod: UInt16         // 僧侶用
        let wand: UInt16        // 魔法使い用
        let armor: UInt16       // 軽鎧
        let heavyArmor: UInt16  // 重鎧
        let robe: UInt16        // 法衣
        let shield: UInt16      // 盾
    }

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        repository = MasterDataRepository()

        // マスターデータを読み込む
        let (loadedDungeons, loadedTables, loadedFloors) = try await repository.allDungeons()
        dungeons = loadedDungeons.sorted { $0.id < $1.id }
        floors = loadedFloors
        encounterTables = Dictionary(uniqueKeysWithValues: loadedTables.map { ($0.id, $0) })

        let enemyList = try await repository.allEnemies()
        enemies = Dictionary(uniqueKeysWithValues: enemyList.map { ($0.id, $0) })

        let skillList = try await repository.allSkills()
        skills = Dictionary(uniqueKeysWithValues: skillList.map { ($0.id, $0) })

        let enemySkillList = try await repository.allEnemySkills()
        enemySkills = Dictionary(uniqueKeysWithValues: enemySkillList.map { ($0.id, $0) })

        let jobList = try await repository.allJobs()
        jobs = Dictionary(uniqueKeysWithValues: jobList.map { ($0.id, $0) })

        let raceList = try await repository.allRaces()
        races = Dictionary(uniqueKeysWithValues: raceList.map { ($0.id, $0) })

        let statusList = try await repository.allStatusEffects()
        statusEffects = Dictionary(uniqueKeysWithValues: statusList.map { ($0.id, $0) })

        racePassiveSkills = try await SQLiteMasterDataManager.shared.fetchAllRacePassiveSkills()

        let itemList = try await repository.allItems()
        items = Dictionary(uniqueKeysWithValues: itemList.map { ($0.id, $0) })

        // 装備グレード別アイテムを選択
        setupEquipmentByGrade()

        // 出力ディレクトリを作成
        try FileManager.default.createDirectory(atPath: Self.outputDirectory,
                                                withIntermediateDirectories: true)
    }

    private func setupEquipmentByGrade() {
        // 各カテゴリのアイテムを価格順にソート
        let katanas = items.values.filter { $0.category == "katana" }.sorted { $0.basePrice < $1.basePrice }
        let thinSwords = items.values.filter { $0.category == "thin_sword" }.sorted { $0.basePrice < $1.basePrice }
        let rods = items.values.filter { $0.category == "rod" }.sorted { $0.basePrice < $1.basePrice }
        let wands = items.values.filter { $0.category == "wand" }.sorted { $0.basePrice < $1.basePrice }
        let armors = items.values.filter { $0.category == "armor" }.sorted { $0.basePrice < $1.basePrice }
        let heavyArmors = items.values.filter { $0.category == "heavy_armor" }.sorted { $0.basePrice < $1.basePrice }
        let robes = items.values.filter { $0.category == "robe" }.sorted { $0.basePrice < $1.basePrice }
        let shields = items.values.filter { $0.category == "shield" }.sorted { $0.basePrice < $1.basePrice }

        // グレードごとにアイテムを選択（配列の位置で選択）
        func selectItem(_ array: [ItemDefinition], at percentile: Double) -> UInt16 {
            guard !array.isEmpty else { return 0 }
            let index = min(Int(Double(array.count - 1) * percentile), array.count - 1)
            return UInt16(array[index].id)
        }

        equipmentByGrade[.early] = GradeEquipment(
            katana: selectItem(katanas, at: 0.1),
            thinSword: selectItem(thinSwords, at: 0.1),
            rod: selectItem(rods, at: 0.1),
            wand: selectItem(wands, at: 0.1),
            armor: selectItem(armors, at: 0.1),
            heavyArmor: selectItem(heavyArmors, at: 0.1),
            robe: selectItem(robes, at: 0.1),
            shield: selectItem(shields, at: 0.1)
        )

        equipmentByGrade[.mid] = GradeEquipment(
            katana: selectItem(katanas, at: 0.4),
            thinSword: selectItem(thinSwords, at: 0.4),
            rod: selectItem(rods, at: 0.4),
            wand: selectItem(wands, at: 0.4),
            armor: selectItem(armors, at: 0.4),
            heavyArmor: selectItem(heavyArmors, at: 0.4),
            robe: selectItem(robes, at: 0.4),
            shield: selectItem(shields, at: 0.4)
        )

        equipmentByGrade[.late] = GradeEquipment(
            katana: selectItem(katanas, at: 0.7),
            thinSword: selectItem(thinSwords, at: 0.7),
            rod: selectItem(rods, at: 0.7),
            wand: selectItem(wands, at: 0.7),
            armor: selectItem(armors, at: 0.7),
            heavyArmor: selectItem(heavyArmors, at: 0.7),
            robe: selectItem(robes, at: 0.7),
            shield: selectItem(shields, at: 0.7)
        )

        equipmentByGrade[.endgame] = GradeEquipment(
            katana: selectItem(katanas, at: 0.95),
            thinSword: selectItem(thinSwords, at: 0.95),
            rod: selectItem(rods, at: 0.95),
            wand: selectItem(wands, at: 0.95),
            armor: selectItem(armors, at: 0.95),
            heavyArmor: selectItem(heavyArmors, at: 0.95),
            robe: selectItem(robes, at: 0.95),
            shield: selectItem(shields, at: 0.95)
        )
    }

    // MARK: - Main Test

    func testAllDungeonsWith16Parties() async throws {
        print("=== 迷宮バランステスト（16パーティ版）===")
        print("パーティ数: \(Self.partyConfigs.count)")
        print("ダンジョン数: \(dungeons.count)")
        print("戦闘回数/ダンジョン/パーティ: \(Self.battleCount)")
        print("注意: Swift 6のConcurrency制約により、シーケンシャル実行です")
        print("")

        var allResults: [PartyDungeonResult] = []

        // パーティをシーケンシャルに処理（MainActor制約のため並列不可）
        for (partyId, partyConfig) in Self.partyConfigs.enumerated() {
            let partyResults = runDungeonTestsForParty(partyId: partyId, partyConfig: partyConfig)
            allResults.append(contentsOf: partyResults)
        }

        // 結果を保存
        try saveResults(allResults)

        XCTAssertFalse(allResults.isEmpty, "テスト結果がありません")
    }

    private func runDungeonTestsForParty(partyId: Int, partyConfig: PartyConfig) -> [PartyDungeonResult] {
        var results: [PartyDungeonResult] = []
        var currentLevel = 1

        for dungeon in dungeons {
            currentLevel = max(currentLevel, dungeon.recommendedLevel)

            let bossEnemyGroups = getBossEnemyGroups(dungeon: dungeon)
            guard !bossEnemyGroups.isEmpty else { continue }

            do {
                let result = try runBossBattles(
                    partyId: partyId,
                    partyConfig: partyConfig,
                    dungeon: dungeon,
                    bossEnemyGroups: bossEnemyGroups,
                    partyLevel: currentLevel
                )
                results.append(result)

                let winRate = Double(result.wins) / Double(result.totalBattles) * 100
                print("Party[\(partyId)] \(partyConfig.name) × \(dungeon.name): \(String(format: "%.1f", winRate))%")
            } catch {
                print("Error: Party[\(partyId)] \(dungeon.name): \(error)")
            }
        }

        return results
    }

    // MARK: - Battle Execution

    private func runBossBattles(
        partyId: Int,
        partyConfig: PartyConfig,
        dungeon: DungeonDefinition,
        bossEnemyGroups: [(enemyId: UInt16, level: Int?, groupMin: Int, groupMax: Int)],
        partyLevel: Int
    ) throws -> PartyDungeonResult {
        var wins = 0
        var losses = 0
        var totalTurns = 0

        let defaultLevel = dungeon.recommendedLevel
        let grade = EquipmentGrade.from(level: partyLevel)

        for seed in 0..<Self.battleCount {
            var random = GameRandomSource(seed: UInt64(partyId * 10000 + seed))

            let groupIndex = random.nextInt(in: 0...(bossEnemyGroups.count - 1))
            let selectedGroup = bossEnemyGroups[groupIndex]
            let enemyLevel = selectedGroup.level ?? defaultLevel
            let groupMin = selectedGroup.groupMin
            let groupMax = selectedGroup.groupMax
            let groupSize = groupMin == groupMax ? groupMin : random.nextInt(in: groupMin...groupMax)

            var enemyActors = try buildEnemyActors(
                enemyId: selectedGroup.enemyId,
                level: enemyLevel,
                groupSize: groupSize,
                random: &random
            )

            var playerActors = try buildPlayerActors(
                partyConfig: partyConfig,
                level: partyLevel,
                grade: grade
            )

            let result = BattleTurnEngine.runBattle(
                players: &playerActors,
                enemies: &enemyActors,
                statusEffects: statusEffects,
                skillDefinitions: skills,
                enemySkillDefinitions: enemySkills,
                random: &random
            )

            if result.outcome == BattleLog.outcomeVictory {
                wins += 1
            } else {
                losses += 1
            }
            totalTurns += Int(result.battleLog.turns)
        }

        return PartyDungeonResult(
            partyId: partyId,
            partyName: partyConfig.name,
            dungeonId: dungeon.id,
            dungeonName: dungeon.name,
            chapter: dungeon.chapter,
            stage: dungeon.stage,
            recommendedLevel: dungeon.recommendedLevel,
            partyLevel: partyLevel,
            totalBattles: Self.battleCount,
            wins: wins,
            losses: losses,
            averageTurns: Double(totalTurns) / Double(Self.battleCount)
        )
    }

    // MARK: - Actor Building

    private func buildEnemyActors(
        enemyId: UInt16,
        level: Int,
        groupSize: Int,
        random: inout GameRandomSource
    ) throws -> [BattleActor] {
        guard let definition = enemies[enemyId] else {
            throw TestError.enemyNotFound(enemyId)
        }

        let count = max(1, groupSize)
        var actors: [BattleActor] = []

        for index in 0..<count {
            guard let slot = BattleContextBuilder.slot(for: index) else { break }

            let snapshot = try CombatSnapshotBuilder.makeEnemySnapshot(
                from: definition,
                levelOverride: level,
                jobDefinitions: jobs
            )

            let skillDefs = definition.specialSkillIds.compactMap { skills[$0] }
            let skillEffects = try SkillRuntimeEffectCompiler.actorEffects(from: skillDefs)

            var resources = BattleActionResource.makeDefault(for: snapshot, spellLoadout: .empty)
            if skillEffects.spell.breathExtraCharges > 0 {
                let current = resources.charges(for: .breath)
                resources.setCharges(for: .breath, value: current + skillEffects.spell.breathExtraCharges)
            }

            let actor = BattleActor(
                identifier: "\(definition.id)_\(index)",
                displayName: definition.name,
                kind: .enemy,
                formationSlot: slot,
                strength: definition.strength,
                wisdom: definition.wisdom,
                spirit: definition.spirit,
                vitality: definition.vitality,
                agility: definition.agility,
                luck: definition.luck,
                partyMemberId: nil,
                level: level,
                jobName: definition.jobId.flatMap { jobs[$0]?.name },
                avatarIndex: nil,
                isMartialEligible: false,
                raceId: definition.raceId,
                snapshot: snapshot,
                currentHP: snapshot.maxHP,
                actionRates: BattleActionRates(
                    attack: definition.actionRates.attack,
                    priestMagic: definition.actionRates.priestMagic,
                    mageMagic: definition.actionRates.mageMagic,
                    breath: definition.actionRates.breath
                ),
                actionResources: resources,
                barrierCharges: skillEffects.combat.barrierCharges,
                skillEffects: skillEffects,
                spellbook: .empty,
                spells: .empty,
                baseSkillIds: Set(definition.specialSkillIds),
                innateResistances: BattleInnateResistances(from: definition.resistances)
            )
            actors.append(actor)
        }

        return actors
    }

    private func buildPlayerActors(
        partyConfig: PartyConfig,
        level: Int,
        grade: EquipmentGrade
    ) throws -> [BattleActor] {
        var actors: [BattleActor] = []
        guard let gradeEquipment = equipmentByGrade[grade] else {
            throw TestError.equipmentGradeNotFound(grade)
        }

        for (index, memberConfig) in partyConfig.members.enumerated() {
            guard let slot = BattleContextBuilder.slot(for: index) else { break }
            guard let race = races[memberConfig.raceId] else {
                throw TestError.raceNotFound(memberConfig.raceId)
            }
            guard let currentJob = jobs[memberConfig.currentJobId] else {
                throw TestError.jobNotFound(memberConfig.currentJobId)
            }

            // スキルを収集（種族パッシブ + 前職パッシブ + 現職パッシブ）
            var learnedSkillIds: [UInt16] = []
            if let raceSkills = racePassiveSkills[memberConfig.raceId] {
                learnedSkillIds.append(contentsOf: raceSkills)
            }
            if let prevJob = jobs[memberConfig.previousJobId] {
                learnedSkillIds.append(contentsOf: prevJob.learnedSkillIds)
            }
            learnedSkillIds.append(contentsOf: currentJob.learnedSkillIds)

            // 装備スキルを追加
            let equippedItemIds = Self.getEquippedItems(for: memberConfig, grade: gradeEquipment)
            for itemId in equippedItemIds where itemId > 0 {
                if let item = items[itemId] {
                    learnedSkillIds.append(contentsOf: item.grantedSkillIds.map { UInt16($0) })
                }
            }

            let learnedSkills = learnedSkillIds.compactMap { skills[$0] }

            // ステータス計算
            let baseStats = race.baseStats
            let strength = baseStats.strength + level / 2
            let wisdom = baseStats.wisdom + level / 2
            let spirit = baseStats.spirit + level / 2
            let vitality = baseStats.vitality + level / 2
            let agility = baseStats.agility + level / 2
            let luck = baseStats.luck + level / 2

            let baseHP = vitality * 12 + spirit * 6 + level * 10
            let maxHP = Int(Double(baseHP) * currentJob.combatCoefficients.maxHP)

            let physAtk = Int(Double(strength * 2 + level * 2) * currentJob.combatCoefficients.physicalAttack)
            let magAtk = Int(Double(wisdom * 2 + level * 2) * currentJob.combatCoefficients.magicalAttack)
            let physDef = Int(Double(vitality * 2 + level) * currentJob.combatCoefficients.physicalDefense)
            let magDef = Int(Double(spirit * 2 + level) * currentJob.combatCoefficients.magicalDefense)
            let hitRate = Int(Double(agility * 2 + luck) * currentJob.combatCoefficients.hitRate)
            let evasion = Int(Double(agility * 2) * currentJob.combatCoefficients.evasionRate)
            let critical = Int(Double(luck / 2 + 5) * currentJob.combatCoefficients.criticalRate)
            let atkCount = max(1, Int(Double(agility / 30 + 1) * currentJob.combatCoefficients.attackCount))
            let magHeal = Int(Double(spirit * 2 + wisdom) * currentJob.combatCoefficients.magicalHealing)

            let snapshot = CharacterValues.Combat(
                maxHP: max(1, maxHP),
                physicalAttack: max(1, physAtk),
                magicalAttack: max(1, magAtk),
                physicalDefense: max(1, physDef),
                magicalDefense: max(1, magDef),
                hitRate: max(1, hitRate),
                evasionRate: max(0, evasion),
                criticalRate: max(0, critical),
                attackCount: max(1, atkCount),
                magicalHealing: max(0, magHeal),
                trapRemoval: 0,
                additionalDamage: 0,
                breathDamage: 0,
                isMartialEligible: !memberConfig.isSamurai
            )

            let stats = ActorStats(
                strength: strength,
                wisdom: wisdom,
                spirit: spirit,
                vitality: vitality,
                agility: agility,
                luck: luck
            )
            let skillEffects = try SkillRuntimeEffectCompiler.actorEffects(from: learnedSkills, stats: stats)

            var resources = BattleActionResource.makeDefault(for: snapshot, spellLoadout: .empty)
            if skillEffects.spell.breathExtraCharges > 0 {
                let current = resources.charges(for: .breath)
                resources.setCharges(for: .breath, value: current + skillEffects.spell.breathExtraCharges)
            }

            let actor = BattleActor(
                identifier: "party\(index)",
                displayName: "\(race.name)\(currentJob.name)",
                kind: .player,
                formationSlot: slot,
                strength: strength,
                wisdom: wisdom,
                spirit: spirit,
                vitality: vitality,
                agility: agility,
                luck: luck,
                partyMemberId: UInt8(index),
                level: level,
                jobName: currentJob.name,
                avatarIndex: nil,
                isMartialEligible: !memberConfig.isSamurai,
                raceId: memberConfig.raceId,
                snapshot: snapshot,
                currentHP: snapshot.maxHP,
                actionRates: memberConfig.actionRates,
                actionResources: resources,
                barrierCharges: skillEffects.combat.barrierCharges,
                skillEffects: skillEffects,
                spellbook: .empty,
                spells: .empty,
                baseSkillIds: Set(learnedSkillIds)
            )
            actors.append(actor)
        }

        return actors
    }

    private static func getEquippedItems(for config: PartyMemberConfig, grade: GradeEquipment) -> [UInt16] {
        var equippedItems: [UInt16] = []

        // 武器
        if config.isSamurai {
            equippedItems.append(grade.katana)
        } else if config.isAttacker {
            equippedItems.append(grade.thinSword)
        } else if config.isBackline {
            // 僧侶系はrod、魔法使い系はwand
            let priestJobs: Set<UInt8> = [6, 13, 106, 113]
            if priestJobs.contains(config.currentJobId) {
                equippedItems.append(grade.rod)
            } else {
                equippedItems.append(grade.wand)
            }
        }

        // 防具
        if config.isBackline {
            equippedItems.append(grade.robe)
        } else {
            let tankJobs: Set<UInt8> = [1, 15, 101, 115]
            if tankJobs.contains(config.currentJobId) {
                equippedItems.append(grade.heavyArmor)
                equippedItems.append(grade.shield)
            } else {
                equippedItems.append(grade.armor)
            }
        }

        return equippedItems
    }

    // MARK: - Helper Methods

    private func getBossEnemyGroups(dungeon: DungeonDefinition) -> [(enemyId: UInt16, level: Int?, groupMin: Int, groupMax: Int)] {
        let bossFloorNumber = dungeon.floorCount
        guard let bossFloor = floors.first(where: { $0.dungeonId == dungeon.id && $0.floorNumber == bossFloorNumber }),
              let table = encounterTables[bossFloor.encounterTableId] else {
            return []
        }

        return table.events.compactMap { event -> (enemyId: UInt16, level: Int?, groupMin: Int, groupMax: Int)? in
            guard let enemyId = event.enemyId else { return nil }
            return (
                enemyId: enemyId,
                level: event.level,
                groupMin: event.groupMin ?? 1,
                groupMax: event.groupMax ?? 1
            )
        }
    }

    // MARK: - Result Output

    private func saveResults(_ results: [PartyDungeonResult]) throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())

        // ダンジョン別の平均勝率を計算
        var dungeonWinRates: [UInt16: [Double]] = [:]
        for result in results {
            let winRate = Double(result.wins) / Double(result.totalBattles)
            dungeonWinRates[result.dungeonId, default: []].append(winRate)
        }

        var markdown = """
        # 迷宮バランステスト結果（16パーティ版）

        実行日時: \(timestamp)
        パーティ数: \(Self.partyConfigs.count)
        ダンジョン数: \(dungeons.count)
        戦闘回数: \(Self.battleCount)回/ダンジョン/パーティ

        ## ダンジョン別平均勝率

        | 章 | ダンジョン | 推奨Lv | 平均勝率 | 最高勝率 | 最低勝率 | 評価 |
        |---:|----------|-------:|--------:|--------:|--------:|------|
        """

        for dungeon in dungeons {
            guard let rates = dungeonWinRates[dungeon.id], !rates.isEmpty else { continue }
            let avgRate = rates.reduce(0, +) / Double(rates.count)
            let maxRate = rates.max() ?? 0
            let minRate = rates.min() ?? 0

            let status: String
            if avgRate >= 0.85 {
                status = "簡単"
            } else if avgRate >= 0.70 {
                status = "適正"
            } else if avgRate >= 0.50 {
                status = "難"
            } else {
                status = "激難"
            }

            markdown += "\n| \(dungeon.chapter)-\(dungeon.stage) | \(dungeon.name) | \(dungeon.recommendedLevel) | \(String(format: "%.1f", avgRate * 100))% | \(String(format: "%.1f", maxRate * 100))% | \(String(format: "%.1f", minRate * 100))% | \(status) |"
        }

        markdown += "\n\n## パーティ別成績\n\n"
        markdown += "| パーティ | 平均勝率 | クリアダンジョン数 |\n"
        markdown += "|----------|--------:|------------------:|\n"

        for (index, config) in Self.partyConfigs.enumerated() {
            let partyResults = results.filter { $0.partyId == index }
            let avgWinRate = partyResults.isEmpty ? 0 : partyResults.map { Double($0.wins) / Double($0.totalBattles) }.reduce(0, +) / Double(partyResults.count)
            let clearedCount = partyResults.filter { Double($0.wins) / Double($0.totalBattles) >= 0.5 }.count
            markdown += "| \(config.name) | \(String(format: "%.1f", avgWinRate * 100))% | \(clearedCount)/\(partyResults.count) |\n"
        }

        let filePath = "\(Self.outputDirectory)/dungeon_balance_\(timestamp).md"
        try markdown.write(toFile: filePath, atomically: true, encoding: .utf8)
        print("\n📄 結果を保存しました: \(filePath)")
    }

    // MARK: - Types

    private struct PartyDungeonResult {
        let partyId: Int
        let partyName: String
        let dungeonId: UInt16
        let dungeonName: String
        let chapter: Int
        let stage: Int
        let recommendedLevel: Int
        let partyLevel: Int
        let totalBattles: Int
        let wins: Int
        let losses: Int
        let averageTurns: Double
    }

    private enum TestError: Error {
        case enemyNotFound(UInt16)
        case raceNotFound(UInt8)
        case jobNotFound(UInt8)
        case equipmentGradeNotFound(EquipmentGrade)
    }
}
