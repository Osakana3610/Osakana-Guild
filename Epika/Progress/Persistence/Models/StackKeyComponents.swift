// ==============================================================================
// StackKeyComponents.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - stackKey文字列のパース・生成
//   - アイテム識別用6要素コンポーネントの管理
//
// 【データ構造】
//   - StackKeyComponents: stackKeyの分解結果
//     - superRareTitleId, normalTitleId, itemId: アイテム本体
//     - socketSuperRareTitleId, socketNormalTitleId, socketItemId: ソケット
//
// 【stackKeyフォーマット】
//   - "超レアID|通常ID|アイテムID|S超レアID|S通常ID|S宝石ID"
//   - 例: "0|2|100|0|0|0"
//
// 【公開API】
//   - init?(stackKey:) - stackKey文字列からパース
//   - init(各コンポーネント) - コンポーネントから生成
//   - stackKey → String - stackKey文字列を生成
//   - makeStackKey(静的) - コンポーネントからstackKey生成
//
// 【使用箇所】
//   - InventoryProgressService: スタック識別
//   - PandoraBoxItem: stackKey変換
//   - 装備・ドロップ処理全般
//
// ==============================================================================

import Foundation

/// stackKey文字列をパースした結果
struct StackKeyComponents: Sendable {
    let superRareTitleId: UInt8
    let normalTitleId: UInt8
    let itemId: UInt16
    let socketSuperRareTitleId: UInt8
    let socketNormalTitleId: UInt8
    let socketItemId: UInt16

    /// コンポーネントからstackKeyを生成
    var stackKey: String {
        "\(superRareTitleId)|\(normalTitleId)|\(itemId)|\(socketSuperRareTitleId)|\(socketNormalTitleId)|\(socketItemId)"
    }

    /// 指定された値からstackKeyを生成（静的メソッド）
    static func makeStackKey(
        superRareTitleId: UInt8,
        normalTitleId: UInt8,
        itemId: UInt16,
        socketSuperRareTitleId: UInt8 = 0,
        socketNormalTitleId: UInt8 = 0,
        socketItemId: UInt16 = 0
    ) -> String {
        "\(superRareTitleId)|\(normalTitleId)|\(itemId)|\(socketSuperRareTitleId)|\(socketNormalTitleId)|\(socketItemId)"
    }

    /// memberwise init
    init(
        superRareTitleId: UInt8,
        normalTitleId: UInt8,
        itemId: UInt16,
        socketSuperRareTitleId: UInt8,
        socketNormalTitleId: UInt8,
        socketItemId: UInt16
    ) {
        self.superRareTitleId = superRareTitleId
        self.normalTitleId = normalTitleId
        self.itemId = itemId
        self.socketSuperRareTitleId = socketSuperRareTitleId
        self.socketNormalTitleId = socketNormalTitleId
        self.socketItemId = socketItemId
    }

    /// stackKey文字列をパースして各コンポーネントを抽出
    /// フォーマット: "superRareTitleId|normalTitleId|itemId|socketSuperRareTitleId|socketNormalTitleId|socketItemId"
    nonisolated init?(stackKey: String) {
        let parts = stackKey.split(separator: "|")
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
}
