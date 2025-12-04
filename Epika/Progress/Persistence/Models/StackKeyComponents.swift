import Foundation

/// stackKey文字列をパースした結果
struct StackKeyComponents: Sendable {
    let superRareTitleIndex: Int16
    let normalTitleIndex: Int8
    let masterDataIndex: Int16
    let socketSuperRareTitleIndex: Int16
    let socketNormalTitleIndex: Int8
    let socketMasterDataIndex: Int16

    /// stackKey文字列をパースして各コンポーネントを抽出
    /// フォーマット: "superRareTitleIndex|normalTitleIndex|masterDataIndex|socketSuperRareTitleIndex|socketNormalTitleIndex|socketMasterDataIndex"
    nonisolated init?(stackKey: String) {
        let parts = stackKey.split(separator: "|")
        guard parts.count == 6,
              let superRare = Int16(parts[0]),
              let normal = Int8(parts[1]),
              let master = Int16(parts[2]),
              let socketSuperRare = Int16(parts[3]),
              let socketNormal = Int8(parts[4]),
              let socketMaster = Int16(parts[5]) else {
            return nil
        }
        self.superRareTitleIndex = superRare
        self.normalTitleIndex = normal
        self.masterDataIndex = master
        self.socketSuperRareTitleIndex = socketSuperRare
        self.socketNormalTitleIndex = socketNormal
        self.socketMasterDataIndex = socketMaster
    }
}
