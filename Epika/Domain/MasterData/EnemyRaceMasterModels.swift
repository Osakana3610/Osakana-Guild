// ==============================================================================
// EnemyRaceMasterModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 敵種族のマスタデータ型定義
//
// 【データ構造】
//   - EnemyRaceDefinition: 敵種族定義
//     - id: 種族ID
//     - name: 種族名（例: スライム族, ドラゴン族）
//     - baseResistances: 種族共通の基本耐性値
//
// 【設計意図】
//   - 種族ごとの共通耐性を定義し、個別の敵はこれを継承・上書き
//   - EnemyDefinition.resistanceOverrides で個別調整可能
//
// 【使用箇所】
//   - BattleEngine: ダメージ計算時の耐性参照
//   - MonsterEncyclopediaView: 種族分類表示
//
// ==============================================================================

import Foundation

struct EnemyRaceDefinition: Identifiable, Sendable, Hashable {
    let id: UInt8
    let name: String
    let baseResistances: EnemyDefinition.Resistances
}
