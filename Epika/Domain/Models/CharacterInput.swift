// ==============================================================================
// CharacterInput.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - Progress層からRuntime層へのキャラクターデータ受け渡し
//   - CharacterSnapshot → CharacterInput 変換
//
// 【データ構造】
//   - CharacterInput: キャラクター入力データ
//     - 基本情報: id, displayName, raceId, jobId, previousJobId, avatarId
//     - レベル・経験値: level, experience
//     - 状態: currentHP
//     - 性格: primaryPersonalityId, secondaryPersonalityId
//     - 行動設定: actionRateAttack/PriestMagic/MageMagic/Breath
//     - 装備: equippedItems
//   - EquippedItem: 装備中アイテム
//     - 称号: superRareTitleId, normalTitleId
//     - アイテム: itemId, quantity
//     - ソケット: socketSuperRareTitleId, socketNormalTitleId, socketItemId
//     - stackKey: スタック識別キー
//
// 【使用箇所】
//   - RuntimeCharacterFactory: RuntimeCharacter生成の入力
//   - ProgressRuntimeService: 探索開始時のデータ変換
//
// ==============================================================================

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
    let displayOrder: UInt8
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
            displayOrder: snapshot.displayOrder,
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

    /// 装備アイテムの中間表現（CharacterValues.EquippedItemと統一）
    typealias EquippedItem = CharacterValues.EquippedItem
}
