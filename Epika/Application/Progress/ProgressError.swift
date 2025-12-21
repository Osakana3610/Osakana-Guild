// ==============================================================================
// ProgressError.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - Progress層のドメインエラー定義
//   - ユーザー向けローカライズエラーメッセージ
//
// 【エラー種別】
//   - invalidInput: 無効な入力
//   - characterNotFound: キャラクター未発見
//   - partyNotFound: パーティ未発見
//   - playerNotFound: プレイヤーデータ未発見
//   - explorationNotFound: 探索記録未発見
//   - shopNotFound: ショップ未発見
//   - shopStockNotFound: ショップ在庫未発見
//   - insufficientFunds: 所持金不足
//   - insufficientStock: 在庫不足
//   - itemDefinitionUnavailable: アイテム定義なし
//   - storyLocked: ストーリー未解放
//   - dungeonLocked: ダンジョン未解放
//   - invalidUnlockModule: 無効な解放モジュール
//
// 【使用箇所】
//   - Progress層の各Serviceでthrow
//   - UI層でエラーメッセージ表示
//
// ==============================================================================

import Foundation

enum ProgressError: Error {
    case invalidInput(description: String)
    case characterNotFound
    case partyNotFound
    case playerNotFound
    case explorationNotFound
    case shopNotFound
    case shopStockNotFound
    case insufficientFunds(required: Int, available: Int)
    case insufficientStock(required: Int, available: Int)
    case itemDefinitionUnavailable(ids: [String])
    case storyLocked(nodeId: String)
    case dungeonLocked(id: String)
    case invalidUnlockModule(String)
}

extension ProgressError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidInput(let description):
            return description
        case .characterNotFound:
            return "キャラクターが見つかりません。"
        case .partyNotFound:
            return "パーティが見つかりません。"
        case .playerNotFound:
            return "プレイヤーデータが見つかりません。"
        case .explorationNotFound:
            return "探索記録が見つかりません。"
        case .shopNotFound:
            return "ショップが見つかりません。"
        case .shopStockNotFound:
            return "ショップ在庫が見つかりません。"
        case .insufficientFunds(let required, let available):
            return "所持金が不足しています (必要: \(required)G / 所持: \(available)G)。"
        case .insufficientStock(let required, let available):
            return "在庫が不足しています (必要: \(required) / 在庫: \(available))。"
        case .itemDefinitionUnavailable(let ids):
            return "マスタに存在しないアイテムIDがあります: \(ids.joined(separator: ", "))."
        case .storyLocked:
            return "まだ解放されていないストーリーです。"
        case .dungeonLocked:
            return "まだ解放されていない迷宮です。"
        case .invalidUnlockModule(let module):
            return "無効な解放モジュール指定です: \(module)"
        }
    }
}
