import Foundation

// MARK: - Reset
extension ProgressService {
    func resetAllProgress() async throws {
        try await gameState.resetAllProgress()
        _ = try await gameState.loadCurrentPlayer()
    }
}
