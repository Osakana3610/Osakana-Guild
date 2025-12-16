import Foundation

// MARK: - Reset
extension ProgressService {
    #if DEBUG
    /// CloudKitとローカルストアを完全削除する。
    /// 削除後はアプリ再起動が必要。
    func purgeAllDataForAppRestart() async throws {
        try await cloudKitCleanup.purgeAllZones()
        try await MainActor.run {
            try ProgressBootstrapper.shared.resetStore()
        }
    }
    #endif

    func resetAllProgress() async throws {
        try await gameState.resetAllProgress()
        _ = try await gameState.loadCurrentPlayer()
    }
}
