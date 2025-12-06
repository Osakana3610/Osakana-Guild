import Foundation

enum PartyAssembler {
    static func assembleState(repository: MasterDataRepository,
                              party: PartySnapshot,
                              characters: [RuntimeCharacterProgress]) async throws -> RuntimePartyState {
        let characterMap = Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0) })
        var assembled: [RuntimeCharacterState] = []
        for characterId in party.memberIds {
            guard let progress = characterMap[characterId] else { continue }
            let state = try await CharacterAssembler.assembleState(repository: repository, from: progress)
            assembled.append(state)
        }
        return try RuntimePartyState(party: party, characters: assembled)
    }
}
