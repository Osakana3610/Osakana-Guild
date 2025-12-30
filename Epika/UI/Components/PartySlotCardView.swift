// ==============================================================================
// PartySlotCardView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - パーティスロットをカード形式で表示
//   - ボーナス情報、メンバー一覧、出撃/帰還ボタンを提供
//
// 【View構成】
//   - ボーナス行: GP倍率、レア倍率、称号倍率、運勢
//   - パーティ名行
//   - メンバー行: PartyCharacterSilhouettesViewで6枠表示
//   - 出撃/帰還ボタン: 探索中は赤、未探索時は青
//   - オプションフッター: ViewBuilderで柔軟に追加可能
//
// 【使用箇所】
//   - ダンジョン画面（各スロットのカード表示）
//   - パーティ一覧画面
//
// ==============================================================================

import SwiftUI

struct PartySlotCardView<Footer: View>: View {
    let party: PartySnapshot
    let members: [RuntimeCharacter]
    let bonuses: PartyDropBonuses
    let isExploring: Bool
    let canStartExploration: Bool
    let onPrimaryAction: () -> Void
    let onMemberTap: ((RuntimeCharacter) -> Void)?
    let onMembersTap: (() -> Void)?
    private let footerBuilder: (() -> Footer)?
    init(party: PartySnapshot,
         members: [RuntimeCharacter],
         bonuses: PartyDropBonuses,
         isExploring: Bool,
         canStartExploration: Bool,
         onPrimaryAction: @escaping () -> Void,
         onMemberTap: ((RuntimeCharacter) -> Void)? = nil,
         onMembersTap: (() -> Void)? = nil,
         @ViewBuilder footer: @escaping () -> Footer) {
        self.party = party
        self.members = members
        self.bonuses = bonuses
        self.isExploring = isExploring
        self.canStartExploration = canStartExploration
        self.onPrimaryAction = onPrimaryAction
        self.onMemberTap = onMemberTap
        self.onMembersTap = onMembersTap
        self.footerBuilder = footer
    }

    init(party: PartySnapshot,
         members: [RuntimeCharacter],
         bonuses: PartyDropBonuses,
         isExploring: Bool,
         canStartExploration: Bool,
         onPrimaryAction: @escaping () -> Void,
         onMemberTap: ((RuntimeCharacter) -> Void)? = nil,
         onMembersTap: (() -> Void)? = nil)
    where Footer == EmptyView {
        self.party = party
        self.members = members
        self.bonuses = bonuses
        self.isExploring = isExploring
        self.canStartExploration = canStartExploration
        self.onPrimaryAction = onPrimaryAction
        self.onMemberTap = onMemberTap
        self.onMembersTap = onMembersTap
        self.footerBuilder = nil
    }

    var body: some View {
        let hasFooter = footerBuilder != nil
        VStack(spacing: 0) {
            bonusRow
                .padding(.top, 12)
            partyNameRow
                .padding(.top, 6)
            membersRow
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, hasFooter ? 0 : 6)

            if let footerBuilder {
                Divider()
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                footerBuilder()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private var bonusRow: some View {
        HStack {
            HStack(spacing: 12) {
                Text("GP \(formatMultiplier(bonuses.goldMultiplier))倍")
                Text("レア \(formatMultiplier(bonuses.rareDropMultiplier))倍")
                Text("称号 \(formatMultiplier(bonuses.titleGrantRateMultiplier))倍")
                Text("運勢 \(bonuses.fortune)")
            }
            .font(.caption)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            Button(action: onPrimaryAction) {
                Text(isExploring ? "帰還" : "出撃")
                    .font(.headline)
                    .foregroundColor((isExploring || canStartExploration) ? .white : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(isExploring ? Color.red : (canStartExploration ? Color.blue : Color.gray))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isExploring && !canStartExploration)
        }
    }

    @ViewBuilder
    private var partyNameRow: some View {
        HStack {
            Text(party.name)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    @ViewBuilder
    private var membersRow: some View {
        if let onMemberTap {
            PartyCharacterSilhouettesView(party: party, characters: members, onMemberTap: onMemberTap)
        } else if let onMembersTap {
            Button(action: onMembersTap) {
                PartyCharacterSilhouettesView(party: party, characters: members)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            PartyCharacterSilhouettesView(party: party, characters: members)
        }
    }

    private func formatMultiplier(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
