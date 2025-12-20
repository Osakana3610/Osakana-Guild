// ==============================================================================
// CharacterSectionType.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクター詳細画面のセクション順序を定義
//   - rawValueで表示順序を固定し、全画面で統一
//
// 【データ構造】
//   - enum CharacterSectionType: 18種類のセクション
//   - rawValue（Int）で表示順序を制御
//   - CaseIterableで全セクションを列挙可能
//   - Sendableでスレッドセーフ
//
// 【使用箇所】
//   - キャラクター詳細画面のセクション構成管理
//   - 各セクションコンポーネントの呼び出し順序制御
//
// ==============================================================================

import Foundation

/// キャラクター詳細画面のセクション順序を定義するenum
/// rawValueで順序が固定され、全画面で統一されたセクション順序を確立する
enum CharacterSectionType: Int, CaseIterable, Sendable {
    case name = 1
    case characterImage = 2
    case race = 3
    case job = 4
    case subJob = 5
    case fixedEquipment = 6
    case levelExp = 7
    case acquisitionBonuses = 8
    case baseStats = 9
    case combatStats = 10
    case personalityTalent = 11
    case damageModifiers = 12
    case equipmentMultipliers = 13
    case mageMagic = 14
    case priestMagic = 15
    case equippedItems = 16
    case ownedSkills = 17
    case actionPreferences = 18
}
