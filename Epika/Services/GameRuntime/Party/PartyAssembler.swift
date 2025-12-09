import Foundation

enum PartyAssembler {
    static func assembleState(repository: MasterDataRepository,
                              party: PartySnapshot,
                              characters: [CharacterInput]) async throws -> RuntimePartyState {
        let characterMap = Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0) })
        var assembled: [RuntimeCharacter] = []
        for characterId in party.memberIds {
            guard let input = characterMap[characterId] else { continue }
            let runtimeCharacter = try await RuntimeCharacterFactory.make(
                from: input,
                repository: repository
            )
            assembled.append(runtimeCharacter)
        }
        return try RuntimePartyState(party: party, characters: assembled)
    }
}
