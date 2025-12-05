import Foundation

// MARK: - Event Entry

struct EventEntry: Codable, Sendable {
    var floor: UInt8
    var kind: UInt8  // EventKind.rawValue
    var enemyIndex: UInt16?
    var battleResult: UInt8?  // BattleResult.rawValue
    var battleLogData: Data?  // BattleLogArchive（将来はCompactLogEntry配列に変換予定）
    var scriptedEventIndex: UInt16?
    var exp: Int32
    var gold: Int32
    var drops: [DropEntry]
    var occurredAt: Date  // イベント発生時刻
}

struct DropEntry: Codable, Sendable {
    var superRareTitleOrder: UInt8   // 超レア称号のorder（0=なし）
    var normalTitleRank: UInt8       // 通常称号のrank（0=なし）
    var itemIndex: Int16             // アイテムのindex（-1=なし）
    var quantity: UInt16
}

enum EventKind: UInt8, Codable, Sendable {
    case nothing = 0
    case combat = 1
    case scripted = 2
}

enum BattleResult: UInt8, Codable, Sendable {
    case victory = 0
    case defeat = 1
    case retreat = 2
}

enum ExplorationResult: UInt8, Codable, Sendable {
    case running = 0
    case completed = 1
    case defeated = 2
    case cancelled = 3
}

// MARK: - Compact Battle Log

struct CompactLogEntry: Codable, Sendable {
    var turn: UInt8                // ターン番号（1〜255、20ターン上限なので十分）
    var template: UInt8            // LogTemplate.rawValue
    var actorIndex: UInt16?        // 行動者（敵: suffix*1000+masterIndex, 味方: characterId）
    var targetIndex: UInt16?       // 対象
    var value: Int32?              // ダメージ/回復量（32,767超えあり）
    var refIndex: UInt16?          // スキル/呪文のマスターデータindex
}

/// rawValue固定の意図:
/// 各caseに明示的なrawValue（0, 1, 10, 20...）を指定することで、
/// 将来新しいテンプレートを追加しても既存のrawValueが変わらず、
/// 保存済みログの後方互換性を維持できる。
/// 新規追加時は既存値の間（例: 24と30の間に25〜29）または末尾に配置する。
enum LogTemplate: UInt8, Codable, Sendable {
    // === 戦闘開始・終了 ===
    case battleStart = 0              // "{enemy}が現れた！"
    case victory = 1                  // "戦闘に勝利した！"
    case defeat = 2                   // "全滅した..."
    case retreat = 3                  // "撤退した"

    // === ターン ===
    case turnStart = 10               // "ターン{turn}"

    // === 物理攻撃 ===
    case physicalAttack = 20          // "{actor}の攻撃！"
    case physicalDamage = 21          // "{target}に{value}のダメージ！"
    case physicalMiss = 22            // "{target}には当たらなかった"
    case physicalCritical = 23        // "会心の一撃！"
    case physicalKill = 24            // "{target}を倒した！"

    // === 魔法攻撃 ===
    case magicCast = 30               // "{actor}は{spell}を唱えた！"
    case magicDamage = 31             // "{target}に{value}のダメージ！"
    case magicHeal = 32               // "{target}のHPが{value}回復！"
    case magicMiss = 33               // "しかし効かなかった"

    // === ブレス ===
    case breathAttack = 40            // "{actor}は{breath}を吐いた！"
    case breathDamage = 41            // "{target}に{value}のダメージ！"

    // === 状態異常 ===
    case statusInflict = 50           // "{target}は{status}になった！"
    case statusResist = 51            // "{target}は抵抗した！"
    case statusRecover = 52           // "{target}の{status}が治った"
    case statusTick = 53              // "{target}は{status}で{value}のダメージ！"

    // === 反撃・特殊行動 ===
    case counterAttack = 60           // "{actor}の反撃！"
    case parry = 61                   // "{actor}は攻撃を受け流した！"
    case shieldBlock = 62             // "{actor}は盾で防いだ！"
    case followUp = 63                // "{actor}の追加攻撃！"

    // === バフ・デバフ ===
    case buffApply = 70               // "{actor}の{buff}！"
    case buffExpire = 71              // "{actor}の{buff}が切れた"

    // === 蘇生・救助 ===
    case resurrection = 80            // "{target}が蘇生した！"
    case rescue = 81                  // "{actor}は{target}を救助した！"

    // === その他 ===
    case actionLocked = 90            // "{actor}は動けない！"
    case noAction = 91                // "{actor}は何もしなかった"
}

// MARK: - Actor Index Encoding

/// actorIndexのエンコード/デコードヘルパー
///
/// エンコーディング規則:
/// - 味方: characterId（1〜200）
/// - 敵: suffix * 1000 + enemyMasterIndex（1000〜29999）
///   - suffix: 出現順（1=A, 2=B, 3=C...）
///   - enemyMasterIndex: EnemyMaster.jsonのindex（0〜999）
enum ActorIndexCoding: Sendable {
    /// 敵のactorIndexを生成
    nonisolated static func encodeEnemy(suffix: Int, masterIndex: UInt16) -> UInt16 {
        UInt16(suffix) * 1000 + masterIndex
    }

    /// actorIndexをデコード
    nonisolated static func decode(_ index: UInt16) -> ActorType {
        if index >= 1000 {
            let suffix = Int(index / 1000)
            let masterIndex = index % 1000
            return .enemy(suffix: suffix, masterIndex: masterIndex)
        } else {
            return .ally(characterId: UInt8(index))
        }
    }

    enum ActorType: Sendable {
        case ally(characterId: UInt8)
        case enemy(suffix: Int, masterIndex: UInt16)
    }
}
