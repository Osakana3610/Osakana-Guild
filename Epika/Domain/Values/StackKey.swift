// ==============================================================================
// StackKey.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アイテムスタック識別用の複合キー
//   - 6つのIDをUInt64にパックして高速比較・省メモリを実現
//
// 【データ構造】
//   - superRareTitleId: UInt8 (8bit) - 超レア称号ID
//   - normalTitleId: UInt8 (8bit) - 通常称号ID
//   - itemId: UInt16 (16bit) - アイテムID
//   - socketSuperRareTitleId: UInt8 (8bit) - ソケット超レア称号ID
//   - socketNormalTitleId: UInt8 (8bit) - ソケット通常称号ID
//   - socketItemId: UInt16 (16bit) - ソケットアイテムID
//   合計: 64bit = UInt64
//
// 【ビットレイアウト】
//   |63    56|55    48|47        32|31    24|23    16|15         0|
//   |superRare|normal  |itemId      |sockSR  |sockNorm|socketItemId|
//
// 【公開API】
//   - packed: UInt64 - パック済み値（永続化・高速比較用）
//   - init(packed:) - パック済み値から復元
//   - stringValue: String - 既存コードとの互換用
//   - init?(stringValue:) - 文字列から生成
//
// 【使用箇所】
//   - パンドラボックス: [UInt64]として永続化
//   - 将来: インベントリ全体のstackKey統一
//
// ==============================================================================

import Foundation

struct StackKey: Sendable, Hashable {
    let superRareTitleId: UInt8
    let normalTitleId: UInt8
    let itemId: UInt16
    let socketSuperRareTitleId: UInt8
    let socketNormalTitleId: UInt8
    let socketItemId: UInt16

    // MARK: - Init

    init(
        superRareTitleId: UInt8 = 0,
        normalTitleId: UInt8 = 0,
        itemId: UInt16,
        socketSuperRareTitleId: UInt8 = 0,
        socketNormalTitleId: UInt8 = 0,
        socketItemId: UInt16 = 0
    ) {
        self.superRareTitleId = superRareTitleId
        self.normalTitleId = normalTitleId
        self.itemId = itemId
        self.socketSuperRareTitleId = socketSuperRareTitleId
        self.socketNormalTitleId = socketNormalTitleId
        self.socketItemId = socketItemId
    }

    // MARK: - UInt64 Pack/Unpack

    /// 6つのIDをUInt64にパック
    var packed: UInt64 {
        UInt64(superRareTitleId) << 56 |
        UInt64(normalTitleId) << 48 |
        UInt64(itemId) << 32 |
        UInt64(socketSuperRareTitleId) << 24 |
        UInt64(socketNormalTitleId) << 16 |
        UInt64(socketItemId)
    }

    /// UInt64からアンパック
    init(packed: UInt64) {
        self.superRareTitleId = UInt8(packed >> 56)
        self.normalTitleId = UInt8((packed >> 48) & 0xFF)
        self.itemId = UInt16((packed >> 32) & 0xFFFF)
        self.socketSuperRareTitleId = UInt8((packed >> 24) & 0xFF)
        self.socketNormalTitleId = UInt8((packed >> 16) & 0xFF)
        self.socketItemId = UInt16(packed & 0xFFFF)
    }

    // MARK: - String Compatibility
    // 既存インベントリ（CachedInventoryItem.stackKey）がString形式のため必要。
    // インベントリ全体をUInt64に統一すれば削除可能。

    /// 既存の文字列形式（"superRare|normal|item|sockSR|sockNorm|sockItem"）
    var stringValue: String {
        "\(superRareTitleId)|\(normalTitleId)|\(itemId)|\(socketSuperRareTitleId)|\(socketNormalTitleId)|\(socketItemId)"
    }

    /// 文字列形式からパース
    init?(stringValue: String) {
        let parts = stringValue.split(separator: "|")
        guard parts.count == 6,
              let superRare = UInt8(parts[0]),
              let normal = UInt8(parts[1]),
              let item = UInt16(parts[2]),
              let socketSuperRare = UInt8(parts[3]),
              let socketNormal = UInt8(parts[4]),
              let socketItem = UInt16(parts[5]) else {
            return nil
        }
        self.superRareTitleId = superRare
        self.normalTitleId = normal
        self.itemId = item
        self.socketSuperRareTitleId = socketSuperRare
        self.socketNormalTitleId = socketNormal
        self.socketItemId = socketItem
    }

    // MARK: - StackKeyComponents Compatibility

    /// StackKeyComponentsから生成
    init(components: StackKeyComponents) {
        self.superRareTitleId = components.superRareTitleId
        self.normalTitleId = components.normalTitleId
        self.itemId = components.itemId
        self.socketSuperRareTitleId = components.socketSuperRareTitleId
        self.socketNormalTitleId = components.socketNormalTitleId
        self.socketItemId = components.socketItemId
    }

    /// StackKeyComponentsに変換
    var components: StackKeyComponents {
        StackKeyComponents(
            superRareTitleId: superRareTitleId,
            normalTitleId: normalTitleId,
            itemId: itemId,
            socketSuperRareTitleId: socketSuperRareTitleId,
            socketNormalTitleId: socketNormalTitleId,
            socketItemId: socketItemId
        )
    }
}
