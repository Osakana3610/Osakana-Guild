// ==============================================================================
// ExplorationEventModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 探索中に発生するイベントのマスタデータ型定義
//
// 【データ構造】
//   - ExplorationEventType: イベント種別
//     - trap: 罠（ダメージ/状態異常）
//     - treasure: 宝箱（アイテム入手）
//     - encounter: 遭遇（敵と戦闘）
//     - rest: 休憩（HP回復）
//     - special: 特殊イベント
//     - battle: 強制戦闘
//     - merchant: 商人（売買）
//     - narrative: ナラティブ（テキストのみ）
//     - resource: 資源採取
//   - ExplorationEventDefinition: イベント定義
//     - id, type, name, description
//     - floorMin/floorMax: 発生フロア範囲
//     - tags: イベントタグ（フィルタ用）
//     - weights: コンテキスト別の出現重み
//     - payloadType/payloadJSON: イベント固有データ
//
// 【使用箇所】
//   - ExplorationEventScheduler: イベント抽選
//   - ExplorationEngine: イベント実行
//
// ==============================================================================

import Foundation

// MARK: - ExplorationEventType

enum ExplorationEventType: UInt8, Sendable, Hashable {
    case trap = 1
    case treasure = 2
    case encounter = 3
    case rest = 4
    case special = 5
    case battle = 6
    case merchant = 7
    case narrative = 8
    case resource = 9

    var identifier: String {
        switch self {
        case .trap: return "trap"
        case .treasure: return "treasure"
        case .encounter: return "encounter"
        case .rest: return "rest"
        case .special: return "special"
        case .battle: return "battle"
        case .merchant: return "merchant"
        case .narrative: return "narrative"
        case .resource: return "resource"
        }
    }
}

// MARK: - ExplorationEventDefinition

struct ExplorationEventDefinition: Identifiable, Sendable {
    struct Weight: Sendable, Hashable {
        let context: UInt8
        let weight: Double
    }

    let id: UInt8
    let type: UInt8
    let name: String
    let description: String
    let floorMin: Int
    let floorMax: Int
    let tags: [UInt8]
    let weights: [Weight]
    let payloadType: UInt8?
    let payloadJSON: String?
}
