import Foundation

// MARK: - RowProfileBase

/// 列プロファイル基本型
/// rawValue: EnumMappings.profileType
enum RowProfileBase: UInt8, Sendable, Hashable {
    case balanced = 1
    case melee = 2
    case mixed = 3
    case ranged = 4
}

// MARK: - ReactionTrigger

/// リアクショントリガー
/// rawValue: EnumMappings.triggerType
enum ReactionTrigger: UInt8, Sendable, Hashable {
    case afterTurn8 = 1
    case allyDamagedPhysical = 2
    case allyDefeated = 3
    case allyMagicAttack = 4
    case battleStart = 5
    case selfAttackNoKill = 6
    case selfDamagedMagical = 7
    case selfDamagedPhysical = 8
    case selfEvadePhysical = 9
    case selfKilledEnemy = 10
    case selfMagicAttack = 11
    case turnElapsed = 12
    case turnStart = 13
}

// MARK: - ReactionTarget

/// リアクションターゲット
/// rawValue: EnumMappings.targetType（一部のみ使用）
enum ReactionTarget: UInt8, Sendable, Hashable {
    case ally = 1
    case attacker = 2
    case enemy = 8
    case killer = 13
    case party = 18
    case `self` = 22
}

// MARK: - SpecialAttackKind

/// 特殊攻撃種別
/// rawValue: EnumMappings.specialAttackIdValue
enum SpecialAttackKind: UInt8, Sendable, Hashable {
    case specialA = 1
    case specialB = 2
    case specialC = 3
    case specialD = 4
    case specialE = 5
}

// MARK: - TimedBuffScope

/// タイムドバフスコープ
enum TimedBuffScope: UInt8, Sendable, Hashable {
    case party = 1
    case `self` = 2
}

// MARK: - StackingType

/// スタッキングタイプ
/// rawValue: EnumMappings.stackingType
enum StackingType: UInt8, Sendable, Hashable {
    case add = 1
    case additive = 2
    case multiply = 3
}
