import Foundation

/// キャラクター名候補の定義
struct CharacterNameDefinition: Sendable, Hashable, Identifiable {
    let id: UInt16
    let genderCode: UInt8  // 1=male, 2=female, 3=genderless
    let name: String
}
