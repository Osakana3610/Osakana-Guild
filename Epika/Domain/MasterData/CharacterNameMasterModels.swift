// ==============================================================================
// CharacterNameMasterModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクター作成時の名前候補データの型定義
//
// 【データ構造】
//   - CharacterNameDefinition: 名前候補
//     - id: 一意識別子
//     - genderCode: 性別コード（1=男性, 2=女性, 3=無性別）
//     - name: 表示名
//
// 【使用箇所】
//   - CharacterCreationView: 名前候補の表示・選択
//   - SQLiteMasterDataQueries.CharacterNames: マスタデータ読込
//
// ==============================================================================

import Foundation

/// キャラクター名候補の定義
struct CharacterNameDefinition: Sendable, Hashable, Identifiable {
    let id: UInt16
    let genderCode: UInt8  // 1=male, 2=female, 3=genderless
    let name: String
}
