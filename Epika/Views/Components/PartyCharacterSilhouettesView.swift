// ==============================================================================
// PartyCharacterSilhouettesView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - パーティメンバーを最大6枠のグリッドで簡易表示
//   - 各メンバーのアバター、レベル、HPを小さく表示
//
// 【View構成】
//   - 2行3列のグリッド（最大6枠）
//   - 各枠: CharacterImageView + Lv + HP
//   - 空枠はグレーの矩形で表示
//   - メンバーが1人もいない場合は案内テキストを表示
//
// 【使用箇所】
//   - パーティ一覧画面
//   - ダンジョン出撃画面（PartySlotCardView内）
//
// ==============================================================================

import SwiftUI

/// パーティメンバーを最大6枠のグリッドで表示する。
struct PartyCharacterSilhouettesView: View {
    let party: RuntimeParty
    let characters: [RuntimeCharacter]

    private var orderedMembers: [RuntimeCharacter] {
        party.memberIds.compactMap { id in
            characters.first { $0.id == id }
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            if orderedMembers.isEmpty {
                VStack(spacing: 4) {
                    Text("メンバーが設定されていません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("パーティを開いて編成してください")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<6, id: \.self) { index in
                        Group {
                            if index < orderedMembers.count {
                                let member = orderedMembers[index]
                                VStack(spacing: 2) {
                                    CharacterImageView(avatarIndex: member.resolvedAvatarId, size: 55)
                                    VStack(spacing: 1) {
                                        Text("Lv.\(member.level)")
                                            .font(.caption2)
                                            .foregroundStyle(.primary)
                                        Text("HP\(member.currentHP)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 48)
                                .id("member_\(member.id)")
                            } else {
                                VStack(spacing: 2) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.systemGray5))
                                        .frame(width: 43, height: 53)
                                    VStack(spacing: 1) {
                                        Text("- / -")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 48)
                                .id("empty_\(index)")
                            }
                        }
                        if index < 5 {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
