// ==============================================================================
// RuntimeEquipment.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 装備アイテムの統合ビュー（マスター+インベントリ+価格）
//   - UI表示・装備選択用のランタイム装備情報
//
// 【データ構造】
//   - RuntimeEquipment: 装備アイテム情報
//     - id: スタック識別キー（6要素の組み合わせ）
//     - itemId: アイテムマスターID
//     - masterDataId: マスターデータID（文字列）
//     - displayName: 表示名
//     - quantity: 数量
//     - category (ItemSaleCategory): カテゴリ
//     - baseValue, sellValue: 基本価格・売却価格
//     - enhancement (Enhancement): 称号・ソケット情報
//     - rarity: レアリティ
//     - statBonuses: ステータスボーナス
//     - combatBonuses: 戦闘ボーナス
//
//   - CurrencyType: gold/catTicket/gem
//
// 【使用箇所】
//   - CharacterEquippedItemsSection: 装備表示
//   - RuntimeEquipmentRow: 装備リストアイテム
//   - CharacterSelectionForEquipmentView: 装備変更画面
//
// ==============================================================================

import Foundation

struct RuntimeEquipment: Identifiable, Sendable, Hashable {
    enum CurrencyType: Sendable {
        case gold
        case catTicket
        case gem
    }

    /// スタック識別キー（6つのidの組み合わせ）
    let id: String
    let itemId: UInt16
    let masterDataId: String
    let displayName: String
    let quantity: Int
    let category: ItemSaleCategory
    let baseValue: Int
    let sellValue: Int
    let enhancement: ItemEnhancement
    let rarity: UInt8?
    let statBonuses: ItemDefinition.StatBonuses
    let combatBonuses: ItemDefinition.CombatBonuses
}

extension RuntimeEquipment {
    static func == (lhs: RuntimeEquipment, rhs: RuntimeEquipment) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
