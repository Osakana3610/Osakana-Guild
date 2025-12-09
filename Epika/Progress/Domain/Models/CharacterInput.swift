import Foundation

/// CharacterRecordからRuntimeCharacterへの変換用中間データ。
/// 計算結果は含まない。Progress層からRuntime層へデータを渡すために使用。
struct CharacterInput: Sendable, Hashable {
    let id: UInt8
    let displayName: String
    let raceId: UInt8
    let jobId: UInt8
    let previousJobId: UInt8
    let avatarId: UInt16
    let level: Int
    let experience: Int
    let currentHP: Int
    let primaryPersonalityId: UInt8
    let secondaryPersonalityId: UInt8
    let actionRateAttack: Int
    let actionRatePriestMagic: Int
    let actionRateMageMagic: Int
    let actionRateBreath: Int
    let updatedAt: Date
    let equippedItems: [EquippedItem]
}

extension CharacterInput {
    /// CharacterSnapshotからCharacterInputを生成
    init(from snapshot: CharacterSnapshot) {
        self.init(
            id: snapshot.id,
            displayName: snapshot.displayName,
            raceId: snapshot.raceId,
            jobId: snapshot.jobId,
            previousJobId: snapshot.previousJobId,
            avatarId: snapshot.avatarId,
            level: snapshot.level,
            experience: snapshot.experience,
            currentHP: snapshot.hitPoints.current,
            primaryPersonalityId: snapshot.personality.primaryId,
            secondaryPersonalityId: snapshot.personality.secondaryId,
            actionRateAttack: snapshot.actionPreferences.attack,
            actionRatePriestMagic: snapshot.actionPreferences.priestMagic,
            actionRateMageMagic: snapshot.actionPreferences.mageMagic,
            actionRateBreath: snapshot.actionPreferences.breath,
            updatedAt: snapshot.updatedAt,
            equippedItems: snapshot.equippedItems.map { item in
                EquippedItem(
                    superRareTitleId: item.superRareTitleId,
                    normalTitleId: item.normalTitleId,
                    itemId: item.itemId,
                    socketSuperRareTitleId: item.socketSuperRareTitleId,
                    socketNormalTitleId: item.socketNormalTitleId,
                    socketItemId: item.socketItemId,
                    quantity: item.quantity
                )
            }
        )
    }

    /// 装備アイテムの中間表現
    struct EquippedItem: Sendable, Hashable {
        let superRareTitleId: UInt8
        let normalTitleId: UInt8
        let itemId: UInt16
        let socketSuperRareTitleId: UInt8
        let socketNormalTitleId: UInt8
        let socketItemId: UInt16
        let quantity: Int

        var stackKey: String {
            "\(superRareTitleId)|\(normalTitleId)|\(itemId)|\(socketSuperRareTitleId)|\(socketNormalTitleId)|\(socketItemId)"
        }
    }
}
