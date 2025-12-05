import Foundation

// MARK: - Reset
extension ProgressService {
    func resetAllProgressIncludingCloudKit() async throws {
        try await cloudKitCleanup.purgeAllZones()
        try await resetAllProgress()
    }

    func resetAllProgress() async throws {
        try await gameState.resetAllProgress()
        _ = try await gameState.loadCurrentPlayer()
    }
}
