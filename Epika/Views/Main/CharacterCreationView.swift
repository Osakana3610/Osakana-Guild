import SwiftUI

struct CharacterCreationView: View {
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
    @State private var raceDetailToShow: RaceDefinition?
    @State private var jobDetailToShow: JobDefinition?

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
                            raceSection
                            jobSection
                            previewSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 24)
                    }
                    .background(Color(.systemGroupedBackground))
                    .avoidBottomGameInfo()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                Task { await createCharacter() }
                            } label: {
                                if isSaving {
                                    ProgressView()
                                } else {
                                    Text("求人")
                                }
                            }
                            .disabled(!canCreate || isSaving)
                        }
                    }
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
            .sheet(item: $raceDetailToShow) { race in
                RaceDetailSheet(race: race)
            }
            .sheet(item: $jobDetailToShow) { job in
                JobDetailSheet(job: job, genderCode: selectedRace?.genderCode)
            }
        }
    }

    // MARK: - Sections

    private var genderSections: [(gender: String, races: [RaceDefinition])] {
        var buckets: [UInt8: [RaceDefinition]] = [:]
        var raceOrder: [UInt8: Int] = [:]
        for (index, race) in races.enumerated() {
            raceOrder[race.id] = index
            buckets[race.genderCode, default: []].append(race)
        }
        // genderCode: 1=male, 2=female, 3=genderless
        let orderedGenderCodes: [UInt8] = [1, 2, 3]
        return orderedGenderCodes.compactMap { code -> (gender: String, races: [RaceDefinition])? in
            guard let genderRaces = buckets[code] else { return nil }
            let sorted = genderRaces.sorted { lhs, rhs in
                guard let lhsIndex = raceOrder[lhs.id], let rhsIndex = raceOrder[rhs.id] else {
                    return lhs.id < rhs.id
                }
                return lhsIndex < rhsIndex
            }
            let genderString: String
            switch code {
            case 1: genderString = "male"
            case 2: genderString = "female"
            default: genderString = "genderless"
            }
            return (gender: genderString, races: sorted)
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
                        ForEach(Array(genderSections.enumerated()), id: \.element.gender) { index, section in
                            if index > 0 {
                                Divider()
                            }
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
                                HStack {
                                    Text(name.trimmingCharacters(in: .whitespaces).isEmpty ? "名前未設定" : name)
                                        .font(.title2)
                                        .foregroundStyle(name.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .primary)
                                    Button {
                                        Task { @MainActor in
                                            do {
                                                let randomName = try await masterData.getRandomCharacterName(forGenderCode: race.genderCode)
                                                name = randomName
                                            } catch {
                                                creationErrorMessage = "名前の取得に失敗しました: \(error.localizedDescription)"
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                }
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

                        if !job.learnedSkillIds.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("習得スキル")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("習得スキル数: \(job.learnedSkillIds.count)件")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
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
        .onTapGesture {
            selectedRace = race
            name = ""
            Task { @MainActor in
                do {
                    let randomName = try await masterData.getRandomCharacterName(forGenderCode: race.genderCode)
                    name = randomName
                } catch {
                    creationErrorMessage = "名前の取得に失敗しました: \(error.localizedDescription)"
                }
            }
        }
        .contextMenu {
            Button {
                selectedRace = race
                name = ""
                Task { @MainActor in
                    do {
                        let randomName = try await masterData.getRandomCharacterName(forGenderCode: race.genderCode)
                        name = randomName
                    } catch {
                        creationErrorMessage = "名前の取得に失敗しました: \(error.localizedDescription)"
                    }
                }
            } label: {
                Label("この種族を選択", systemImage: "checkmark.circle")
            }
            Button {
                raceDetailToShow = race
            } label: {
                Label("詳細を見る", systemImage: "info.circle")
            }
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
            Button {
                jobDetailToShow = job
            } label: {
                Label("詳細を見る", systemImage: "info.circle")
            }
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
        BaseStat.allCases.map { stat in
            StatRow(label: stat.displayName, value: "\(stat.value(from: race.baseStats))")
        }
    }

    private func jobCoefficients(for job: JobDefinition) -> [StatRow] {
        CombatStat.allCases.map { stat in
            let formatted = String(format: "%.2fx", stat.value(from: job.combatCoefficients))
            return StatRow(label: stat.displayName, value: formatted)
        }
    }

    private func raceDescription(_ race: RaceDefinition) -> String {
        if let stat = BaseStat.allCases.max(by: { $0.value(from: race.baseStats) < $1.value(from: race.baseStats) }) {
            return "特徴: \(stat.displayName)"
        }
        return "固有の特徴を持つ種族"
    }

    private func jobDescription(_ job: JobDefinition) -> String {
        // 職業名だけで十分な説明となる
        job.name
    }

    private func creationCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            // マスター職業（ID 101-116）は転職画面でのみ表示
            jobs = jobResults.filter { $0.id < 101 || $0.id > 116 }
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
            creationErrorMessage = "キャラクター名が設定されていません。プレビューで再抽選してください。"
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

// MARK: - Supporting Views

struct StatRow: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let value: String
}

struct StatGrid: View {
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

struct RaceDetailSheet: View {
    let race: RaceDefinition

    @Environment(\.dismiss) private var dismiss
    @State private var skills: [UInt16: SkillDefinition] = [:]
    @State private var passiveSkillIds: [UInt16] = []
    @State private var skillUnlocks: [(level: Int, skillId: UInt16)] = []
    @State private var isLoading = true

    private let masterData = MasterDataRuntimeService.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        CharacterImageView(avatarIndex: UInt16(race.id), size: 80)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(race.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            Text(race.genderDisplayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("最大Lv: \(race.maxLevel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                if !race.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("説明") {
                        Text(race.description)
                            .font(.body)
                    }
                }

                Section("基礎能力") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(BaseStat.allCases, id: \.self) { stat in
                            VStack(spacing: 2) {
                                Text(stat.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("\(stat.value(from: race.baseStats))")
                                    .font(.body)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }

                if !passiveSkillIds.isEmpty {
                    Section("パッシブスキル") {
                        if isLoading {
                            ProgressView()
                        } else {
                            ForEach(passiveSkillIds, id: \.self) { skillId in
                                skillRow(skillId: skillId)
                            }
                        }
                    }
                }

                if !skillUnlocks.isEmpty {
                    Section("レベルで習得するスキル") {
                        if isLoading {
                            ProgressView()
                        } else {
                            ForEach(skillUnlocks, id: \.skillId) { unlock in
                                HStack {
                                    Text("Lv.\(unlock.level)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 50, alignment: .leading)
                                    skillRow(skillId: unlock.skillId)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(race.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await loadData() }
        }
    }

    @ViewBuilder
    private func skillRow(skillId: UInt16) -> some View {
        if let skill = skills[skillId] {
            Text(skill.name)
                .font(.body)
        } else {
            Text("スキルID: \(skillId)")
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func loadData() async {
        do {
            async let skillsTask = masterData.getAllSkills()
            async let passiveTask = masterData.getRacePassiveSkills()
            async let unlocksTask = masterData.getRaceSkillUnlocks()

            let (allSkills, allPassive, allUnlocks) = try await (skillsTask, passiveTask, unlocksTask)

            var skillMap: [UInt16: SkillDefinition] = [:]
            for skill in allSkills {
                skillMap[skill.id] = skill
            }
            skills = skillMap
            passiveSkillIds = allPassive[race.id] ?? []
            skillUnlocks = allUnlocks[race.id] ?? []
        } catch {
            // 取得失敗時は空のまま
        }
        isLoading = false
    }
}

struct JobDetailSheet: View {
    let job: JobDefinition
    let genderCode: UInt8?

    @Environment(\.dismiss) private var dismiss
    @State private var skills: [UInt16: SkillDefinition] = [:]
    @State private var skillUnlocks: [(level: Int, skillId: UInt16)] = []
    @State private var category: String?
    @State private var growthTendency: String?
    @State private var isLoading = true

    private let masterData = MasterDataRuntimeService.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        CharacterImageView(avatarIndex: UInt16(genderCode ?? 3) * 100 + UInt16(job.id), size: 80)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            if let category {
                                Text(localizedCategory(category))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                if let growthTendency, !growthTendency.isEmpty {
                    Section("成長傾向") {
                        Text(growthTendency)
                            .font(.body)
                    }
                }

                if !job.learnedSkillIds.isEmpty {
                    Section("パッシブスキル") {
                        if isLoading {
                            ProgressView()
                        } else {
                            ForEach(job.learnedSkillIds, id: \.self) { skillId in
                                skillRow(skillId: skillId)
                            }
                        }
                    }
                }

                if !skillUnlocks.isEmpty {
                    Section("レベルで習得するスキル") {
                        if isLoading {
                            ProgressView()
                        } else {
                            ForEach(skillUnlocks, id: \.skillId) { unlock in
                                HStack {
                                    Text("Lv.\(unlock.level)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 50, alignment: .leading)
                                    skillRow(skillId: unlock.skillId)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(job.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await loadData() }
        }
    }

    @ViewBuilder
    private func skillRow(skillId: UInt16) -> some View {
        if let skill = skills[skillId] {
            Text(skill.name)
                .font(.body)
        } else {
            Text("スキルID: \(skillId)")
                .foregroundStyle(.secondary)
        }
    }

    private func localizedCategory(_ category: String) -> String {
        switch category {
        case "frontline": return "前衛"
        case "midline": return "中衛"
        case "backline": return "後衛"
        default: return category
        }
    }

    @MainActor
    private func loadData() async {
        do {
            async let skillsTask = masterData.getAllSkills()
            async let unlocksTask = masterData.getJobSkillUnlocks()
            async let metadataTask = masterData.getJobMetadata()

            let (allSkills, allUnlocks, allMetadata) = try await (skillsTask, unlocksTask, metadataTask)

            var skillMap: [UInt16: SkillDefinition] = [:]
            for skill in allSkills {
                skillMap[skill.id] = skill
            }
            skills = skillMap
            skillUnlocks = allUnlocks[job.id] ?? []

            if let metadata = allMetadata[job.id] {
                category = metadata.category
                growthTendency = metadata.growthTendency
            }
        } catch {
            // 取得失敗時は空のまま
        }
        isLoading = false
    }
}
