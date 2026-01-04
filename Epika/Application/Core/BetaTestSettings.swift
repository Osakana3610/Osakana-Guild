// ==============================================================================
// BetaTestSettings.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ベータテスト用の設定値を保持
//   - 戦闘乱数のオーバーライドモード管理
//
// 【注意】
//   - メモリのみで保持（アプリ再起動でリセット）
//   - 製品版リリース時に削除予定
//
// ==============================================================================

import Foundation
import os

/// ベータテスト用の設定
/// アプリ再起動でリセットされる（永続化しない）
struct BetaTestSettings {
    /// 戦闘乱数のオーバーライドモード
    enum RandomMode: Int, CaseIterable, Sendable {
        case normal = 0      // 通常の乱数
        case fixedSeed = 1   // シード固定（同じシードで同じ結果）
        case fixedMedian = 2 // 中央値固定（乱数を使わない）

        var displayName: String {
            switch self {
            case .normal: "通常"
            case .fixedSeed: "シード固定"
            case .fixedMedian: "中央値固定"
            }
        }

        var description: String {
            switch self {
            case .normal: "通常の乱数を使用"
            case .fixedSeed: "同じシードで毎回同じ結果"
            case .fixedMedian: "乱数を使わず常に中間値"
            }
        }
    }

    /// 内部状態（ロックで保護）
    private struct State: Sendable {
        var randomMode: RandomMode = .normal
        var fixedSeed: UInt64 = 12345
    }

    private static let lock = OSAllocatedUnfairLock(initialState: State())

    /// 現在の乱数モード
    static var randomMode: RandomMode {
        get { lock.withLock { $0.randomMode } }
        set { lock.withLock { $0.randomMode = newValue } }
    }

    /// シード固定モード時に使用するシード値
    static var fixedSeed: UInt64 {
        get { lock.withLock { $0.fixedSeed } }
        set { lock.withLock { $0.fixedSeed = newValue } }
    }
}
