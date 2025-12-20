// ==============================================================================
// CharacterActionPreferencesSection.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクターの行動優先度（攻撃/僧侶魔法/魔法使い魔法/ブレス）を表示・編集
//   - 各行動カテゴリの抽選重み（0〜100%）を設定
//
// 【View構成】
//   - 編集モード: 4つのスライダー + 保存ボタン
//     - ブレスダメージ0の場合はブレススライダーを無効化
//     - 変更検知で保存ボタンを有効化
//   - 読み取り専用モード: LabeledContentで各重みを表示
//   - 行動抽選順序の説明テキスト
//
// 【使用箇所】
//   - キャラクター詳細画面（CharacterSectionType.actionPreferences）
//
// ==============================================================================

import SwiftUI

/// キャラクターの行動優先度を表示・編集するセクション
/// CharacterSectionType: actionPreferences
@MainActor
struct CharacterActionPreferencesSection: View {
    let character: RuntimeCharacter
    let onActionPreferencesChange: ((CharacterSnapshot.ActionPreferences) async throws -> Void)?

    @State private var actionPreferenceAttack: Double
    @State private var actionPreferencePriest: Double
    @State private var actionPreferenceMage: Double
    @State private var actionPreferenceBreath: Double
    @State private var actionPreferenceError: String?
    @State private var isUpdatingActionPreferences = false

    init(character: RuntimeCharacter,
         onActionPreferencesChange: ((CharacterSnapshot.ActionPreferences) async throws -> Void)? = nil) {
        self.character = character
        self.onActionPreferencesChange = onActionPreferencesChange
        let preferences = character.actionPreferences
        _actionPreferenceAttack = State(initialValue: Double(preferences.attack))
        _actionPreferencePriest = State(initialValue: Double(preferences.priestMagic))
        _actionPreferenceMage = State(initialValue: Double(preferences.mageMagic))
        _actionPreferenceBreath = State(initialValue: Double(preferences.breath))
    }

    var body: some View {
        Group {
            if onActionPreferencesChange != nil {
                actionPreferenceEditor
            } else {
                actionPreferenceSummary
            }
        }
        .onChange(of: character.actionPreferences) { _, newValue in
            actionPreferenceAttack = Double(newValue.attack)
            actionPreferencePriest = Double(newValue.priestMagic)
            actionPreferenceMage = Double(newValue.mageMagic)
            actionPreferenceBreath = Double(newValue.breath)
            actionPreferenceError = nil
            isUpdatingActionPreferences = false
        }
    }

    private var actionPreferenceEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("行動抽選は「ブレス > 僧侶魔法 > 魔法使い魔法 > 物理攻撃」の順に行われます。各スライダーはカテゴリの重みを0〜100%で指定します。")
                .font(.caption)
                .foregroundStyle(.secondary)

            actionSliderRow(label: "ブレス",
                            description: "ブレス行動の抽選重み。ブレスダメージを持たない場合は調整できません。",
                            value: breathSliderBinding,
                            isDisabled: !canEditBreathRate)

            actionSliderRow(label: "僧侶魔法",
                            description: "回復・支援魔法の抽選重み。",
                            value: priestSliderBinding)

            actionSliderRow(label: "魔法使い魔法",
                            description: "攻撃魔法の抽選重み。",
                            value: mageSliderBinding)

            actionSliderRow(label: "物理攻撃",
                            description: "通常攻撃／格闘攻撃の抽選重み。",
                            value: attackSliderBinding)

            if let error = actionPreferenceError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("設定を保存") {
                    saveActionPreferences()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!actionPreferencesDirty || isUpdatingActionPreferences)

                if isUpdatingActionPreferences {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 8)
                }
                Spacer()
            }
        }
    }

    private var actionPreferenceSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            let prefs = character.actionPreferences
            Text("行動抽選の重みを表示します。")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("ブレス", value: "\(prefs.breath)%")
            LabeledContent("僧侶魔法", value: "\(prefs.priestMagic)%")
            LabeledContent("魔法使い魔法", value: "\(prefs.mageMagic)%")
            LabeledContent("物理攻撃", value: "\(prefs.attack)%")
        }
    }
}

private extension CharacterActionPreferencesSection {
    var originalActionPreferences: CharacterSnapshot.ActionPreferences {
        character.actionPreferences
    }

    var editedActionPreferences: CharacterSnapshot.ActionPreferences {
        func clamp(_ value: Double) -> Int {
            let rounded = Int(value.rounded())
            return max(0, min(100, rounded))
        }
        return CharacterSnapshot.ActionPreferences(attack: clamp(actionPreferenceAttack),
                                                   priestMagic: clamp(actionPreferencePriest),
                                                   mageMagic: clamp(actionPreferenceMage),
                                                   breath: clamp(actionPreferenceBreath))
    }

    var actionPreferencesDirty: Bool {
        editedActionPreferences != originalActionPreferences
    }

    var canEditBreathRate: Bool {
        character.combat.breathDamage > 0
    }

    var attackSliderBinding: Binding<Double> {
        Binding(
            get: { actionPreferenceAttack },
            set: { newValue in
                actionPreferenceAttack = newValue
                actionPreferenceError = nil
            }
        )
    }

    var priestSliderBinding: Binding<Double> {
        Binding(
            get: { actionPreferencePriest },
            set: { newValue in
                actionPreferencePriest = newValue
                actionPreferenceError = nil
            }
        )
    }

    var mageSliderBinding: Binding<Double> {
        Binding(
            get: { actionPreferenceMage },
            set: { newValue in
                actionPreferenceMage = newValue
                actionPreferenceError = nil
            }
        )
    }

    var breathSliderBinding: Binding<Double> {
        Binding(
            get: { actionPreferenceBreath },
            set: { newValue in
                actionPreferenceBreath = newValue
                actionPreferenceError = nil
            }
        )
    }

    func actionSliderRow(label: String,
                         description: String,
                         value: Binding<Double>,
                         isDisabled: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...100, step: 1)
                .tint(.accentColor)
                .disabled(isDisabled || isUpdatingActionPreferences)
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    func saveActionPreferences() {
        guard let onActionPreferencesChange else { return }
        guard actionPreferencesDirty else {
            actionPreferenceError = nil
            return
        }
        actionPreferenceError = nil
        isUpdatingActionPreferences = true
        let newPreferences = editedActionPreferences
        Task {
            do {
                try await onActionPreferencesChange(newPreferences)
            } catch {
                await MainActor.run {
                    actionPreferenceError = error.localizedDescription
                }
            }
            await MainActor.run {
                isUpdatingActionPreferences = false
            }
        }
    }
}
