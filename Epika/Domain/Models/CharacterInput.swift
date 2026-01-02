// ==============================================================================
// CharacterInput.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - Progress層からRuntime層へのキャラクターデータ受け渡し
//   - CachedCharacter → CharacterInput 変換
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
//   - CachedCharacterFactory: CachedCharacter生成の入力
//   - ProgressRuntimeService: 探索開始時のデータ変換
//
// ==============================================================================

import Foundation

/// CharacterRecordからCachedCharacterへの変換用中間データ。
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
    /// CachedCharacterからCharacterInputを生成
    init(from character: CachedCharacter) {
        self.init(
            id: character.id,
            displayName: character.displayName,
            raceId: character.raceId,
            jobId: character.jobId,
            previousJobId: character.previousJobId,
            avatarId: character.avatarId,
            level: character.level,
            experience: character.experience,
            currentHP: character.currentHP,
            primaryPersonalityId: character.primaryPersonalityId,
            secondaryPersonalityId: character.secondaryPersonalityId,
            actionRateAttack: character.actionRateAttack,
            actionRatePriestMagic: character.actionRatePriestMagic,
            actionRateMageMagic: character.actionRateMageMagic,
            actionRateBreath: character.actionRateBreath,
            updatedAt: character.updatedAt,
            displayOrder: character.displayOrder,
            equippedItems: character.equippedItems
        )
    }

    /// 装備アイテムの中間表現（CharacterValues.EquippedItemと統一）
    typealias EquippedItem = CharacterValues.EquippedItem
}
