import Foundation

enum PartyAssembler {
    static func assembleState(repository: MasterDataRepository,
                              party: PartySnapshot,
                              characters: [RuntimeCharacterProgress]) async throws -> RuntimePartyState {
        let characterMap = Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0) })
        var assembled: [RuntimeCharacter] = []
        for characterId in party.memberIds {
            guard let progress = characterMap[characterId] else { continue }
            let runtimeCharacter = try await CharacterAssembler.assembleRuntimeCharacter(
                repository: repository,
                from: progress
            )
            assembled.append(runtimeCharacter)
        }
        return try RuntimePartyState(party: party, characters: assembled)
    }
}
