// ==============================================================================
// EncounterDetailView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 探索中の特定の遭遇（戦闘・イベント）の詳細を表示
//
// 【View構成】
//   - 戦闘ログのターン別表示（BattleTurnView）
//   - ターンごとのHP変動の可視化
//   - アクターアイコンの表示（味方・敵）
//   - HP バーによる視覚的なダメージ表現
//
// 【使用箇所】
//   - ExplorationRunSummaryViewから遭遇ログをタップ時にナビゲーション
//
// ==============================================================================

import SwiftUI
import SwiftData

struct EncounterDetailView: View {
    let snapshot: ExplorationSnapshot
    let party: PartySnapshot
    let encounter: ExplorationSnapshot.EncounterLog

    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var appServices

    @State private var battleLogArchive: BattleLogArchive?
    @State private var renderedActions: [BattleLogRenderer.RenderedAction] = []
    @State private var isLoadingBattleLog = false
    @State private var battleLogError: String?
    @State private var actorIdentifierToMemberId: [String: UInt8] = [:]
    @State private var actorIcons: [String: CharacterIconInfo] = [:]

    var body: some View {
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
            } else {
                ForEach(turnSummaries, id: \.id) { summary in
                    BattleTurnView(summary: summary,
                                   isFirst: summary.turn == 1,
                                   partyName: party.name,
                                   iconProvider: { participant in
                                       guard let participant else { return nil }
                                       // プレイヤーはpartyMemberIdで、敵はactorId（id）で検索
                                       if let memberId = participant.partyMemberId {
                                           return iconInfo(forMember: memberId)
                                       }
                                       return iconInfo(for: participant.id)
                                   })
                }
            }
        }
    }

    private var turnSummaries: [TurnSummary] {
        buildTurnSummaries()
    }

    private func buildTurnSummaries() -> [TurnSummary] {
        guard let archive = battleLogArchive else { return [] }

        // actorIndex → actorId
        var indexToId: [UInt16: String] = [:]

        var states: [String: ParticipantState] = [:]

        for (index, participant) in archive.playerSnapshots.enumerated() {
            guard let memberId = participant.partyMemberId else { continue }
            let actorIndex = UInt16(memberId)
            let initialHP = Int(archive.battleLog.initialHP[actorIndex] ?? UInt32(participant.maxHP))
            states[participant.actorId] = ParticipantState(
                id: participant.actorId,
                name: participant.name,
                currentHP: initialHP,
                previousHP: initialHP,
                maxHP: participant.maxHP,
                level: participant.level,
                jobName: nil,
                partyMemberId: memberId,
                role: .player,
                order: index
            )
            indexToId[actorIndex] = participant.actorId
        }

        for (index, participant) in archive.enemySnapshots.enumerated() {
            guard let actorIndex = UInt16(participant.actorId) else { continue }
            let initialHP = Int(archive.battleLog.initialHP[actorIndex] ?? UInt32(participant.maxHP))
            states[participant.actorId] = ParticipantState(
                id: participant.actorId,
                name: participant.name,
                currentHP: initialHP,
                previousHP: initialHP,
                maxHP: participant.maxHP,
                level: participant.level,
                jobName: nil,
                partyMemberId: nil,
                role: .enemy,
                order: index
            )
            indexToId[actorIndex] = participant.actorId
        }

        var result: [TurnSummary] = []
        var stateMap = states
        var previousTurnStartStates = states

        let groupedByTurn = Dictionary(grouping: renderedActions, by: { $0.turn })
        let sortedTurns = groupedByTurn.keys.sorted().filter { $0 > 0 }

        for turn in sortedTurns {
            let turnStartStates = stateMap

            var summaryStates: [String: ParticipantState] = [:]
            for (id, var state) in turnStartStates {
                state.previousHP = previousTurnStartStates[id]?.currentHP ?? state.currentHP
                summaryStates[id] = state
            }

            let actions = (groupedByTurn[turn] ?? []).sorted { $0.id < $1.id }
            var groupedActions: [GroupedBattleAction] = []
            var groupId = 0

            for action in actions {
                let hpChanges = computeHPChanges(for: action,
                                                 stateMap: &stateMap,
                                                 indexToId: indexToId)
                let grouped = GroupedBattleAction(id: turn * 1000 + groupId,
                                                  primaryEntry: action.declaration,
                                                  results: action.results,
                                                  hpChanges: hpChanges)
                groupedActions.append(grouped)
                groupId += 1
            }

            let partyStates = summaryStates.values
                .filter { $0.role == .player }
                .sorted { $0.order < $1.order }
            let enemyStates = summaryStates.values
                .filter { $0.role == .enemy }
                .sorted { $0.order < $1.order }

            result.append(TurnSummary(id: turn,
                                      turn: turn,
                                      party: partyStates,
                                      enemies: enemyStates,
                                      participants: summaryStates,
                                      groupedActions: groupedActions))

            previousTurnStartStates = turnStartStates
        }

        return result
    }

    @MainActor
    private func loadBattleLogIfNeeded() async {
        guard encounter.combatSummary?.battleLogId != nil else { return }
        guard renderedActions.isEmpty, !isLoadingBattleLog, battleLogError == nil else { return }

        isLoadingBattleLog = true
        battleLogError = nil
        do {
            guard let archive = try fetchBattleLogArchive() else {
                battleLogError = EncounterDetailError.battleLogNotAvailable.errorDescription
                isLoadingBattleLog = false
                return
            }
            battleLogArchive = archive

            // 名前マップを構築
            var allyNames: [UInt8: String] = [:]
            var enemyNames: [UInt16: String] = [:]
            var memberMap: [String: UInt8] = [:]
            var iconMap: [String: CharacterIconInfo] = [:]
            var actorIdentifiers: [UInt16: String] = [:]

            for participant in archive.playerSnapshots {
                if let memberId = participant.partyMemberId {
                    allyNames[memberId] = participant.name
                    memberMap[participant.actorId] = memberId
                    actorIdentifiers[UInt16(memberId)] = participant.actorId
                }
                if let avatarIndex = participant.avatarIndex {
                    iconMap[participant.actorId] = CharacterIconInfo(avatarIndex: avatarIndex,
                                                                     enemyId: nil,
                                                                     displayName: participant.name)
                }
            }

            for participant in archive.enemySnapshots {
                // actorIdは "(arrayIndex+1)*1000+enemyMasterIndex" 形式で保存されている
                if let actorIndex = UInt16(participant.actorId) {
                    enemyNames[actorIndex] = participant.name
                    actorIdentifiers[actorIndex] = participant.actorId
                    let enemyId = actorIndex % 1000
                    iconMap[participant.actorId] = CharacterIconInfo(avatarIndex: nil,
                                                                     enemyId: enemyId,
                                                                     displayName: participant.name)
                }
            }

            // 呪文名マップを構築
            var spellNames: [UInt8: String] = [:]
            for spell in appServices.masterDataCache.allSpells {
                spellNames[spell.id] = spell.name
            }

            // 敵スキル名マップを構築
            var enemySkillNames: [UInt16: String] = [:]
            for skill in appServices.masterDataCache.allEnemySkills {
                enemySkillNames[skill.id] = skill.name
            }

            // 汎用スキル名マップ
            var skillNames: [UInt16: String] = [:]
            for skill in appServices.masterDataCache.allSkills {
                skillNames[skill.id] = skill.name
            }

            // BattleLogRenderer で変換
            renderedActions = BattleLogRenderer.render(
                battleLog: archive.battleLog,
                allyNames: allyNames,
                enemyNames: enemyNames,
                spellNames: spellNames,
                enemySkillNames: enemySkillNames,
                skillNames: skillNames,
                actorIdentifiers: actorIdentifiers
            )

            actorIdentifierToMemberId = memberMap
            actorIcons = iconMap
        } catch EncounterDetailError.unsupportedBattleLogVersion {
            battleLogError = EncounterDetailError.unsupportedBattleLogVersion.errorDescription
        } catch {
            battleLogError = EncounterDetailError.decodingFailed.errorDescription
        }
        isLoadingBattleLog = false
    }

    private func fetchBattleLogArchive() throws -> BattleLogArchive? {
        guard let id = encounter.combatSummary?.battleLogId,
              let record = modelContext.model(for: id) as? BattleLogRecord else {
            return nil
        }
        return try restoreBattleLogArchive(from: record)
    }

    private func restoreBattleLogArchive(from record: BattleLogRecord) throws -> BattleLogArchive? {
        // バイナリBLOBからデコード
        let decoded: ExplorationProgressService.DecodedBattleLogData
        do {
            decoded = try ExplorationProgressService.decodeBattleLogData(record.logData)
        } catch ExplorationProgressService.BattleLogArchiveDecodingError.unsupportedVersion {
            throw EncounterDetailError.unsupportedBattleLogVersion
        } catch {
            throw EncounterDetailError.decodingFailed
        }

        let battleLog = BattleLog(
            initialHP: decoded.initialHP,
            entries: decoded.entries,
            outcome: decoded.outcome,
            turns: decoded.turns
        )

        return BattleLogArchive(
            enemyId: record.enemyId,
            enemyName: record.enemyName,
            result: BattleService.BattleResult(rawValue: record.result) ?? .victory,
            turns: Int(record.turns),
            timestamp: record.timestamp,
            battleLog: battleLog,
            playerSnapshots: decoded.playerSnapshots,
            enemySnapshots: decoded.enemySnapshots
        )
    }

    enum EncounterDetailError: LocalizedError {
        case battleLogNotAvailable
        case decodingFailed
        case unsupportedBattleLogVersion

        var errorDescription: String? {
            switch self {
            case .battleLogNotAvailable:
                return "戦闘ログを取得できませんでした"
            case .decodingFailed:
                return "戦闘ログのデコードに失敗しました"
            case .unsupportedBattleLogVersion:
                return "旧形式の戦闘ログのため表示できません"
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
}

// MARK: - Supporting Types

struct CharacterIconInfo: Hashable {
    let avatarIndex: UInt16?
    let enemyId: UInt16?
    let displayName: String
}

struct TurnSummary: Identifiable {
    let id: Int
    let turn: Int
    let party: [ParticipantState]
    let enemies: [ParticipantState]
    let participants: [String: ParticipantState]
    let groupedActions: [GroupedBattleAction]
}

/// アクション実行時のHP変動情報
struct ActionHPChange {
    let targetId: String
    let targetName: String
    let beforeHP: Int
    let afterHP: Int
    let maxHP: Int
}

/// グループ化されたバトルアクション（アクション宣言 + 結果をまとめる）
struct GroupedBattleAction: Identifiable {
    let id: Int  // グループの一意識別子
    let primaryEntry: BattleLogEntry  // アクション宣言（攻撃、魔法等）
    let results: [BattleLogEntry]  // ダメージ、回復等の結果
    let hpChanges: [ActionHPChange]  // HP変動情報
}

struct ParticipantState: Identifiable {
    enum Role {
        case player
        case enemy
    }

    let id: String
    let name: String
    var currentHP: Int
    var previousHP: Int  // 前ターンのHP（変動表示用）
    let maxHP: Int
    let level: Int?
    let jobName: String?
    let partyMemberId: UInt8?
    let role: Role
    let order: Int
}

// MARK: - Battle Turn View

struct BattleTurnView: View {
    let summary: TurnSummary
    let isFirst: Bool
    let partyName: String
    let iconProvider: (ParticipantState?) -> CharacterIconInfo?

    var body: some View {
        Section {
            // HP概要
            VStack(alignment: .leading, spacing: 4) {
                // 味方HP
                ParticipantSummaryView(title: partyName,
                                       participants: summary.party,
                                       role: .player)

                // 敵HP
                if !summary.enemies.isEmpty {
                    Text("vs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ParticipantSummaryView(title: nil,
                                           participants: summary.enemies,
                                           role: .enemy)
                }
            }
            .padding(.vertical, 4)

            // 各アクショングループを行として表示
            ForEach(summary.groupedActions) { group in
                let participant = summary.participants[group.primaryEntry.actorId ?? ""]
                GroupedActionRowView(group: group,
                                     actor: participant,
                                     iconInfo: iconProvider(participant))
            }
        } header: {
            Text("\(summary.turn)ターン目")
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .textCase(nil)
    }
}

struct ParticipantSummaryView: View {
    let title: String?
    let participants: [ParticipantState]
    let role: ParticipantState.Role

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }

            if participants.isEmpty {
                Text("情報がありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(participants) { participant in
                    ParticipantHPRow(participant: participant, role: role)
                }
            }
        }
    }
}

struct ParticipantHPRow: View {
    let participant: ParticipantState
    let role: ParticipantState.Role

    var body: some View {
        HStack(spacing: 8) {
            // 名前
            Text(formatName())
                .font(.caption)
                .foregroundStyle(.primary)
                .frame(minWidth: 60, alignment: .leading)

            // HPバー
            HPBarView(
                currentHP: participant.currentHP,
                previousHP: participant.previousHP,
                maxHP: participant.maxHP
            )
            .frame(maxWidth: 120)
        }
    }

    private func formatName() -> String {
        var name = participant.name
        if let level = participant.level {
            name += " Lv\(level)"
        }
        return name
    }
}

/// グループ化されたアクションの表示（アクション宣言 + 複数のHP変動を1行で表示）
struct GroupedActionRowView: View {
    let group: GroupedBattleAction
    let actor: ParticipantState?
    let iconInfo: CharacterIconInfo?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BattleActorIcon(actor: actor, iconInfo: iconInfo)

            VStack(alignment: .leading, spacing: 4) {
                // アクター名
                if let name = actor?.name, !name.isEmpty {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let displayName = iconInfo?.displayName, !displayName.isEmpty {
                    Text(displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // アクションメッセージ
                Text(group.primaryEntry.message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                // primaryEntry自体がダメージ/回復の場合（アクション宣言なし）、HPバーを表示
                if group.results.isEmpty && !group.hpChanges.isEmpty {
                    ForEach(group.hpChanges.indices, id: \.self) { idx in
                        HPBarView(
                            currentHP: group.hpChanges[idx].afterHP,
                            previousHP: group.hpChanges[idx].beforeHP,
                            maxHP: group.hpChanges[idx].maxHP
                        )
                        .frame(maxWidth: 120)
                    }
                }

                let partition = partitionResults(group.results)
                let sections: [TargetResultSection] = group.hpChanges.map { hpChange in
                    let entries = partition.byTarget[hpChange.targetId] ?? []
                    let (beforeHPEntries, afterHPEntries) = splitEntries(entries)
                    return TargetResultSection(id: hpChange.targetId,
                                               hpChange: hpChange,
                                               beforeEntries: beforeHPEntries,
                                               afterEntries: afterHPEntries)
                }
                let handledTargets = Set(sections.map { $0.id })
                let remainingTargets = partition.order.filter { !handledTargets.contains($0) }

                ForEach(sections) { section in
                    ForEach(section.beforeEntries.indices, id: \.self) { idx in
                        Text(section.beforeEntries[idx].message)
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }

                    HPBarView(
                        currentHP: section.hpChange.afterHP,
                        previousHP: section.hpChange.beforeHP,
                        maxHP: section.hpChange.maxHP
                    )
                    .frame(maxWidth: 120)

                    ForEach(section.afterEntries.indices, id: \.self) { idx in
                        Text(section.afterEntries[idx].message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(remainingTargets, id: \.self) { targetId in
                    if let entries = partition.byTarget[targetId] {
                        ForEach(entries.indices, id: \.self) { idx in
                            Text(entries[idx].message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ForEach(partition.untargetedResults.indices, id: \.self) { idx in
                    Text(partition.untargetedResults[idx].message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

private struct TargetResultSection: Identifiable {
    let id: String
    let hpChange: ActionHPChange
    let beforeEntries: [BattleLogEntry]
    let afterEntries: [BattleLogEntry]
}

private func partitionResults(_ results: [BattleLogEntry]) -> (byTarget: [String: [BattleLogEntry]], order: [String], untargetedResults: [BattleLogEntry]) {
    var dictionary: [String: [BattleLogEntry]] = [:]
    var order: [String] = []
    var untargeted: [BattleLogEntry] = []

    for entry in results {
        if let targetId = entry.targetId {
            if dictionary[targetId] == nil {
                dictionary[targetId] = []
                order.append(targetId)
            }
            dictionary[targetId]?.append(entry)
        } else {
            untargeted.append(entry)
        }
    }

    return (dictionary, order, untargeted)
}

private func splitEntries(_ entries: [BattleLogEntry]) -> ([BattleLogEntry], [BattleLogEntry]) {
    var before: [BattleLogEntry] = []
    var after: [BattleLogEntry] = []
    for entry in entries {
        if entry.type == .defeat {
            after.append(entry)
        } else {
            before.append(entry)
        }
    }
    return (before, after)
}

struct BattleActorIcon: View {
    let actor: ParticipantState?
    let iconInfo: CharacterIconInfo?

    var body: some View {
        Group {
            if let iconInfo {
                if let avatarIndex = iconInfo.avatarIndex {
                    CharacterImageView(avatarIndex: avatarIndex, size: 55)
                } else if let enemyId = iconInfo.enemyId {
                    EnemyImageView(enemyId: enemyId, size: 55)
                } else {
                    fallbackView
                }
            } else if actor?.role == .enemy {
                fallbackEnemyView
            } else {
                fallbackView
            }
        }
    }

    private var fallbackView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.15))
            .frame(width: 55, height: 55)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            )
    }

    private var fallbackEnemyView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.2))
            .frame(width: 55, height: 55)
            .overlay(
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            )
    }
}
    private func computeHPChanges(for action: BattleLogRenderer.RenderedAction,
                                  stateMap: inout [String: ParticipantState],
                                  indexToId: [UInt16: String]) -> [ActionHPChange] {
        struct AggregatedChange {
            var targetId: String
            var targetName: String
            var beforeHP: Int
            var afterHP: Int
            var maxHP: Int
        }

        var aggregated: [String: AggregatedChange] = [:]
        var order: [String] = []

        for effect in action.model.effects {
            guard let impact = BattleLogEffectInterpreter.impact(for: effect) else { continue }

            let targetIndex: UInt16
            switch impact {
            case .damage(let target, _), .heal(let target, _), .setHP(let target, _):
                targetIndex = target
            }

            guard let participantId = indexToId[targetIndex],
                  var participant = stateMap[participantId] else { continue }

            if aggregated[participantId] == nil {
                aggregated[participantId] = AggregatedChange(targetId: participantId,
                                                             targetName: participant.name,
                                                             beforeHP: participant.currentHP,
                                                             afterHP: participant.currentHP,
                                                             maxHP: participant.maxHP)
                order.append(participantId)
            }

            switch impact {
            case .damage(_, let amount):
                participant.currentHP = max(0, participant.currentHP - amount)
            case .heal(_, let amount):
                participant.currentHP = min(participant.maxHP, participant.currentHP + amount)
            case .setHP(_, let amount):
                participant.currentHP = max(0, min(participant.maxHP, amount))
            }

            stateMap[participantId] = participant

            var change = aggregated[participantId]!
            change.afterHP = participant.currentHP
            aggregated[participantId] = change
        }

        return order.compactMap { key in
            guard let change = aggregated[key] else { return nil }
            return ActionHPChange(targetId: change.targetId,
                                  targetName: change.targetName,
                                  beforeHP: change.beforeHP,
                                  afterHP: change.afterHP,
                                  maxHP: change.maxHP)
        }
    }
