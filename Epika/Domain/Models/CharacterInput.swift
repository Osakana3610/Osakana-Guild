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
    nonisolated let id: UInt8
    nonisolated let displayName: String
    nonisolated let raceId: UInt8
    nonisolated let jobId: UInt8
    nonisolated let previousJobId: UInt8
    nonisolated let avatarId: UInt16
    nonisolated let level: Int
    nonisolated let experience: Int
    nonisolated let currentHP: Int
    nonisolated let primaryPersonalityId: UInt8
    nonisolated let secondaryPersonalityId: UInt8
    nonisolated let actionRateAttack: Int
    nonisolated let actionRatePriestMagic: Int
    nonisolated let actionRateMageMagic: Int
    nonisolated let actionRateBreath: Int
    nonisolated let updatedAt: Date
    nonisolated let displayOrder: UInt8
    nonisolated let equippedItems: [EquippedItem]
}

extension CharacterInput {
    /// CachedCharacterからCharacterInputを生成
    nonisolated init(from character: CachedCharacter) {
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
            equippedItems: character.equippedItems.map { $0.toEquippedItem() }
        )
    }

    /// 装備アイテムの中間表現（CharacterValues.EquippedItemと統一）
    typealias EquippedItem = CharacterValues.EquippedItem
}
