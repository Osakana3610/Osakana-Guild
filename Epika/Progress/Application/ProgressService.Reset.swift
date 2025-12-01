import Foundation

// MARK: - Reset
extension ProgressService {
    func resetAllProgressIncludingCloudKit() async throws {
        try await cloudKitCleanup.purgeAllZones()
        try await resetAllProgress()
    }

    func resetAllProgress() async throws {
        try await metadata.resetAllProgress()
        _ = try await player.loadCurrentPlayer()
    }
}
