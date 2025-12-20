// ==============================================================================
// RuntimeParty.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - RuntimeParty型エイリアスの定義
//   - 後方互換性のためのPartySnapshotへのエイリアス
//
// 【型定義】
//   - RuntimeParty = PartySnapshot（型エイリアス）
//
// 【注意】
//   - @deprecated: 新規コードではPartySnapshotを直接使用すること
//
// ==============================================================================

import Foundation

/// @deprecated PartySnapshotを直接使用してください。
typealias RuntimeParty = PartySnapshot
