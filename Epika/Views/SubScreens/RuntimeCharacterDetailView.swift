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

    @State private var nameText: String
    @State private var renameError: String?
    @State private var isRenaming = false
    @FocusState private var isNameFieldFocused: Bool
    @State private var isAvatarSheetPresented = false
    @State private var avatarChangeError: String?
    @State private var isChangingAvatar = false
    @State private var actionPreferenceAttack: Double
    @State private var actionPreferencePriest: Double
    @State private var actionPreferenceMage: Double
    @State private var actionPreferenceBreath: Double
    @State private var actionPreferenceError: String?
    @State private var isUpdatingActionPreferences = false

    init(character: RuntimeCharacter,
         onRename: ((String) async throws -> Void)? = nil,
         onAvatarChange: ((String) async throws -> Void)? = nil,
         onActionPreferencesChange: ((CharacterSnapshot.ActionPreferences) async throws -> Void)? = nil) {
        self.character = character
        self.onRename = onRename
        self.onAvatarChange = onAvatarChange
        self.onActionPreferencesChange = onActionPreferencesChange
        _nameText = State(initialValue: character.name)
        let preferences = character.progress.actionPreferences
        _actionPreferenceAttack = State(initialValue: Double(preferences.attack))
        _actionPreferencePriest = State(initialValue: Double(preferences.priestMagic))
        _actionPreferenceMage = State(initialValue: Double(preferences.mageMagic))
        _actionPreferenceBreath = State(initialValue: Double(preferences.breath))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                identitySection
                levelSection
                baseStatSection
                combatStatSection
                actionPreferenceSection
                skillSection
            }
            .padding()
        }
        .avoidBottomGameInfo()
        .onChange(of: character.name) { _, newValue in
            nameText = newValue
        }
        .onChange(of: character.avatarIdentifier) { _, _ in
            avatarChangeError = nil
        }
        .sheet(isPresented: $isAvatarSheetPresented) {
            CharacterAvatarSelectionSheet(currentIdentifier: character.avatarIdentifier,
                                          defaultIdentifier: defaultAvatarIdentifier) { identifier in
                applyAvatarChange(identifier)
            }
        }
        .onChange(of: character.progress.actionPreferences) { _, newValue in
            actionPreferenceAttack = Double(newValue.attack)
            actionPreferencePriest = Double(newValue.priestMagic)
            actionPreferenceMage = Double(newValue.mageMagic)
            actionPreferenceBreath = Double(newValue.breath)
            actionPreferenceError = nil
            isUpdatingActionPreferences = false
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 16) {
            CharacterImageView(avatarIdentifier: character.avatarIdentifier, size: 60)
                .frame(width: 60, height: 60, alignment: .center)
                .overlay(alignment: .bottomTrailing) {
                    if onAvatarChange != nil {
                        Image(systemName: "pencil.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .offset(x: -2, y: -2)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard onAvatarChange != nil, !isChangingAvatar else { return }
                    isAvatarSheetPresented = true
                }

            VStack(alignment: .leading, spacing: 6) {
                if onRename != nil {
                    HStack(spacing: 8) {
                        TextField("キャラクター名", text: $nameText)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)
                            .disabled(isRenaming)
                            .focused($isNameFieldFocused)
                            .onSubmit { triggerRename() }
                            .onChange(of: nameText) { _, _ in renameError = nil }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: isNameFieldFocused) { _, focused in
                        if !focused {
                            triggerRename()
                        }
                    }

                    if let renameError {
                        Text(renameError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } else {
                    Text(character.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let avatarChangeError {
                    Text(avatarChangeError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .overlay(alignment: .topLeading) {
            if isChangingAvatar {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
            }
        }
    }

    private var identitySection: some View {
        GroupBox("プロフィール") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("種族", value: character.raceName)
                LabeledContent("職業", value: character.jobName)
                LabeledContent("性別", value: character.gender)
            }
        }
    }

    private var levelSection: some View {
        GroupBox("レベル / 経験値") {
            VStack(alignment: .leading, spacing: 8) {
                switch experienceSummary {
                case .success(let data):
                    Text(summaryLine(from: data))
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .monospacedDigit()
                case .failure(let message):
                    Text("経験値情報を取得できません: \(message)")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var baseStatSection: some View {
        GroupBox("基本能力値") {
            LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                BaseStatRow(label: "力", value: character.baseStats.strength)
                BaseStatRow(label: "知恵", value: character.baseStats.wisdom)
                BaseStatRow(label: "精神", value: character.baseStats.spirit)
                BaseStatRow(label: "体力", value: character.baseStats.vitality)
                BaseStatRow(label: "敏捷", value: character.baseStats.agility)
                BaseStatRow(label: "運", value: character.baseStats.luck)
            }
        }
    }

    private var combatStatSection: some View {
        GroupBox("戦闘ステータス") {
            let stats = character.combatStats
            let isMartial = character.isMartialEligible
            let physicalLabel = isMartial ? "物理攻撃(格闘)" : "物理攻撃"
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                CombatStatRow(label: "最大HP", value: stats.maxHP)
                CombatStatRow(label: physicalLabel, value: stats.physicalAttack)
                CombatStatRow(label: "魔法攻撃", value: stats.magicalAttack)
                CombatStatRow(label: "物理防御", value: stats.physicalDefense)
                CombatStatRow(label: "魔法防御", value: stats.magicalDefense)
                CombatStatRow(label: "命中", value: stats.hitRate)
                CombatStatRow(label: "回避", value: stats.evasionRate)
                CombatStatRow(label: "クリティカル", value: stats.criticalRate)
                CombatStatRow(label: "攻撃回数", value: stats.attackCount)
                CombatStatRow(label: "魔法治療", value: stats.magicalHealing)
                CombatStatRow(label: "罠解除", value: stats.trapRemoval)
                CombatStatRow(label: "追加ダメージ", value: stats.additionalDamage)
                CombatStatRow(label: "ブレスダメージ", value: stats.breathDamage)
            }
        }
    }

    private var actionPreferenceSection: some View {
        GroupBox("行動優先度") {
            if onActionPreferencesChange != nil {
                actionPreferenceEditor
            } else {
                actionPreferenceSummary
            }
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
            let prefs = character.progress.actionPreferences
            Text("行動抽選の重みを表示します。")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("ブレス", value: "\(prefs.breath)%")
            LabeledContent("僧侶魔法", value: "\(prefs.priestMagic)%")
            LabeledContent("魔法使い魔法", value: "\(prefs.mageMagic)%")
            LabeledContent("物理攻撃", value: "\(prefs.attack)%")
        }
    }

    private var skillSection: some View {
        GroupBox("習得スキル") {
            let skills = character.masteredSkills
            if skills.isEmpty {
                Text("スキルなし")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(skills, id: \.id) { skill in
                        Text("• \(skill.name)")
                    }
                }
            }
        }
    }

}

private extension CharacterDetailContent {
    enum ExperienceSummary {
        case success(ExperienceData)
        case failure(String)
    }

    struct ExperienceData {
        let level: Int
        let cap: Int
        let totalExperience: Int
        let currentProgress: Int
        let nextLevelRequirement: Int?
        let remainingToNext: Int?
        let multiplier: Double
    }

    var experienceSummary: ExperienceSummary {
        do {
            return .success(try makeExperienceData())
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func makeExperienceData() throws -> ExperienceData {
        let level = max(1, character.level)
        let cap = character.raceData?.maxLevel ?? 200
        let total = character.experience
        let progress = try CharacterExperienceTable.experienceIntoCurrentLevel(accumulatedExperience: total,
                                                                               level: level)
        let multiplier = try experienceMultiplier()
        if level >= cap {
            return ExperienceData(level: level,
                                  cap: cap,
                                  totalExperience: total,
                                  currentProgress: progress,
                                  nextLevelRequirement: nil,
                                  remainingToNext: nil,
                                  multiplier: multiplier)
        }
        let delta = try CharacterExperienceTable.experienceToNextLevel(from: level)
        let remaining = max(0, delta - progress)
        return ExperienceData(level: level,
                              cap: cap,
                              totalExperience: total,
                              currentProgress: progress,
                              nextLevelRequirement: delta,
                              remainingToNext: remaining,
                              multiplier: multiplier)
    }

    func summaryLine(from data: ExperienceData) -> String {
        let remainingText = data.remainingToNext.map(formatNumber) ?? "0"
        return "Lv\(data.level) Exp \(formatNumber(data.totalExperience)) (×\(formatMultiplier(data.multiplier))) 次のLvまで\(remainingText)"
    }

    func experienceMultiplier() throws -> Double {
        let equippedSkillIds = Set(character.progress.learnedSkills.filter { $0.isEquipped }.map { $0.skillId })
        guard !equippedSkillIds.isEmpty else { return 1.0 }
        let equippedDefinitions = character.masteredSkills.filter { equippedSkillIds.contains($0.id) }
        guard !equippedDefinitions.isEmpty else { return 1.0 }
        let components = try SkillRuntimeEffectCompiler.rewardComponents(from: equippedDefinitions)
        return components.experienceScale()
    }

    func formatNumber(_ value: Int) -> String {
        if let formatted = Self.numberFormatter.string(from: NSNumber(value: value)) {
            return formatted
        }
        return "\(value)"
    }

    func formatMultiplier(_ value: Double) -> String {
        let clamped = max(0.0, value)
        return String(format: "%.2f", clamped)
    }

    static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()

    var defaultAvatarIdentifier: String? {
        try? CharacterAvatarIdentifierResolver.defaultAvatarIdentifier(jobId: character.jobId,
                                                                       genderRawValue: character.gender)
    }

    private var originalActionPreferences: CharacterSnapshot.ActionPreferences {
        let prefs = character.progress.actionPreferences
        return CharacterSnapshot.ActionPreferences(attack: prefs.attack,
                                                   priestMagic: prefs.priestMagic,
                                                   mageMagic: prefs.mageMagic,
                                                   breath: prefs.breath)
    }

    private var editedActionPreferences: CharacterSnapshot.ActionPreferences {
        func clamp(_ value: Double) -> Int {
            let rounded = Int(value.rounded())
            return max(0, min(100, rounded))
        }
        return CharacterSnapshot.ActionPreferences(attack: clamp(actionPreferenceAttack),
                                                   priestMagic: clamp(actionPreferencePriest),
                                                   mageMagic: clamp(actionPreferenceMage),
                                                   breath: clamp(actionPreferenceBreath))
    }

    private var actionPreferencesDirty: Bool {
        editedActionPreferences != originalActionPreferences
    }

    private var canEditBreathRate: Bool {
        character.combatStats.breathDamage > 0
    }

    private var attackSliderBinding: Binding<Double> {
        Binding(
            get: { actionPreferenceAttack },
            set: { newValue in
                actionPreferenceAttack = newValue
                actionPreferenceError = nil
            }
        )
    }

    private var priestSliderBinding: Binding<Double> {
        Binding(
            get: { actionPreferencePriest },
            set: { newValue in
                actionPreferencePriest = newValue
                actionPreferenceError = nil
            }
        )
    }

    private var mageSliderBinding: Binding<Double> {
        Binding(
            get: { actionPreferenceMage },
            set: { newValue in
                actionPreferenceMage = newValue
                actionPreferenceError = nil
            }
        )
    }

    private var breathSliderBinding: Binding<Double> {
        Binding(
            get: { actionPreferenceBreath },
            set: { newValue in
                actionPreferenceBreath = newValue
                actionPreferenceError = nil
            }
        )
    }

    private func actionSliderRow(label: String,
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

    private func triggerRename() {
        guard let onRename else { return }
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nameText = character.name
            renameError = "名前を入力してください"
            return
        }
        guard trimmed != character.name else {
            renameError = nil
            return
        }
        renameError = nil
        isRenaming = true
        Task {
            do {
                try await onRename(trimmed)
                await MainActor.run {
                    nameText = trimmed
                    renameError = nil
                    isRenaming = false
                }
            } catch {
                await MainActor.run {
                    renameError = error.localizedDescription
                    nameText = character.name
                    isRenaming = false
                }
            }
        }
    }

    private func applyAvatarChange(_ identifier: String) {
        guard let onAvatarChange else { return }
        avatarChangeError = nil
        isChangingAvatar = true
        Task {
            do {
                try await onAvatarChange(identifier)
                await MainActor.run {
                    isChangingAvatar = false
                    isAvatarSheetPresented = false
                }
            } catch {
                await MainActor.run {
                    isChangingAvatar = false
                    avatarChangeError = error.localizedDescription
                }
            }
        }
    }

    private func saveActionPreferences() {
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

private struct BaseStatRow: View {
    let label: String
    let value: Int
    let equipmentBonus: Int
    let maxValue: Int

    init(label: String, value: Int, equipmentBonus: Int = 0, maxValue: Int = 99) {
        self.label = label
        self.value = value
        self.equipmentBonus = equipmentBonus
        self.maxValue = maxValue
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label.count == 1 ? "\(label)　" : label)
                .font(.subheadline)
                .foregroundStyle(.primary)

            HStack(alignment: .center, spacing: 4) {
                Text(paddedTwoDigit(value))
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("(\(paddedSignedTwoDigit(equipmentBonus)))")
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 0) {
                SimpleProgressBar(currentValue: value, maxValue: maxValue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func paddedTwoDigit(_ value: Int) -> String {
        let raw = String(format: "%2d", value)
        return raw.replacingOccurrences(of: " ", with: "\u{2007}")
    }

    private func paddedSignedTwoDigit(_ value: Int) -> String {
        let raw = String(format: "%+2d", value)
        return raw.replacingOccurrences(of: " ", with: "\u{2007}")
    }
}

private struct SimpleProgressBar: View {
    let currentValue: Int
    let maxValue: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let clamped = max(1, min(currentValue, maxValue))
        let barCount = min(clamped, maxBarCount)
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { _ in
                Capsule()
                    .fill(Color.primary.opacity(0.8))
                    .frame(width: barSize.width, height: barSize.height)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var barSize: CGSize {
        switch dynamicTypeSize {
        case .xSmall, .small:
            return CGSize(width: 2, height: 10)
        case .medium:
            return CGSize(width: 2, height: 12)
        case .large:
            return CGSize(width: 3, height: 14)
        case .xLarge:
            return CGSize(width: 3, height: 16)
        case .xxLarge:
            return CGSize(width: 3, height: 18)
        case .xxxLarge:
            return CGSize(width: 4, height: 20)
        default: // accessibility sizes
            return CGSize(width: 5, height: 24)
        }
    }

    private var barSpacing: CGFloat {
        isAccessibilityCategory ? 3 : 2
    }

    private var maxBarCount: Int {
        isAccessibilityCategory ? 20 : 40
    }

    private var isAccessibilityCategory: Bool {
        switch dynamicTypeSize {
        case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
            return true
        default:
            return false
        }
    }
}

private struct CombatStatRow: View {
    let label: String
    let value: Int

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text("\(value)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
