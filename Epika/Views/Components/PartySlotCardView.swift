import SwiftUI

struct PartySlotBonuses: Sendable {
    let goldMultiplier: Double
    let rareMultiplier: Double
    let titleMultiplier: Double
    let fortune: Int

    static let zero = PartySlotBonuses(goldMultiplier: 0.0,
                                       rareMultiplier: 0.0,
                                       titleMultiplier: 0.0,
                                       fortune: 0)
}

struct PartySlotCardView<Footer: View>: View {
    let party: RuntimeParty
    let members: [RuntimeCharacter]
    let bonuses: PartySlotBonuses
    let isExploring: Bool
    let canStartExploration: Bool
    let onPrimaryAction: () -> Void
    let onMembersTap: (() -> Void)?
    private let footerBuilder: (() -> Footer)?
    init(party: RuntimeParty,
         members: [RuntimeCharacter],
         bonuses: PartySlotBonuses,
         isExploring: Bool,
         canStartExploration: Bool,
         onPrimaryAction: @escaping () -> Void,
         onMembersTap: (() -> Void)? = nil,
         @ViewBuilder footer: @escaping () -> Footer) {
        self.party = party
        self.members = members
        self.bonuses = bonuses
        self.isExploring = isExploring
        self.canStartExploration = canStartExploration
        self.onPrimaryAction = onPrimaryAction
        self.onMembersTap = onMembersTap
        self.footerBuilder = footer
    }

    init(party: RuntimeParty,
         members: [RuntimeCharacter],
         bonuses: PartySlotBonuses,
         isExploring: Bool,
         canStartExploration: Bool,
         onPrimaryAction: @escaping () -> Void,
         onMembersTap: (() -> Void)? = nil)
    where Footer == EmptyView {
        self.party = party
        self.members = members
        self.bonuses = bonuses
        self.isExploring = isExploring
        self.canStartExploration = canStartExploration
        self.onPrimaryAction = onPrimaryAction
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
                Text("レア \(formatMultiplier(bonuses.rareMultiplier))倍")
                Text("称号 \(formatMultiplier(bonuses.titleMultiplier))倍")
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
        if let onMembersTap {
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
