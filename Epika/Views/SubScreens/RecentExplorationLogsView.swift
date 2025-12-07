import SwiftUI
import SwiftData

extension ExplorationSnapshot: Identifiable {}
extension ExplorationSnapshot.EncounterLog: Identifiable {}
extension CharacterSnapshot: Identifiable {}

private struct CharacterIconInfo: Hashable {
    let avatarIndex: UInt16
    let displayName: String
}

struct RecentExplorationLogsView: View {
    let party: RuntimeParty
    let runs: [ExplorationSnapshot]

    @State private var showingInProgressDetail = false
    @State private var activeRunForProgress: ExplorationSnapshot?
    @State private var selectedRunForSummary: ExplorationSnapshot?
    @State private var selectedRunForResultSummary: ExplorationSnapshot?

    private let maxDisplayCount = 2

    private var partyRuns: [ExplorationSnapshot] {
        runs
            .filter { $0.party.partyId == party.id }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(maxDisplayCount)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            if partyRuns.isEmpty {
                emptyState
            } else {
                ForEach(Array(partyRuns.enumerated()), id: \.element.id) { index, run in
                    if index > 0 {
                        Divider()
                            .padding(.horizontal, 0)
                    }

                    ExplorationLogRowView(
                        header: formatSummaryHeader(run.summary),
                        content: run.summary.body,
                        onShowDetail: {
                            handleDetailButton(for: run)
                        },
                        onRowTap: {
                            handleRowTap(for: run)
                        }
                    )
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingInProgressDetail, onDismiss: {
            activeRunForProgress = nil
        }) {
            InProgressStatusView(
                dungeonName: activeRunForProgress?.displayDungeonName ?? "",
                statusText: progressText(for: activeRunForProgress)
            )
        }
        .sheet(item: $selectedRunForSummary) { snapshot in
            ExplorationRunSummaryView(
                snapshot: snapshot,
                party: party
            )
        }
        .sheet(item: $selectedRunForResultSummary) { snapshot in
            ExplorationRunResultSummaryView(snapshot: snapshot,
                                             party: party)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("まだ探索ログがありません")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("出撃ボタンを押して探索を開始してください")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func progressText(for run: ExplorationSnapshot?) -> String {
        guard let run else {
            return "探索状況を取得できませんでした"
        }
        let referenceDate: Date
        let label: String
        switch run.summary.timing {
        case .expectedReturn(let expected):
            referenceDate = expected
            label = "帰還予定"
        case .actualReturn(let actual):
            referenceDate = actual
            label = "帰還日時"
        }
        let timestamp = DateFormatters.timestamp.string(from: referenceDate)
        return "探索進行中...（\(run.activeFloorNumber)F到達・\(label) \(timestamp)）"
    }

    private func handleDetailButton(for run: ExplorationSnapshot) {
        if run.status == .running {
            activeRunForProgress = run
            showingInProgressDetail = true
            return
        }
        selectedRunForSummary = run
    }

    private func handleRowTap(for run: ExplorationSnapshot) {
        if run.status == .running {
            activeRunForProgress = run
            showingInProgressDetail = true
            return
        }
        selectedRunForResultSummary = run
    }

}

private struct ExplorationLogRowView: View {
    let header: String
    let content: String
    let onShowDetail: () -> Void
    let onRowTap: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                if !header.isEmpty {
                    Text(header)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Text(content)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onRowTap)

            Spacer()

            Button(action: onShowDetail) {
                Image(systemName: "info.circle")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }
}

private struct InProgressStatusView: View {
    let dungeonName: String
    let statusText: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("探索進行中")
                    .font(.title2)
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: 8) {
                    Text("迷宮")
                        .font(.headline)
                    Text(dungeonName.isEmpty ? "不明な迷宮" : dungeonName)
                        .font(.body)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("現在の状況")
                        .font(.headline)
                    Text(statusText)
                        .font(.body)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("探索状況")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

fileprivate func formatSummaryHeader(_ summary: ExplorationSnapshot.Summary) -> String {
    let date: Date
    let label: String
    switch summary.timing {
    case .expectedReturn(let expected):
        date = expected
        label = "帰還予定"
    case .actualReturn(let actual):
        date = actual
        label = "帰還日時"
    }
    let timestamp = DateFormatters.short.string(from: date)
    return "[\(summary.floorNumber)F] \(label) \(timestamp)"
}

private struct ExplorationRunSummaryView: View {
    let snapshot: ExplorationSnapshot
    let party: RuntimeParty

    @Environment(\.dismiss) private var dismiss
    @State private var selectedEncounter: ExplorationSnapshot.EncounterLog?
    @State private var showingResultSummary = false

    private var eventsByFloor: [(floor: Int, events: [ExplorationSnapshot.EncounterLog])] {
        let grouped = Dictionary(grouping: snapshot.encounterLogs) { $0.floorNumber }
        return grouped.keys.sorted().map { floor in
            let events = (grouped[floor] ?? []).sorted { lhs, rhs in
                lhs.eventIndex < rhs.eventIndex
            }
            return (floor, events)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                explorationLogSections
            }
            .avoidBottomGameInfo()
            .navigationTitle("冒険の記録")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedEncounter) { encounter in
                EncounterDetailView(snapshot: snapshot,
                                    party: party,
                                    encounter: encounter)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(isPresented: $showingResultSummary) {
                ExplorationRunResultSummaryView(snapshot: snapshot,
                                                 party: party)
            }
        }
    }

    private var explorationLogSections: some View {
        Group {
            if snapshot.encounterLogs.isEmpty {
                Section("探索ログ") {
                    VStack(spacing: 12) {
                        Text("詳細ログがありません")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("この探索ではイベント情報が記録されていません")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Text("Run ID: \(snapshot.id.uuidString)")
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                finalSummaryRow
            } else {
                ForEach(eventsByFloor, id: \.floor) { floorData in
                    Section("\(floorData.floor)F") {
                        ForEach(floorData.events) { encounter in
                            Button {
                                selectedEncounter = encounter
                            } label: {
                                SimplifiedEventSummaryRowView(
                                    encounter: encounter,
                                    runStatus: snapshot.status
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                finalSummaryRow
            }
        }
    }

    @ViewBuilder
    private var finalSummaryRow: some View {
        if snapshot.status != .running {
            Button {
                showingResultSummary = true
            } label: {
                FinalExplorationSummaryRowView(summary: snapshot.summary)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct FinalExplorationSummaryRowView: View {
    let summary: ExplorationSnapshot.Summary

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatSummaryHeader(summary))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Text(summary.body)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ExplorationRunResultSummaryView: View {
    let snapshot: ExplorationSnapshot
    let party: RuntimeParty

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(snapshot.displayDungeonName)：\(ExplorationSnapshot.resultMessage(for: snapshot.status))")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let returnInfo {
                        Text("\(returnInfo.label)：\(returnInfo.value)")
                    }

                    Text("最終到達階層：\(snapshot.summary.floorNumber)F")

                    if let experience = snapshot.rewards["経験値"], experience > 0 {
                        Text("獲得経験値：\(formatNumber(experience))")
                    }

                    if let gold = snapshot.rewards["ゴールド"], gold > 0 {
                        Text("獲得ゴールド：\(formatNumber(gold))")
                    }

                    if !itemRows.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("入手アイテム：")
                            ForEach(itemRows, id: \.name) { row in
                                Text("・\(row.name) x\(row.count)")
                            }
                        }
                    }

                    Text("探索開始：\(DateFormatters.timestamp.string(from: snapshot.startedAt))")

                    if let actual = actualReturnDate {
                        Text("探索終了：\(DateFormatters.timestamp.string(from: actual))")
                        Text("所要時間：\(durationString(from: snapshot.startedAt, to: actual))")
                    }

                    Text("パーティ人数：\(party.memberIds.count)人")

                    Text("Run ID：\(snapshot.id.uuidString)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .navigationTitle("探索サマリー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private var returnInfo: (label: String, value: String)? {
        switch snapshot.summary.timing {
        case .expectedReturn(let expected):
            return ("帰還予定", DateFormatters.timestamp.string(from: expected))
        case .actualReturn(let actual):
            return ("帰還日時", DateFormatters.timestamp.string(from: actual))
        }
    }

    private var actualReturnDate: Date? {
        switch snapshot.summary.timing {
        case .expectedReturn:
            return nil
        case .actualReturn(let date):
            return date
        }
    }

    private var itemRows: [(name: String, count: String)] {
        snapshot.rewards
            .filter { key, _ in key != "経験値" && key != "ゴールド" }
            .sorted { lhs, rhs in lhs.key.localizedCompare(rhs.key) == .orderedAscending }
            .map { ($0.key, formatNumber($0.value)) }
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.groupingSeparator = ","
        return formatter
    }()

    private func durationString(from start: Date, to end: Date) -> String {
        let interval = max(0, Int(end.timeIntervalSince(start)))
        let hours = interval / 3600
        let minutes = (interval % 3600) / 60
        let seconds = interval % 60
        if hours > 0 {
            return String(format: "%d時間 %d分 %d秒", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%d分 %d秒", minutes, seconds)
        } else {
            return String(format: "%d秒", seconds)
        }
    }

    private func formatNumber(_ value: Int) -> String {
        Self.numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
private struct SimplifiedEventSummaryRowView: View {
    let encounter: ExplorationSnapshot.EncounterLog
    let runStatus: ExplorationSnapshot.Status

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                if let detail = subtitleText {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let result = resultText {
                Text(result)
                    .font(.caption)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var titleText: String {
        return ExplorationSnapshot.eventTitle(for: encounter, status: runStatus)
    }

    private var subtitleText: String? {
        if let drops = encounter.context["drops"], !drops.isEmpty {
            return drops
        }
        if let exp = encounter.context["exp"], !exp.isEmpty {
            return "経験値 \(exp)"
        }
        if let gold = encounter.context["gold"], !gold.isEmpty {
            return "GP \(gold)"
        }
        if let effects = encounter.context["effects"], !effects.isEmpty {
            return effects
        }
        return nil
    }

    private var resultText: String? {
        if let raw = encounter.context["result"], !raw.isEmpty {
            return ExplorationSnapshot.localizedCombatResult(raw)
        }
        return nil
    }
}

private struct EncounterDetailView: View {
    let snapshot: ExplorationSnapshot
    let party: RuntimeParty
    let encounter: ExplorationSnapshot.EncounterLog

    @Environment(\.modelContext) private var modelContext

    @State private var battleLogEntries: [BattleLogEntry] = []
    @State private var isLoadingBattleLog = false
    @State private var battleLogError: String?
    @State private var actorIdentifierToMemberId: [String: UInt8] = [:]
    @State private var actorIcons: [String: CharacterIconInfo] = [:]

    var body: some View {
        NavigationStack {
            List {
                battleSection
            }
            .avoidBottomGameInfo()
            .navigationTitle(encounter.kind == .enemyEncounter ? "戦いの記録" : "\(encounter.floorNumber)F・イベント")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadBattleLogIfNeeded()
            }
        }
    }

    private var battleSection: some View {
        Group {
            if encounter.combatSummary == nil {
                Section("戦闘") {
                    Text("戦闘は発生していません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if isLoadingBattleLog {
                Section("戦闘") {
                    ProgressView("戦闘ログを読み込み中…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let battleLogError {
                Section("戦闘") {
                    Text(battleLogError)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            } else if battleLogEntries.isEmpty {
                Section("戦闘") {
                    Text("戦闘ログは記録されていません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                let summaries = turnSummaries
                if summaries.isEmpty {
                    Section("戦闘") {
                        ForEach(battleLogEntries.filter(shouldDisplayAction), id: \.self) { entry in
                            BattleActionRowView(entry: entry,
                                                actor: nil,
                                                iconInfo: iconInfo(for: entry.actorId))
                                .padding(.vertical, 4)
                        }
                    }
                } else {
                    ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                        BattleTurnView(summary: summary,
                                       isFirst: index == 0,
                                       partyName: party.name,
                                       iconProvider: { participant in
                                           if let memberId = participant?.partyMemberId,
                                              let info = iconInfo(forMember: memberId) {
                                                return info
                                            }
                                           return iconInfo(for: participant?.id)
                                       })
                    }
                }
            }
        }
    }

    private var turnSummaries: [TurnSummary] {
        buildTurnSummaries()
    }

    private func buildTurnSummaries() -> [TurnSummary] {
        guard encounter.combatSummary != nil else { return [] }
        var states: [String: ParticipantState] = [:]
        var grouped: [Int: [BattleLogEntry]] = [:]

        for entry in battleLogEntries {
            if entry.turn == 0,
               let state = makeParticipantState(from: entry) {
                states[state.id] = state
                continue
            }
            grouped[entry.turn, default: []].append(entry)
        }

        guard !states.isEmpty else { return [] }

        var result: [TurnSummary] = []
        var stateMap = states
        let sortedTurns = grouped.keys.sorted().filter { $0 > 0 }

        for turn in sortedTurns {
            let partyStates = stateMap.values
                .filter { $0.role == .player }
                .sorted { $0.order < $1.order }
            let enemyStates = stateMap.values
                .filter { $0.role == .enemy }
                .sorted { $0.order < $1.order }

            let actions = (grouped[turn] ?? []).filter(shouldDisplayAction)
            let participantsById = stateMap
            result.append(TurnSummary(id: turn,
                                      turn: turn,
                                      party: partyStates,
                                      enemies: enemyStates,
                                      participants: participantsById,
                                      actions: actions))

            for entry in grouped[turn] ?? [] {
                if let targetId = entry.targetId,
                   let hpString = entry.metadata["targetHP"],
                   let hp = Int(hpString),
                   var state = stateMap[targetId] {
                    state.currentHP = max(0, min(state.maxHP, hp))
                    stateMap[targetId] = state
                }
                if let actorId = entry.actorId,
                   let hpString = entry.metadata["actorHP"],
                   let hp = Int(hpString),
                   var state = stateMap[actorId] {
                    state.currentHP = max(0, min(state.maxHP, hp))
                    stateMap[actorId] = state
                }
            }
        }

        return result
    }

    private func makeParticipantState(from entry: BattleLogEntry) -> ParticipantState? {
        guard entry.metadata["category"] == "initialState" else { return nil }
        guard let rawId = entry.actorId ?? entry.metadata["identifier"],
              let roleValue = entry.metadata["role"],
              let current = entry.metadata["currentHP"].flatMap(Int.init),
              let max = entry.metadata["maxHP"].flatMap(Int.init),
              let order = entry.metadata["order"].flatMap(Int.init) else {
            return nil
        }

        let role: ParticipantState.Role = roleValue == "player" ? .player : .enemy
        let name = entry.metadata["name"].flatMap { $0.isEmpty ? nil : $0 } ?? "-"
        let level = entry.metadata["level"].flatMap(Int.init)
        let job = entry.metadata["job"].flatMap { $0.isEmpty ? nil : $0 }
        let memberId = entry.metadata["partyMemberId"].flatMap(UInt8.init)

        return ParticipantState(id: rawId,
                                name: name,
                                currentHP: current,
                                maxHP: max,
                                level: level,
                                jobName: job,
                                partyMemberId: memberId,
                                role: role,
                                order: order)
    }

    private func shouldDisplayAction(_ entry: BattleLogEntry) -> Bool {
        if entry.metadata["category"] == "initialState" { return false }
        if entry.turn == 0 { return false }
        if entry.message.isEmpty { return false }
        if entry.type == .system {
            if entry.message.hasPrefix("---") { return false }
            if entry.message.contains("戦闘開始") { return false }
            if entry.message.hasSuffix("が現れた！") { return false }
        }
        return true
    }

    private struct TurnSummary: Identifiable {
        let id: Int
        let turn: Int
        let party: [ParticipantState]
        let enemies: [ParticipantState]
        let participants: [String: ParticipantState]
        let actions: [BattleLogEntry]
    }

    private struct ParticipantState: Identifiable {
        enum Role {
            case player
            case enemy
        }

        let id: String
        let name: String
        var currentHP: Int
        let maxHP: Int
        let level: Int?
        let jobName: String?
        let partyMemberId: UInt8?
        let role: Role
        let order: Int
    }

    private struct ParticipantSummaryView: View {
        let title: String?
        let participants: [ParticipantState]
        let role: ParticipantState.Role

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                }

                if participants.isEmpty {
                    Text("情報がありません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(participants) { participant in
                        HStack(spacing: 6) {
                            Text("(\(participant.currentHP)/\(participant.maxHP))")
                                .font(.caption)
                                .foregroundStyle(.primary)

                            Text(participant.name)
                                .font(.caption)
                                .foregroundStyle(.primary)

                            if role == .player, let job = participant.jobName, !job.isEmpty {
                                Text(job)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }

                            if let level = participant.level {
                                Text("Lv.\(level)")
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func loadBattleLogIfNeeded() async {
        guard encounter.combatSummary?.battleLogData != nil else { return }
        guard battleLogEntries.isEmpty, !isLoadingBattleLog, battleLogError == nil else { return }

        isLoadingBattleLog = true
        battleLogError = nil
        do {
            let archive = try fetchBattleLogArchive()

            // 名前マップを構築
            var allyNames: [UInt8: String] = [:]
            var enemyNames: [UInt16: String] = [:]
            var memberMap: [String: UInt8] = [:]
            var iconMap: [String: CharacterIconInfo] = [:]

            for participant in archive.playerSnapshots {
                if let memberId = participant.partyMemberId {
                    allyNames[memberId] = participant.name
                    memberMap[participant.actorId] = memberId
                }
                if let avatarIndex = participant.avatarIndex {
                    iconMap[participant.actorId] = CharacterIconInfo(avatarIndex: avatarIndex,
                                                                     displayName: participant.name)
                }
            }

            for participant in archive.enemySnapshots {
                // actorIdは "suffix*1000+index" 形式で保存されている
                if let actorIndex = UInt16(participant.actorId) {
                    enemyNames[actorIndex] = participant.name
                }
            }

            // BattleLogRenderer で変換
            battleLogEntries = BattleLogRenderer.render(
                battleLog: archive.battleLog,
                allyNames: allyNames,
                enemyNames: enemyNames
            )

            actorIdentifierToMemberId = memberMap
            actorIcons = iconMap
        } catch {
            battleLogError = error.localizedDescription
        }
        isLoadingBattleLog = false
    }

    private func fetchBattleLogArchive() throws -> BattleLogArchive {
        guard let data = encounter.combatSummary?.battleLogData else {
            throw EncounterDetailError.battleLogNotAvailable
        }
        return try JSONDecoder().decode(BattleLogArchive.self, from: data)
    }

    enum EncounterDetailError: LocalizedError {
        case battleLogNotAvailable
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .battleLogNotAvailable:
                return "戦闘ログを取得できませんでした"
            case .decodingFailed:
                return "戦闘ログのデコードに失敗しました"
            }
        }
    }

    private func iconInfo(for identifier: String?) -> CharacterIconInfo? {
        guard let identifier else { return nil }
        return actorIcons[identifier]
    }

    private func iconInfo(forMember memberId: UInt8?) -> CharacterIconInfo? {
        guard let memberId else { return nil }
        if let identifier = actorIdentifierToMemberId.first(where: { $0.value == memberId })?.key {
            return actorIcons[identifier]
        }
        return nil
    }

    private struct BattleTurnView: View {
        let summary: TurnSummary
        let isFirst: Bool
        let partyName: String
        let iconProvider: (ParticipantState?) -> CharacterIconInfo?

        var body: some View {
            Section {
                VStack(alignment: .leading, spacing: 0) {
                    ParticipantSummaryView(title: partyName,
                                           participants: summary.party,
                                           role: .player)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    if !summary.enemies.isEmpty {
                        Text("VS")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)

                        ParticipantSummaryView(title: nil,
                                               participants: summary.enemies,
                                               role: .enemy)
                            .padding(.horizontal, 16)
                    }

                    if !summary.actions.isEmpty {
                        Divider()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(summary.actions.enumerated()), id: \.element) { index, entry in
                                let participant = summary.participants[entry.actorId ?? ""]
                                BattleActionRowView(entry: entry,
                                                    actor: participant,
                                                    iconInfo: iconProvider(participant))
                                    .padding(.horizontal, 16)
                                if index < summary.actions.count - 1 {
                                    Divider()
                                        .padding(.leading, 83)
                                        .padding(.vertical, 4)
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
                .padding(.bottom, 8)
                .background(Color(uiColor: .systemBackground))
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(summary.turn)ターン目")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                }
                .padding(.top, isFirst ? 24 : 20)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
    }

    private struct BattleActionRowView: View {
        let entry: BattleLogEntry
        let actor: ParticipantState?
        let iconInfo: CharacterIconInfo?

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                BattleActorIcon(actor: actor, iconInfo: iconInfo)

                VStack(alignment: .leading, spacing: 4) {
                    if let name = actor?.name, !name.isEmpty {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let displayName = iconInfo?.displayName, !displayName.isEmpty {
                        Text(displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(entry.message)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    private struct BattleActorIcon: View {
        let actor: ParticipantState?
        let iconInfo: CharacterIconInfo?

        var body: some View {
            Group {
                if let iconInfo {
                    CharacterImageView(avatarIndex: iconInfo.avatarIndex, size: 55)
                } else if actor?.role == .enemy {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 55, height: 55)
                        .overlay(
                            Text("敵")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 55, height: 55)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                        )
                }
            }
        }
    }
}

private struct DateFormatters {
    static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    static let short: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "MM/dd HH:mm:ss"
        return formatter
    }()
}
