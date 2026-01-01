// ==============================================================================
// ItemAttributes.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アイテムの属性を表す小さな型の定義
//
// 【型】
//   - ItemEnhancement: 強化情報（称号・ソケット）
//   - ItemStorage: 保管場所
//
// ==============================================================================

import Foundation

// MARK: - ItemEnhancement

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

// MARK: - ItemStorage

/// アイテムの保管場所
/// - Note: 0 は「未初期化」を表す予約値。新しいケースは 1 以上で追加すること。
enum ItemStorage: UInt8, Codable, Sendable {
    case playerItem = 1
    case unknown = 2
}
