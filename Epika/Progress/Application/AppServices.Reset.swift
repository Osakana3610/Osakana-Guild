import Foundation

// MARK: - Reset
extension AppServices {
    func resetAllProgress() async throws {
        try await gameState.resetAllProgress()
        _ = try await gameState.loadCurrentPlayer()
    }
}
