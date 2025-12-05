import Foundation

enum ProgressPersistenceError: Error {
    case gameStateUnavailable
    case explorationRunNotFound(runId: UUID)
    case explorationRunNotFoundByPersistentId
}
