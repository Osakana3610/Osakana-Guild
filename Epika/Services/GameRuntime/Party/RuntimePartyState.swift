import Foundation

struct RuntimePartyState: Sendable {
    struct Member: Identifiable, Sendable {
        var id: UInt8 { characterId }
        let characterId: UInt8
        let order: Int
        let character: RuntimeCharacterState
    }

    let party: PartySnapshot
    let members: [Member]

    init(party: PartySnapshot, characters: [RuntimeCharacterState]) throws {
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
