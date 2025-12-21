// ==============================================================================
// AppConstants.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アプリケーション全体の定数定義
//   - UIサイズ・進行データ上限・コスト計算
//
// 【データ構造】
//   - AppConstants.UI: UI関連定数
//     - listRowHeight: リスト行高さ
//
//   - AppConstants.Progress: 進行データ関連定数
//     - defaultPartySlotCount: 初期パーティスロット数（1）
//     - maximumPartySlotsWithGold: ゴールド購入可能最大スロット（7）
//     - defaultCharacterSlotCount: キャラクタースロット上限（200）
//     - partySlotExpansionCost(for:) → Int: スロット拡張コスト
//
// 【使用箇所】
//   - GameStateService: 初期パーティスロット数
//   - PartySlotExpansionView: 拡張コスト計算
//
// ==============================================================================

import CoreGraphics

enum AppConstants {
    enum UI {
        static let listRowHeight: CGFloat = 0
    }

    enum Progress {
        nonisolated static let defaultPartySlotCount = 1
        nonisolated static let maximumPartySlotsWithGold = 7
        nonisolated static let defaultCharacterSlotCount = 200

        static func partySlotExpansionCost(for nextSlot: Int) -> Int {
            // 旧実装と同じくゴールドコストは一定。
            nextSlot >= 2 && nextSlot <= maximumPartySlotsWithGold ? 1 : 0
        }
    }
}
