import Foundation

struct RuntimePartyProgress: Sendable, Hashable {
    var id: UInt8                              // 1〜8
    var displayName: String
    var lastSelectedDungeonIndex: UInt16       // 0=未選択
    var lastSelectedDifficulty: UInt8
    var targetFloor: UInt8
    var memberIds: [UInt8]                     // 順序=配列index
}

struct RuntimePartyState: Sendable {
    struct Member: Identifiable, Sendable {
        var id: UInt8 { characterId }
        let characterId: UInt8
        let order: Int
        let character: RuntimeCharacterState
    }

    let party: RuntimePartyProgress
    let members: [Member]

    init(party: RuntimePartyProgress, characters: [RuntimeCharacterState]) throws {
        self.party = party
        let characterMap = Dictionary(uniqueKeysWithValues: characters.map { ($0.progress.id, $0) })
        var mappedMembers: [Member] = []
        for (order, characterId) in party.memberIds.enumerated() {
            guard let character = characterMap[characterId] else {
                throw RuntimeError.missingProgressData(reason: "Party member \(characterId) のキャラクターデータが見つかりません")
            }
            mappedMembers.append(Member(characterId: characterId,
                                        order: order,
                                        character: character))
        }
        self.members = mappedMembers
    }
}
