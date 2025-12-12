import Foundation

/// BattleLog（数値のみ）を BattleLogEntry（表示用）に変換するレンダラー
struct BattleLogRenderer {

    /// BattleLogを表示用のBattleLogEntryに変換
    /// - Parameters:
    ///   - battleLog: 数値形式の戦闘ログ
    ///   - allyNames: characterId → 表示名
    ///   - enemyNames: actorIndex → 表示名（敵）
    /// - Returns: 表示用のBattleLogEntry配列
    static func render(
        battleLog: BattleLog,
        allyNames: [UInt8: String],
        enemyNames: [UInt16: String]
    ) -> [BattleLogEntry] {
        var entries: [BattleLogEntry] = []

        for action in battleLog.actions {
            guard let kind = ActionKind(rawValue: action.kind) else { continue }

            let actorName = resolveName(index: action.actor, allyNames: allyNames, enemyNames: enemyNames)
            let targetName: String?
            if let target = action.target {
                targetName = resolveName(index: target, allyNames: allyNames, enemyNames: enemyNames)
            } else {
                targetName = nil
            }

            let entry = makeEntry(
                turn: Int(action.turn),
                kind: kind,
                actorName: actorName,
                targetName: targetName,
                value: action.value.map { Int($0) },
                actorId: String(action.actor),
                targetId: action.target.map { String($0) }
            )

            if let entry = entry {
                entries.append(entry)
            }
        }

        return entries
    }

    private static func resolveName(
        index: UInt16,
        allyNames: [UInt8: String],
        enemyNames: [UInt16: String]
    ) -> String {
        if index >= 1000 {
            // 敵
            return enemyNames[index] ?? "敵\(index)"
        } else {
            // 味方
            return allyNames[UInt8(index)] ?? "キャラ\(index)"
        }
    }

    private static func makeEntry(
        turn: Int,
        kind: ActionKind,
        actorName: String,
        targetName: String?,
        value: Int?,
        actorId: String,
        targetId: String?
    ) -> BattleLogEntry? {
        let (message, type) = messageAndType(
            kind: kind,
            actorName: actorName,
            targetName: targetName,
            value: value
        )

        guard !message.isEmpty else { return nil }

        return BattleLogEntry(
            turn: turn,
            message: message,
            type: type,
            actorId: actorId,
            targetId: targetId
        )
    }

    private static func messageAndType(
        kind: ActionKind,
        actorName: String,
        targetName: String?,
        value: Int?
    ) -> (String, BattleLogEntry.LogType) {
        switch kind {
        // 行動選択
        case .defend:
            return ("\(actorName)は防御態勢を取った", .guard)
        case .physicalAttack:
            return ("\(actorName)の攻撃！", .action)
        case .priestMagic:
            return ("\(actorName)は回復魔法を唱えた！", .action)
        case .mageMagic:
            return ("\(actorName)は攻撃魔法を唱えた！", .action)
        case .breath:
            return ("\(actorName)はブレスを吐いた！", .action)

        // 戦闘開始・終了
        case .battleStart:
            return ("戦闘開始！", .system)
        case .turnStart:
            return ("--- \(value ?? 1)ターン目 ---", .system)
        case .victory:
            return ("勝利！ 敵を倒した！", .victory)
        case .defeat:
            return ("敗北… パーティは全滅した…", .defeat)
        case .retreat:
            return ("戦闘は長期化し、パーティは撤退を決断した", .retreat)

        // 物理攻撃結果
        case .physicalDamage:
            let target = targetName ?? "対象"
            let dmg = value ?? 0
            return ("\(target)に\(dmg)のダメージ！", .damage)
        case .physicalEvade:
            let target = targetName ?? "対象"
            return ("\(target)は攻撃をかわした！", .miss)
        case .physicalParry:
            return ("\(actorName)の受け流し！", .action)
        case .physicalBlock:
            return ("\(actorName)は大盾で防いだ！", .action)
        case .physicalKill:
            let target = targetName ?? "対象"
            return ("\(target)を倒した！", .defeat)
        case .martialArts:
            return ("\(actorName)の格闘戦！", .action)

        // 魔法結果
        case .magicDamage:
            let target = targetName ?? "対象"
            let dmg = value ?? 0
            return ("\(target)に\(dmg)のダメージ！", .damage)
        case .magicHeal:
            let target = targetName ?? "対象"
            let heal = value ?? 0
            return ("\(target)のHPが\(heal)回復！", .heal)
        case .magicMiss:
            return ("しかし効かなかった", .miss)

        // ブレス結果
        case .breathDamage:
            let target = targetName ?? "対象"
            let dmg = value ?? 0
            return ("\(target)に\(dmg)のダメージ！", .damage)

        // 状態異常
        case .statusInflict:
            let target = targetName ?? "対象"
            return ("\(target)は状態異常になった！", .status)
        case .statusResist:
            let target = targetName ?? "対象"
            return ("\(target)は抵抗した！", .status)
        case .statusRecover:
            let target = targetName ?? "対象"
            return ("\(target)の状態異常が治った", .status)
        case .statusTick:
            let target = targetName ?? "対象"
            let dmg = value ?? 0
            return ("\(target)は継続ダメージで\(dmg)のダメージ！", .damage)
        case .statusConfusion:
            return ("\(actorName)は暴走して混乱した！", .status)
        case .statusRampage:
            return ("\(actorName)の暴走！", .action)

        // 反撃・特殊
        case .reactionAttack:
            return ("\(actorName)の反撃！", .action)
        case .followUp:
            return ("\(actorName)の追加攻撃！", .action)

        // 回復・吸収
        case .healAbsorb:
            let heal = value ?? 0
            return ("\(actorName)は吸収能力で\(heal)回復", .heal)
        case .healVampire:
            let heal = value ?? 0
            return ("\(actorName)は吸血で\(heal)回復", .heal)
        case .healParty:
            let target = targetName ?? "対象"
            let heal = value ?? 0
            return ("\(target)のHPが\(heal)回復！", .heal)
        case .healSelf:
            let heal = value ?? 0
            return ("\(actorName)は自身の効果で\(heal)回復", .heal)
        case .damageSelf:
            let dmg = value ?? 0
            return ("\(actorName)は自身の効果で\(dmg)ダメージ", .damage)

        // バフ
        case .buffApply:
            return ("効果が発動した", .status)
        case .buffExpire:
            return ("\(actorName)の効果が切れた", .status)

        // 蘇生・救助
        case .resurrection:
            let target = targetName ?? actorName
            return ("\(target)が蘇生した！", .heal)
        case .necromancer:
            let target = targetName ?? "対象"
            return ("\(actorName)のネクロマンサーで\(target)が蘇生した！", .heal)
        case .rescue:
            let target = targetName ?? "対象"
            return ("\(actorName)は\(target)を救出した！", .heal)

        // 行動不能・特殊
        case .actionLocked:
            return ("\(actorName)は動けない", .status)
        case .noAction:
            return ("\(actorName)は何もしなかった", .action)
        case .withdraw:
            return ("\(actorName)は戦線離脱した", .action)
        case .sacrifice:
            let target = targetName ?? "対象"
            return ("古の儀：\(target)が供儀対象になった", .status)
        case .vampireUrge:
            return ("\(actorName)は吸血衝動に駆られた", .status)

        // 敵出現
        case .enemyAppear:
            return ("敵が現れた！", .system)

        // 敵専用技
        case .enemySpecialSkill:
            return ("\(actorName)の特殊攻撃！", .action)
        case .enemySpecialDamage:
            let target = targetName ?? "対象"
            let dmg = value ?? 0
            return ("\(target)に\(dmg)のダメージ！", .damage)
        case .enemySpecialHeal:
            let heal = value ?? 0
            return ("\(actorName)は\(heal)回復した！", .heal)
        case .enemySpecialBuff:
            return ("\(actorName)は能力を強化した！", .status)

        // スキル効果
        case .spellChargeRecover:
            return ("\(actorName)は魔法のチャージを回復した", .heal)
        }
    }
}
