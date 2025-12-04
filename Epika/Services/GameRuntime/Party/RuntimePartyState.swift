import Foundation

struct RuntimePartyProgress: Sendable, Hashable {
    struct Member: Sendable, Hashable {
        let id: UUID
        let characterId: Int32
        let order: Int
        let isReserve: Bool
        let createdAt: Date
        let updatedAt: Date
    }

    var id: UUID
    var displayName: String
    var formationId: String?
    var lastSelectedDungeonId: String?
    var lastSelectedDifficulty: Int
    var targetFloor: Int
    var members: [Member]
}

struct RuntimePartyState: Sendable {
    struct Member: Identifiable, Sendable {
        let id: UUID
        let characterId: Int32
        let order: Int
        let isReserve: Bool
        let character: RuntimeCharacterState
    }

    let party: RuntimePartyProgress
    let members: [Member]

    init(party: RuntimePartyProgress, characters: [RuntimeCharacterState]) throws {
        self.party = party
        let characterMap = Dictionary(uniqueKeysWithValues: characters.map { ($0.progress.id, $0) })
        var mappedMembers: [Member] = []
        for member in party.members {
            guard let character = characterMap[member.characterId] else {
                throw RuntimeError.missingProgressData(reason: "Party member \(member.characterId) のキャラクターデータが見つかりません")
            }
            mappedMembers.append(Member(id: member.id,
                                        characterId: member.characterId,
                                        order: member.order,
                                        isReserve: member.isReserve,
                                        character: character))
        }
        self.members = mappedMembers.sorted { $0.order < $1.order }
    }
}
