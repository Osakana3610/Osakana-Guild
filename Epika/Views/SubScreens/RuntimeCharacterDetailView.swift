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
    let onAvatarChange: ((String) async throws -> Void)?
    let onActionPreferencesChange: ((CharacterSnapshot.ActionPreferences) async throws -> Void)?

    init(character: RuntimeCharacter,
         onRename: ((String) async throws -> Void)? = nil,
         onAvatarChange: ((String) async throws -> Void)? = nil,
         onActionPreferencesChange: ((CharacterSnapshot.ActionPreferences) async throws -> Void)? = nil) {
        self.character = character
        self.onRename = onRename
        self.onAvatarChange = onAvatarChange
        self.onActionPreferencesChange = onActionPreferencesChange
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Section order: name(1), characterImage(2) - combined in header
                CharacterHeaderSection(character: character,
                                       onRename: onRename,
                                       onAvatarChange: onAvatarChange)

                // Section order: race(3), job(4)
                CharacterIdentitySection(character: character)

                // Section order: levelExp(7)
                CharacterLevelSection(character: character)

                // Section order: baseStats(9)
                CharacterBaseStatsSection(character: character)

                // Section order: combatStats(10)
                CharacterCombatStatsSection(character: character)

                // Section order: actionPreferences(18)
                CharacterActionPreferencesSection(character: character,
                                                  onActionPreferencesChange: onActionPreferencesChange)

                // Section order: ownedSkills(17)
                CharacterSkillsSection(character: character)
            }
            .padding()
        }
        .avoidBottomGameInfo()
    }
}
