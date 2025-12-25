// ==============================================================================
// AppServices.Reset.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ゲームデータの完全リセット
//
// 【公開API】
//   - resetAllProgress()
//     全進行データを削除し、初期状態に戻す
//
// ==============================================================================

import Foundation

// MARK: - Reset
extension AppServices {
    func resetAllProgress() async throws {
        try await gameState.resetAllProgress()
        _ = try await gameState.loadCurrentPlayer()
    }
}
