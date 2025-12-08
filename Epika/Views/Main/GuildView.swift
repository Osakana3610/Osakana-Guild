import SwiftUI

struct GuildView: View {
    @EnvironmentObject private var progressService: ProgressService
    @State private var characterState = CharacterViewState()
    @State private var maxCharacterSlots: Int = AppConstants.Progress.defaultCharacterSlotCount
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didLoadOnce = false

    private var aliveSummaries: [CharacterViewState.CharacterSummary] {
        characterState.summaries.filter { $0.isAlive }
    }

    private var fallenSummaries: [CharacterViewState.CharacterSummary] {
        characterState.summaries.filter { !$0.isAlive }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    errorState(message: errorMessage)
                } else if isLoading && characterState.summaries.isEmpty {
                    loadingState
                } else {
                    contentList
                }
            }
            .navigationTitle("ギルド")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                characterState.configureIfNeeded(with: progressService)
                Task { await loadOnce() }
            }
            .refreshable { await reload() }
        }
    }

    private var contentList: some View {
        List {
            Section("ギルド機能") {
                NavigationLink {
                    CharacterCreationView(progressService: progressService) {
                        Task { await reload() }
                    }
                } label: {
                    GuildActionLabel(title: "新しいキャラクターを登録",
                                      icon: "person.badge.plus",
                                      tint: .blue)
                }

                NavigationLink {
                    CharacterReviveView(progressService: progressService) {
                        Task { await reload() }
                    }
                } label: {
                    GuildActionLabel(title: "キャラクターを蘇生させる",
                                      icon: "heart.fill",
                                      tint: .red,
                                      badgeCount: fallenSummaries.count)
                }

                NavigationLink {
                    CharacterJobChangeView(progressService: progressService) {
                        Task { await reload() }
                    }
                } label: {
                    GuildActionLabel(title: "キャラクターを転職させる",
                                      icon: "arrow.triangle.2.circlepath",
                                      tint: .green)
                }

                NavigationLink {
                    BattleStatsView(characters: characterState.allCharacters)
                } label: {
                    GuildActionLabel(title: "戦闘能力一覧",
                                      icon: "chart.bar",
                                      tint: .purple)
                }

                NavigationLink {
                    PartySlotExpansionView(progressService: progressService) {
                        Task { await reload() }
                    }
                } label: {
                    GuildActionLabel(title: "ギルドを改造する",
                                      icon: "house",
                                      tint: .orange)
                }

            }

            Section("登録キャラクター (\(characterState.summaries.count)/\(maxCharacterSlots))") {
                if aliveSummaries.isEmpty {
                    Text("在籍中のキャラクターがいません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(aliveSummaries) { summary in
                        NavigationLink {
                            LazyRuntimeCharacterDetailView(characterId: summary.id,
                                                            summary: summary,
                                                            progressService: progressService)
                        } label: {
                            GuildCharacterRow(summary: summary)
                        }
                    }
                }
            }

            if !fallenSummaries.isEmpty {
                Section("戦線離脱 (\(fallenSummaries.count))") {
                    ForEach(fallenSummaries) { summary in
                        GuildCharacterRow(summary: summary)
                            .opacity(0.6)
                    }
                }
            }

            Section {
                NavigationLink("キャラクターを解雇する") {
                    LazyDismissCharacterView {
                        Task { await reload() }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .avoidBottomGameInfo()
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("ギルド情報を読み込み中…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 44))
                .foregroundColor(.primary)
            Text("ギルド情報の取得に失敗しました")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("再試行") {
                Task { await reload() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func loadOnce() async {
        if didLoadOnce { return }
        await loadData()
        didLoadOnce = true
    }

    private func loadData() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        do {
            async let summariesTask: Void = characterState.loadCharacterSummaries()
            async let allCharactersTask: Void = characterState.loadAllCharacters()
            _ = try await progressService.gameState.loadCurrentPlayer()
            try await summariesTask
            try await allCharactersTask
            maxCharacterSlots = AppConstants.Progress.defaultCharacterSlotCount
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func reload() async {
        await loadData()
    }
}

// MARK: - Action Row

private struct GuildActionLabel: View {
    let title: String
    let icon: String
    let tint: Color
    var badgeCount: Int?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24, height: 24)
                .foregroundStyle(tint)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            if let badgeCount, badgeCount > 0 {
                Text("(\(badgeCount))")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
        .frame(height: AppConstants.UI.listRowHeight)
    }
}

private struct GuildCharacterRow: View {
    let summary: CharacterViewState.CharacterSummary

    var body: some View {
        HStack(spacing: 12) {
            CharacterImageView(avatarIndex: summary.resolvedAvatarId, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.name)
                    .font(.headline)
                    .foregroundStyle(summary.isAlive ? .primary : .secondary)
                HStack(spacing: 8) {
                    Text("Lv.\(summary.level)")
                    Text(summary.raceName)
                    Text(summary.jobName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("HP")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(summary.currentHP)/\(summary.maxHP)")
                    .font(.caption)
                    .foregroundColor(summary.isAlive ? .primary : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Character Detail Loader

private struct LazyRuntimeCharacterDetailView: View {
    let characterId: UInt8
    let summary: CharacterViewState.CharacterSummary
    let progressService: ProgressService

    @State private var runtimeCharacter: RuntimeCharacter?
    @State private var errorMessage: String?
    @State private var isLoading = false

    private var characterService: CharacterProgressService { progressService.character }

    var body: some View {
        Group {
            if let runtimeCharacter {
                CharacterDetailContent(character: runtimeCharacter,
                                      onRename: { newName in
                                          try await renameCharacter(to: newName)
                                      },
                                      onAvatarChange: { identifier in
                                          try await changeAvatar(to: identifier)
                                      },
                                      onActionPreferencesChange: { preferences in
                                          try await updateActionPreferences(to: preferences)
                                      })
                    .navigationTitle(runtimeCharacter.name)
                    .navigationBarTitleDisplayMode(.inline)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    Button("再読み込み") { Task { await loadCharacter() } }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .navigationTitle(summary.name)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(summary.name)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task { await loadCharacter() }
    }

    @MainActor
    private func loadCharacter() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if let progress = try await characterService.character(withId: characterId) {
                runtimeCharacter = try await characterService.runtimeCharacter(from: progress)
            } else {
                throw RuntimeError.missingProgressData(reason: "Character not found")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func renameCharacter(to newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProgressError.invalidInput(description: "キャラクター名を入力してください")
        }
        if trimmed == runtimeCharacter?.name {
            return
        }
        let snapshot = try await characterService.updateCharacter(id: characterId) { snapshot in
            snapshot.displayName = trimmed
        }
        runtimeCharacter = try await characterService.runtimeCharacter(from: snapshot)
    }

    @MainActor
    private func changeAvatar(to avatarId: UInt16) async throws {
        if let current = runtimeCharacter, current.avatarId == avatarId {
            return
        }
        let snapshot = try await characterService.updateCharacter(id: characterId) { snapshot in
            snapshot.avatarId = avatarId
        }
        runtimeCharacter = try await characterService.runtimeCharacter(from: snapshot)
    }

    @MainActor
    private func updateActionPreferences(to newPreferences: CharacterSnapshot.ActionPreferences) async throws {
        let normalized = CharacterSnapshot.ActionPreferences.normalized(attack: newPreferences.attack,
                                                                        priestMagic: newPreferences.priestMagic,
                                                                        mageMagic: newPreferences.mageMagic,
                                                                        breath: newPreferences.breath)
        let snapshot = try await characterService.updateCharacter(id: characterId) { snapshot in
            snapshot.actionPreferences = normalized
        }
        runtimeCharacter = try await characterService.runtimeCharacter(from: snapshot)
    }
}

// MARK: - Character Creation

private struct CharacterCreationView: View {
    let progressService: ProgressService
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var races: [RaceDefinition] = []
    @State private var jobs: [JobDefinition] = []
    @State private var selectedRace: RaceDefinition?
    @State private var selectedJob: JobDefinition?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var loadErrorMessage: String?
    @State private var creationErrorMessage: String?

    private let masterData = MasterDataRuntimeService.shared
    private var characterService: CharacterProgressService { progressService.character }
    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage = loadErrorMessage, races.isEmpty && jobs.isEmpty {
                    ErrorView(message: errorMessage) {
                        Task { await loadMasterData() }
                    }
                } else if isLoading && races.isEmpty && jobs.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            nameSection
                            raceSection
                            jobSection
                            previewSection
                            createButton
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 24)
                    }
                    .avoidBottomGameInfo()
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("キャラクター作成")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadMasterData() }
            .alert("エラー", isPresented: Binding(get: { creationErrorMessage != nil }, set: { value in
                if !value { creationErrorMessage = nil }
            })) {
                Button("OK", role: .cancel) { creationErrorMessage = nil }
            } message: {
                Text(creationErrorMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        creationCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("キャラクター名")
                    .font(.headline)
                TextField("名前を入力してください", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
            }
        }
    }

    private var genderSections: [(gender: String, races: [RaceDefinition])] {
        var buckets: [String: [RaceDefinition]] = [:]
        var raceOrder: [UInt8: Int] = [:]
        for (index, race) in races.enumerated() {
            raceOrder[race.id] = index
            buckets[race.gender, default: []].append(race)
        }
        let orderedGenders: [String] = ["male", "female", "genderless"]
        return orderedGenders.compactMap { gender -> (gender: String, races: [RaceDefinition])? in
            guard let genderRaces = buckets[gender] else { return nil }
            let sorted = genderRaces.sorted { lhs, rhs in
                guard let lhsIndex = raceOrder[lhs.id], let rhsIndex = raceOrder[rhs.id] else {
                    return lhs.id < rhs.id
                }
                return lhsIndex < rhsIndex
            }
            return (gender: gender, races: sorted)
        }
    }

    private var raceSection: some View {
        creationCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("種族選択")
                        .font(.headline)
                    Spacer()
                    if selectedRace != nil {
                        Button("変更") { selectedRace = nil }
                            .font(.subheadline)
                    }
                }

                if let currentRace = selectedRace {
                    selectedRaceSummary(currentRace)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(genderSections, id: \.gender) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(genderTitle(for: section.gender))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 12) {
                                    ForEach(section.races, id: \.id) { race in
                                        raceTile(for: race)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var jobSection: some View {
        creationCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("職業選択")
                        .font(.headline)
                    Spacer()
                    if selectedJob != nil {
                        Button("変更") { selectedJob = nil }
                            .font(.subheadline)
                    }
                }

                if let currentJob = selectedJob {
                    selectedJobSummary(currentJob)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                        ForEach(jobs, id: \.id) { job in
                            jobTile(for: job)
                        }
                    }
                }
            }
        }
    }

    private var previewSection: some View {
        Group {
            if let race = selectedRace, let job = selectedJob {
                creationCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("キャラクタープレビュー")
                            .font(.headline)

                        HStack(alignment: .top, spacing: 16) {
                            CharacterImageView(
                                avatarIndex: UInt16(race.genderCode) * 100 + UInt16(job.id),
                                size: 80
                            )
                            VStack(alignment: .leading, spacing: 8) {
                                Text(name.trimmingCharacters(in: .whitespaces).isEmpty ? "名前未設定" : name)
                                    .font(.title2)
                                    .foregroundStyle(name.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .primary)
                                Text("\(race.name) / \(job.name)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("基本能力値")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            StatGrid(rows: previewStats(for: race))
                        }

                        if !jobCoefficients(for: job).isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("職業補正")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                StatGrid(rows: jobCoefficients(for: job))
                            }
                        }

                        if !job.learnedSkills.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("習得スキル")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("初期習得: \(job.learnedSkills.filter { $0.orderIndex == 0 }.count)件 / レベル習得: \(job.learnedSkills.filter { $0.orderIndex > 0 }.count)件")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var createButton: some View {
        Button {
            Task { await createCharacter() }
        } label: {
            if isSaving {
                ProgressView()
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
            } else {
                Text("キャラクターを登録する")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canCreate || isSaving)
    }

    // MARK: - Helpers

    private var canCreate: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && selectedRace != nil && selectedJob != nil
    }

    private func genderTitle(for gender: String) -> String {
        switch gender {
        case "male": return "男性種族"
        case "female": return "女性種族"
        case "genderless": return "性別不明"
        default: return gender
        }
    }

    private func raceTile(for race: RaceDefinition) -> some View {
        VStack(spacing: 6) {
            CharacterImageView(avatarIndex: UInt16(race.id), size: 48)
            Text(race.name)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .frame(height: 88)
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(selectedRace?.id == race.id ? Color.accentColor.opacity(0.2) : Color(.systemGray6))
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture { selectedRace = race }
        .contextMenu {
            Button {
                selectedRace = race
            } label: {
                Label("この種族を選択", systemImage: "checkmark.circle")
            }
        } preview: {
            RaceDetailPreview(race: race)
        }
    }

    private func jobTile(for job: JobDefinition) -> some View {
        VStack(spacing: 8) {
            CharacterImageView(avatarIndex: UInt16(selectedRace?.genderCode ?? 3) * 100 + UInt16(job.id), size: 48)
            Text(job.name)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .frame(height: 96)
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(selectedJob?.id == job.id ? Color.accentColor.opacity(0.2) : Color(.systemGray6))
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture { selectedJob = job }
        .contextMenu {
            Button {
                selectedJob = job
            } label: {
                Label("この職業を選択", systemImage: "checkmark.circle")
            }
        } preview: {
            JobDetailPreview(job: job, genderCode: selectedRace?.genderCode)
        }
    }

    private func selectedRaceSummary(_ race: RaceDefinition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                CharacterImageView(avatarIndex: UInt16(race.id), size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(race.name)
                        .font(.headline)
                    Text(raceDescription(race))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            StatGrid(rows: previewStats(for: race))
        }
    }

    private func selectedJobSummary(_ job: JobDefinition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                CharacterImageView(avatarIndex: UInt16(selectedRace?.genderCode ?? 3) * 100 + UInt16(job.id), size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.name)
                        .font(.headline)
                    Text(jobDescription(job))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !jobCoefficients(for: job).isEmpty {
                Divider()
                StatGrid(rows: jobCoefficients(for: job))
            }
        }
    }

    private func previewStats(for race: RaceDefinition) -> [StatRow] {
        race.baseStats.map { base in
            StatRow(label: statLabel(for: base.stat), value: "\(base.value)")
        }
    }

    private func jobCoefficients(for job: JobDefinition) -> [StatRow] {
        job.combatCoefficients.map { coeff in
            let formatted = String(format: "%.2fx", coeff.value)
            return StatRow(label: statLabel(for: coeff.stat), value: formatted)
        }
    }

    private func raceDescription(_ race: RaceDefinition) -> String {
        if let stat = race.baseStats.max(by: { $0.value < $1.value }) {
            return "特徴: \(statLabel(for: stat.stat))"
        }
        return "固有の特徴を持つ種族"
    }

    private func jobDescription(_ job: JobDefinition) -> String {
        if let tendency = job.growthTendency, !tendency.isEmpty {
            return tendency
        }
        return job.category
    }

    private func creationCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(18)
    }

    @MainActor
    private func loadMasterData() async {
        if isLoading { return }
        isLoading = true
        loadErrorMessage = nil
        do {
            async let racesTask = masterData.getAllRaces()
            async let jobsTask = masterData.getAllJobs()
            let (raceResults, jobResults) = try await (racesTask, jobsTask)
            races = raceResults
            jobs = jobResults
        } catch {
            loadErrorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func createCharacter() async {
        guard !isSaving, let race = selectedRace, let job = selectedJob else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            creationErrorMessage = "キャラクター名を入力してください"
            return
        }

        isSaving = true
        do {
            let request = CharacterProgressService.CharacterCreationRequest(
                displayName: trimmed,
                raceId: UInt8(race.id),
                jobId: UInt8(job.id)
            )
            _ = try await characterService.createCharacter(request)
            onComplete()
            dismiss()
        } catch {
            creationErrorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

private struct StatRow: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let value: String
}

private struct StatGrid: View {
    let rows: [StatRow]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(rows) { row in
                HStack {
                    Text(row.label)
                        .font(.caption)
                    Spacer()
                    Text(row.value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct RaceDetailPreview: View {
    let race: RaceDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if !race.baseStats.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("基礎能力")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(race.baseStats, id: \.stat) { stat in
                            DetailStatItem(label: statLabel(for: stat.stat), value: String(stat.value))
                        }
                    }
                }
            }

            if let description = descriptionText {
                VStack(alignment: .leading, spacing: 6) {
                    Text("説明")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 360, maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var descriptionText: String? {
        let trimmed = race.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            CharacterImageView(avatarIndex: UInt16(race.id), size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(race.name)
                    .font(.headline)
                    .fontWeight(.bold)
                Text("性別: \(localizedGender(race.gender))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let category = nonEmptyCategory {
                    Text("カテゴリ: \(category)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func localizedGender(_ gender: String) -> String {
        switch gender {
        case "male": return "男性"
        case "female": return "女性"
        case "genderless": return "性別不明"
        default: return gender
        }
    }

    private var nonEmptyCategory: String? {
        let trimmed = race.category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct JobDetailPreview: View {
    let job: JobDefinition
    let genderCode: UInt8?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if !combatCoefficientItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("戦闘補正")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(Array(combatCoefficientItems.enumerated()), id: \.offset) { _, item in
                            DetailStatItem(label: item.label, value: String(format: "%.2fx", item.value))
                        }
                    }
                }
            }

            if !sortedSkills.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("習得スキル")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(sortedSkills, id: \.self) { skill in
                            DetailMetadataRow(label: orderLabel(for: skill.orderIndex), value: String(skill.skillId))
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 360, maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var sortedSkills: [JobDefinition.LearnedSkill] {
        job.learnedSkills.sorted { lhs, rhs in
            if lhs.orderIndex == rhs.orderIndex {
                return lhs.skillId < rhs.skillId
            }
            return lhs.orderIndex < rhs.orderIndex
        }
    }

    private var combatCoefficientItems: [(label: String, value: Double)] {
        let lookup: [String: Double] = Dictionary(uniqueKeysWithValues: job.combatCoefficients.map { ($0.stat.lowercased(), $0.value) })
        return Self.combatStatDisplayOrder.map { key in
            let value = lookup[key] ?? 1.0
            return (label: statLabel(for: key), value: value)
        }
    }

    private static let combatStatDisplayOrder: [String] = [
        "maxhp",
        "physicalattack",
        "magicalattack",
        "physicaldefense",
        "magicaldefense",
        "hitrate",
        "evasionrate",
        "criticalrate",
        "attackcount",
        "magicalhealing",
        "trapremoval",
        "additionaldamage",
        "breathdamage"
    ]

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            CharacterImageView(avatarIndex: UInt16(genderCode ?? 3) * 100 + UInt16(job.id), size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(job.name)
                    .font(.headline)
                    .fontWeight(.bold)
                if let tendency = nonEmptyTendency {
                    Text(tendency)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func orderLabel(for index: Int) -> String {
        index == 0 ? "初期" : "Lv.\(index)"
    }

    private var nonEmptyTendency: String? {
        guard let tendency = job.growthTendency?.trimmingCharacters(in: .whitespacesAndNewlines), !tendency.isEmpty else {
            return nil
        }
        return tendency
    }
}

private struct DetailStatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DetailMetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        }
    }
}

private func statLabel(for key: String) -> String {
    switch key.lowercased() {
    case "strength": return "力"
    case "wisdom": return "知恵"
    case "spirit": return "精神"
    case "vitality": return "体力"
    case "agility": return "敏捷"
    case "luck": return "運"
    case "maxhp", "hp": return "最大HP"
    case "physicalattack": return "物理攻撃"
    case "magicalattack": return "魔法攻撃"
    case "physicaldefense": return "物理防御"
    case "magicaldefense": return "魔法防御"
    case "hitrate": return "命中"
    case "evasionrate": return "回避"
    case "criticalrate": return "クリティカル"
    case "attackcount": return "攻撃回数"
    case "magicalhealing": return "魔法回復"
    case "trapremoval": return "罠解除"
    case "additionaldamage": return "追加ダメージ"
    case "breathdamage": return "ブレスダメージ"
    default: return key
    }
}
// MARK: - Character Revive

private struct CharacterReviveView: View {
    let progressService: ProgressService
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var deadCharacters: [RuntimeCharacter] = []
    @State private var isLoading = false
    @State private var isProcessing = false
    @State private var errorMessage: String?

    private var characterService: CharacterProgressService { progressService.character }

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        Button("再読み込み") {
                            Task { await loadDeadCharacters() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if deadCharacters.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.primary)
                        Text("蘇生が必要なキャラクターはいません")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(deadCharacters, id: \.id) { character in
                            HStack {
                                CharacterImageView(avatarIndex: character.resolvedAvatarId, size: 44)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(character.name)
                                        .font(.headline)
                                    Text("Lv.\(character.level) / \(character.jobName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("HP: 0/\(character.maxHP)")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                                Spacer()
                                Button("蘇生") {
                                    Task { await reviveCharacter(character) }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(isProcessing)
                            }
                        }
                    }
                    .avoidBottomGameInfo()
                }
            }
            .navigationTitle("キャラクター蘇生")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadDeadCharacters() }
        }
    }

    @MainActor
    private func loadDeadCharacters() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let progresses = try await characterService.allCharacters()
            let deceased = progresses.filter { $0.hitPoints.current <= 0 }
            var runtime: [RuntimeCharacter] = []
            for progress in deceased {
                let character = try await characterService.runtimeCharacter(from: progress)
                runtime.append(character)
            }
            deadCharacters = runtime.sorted { $0.id < $1.id }
        } catch {
            errorMessage = error.localizedDescription
            deadCharacters = []
        }
    }

    @MainActor
    private func reviveCharacter(_ character: RuntimeCharacter) async {
        if isProcessing { return }
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }
        do {
            _ = try await characterService.updateCharacter(id: character.id) { progress in
                var hitPoints = progress.hitPoints
                hitPoints.current = max(1, hitPoints.maximum / 2)
                progress.hitPoints = hitPoints
            }
            await loadDeadCharacters()
            onComplete()
            if deadCharacters.isEmpty {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Job Change

private struct CharacterJobChangeView: View {
    let progressService: ProgressService
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var characters: [RuntimeCharacter] = []
    @State private var jobs: [JobDefinition] = []
    @State private var selectedCharacterId: UInt8?
    @State private var selectedJobIndex: UInt8?
    @State private var isLoading = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var didLoadOnce = false

    private let masterData = MasterDataRuntimeService.shared
    private let genderOrder = ["male", "female", "genderless"]

    private var characterService: CharacterProgressService { progressService.character }

    var body: some View {
        NavigationStack {
            Form {
                Section("キャラクター") {
                    if characters.isEmpty {
                        ProgressView()
                    } else {
                        Picker("対象", selection: $selectedCharacterId) {
                            Text("未選択").tag(UInt8?.none)
                            ForEach(characters, id: \.id) { character in
                                Text("\(character.name) (Lv.\(character.level))").tag(UInt8?.some(character.id))
                            }
                        }
                    }
                }

                Section("職業") {
                    if jobs.isEmpty {
                        ProgressView()
                    } else {
                        Picker("新しい職業", selection: $selectedJobIndex) {
                            Text("未選択").tag(UInt8?.none)
                            ForEach(jobs) { job in
                                Text(job.name).tag(UInt8?.some(UInt8(job.id)))
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.primary)
                            .font(.caption)
                    }
                }

                Section {
                    Button("転職する") {
                        Task { await changeJob() }
                    }
                    .disabled(!canSubmit || isProcessing)
                }
            }
            .avoidBottomGameInfo()
            .navigationTitle("キャラクター転職")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { Task { await loadOnce() } }
        }
    }

    private var canSubmit: Bool {
        selectedCharacterId != nil && selectedJobIndex != nil
    }

    @MainActor
    private func loadOnce() async {
        if didLoadOnce { return }
        await loadData()
        didLoadOnce = true
    }

    private func loadData() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let progresses = try await characterService.allCharacters()
            var runtime: [RuntimeCharacter] = []
            for progress in progresses {
                let character = try await characterService.runtimeCharacter(from: progress)
                runtime.append(character)
            }
            characters = runtime.sorted { $0.id < $1.id }
            jobs = try await masterData.getAllJobs().sorted { $0.name < $1.name }
            if selectedCharacterId == nil {
                selectedCharacterId = characters.first?.id
            }
            if selectedJobIndex == nil {
                selectedJobIndex = jobs.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
            characters = []
            jobs = []
        }
    }

    @MainActor
    private func changeJob() async {
        guard let characterId = selectedCharacterId, let jobIndex = selectedJobIndex else { return }
        if isProcessing { return }
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }
        do {
            let updated = try await characterService.updateCharacter(id: characterId) { progress in
                progress.jobId = jobIndex
                if !progress.jobHistory.contains(where: { $0.jobId == jobIndex }) {
                    let now = Date()
                    progress.jobHistory.append(
                        .init(id: UUID(),
                              jobId: jobIndex,
                              achievedAt: now,
                              createdAt: now,
                              updatedAt: now)
                    )
                }
            }
            let runtime = try await characterService.runtimeCharacter(from: updated)
            if let index = characters.firstIndex(where: { $0.id == runtime.id }) {
                characters[index] = runtime
            }
            onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Battle Stats

private struct BattleStatsView: View {
    let characters: [RuntimeCharacter]

    var body: some View {
        List {
            if characters.isEmpty {
                Text("キャラクターがいません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(characters, id: \.id) { character in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(character.name)
                            .font(.headline)
                        HStack(spacing: 12) {
                            statItem(label: "HP", value: character.combatStats.maxHP)
                            statItem(label: "物攻", value: character.combatStats.physicalAttack)
                            statItem(label: "魔攻", value: character.combatStats.magicalAttack)
                            statItem(label: "物防", value: character.combatStats.physicalDefense)
                            statItem(label: "魔防", value: character.combatStats.magicalDefense)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .avoidBottomGameInfo()
        .navigationTitle("戦闘能力一覧")
    }

    private func statItem(label: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Text("\(value)")
        }
    }
}
