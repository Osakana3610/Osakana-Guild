import Foundation
import SwiftUI

struct RuntimeCharacterDetailSheetView: View {
    let character: RuntimeCharacter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CharacterDetailContent(character: character)
                .navigationTitle(character.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("閉じる") { dismiss() }
                    }
                }
        }
    }
}

struct CharacterDetailContent: View {
    let character: RuntimeCharacter
    let onRename: ((String) async throws -> Void)?
    let onAvatarChange: ((UInt16) async throws -> Void)?
    let onActionPreferencesChange: ((CharacterSnapshot.ActionPreferences) async throws -> Void)?

    init(character: RuntimeCharacter,
         onRename: ((String) async throws -> Void)? = nil,
         onAvatarChange: ((UInt16) async throws -> Void)? = nil,
         onActionPreferencesChange: ((CharacterSnapshot.ActionPreferences) async throws -> Void)? = nil) {
        self.character = character
        self.onRename = onRename
        self.onAvatarChange = onAvatarChange
        self.onActionPreferencesChange = onActionPreferencesChange
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // ヘッダー
                detailCard {
                    CharacterHeaderSection(character: character,
                                           onRename: onRename,
                                           onAvatarChange: onAvatarChange)
                }

                detailCard(title: "プロフィール") {
                    CharacterIdentitySection(character: character)
                }

                detailCard(title: "レベル / 経験値") {
                    CharacterLevelSection(character: character)
                }

                detailCard(title: "基本能力値") {
                    CharacterBaseStatsSection(character: character)
                }

                detailCard(title: "戦闘ステータス") {
                    CharacterCombatStatsSection(character: character)
                }

                detailCard(title: "行動優先度") {
                    CharacterActionPreferencesSection(character: character,
                                                      onActionPreferencesChange: onActionPreferencesChange)
                }

                detailCard(title: "習得スキル") {
                    CharacterSkillsSection(character: character)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .avoidBottomGameInfo()
    }

    @ViewBuilder
    private func detailCard<Content: View>(title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.headline)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
