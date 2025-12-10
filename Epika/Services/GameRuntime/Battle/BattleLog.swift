import Foundation

// MARK: - BattleAction

/// 戦闘中の1行動 = ログエントリ
/// すべて数値で表現し、表示時のみRendererで文字列化
struct BattleAction: Codable, Sendable {
    var turn: UInt8           // ターン番号（1〜20）
    var kind: UInt8           // ActionKind.rawValue
    var actor: UInt16         // 行動者（味方:1〜200, 敵:1000〜）
    var target: UInt16?       // 対象
    var value: UInt32?        // ダメージ/回復量（常に正の絶対値）
    var skillIndex: UInt16?   // スキル/スペルのマスターデータindex
    var extra: UInt16?        // 倍率×100等（UI表示用）
}

// MARK: - BattleLog

/// 戦闘ログ全体
struct BattleLog: Codable, Sendable {
    var initialHP: [UInt16: UInt32]  // actorIndex → 開始時HP
    var actions: [BattleAction]       // 行動列（これがログ本体）
    var outcome: UInt8                // 0=victory, 1=defeat, 2=retreat
    var turns: UInt8                  // 総ターン数

    static let empty = BattleLog(initialHP: [:], actions: [], outcome: 0, turns: 0)
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
    case physicalParry = 22       // "{actor}の受け流し！"
    case physicalBlock = 23       // "{actor}は大盾で防いだ！"
    case physicalKill = 24        // "{target}を倒した！"
    case martialArts = 25         // "{actor}の格闘戦！"

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
}

// MARK: - Outcome Values

extension BattleLog {
    static let outcomeVictory: UInt8 = 0
    static let outcomeDefeat: UInt8 = 1
    static let outcomeRetreat: UInt8 = 2
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
