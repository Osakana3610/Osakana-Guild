import Foundation

enum PartyAssembler {
    static func assembleState(repository: MasterDataRepository,
                              party: RuntimePartyProgress,
                              characters: [RuntimeCharacterProgress]) async throws -> RuntimePartyState {
        let characterMap = Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0) })
        var assembled: [RuntimeCharacterState] = []
        for member in party.members.sorted(by: { $0.order < $1.order }) {
            guard let progress = characterMap[member.characterId] else { continue }
            let state = try await CharacterAssembler.assembleState(repository: repository, from: progress)
            assembled.append(state)
        }
        return try RuntimePartyState(party: party, characters: assembled)
    }
}
