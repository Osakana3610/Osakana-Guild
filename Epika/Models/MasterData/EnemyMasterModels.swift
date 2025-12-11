import Foundation

struct EnemyDefinition: Identifiable, Sendable {
    struct ActionRates: Sendable, Hashable {
        let attack: Int
        let priestMagic: Int
        let mageMagic: Int
        let breath: Int
    }

    /// 耐性値（ダメージ倍率: 1.0=通常, 0.5=半減, 2.0=弱点）
    struct Resistances: Sendable, Hashable {
        let physical: Double      // 物理攻撃
        let piercing: Double      // 追加ダメージ（貫通）
        let critical: Double      // クリティカルダメージ
        let breath: Double        // ブレス
        let spells: [UInt8: Double]  // 個別魔法（spellId → 倍率）

        static let neutral = Resistances(
            physical: 1.0, piercing: 1.0, critical: 1.0, breath: 1.0, spells: [:]
        )
    }

    let id: UInt16
    let name: String
    let raceId: UInt8
    let jobId: UInt8?
    let baseExperience: Int
    let isBoss: Bool
    let strength: Int
    let wisdom: Int
    let spirit: Int
    let vitality: Int
    let agility: Int
    let luck: Int
    let resistances: Resistances
    let resistanceOverrides: Resistances?
    let specialSkillIds: [UInt16]
    let drops: [UInt16]
    let actionRates: ActionRates
}
