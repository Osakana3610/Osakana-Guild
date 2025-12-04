import Foundation
import Observation

@MainActor
@Observable
final class PartyViewState {
    private let progressService: ProgressService

    var parties: [RuntimeParty] = []
    var isLoading: Bool = false
    private var ongoingLoad: Task<Void, Error>? = nil

    init(progressService: ProgressService) {
        self.progressService = progressService
    }

    private var partyService: PartyProgressService { progressService.party }

    func loadAllParties() async throws {
        if let task = ongoingLoad {
            try await task.value
            return
        }

        let task = Task { @MainActor in
            isLoading = true
            defer {
                isLoading = false
                ongoingLoad = nil
            }
            let partySnapshots = try await partyService.allParties()
            parties = partySnapshots
                .map { RuntimeParty(snapshot: $0) }
                .sorted { lhs, rhs in
                    if lhs.slotIndex != rhs.slotIndex {
                        return lhs.slotIndex < rhs.slotIndex
                    }
                    return lhs.createdAt < rhs.createdAt
                }
        }
        ongoingLoad = task
        try await task.value
    }

    func refresh() async throws {
        try await loadAllParties()
    }

    func updatePartyMembers(party: RuntimeParty, memberIds: [Int32]) async throws {
        _ = try await partyService.updatePartyMembers(persistentIdentifier: party.persistentIdentifier, memberIds: memberIds)
        try await refresh()
    }
}
