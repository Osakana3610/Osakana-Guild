import Foundation

/// stackKey文字列をパースした結果
struct StackKeyComponents: Sendable {
    let superRareTitleId: UInt8
    let normalTitleId: UInt8
    let itemId: UInt16
    let socketSuperRareTitleId: UInt8
    let socketNormalTitleId: UInt8
    let socketItemId: UInt16

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
