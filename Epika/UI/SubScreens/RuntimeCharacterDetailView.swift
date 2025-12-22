// ==============================================================================
// RuntimeCharacterDetailView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクターの詳細情報を表示するシートとコンテンツを提供
//
// 【View構成】
//   - RuntimeCharacterDetailSheetView: シート形式の詳細画面
//   - CharacterDetailContent: 詳細情報の本体
//     - キャラクターヘッダー（名前・アバター変更）
//     - プロフィール情報
//     - レベル・経験値
//     - 基本能力値
//     - 戦闘ステータス
//     - 種族スキル
//     - 職業スキル
//     - 習得スキル一覧
//     - 魔法使い魔法
//     - 僧侶魔法
//     - 行動優先度設定
//
// 【使用箇所】
//   - キャラクター一覧からシート表示
//   - パーティ編成画面から参照
//
// ==============================================================================

import Foundation
import SwiftUI
import TipKit

struct CharacterDetailTip: Tip {
    var title: Text {
        Text("詳細を表示")
    }
    var message: Text? {
        Text("種族・職業・スキルをタップすると詳細を確認できます")
    }
}

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
    @Environment(AppServices.self) private var appServices

    init(character: RuntimeCharacter,
         onRename: ((String) async throws -> Void)? = nil,
         onAvatarChange: ((UInt16) async throws -> Void)? = nil,
         onActionPreferencesChange: ((CharacterSnapshot.ActionPreferences) async throws -> Void)? = nil) {
        self.character = character
        self.onRename = onRename
        self.onAvatarChange = onAvatarChange
        self.onActionPreferencesChange = onActionPreferencesChange
    }

    private var raceSkillUnlocks: [(level: Int, skill: SkillDefinition)] {
        let masterData = appServices.masterDataCache
        let unlocks = masterData.raceSkillUnlocks[character.raceId] ?? []
        return unlocks.compactMap { unlock in
            guard let skill = masterData.skill(unlock.skillId) else { return nil }
            return (level: unlock.level, skill: skill)
        }
    }

    private var jobSkillUnlocks: [(level: Int, skill: SkillDefinition)] {
        let masterData = appServices.masterDataCache
        // レベル習得スキルは現職のみ（転職したら前職のは失う）
        let unlocks = masterData.jobSkillUnlocks[character.jobId] ?? []
        return unlocks.compactMap { unlock in
            guard let skill = masterData.skill(unlock.skillId) else { return nil }
            return (level: unlock.level, skill: skill)
        }
    }

    var body: some View {
        List {
            Section {
                CharacterHeaderSection(character: character,
                                       onRename: onRename,
                                       onAvatarChange: onAvatarChange)
            }

            Section("プロフィール") {
                CharacterIdentitySection(character: character)
            }

            Section("レベル / 経験値") {
                CharacterLevelSection(character: character)
            }

            Section("基本能力値") {
                CharacterBaseStatsSection(character: character)
            }

            Section("戦闘ステータス") {
                CharacterCombatStatsSection(character: character)
            }

            Section("種族スキル") {
                CharacterRaceSkillsSection(skillUnlocks: raceSkillUnlocks, characterLevel: character.level)
            }

            Section("職業スキル") {
                CharacterJobSkillsSection(skillUnlocks: jobSkillUnlocks, characterLevel: character.level)
            }

            Section("習得スキル") {
                CharacterSkillsSection(character: character)
            }

            Section("魔法使い魔法") {
                CharacterMageSpellsSection(character: character)
            }

            Section("僧侶魔法") {
                CharacterPriestSpellsSection(character: character)
            }

            Section("行動優先度") {
                CharacterActionPreferencesSection(character: character,
                                                  onActionPreferencesChange: onActionPreferencesChange)
            }
        }
        .listStyle(.insetGrouped)
        .avoidBottomGameInfo()
    }
}
