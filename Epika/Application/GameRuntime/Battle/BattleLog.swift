// ==============================================================================
// BattleLog.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 戦闘ログのデータ構造定義（数値形式）
//   - 行動種別（ActionKind）の定義
//   - パーティメンバースナップショットの保持
//
// 【データ構造】
//   - BattleLog: 戦闘全体のログ（初期HP、行動リスト、結果、ターン数）
//   - ActionKind: 行動種別の列挙（攻撃、魔法、状態異常等）
//   - PartyMemberSnapshot: 探索開始時のパーティメンバー情報
//
// 【使用箇所】
//   - BattleContext（ログの記録）
//   - BattleLogRenderer（表示用変換）
//
// ==============================================================================

import Foundation

// MARK: - BattleActionEntry (Next-gen structure)

/// 行動宣言と結果を1レコードにまとめた新版ログ構造
/// 移行期間はBattleActionと併存させ、順次こちらへ置き換える
nonisolated struct BattleActionEntry: Codable, Sendable {
    struct Declaration: Codable, Sendable {
        var kind: ActionKind
        var skillIndex: UInt16?
        var extra: UInt16?
        var label: String?
    }

    struct Effect: Codable, Sendable {
        enum Kind: UInt8, Codable, Sendable {
            case physicalDamage
            case physicalEvade
            case physicalParry
            case physicalBlock
            case physicalKill
            case martial
            case magicDamage
            case magicHeal
            case magicMiss
            case breathDamage
            case statusInflict
            case statusResist
            case statusRecover
            case statusTick
            case statusConfusion
            case statusRampage
            case reactionAttack
            case followUp
            case healAbsorb
            case healVampire
            case healParty
            case healSelf
            case damageSelf
            case buffApply
            case buffExpire
            case resurrection
            case necromancer
            case rescue
            case actionLocked
            case noAction
            case withdraw
            case sacrifice
            case vampireUrge
            case enemySpecialDamage
            case enemySpecialHeal
            case enemySpecialBuff
            case spellChargeRecover
            case enemyAppear
            case logOnly
        }

        var kind: Kind
        var target: UInt16?
        var value: UInt32?
        var statusId: UInt16?
        var extra: UInt16?
    }

    var turn: UInt8
    var actor: UInt16?
    var declaration: Declaration
    var effects: [Effect]

    nonisolated init(turn: Int,
         actor: UInt16?,
         declaration: Declaration,
         effects: [Effect] = []) {
        self.turn = UInt8(clamping: turn)
        self.actor = actor
        self.declaration = declaration
        self.effects = effects
    }
}

extension BattleActionEntry {
    nonisolated final class Builder {
        let turn: Int
        let actor: UInt16?
        let declaration: Declaration
        private var effects: [Effect]

        nonisolated init(turn: Int, actor: UInt16?, declaration: Declaration) {
            self.turn = turn
            self.actor = actor
            self.declaration = declaration
            self.effects = []
        }

        nonisolated func addEffect(_ effect: Effect) {
            effects.append(effect)
        }

        nonisolated func addEffect(kind: Effect.Kind,
                       target: UInt16?,
                       value: UInt32? = nil,
                       statusId: UInt16? = nil,
                       extra: UInt16? = nil) {
            addEffect(Effect(kind: kind, target: target, value: value, statusId: statusId, extra: extra))
        }

        nonisolated func build() -> BattleActionEntry {
            BattleActionEntry(
                turn: turn,
                actor: actor,
                declaration: declaration,
                effects: effects
            )
        }
    }
}

// MARK: - BattleLog

/// 戦闘ログ全体
nonisolated struct BattleLog: Codable, Sendable {
    static let currentVersion: UInt8 = 3

    var version: UInt8               // battle log schema version
    var initialHP: [UInt16: UInt32]  // actorIndex → 開始時HP
    var entries: [BattleActionEntry] // 新形式
    var outcome: UInt8               // 0=victory, 1=defeat, 2=retreat
    var turns: UInt8                 // 総ターン数

    static let empty = BattleLog(initialHP: [:], entries: [], outcome: 0, turns: 0)

    private enum CodingKeys: String, CodingKey {
        case version
        case initialHP
        case entries
        case outcome
        case turns
    }

    init(initialHP: [UInt16: UInt32],
         entries: [BattleActionEntry] = [],
         outcome: UInt8,
         turns: UInt8,
         version: UInt8 = BattleLog.currentVersion) {
        self.version = version
        self.initialHP = initialHP
        self.entries = entries
        self.outcome = outcome
        self.turns = turns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(UInt8.self, forKey: .version) ?? 0
        guard decodedVersion == BattleLog.currentVersion else {
            throw BattleLogDecodingError.unsupportedVersion(decodedVersion)
        }
        version = decodedVersion
        initialHP = try container.decode([UInt16: UInt32].self, forKey: .initialHP)
        entries = try container.decode([BattleActionEntry].self, forKey: .entries)
        outcome = try container.decode(UInt8.self, forKey: .outcome)
        turns = try container.decode(UInt8.self, forKey: .turns)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(initialHP, forKey: .initialHP)
        try container.encode(entries, forKey: .entries)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(turns, forKey: .turns)
    }
}

enum BattleLogDecodingError: Error {
    case unsupportedVersion(UInt8)
}

// MARK: - ActionKind

/// 行動種別（行動選択用 + ログ専用を統合）
/// rawValue は後方互換性のため固定。新規追加時は既存値の間または末尾に配置
enum ActionKind: UInt8, Codable, Sendable {
    // === 行動選択で使用（旧ActionCategory） ===
    case defend = 1               // "{actor}は防御態勢を取った"
    case physicalAttack = 2       // "{actor}の攻撃！"
    case priestMagic = 3          // 僧侶魔法
    case mageMagic = 4            // 魔法使い魔法
    case breath = 5               // ブレス攻撃

    // === ログ専用（結果記録） ===

    // 戦闘開始・終了
    case battleStart = 10         // "戦闘開始！"
    case turnStart = 11           // "--- {turn}ターン目 ---"
    case victory = 12             // "勝利！ 敵を倒した！"
    case defeat = 13              // "敗北… パーティは全滅した…"
    case retreat = 14             // "戦闘は長期化し、パーティは撤退を決断した"

    // 物理攻撃結果
    case physicalDamage = 20      // "{target}に{value}のダメージ！"
    case physicalEvade = 21       // "{target}は攻撃をかわした！"
    case physicalParry = 22       // "{actor}のパリィ！"
    case physicalBlock = 23       // "{actor}の盾防御！"
    case physicalKill = 24        // "{target}を倒した！"
    case martial = 25             // "{actor}の格闘戦！"

    // 魔法結果
    case magicDamage = 30         // "{target}に{value}のダメージ！"
    case magicHeal = 31           // "{target}のHPが{value}回復！"
    case magicMiss = 32           // "しかし効かなかった"

    // ブレス結果
    case breathDamage = 40        // "{target}に{value}のダメージ！"

    // 状態異常
    case statusInflict = 50       // "{target}は{status}になった！"
    case statusResist = 51        // "{target}は抵抗した！"
    case statusRecover = 52       // "{target}の{status}が治った"
    case statusTick = 53          // "{target}は{status}で{value}のダメージ！"
    case statusConfusion = 54     // "{actor}は暴走して混乱した！"
    case statusRampage = 55       // "{actor}の暴走！"

    // 反撃・特殊
    case reactionAttack = 60      // "{actor}の{reaction}！"
    case followUp = 61            // "{actor}の追加攻撃！"

    // 回復・吸収
    case healAbsorb = 70          // "{actor}は吸収能力でHP回復"
    case healVampire = 71         // "{actor}は吸血で回復"
    case healParty = 72           // "{actor}の全体回復！"
    case healSelf = 73            // "{actor}は自身の効果で回復"
    case damageSelf = 74          // "{actor}は自身の効果でダメージ"

    // バフ
    case buffApply = 80           // "{buff}が発動（全体）"
    case buffExpire = 81          // "{actor}の効果が切れた"

    // 蘇生・救助
    case resurrection = 90        // "{target}が蘇生した！"
    case necromancer = 91         // "{actor}のネクロマンサーで蘇生"
    case rescue = 92              // "{actor}は{target}を救出した！"

    // 行動不能・特殊
    case actionLocked = 100       // "{actor}は動けない"
    case noAction = 101           // "{actor}は何もしなかった"
    case withdraw = 102           // "{actor}は戦線離脱した"
    case sacrifice = 103          // "古の儀：{target}が供儀対象になった"
    case vampireUrge = 104        // "{actor}は吸血衝動に駆られた"

    // 敵出現
    case enemyAppear = 110        // "{enemy}が現れた！"

    // 敵専用技
    case enemySpecialSkill = 120  // "{actor}の{skill}！"
    case enemySpecialDamage = 121 // "{target}に{value}のダメージ！"
    case enemySpecialHeal = 122   // "{actor}は{value}回復した！"
    case enemySpecialBuff = 123   // "{actor}は{buff}を発動した！"

    // スキル効果
    case spellChargeRecover = 130 // "{actor}は{spell}のチャージを回復した"
}

// MARK: - Outcome Values

extension BattleLog {
    nonisolated static let outcomeVictory: UInt8 = 0
    nonisolated static let outcomeDefeat: UInt8 = 1
    nonisolated static let outcomeRetreat: UInt8 = 2
}

// MARK: - PartyMemberSnapshot

/// 探索開始時のパーティメンバースナップショット
/// ログ表示時に解雇済みキャラクターでも名前を表示できるように保存
struct PartyMemberSnapshot: Codable, Sendable {
    var characterId: UInt8
    var maxHP: UInt32
    var name: String
    var jobName: String?
}
