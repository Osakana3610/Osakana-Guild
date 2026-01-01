// ==============================================================================
// ItemEnhancement.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アイテムの強化情報（称号・ソケット）を表現
//
// 【データ構造】
//   - superRareTitleId: 超レア称号ID（0=なし）
//   - normalTitleId: 通常称号rank（0=なし）
//   - socketSuperRareTitleId, socketNormalTitleId, socketItemId: ソケット宝石
//
// 【導出プロパティ】
//   - hasSocket → Bool: 宝石改造の有無
//
// ==============================================================================

import Foundation

/// アイテムの強化情報（称号・ソケット）
struct ItemEnhancement: Sendable, Equatable, Hashable {
    var superRareTitleId: UInt8
    var normalTitleId: UInt8
    var socketSuperRareTitleId: UInt8
    var socketNormalTitleId: UInt8
    var socketItemId: UInt16

    init(superRareTitleId: UInt8 = 0,
         normalTitleId: UInt8 = 0,
         socketSuperRareTitleId: UInt8 = 0,
         socketNormalTitleId: UInt8 = 0,
         socketItemId: UInt16 = 0) {
        self.superRareTitleId = superRareTitleId
        self.normalTitleId = normalTitleId
        self.socketSuperRareTitleId = socketSuperRareTitleId
        self.socketNormalTitleId = socketNormalTitleId
        self.socketItemId = socketItemId
    }

    /// 宝石改造が施されているか
    var hasSocket: Bool {
        socketItemId != 0
    }
}
