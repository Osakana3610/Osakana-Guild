import Foundation

enum PartyAssembler {
    static func assembleState(masterData: MasterDataCache,
                              party: PartySnapshot,
                              characters: [CharacterInput]) throws -> RuntimePartyState {
        let characterMap = Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0) })
        var assembled: [RuntimeCharacter] = []
        for characterId in party.memberIds {
            guard let input = characterMap[characterId] else { continue }
            let runtimeCharacter = try RuntimeCharacterFactory.make(
                from: input,
                masterData: masterData
            )
            assembled.append(runtimeCharacter)
        }
        return try RuntimePartyState(party: party, characters: assembled)
    }
}
