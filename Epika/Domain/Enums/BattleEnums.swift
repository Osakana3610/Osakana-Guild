import Foundation

// MARK: - BattleDamageType

/// ダメージ種別
/// rawValue: EnumMappings.damageType (physical=1, magical=2, breath=3)
enum BattleDamageType: UInt8, Sendable, Hashable {
    case physical = 1
    case magical = 2
    case breath = 3

    /// 表示用識別子
    var identifier: String {
        switch self {
        case .physical: "physical"
        case .magical: "magical"
        case .breath: "breath"
        }
    }
}
