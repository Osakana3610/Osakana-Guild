// ==============================================================================
// ItemAttributes.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アイテムの属性を表す小さな型の定義
//
// 【型】
//   - CachedInventoryItem: キャッシュ用の軽量アイテム
//   - ItemEnhancement: 強化情報（称号・ソケット）
//   - ItemStorage: 保管場所
//
// ==============================================================================

import Foundation

// MARK: - CachedInventoryItem

/// UserDataLoadServiceがキャッシュとして保持する軽量なアイテム型
/// SwiftDataのマネージドオブジェクトではなく、値型としてメモリ効率が良い
struct CachedInventoryItem: Sendable, Identifiable, Hashable {
    nonisolated let stackKey: String
    nonisolated let itemId: UInt16
    nonisolated var quantity: UInt16
    nonisolated let normalTitleId: UInt8
    nonisolated let superRareTitleId: UInt8
    nonisolated let socketItemId: UInt16
    nonisolated let socketNormalTitleId: UInt8
    nonisolated let socketSuperRareTitleId: UInt8
    nonisolated let category: ItemSaleCategory
    nonisolated let rarity: UInt8?
    nonisolated let displayName: String
    nonisolated let baseValue: Int
    nonisolated let sellValue: Int
    nonisolated let statBonuses: ItemDefinition.StatBonuses
    nonisolated var combatBonuses: ItemDefinition.CombatBonuses  // パンドラ変更時に更新可能
    nonisolated let grantedSkillIds: [UInt16]

    nonisolated var id: String { stackKey }

    nonisolated var enhancement: ItemEnhancement {
        ItemEnhancement(
            superRareTitleId: superRareTitleId,
            normalTitleId: normalTitleId,
            socketSuperRareTitleId: socketSuperRareTitleId,
            socketNormalTitleId: socketNormalTitleId,
            socketItemId: socketItemId
        )
    }

    /// 宝石改造が施されているか
    nonisolated var hasGemModification: Bool {
        socketItemId != 0
    }

    /// CharacterInput.EquippedItemへ変換（永続化用）
    nonisolated func toEquippedItem() -> CharacterInput.EquippedItem {
        CharacterInput.EquippedItem(
            superRareTitleId: superRareTitleId,
            normalTitleId: normalTitleId,
            itemId: itemId,
            socketSuperRareTitleId: socketSuperRareTitleId,
            socketNormalTitleId: socketNormalTitleId,
            socketItemId: socketItemId,
            quantity: Int(quantity)
        )
    }
}

// MARK: - CurrencyType

/// 通貨タイプ（UI表示用）
enum CurrencyType: Sendable {
    case gold
    case catTicket
    case gem
}

// MARK: - ItemEnhancement

/// アイテムの強化情報（称号・ソケット）
struct ItemEnhancement: Sendable, Equatable, Hashable {
    nonisolated var superRareTitleId: UInt8
    nonisolated var normalTitleId: UInt8
    nonisolated var socketSuperRareTitleId: UInt8
    nonisolated var socketNormalTitleId: UInt8
    nonisolated var socketItemId: UInt16

    nonisolated init(superRareTitleId: UInt8 = 0,
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
    nonisolated var hasSocket: Bool {
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
