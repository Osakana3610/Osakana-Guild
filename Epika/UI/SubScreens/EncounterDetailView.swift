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
    @State private var battleLogEntries: [BattleLogEntry] = []
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

        // actorIndex → actorId のマッピング
        var indexToId: [UInt16: String] = [:]

        // 初期状態をarchiveから構築
        var states: [String: ParticipantState] = [:]

        for (index, participant) in archive.playerSnapshots.enumerated() {
            // initialHPとBattleActionはpartyMemberIdをキーに使用
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
            // actorId は CombatExecutionService で BattleContext.actorIndex と同じ計算式で保存されている
            // 形式: (arrayIndex + 1) * 1000 + enemyMasterIndex
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

        // 生アクションをターンごとにグループ化（HP計算用）
        var rawActionsByTurn: [Int: [BattleAction]] = [:]
        for action in archive.battleLog.actions {
            rawActionsByTurn[Int(action.turn), default: []].append(action)
        }

        // 表示用エントリーをターンごとにグループ化
        var grouped: [Int: [BattleLogEntry]] = [:]
        for entry in battleLogEntries {
            grouped[entry.turn, default: []].append(entry)
        }

        var result: [TurnSummary] = []
        var stateMap = states
        var previousTurnStartStates = states  // 前ターン開始時の状態
        let sortedTurns = grouped.keys.sorted().filter { $0 > 0 }

        for turn in sortedTurns {
            // ターン開始時の状態を記録
            let turnStartStates = stateMap

            // HP概要用：currentHP=ターン開始時、previousHP=前ターン開始時
            var summaryStates: [String: ParticipantState] = [:]
            for (id, var state) in turnStartStates {
                state.previousHP = previousTurnStartStates[id]?.currentHP ?? state.currentHP
                summaryStates[id] = state
            }

            // フィルタ後のアクション
            let actions = (grouped[turn] ?? []).filter(shouldDisplayAction)

            // アクションごとのHP変動を計算
            let rawActions = rawActionsByTurn[turn] ?? []
            let (actionHPChanges, _) = computeActionHPChanges(
                rawActions: rawActions,
                filteredActions: actions,
                stateMap: &stateMap,
                indexToId: indexToId
            )

            // エントリをグループ化
            let groupedActions = groupEntries(actions, actionHPChanges: actionHPChanges, participants: summaryStates)

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

            // 次ターン用に前ターン開始時の状態を更新
            previousTurnStartStates = turnStartStates
        }

        return result
    }

    /// アクションごとのHP変動を計算し、stateMapを更新する
    /// - Returns: (actionHPChanges, 更新後のstateMap)
    private func computeActionHPChanges(
        rawActions: [BattleAction],
        filteredActions: [BattleLogEntry],
        stateMap: inout [String: ParticipantState],
        indexToId: [UInt16: String]
    ) -> ([Int: ActionHPChange], [String: ParticipantState]) {
        var actionHPChanges: [Int: ActionHPChange] = [:]

        // rawActionsとfilteredActionsの対応を追跡するためのインデックス
        var filteredIndex = 0

        for action in rawActions {
            guard let kind = ActionKind(rawValue: action.kind) else { continue }
            let value = Int(action.value ?? 0)

            // このrawActionに対応するfilteredActionを探す
            let matchingFilteredIndex = findMatchingFilteredIndex(
                action: action,
                kind: kind,
                filteredActions: filteredActions,
                startFrom: filteredIndex,
                indexToId: indexToId
            )

            switch kind {
            // ダメージ（ターゲットのHPを減らす）
            case .physicalDamage, .magicDamage, .breathDamage, .statusTick,
                 .enemySpecialDamage:
                if let target = action.target,
                   let targetId = indexToId[target],
                   var state = stateMap[targetId] {
                    let beforeHP = state.currentHP
                    state.currentHP = max(0, state.currentHP - value)
                    stateMap[targetId] = state

                    if let idx = matchingFilteredIndex {
                        actionHPChanges[idx] = ActionHPChange(
                            targetId: targetId,
                            targetName: state.name,
                            beforeHP: beforeHP,
                            afterHP: state.currentHP,
                            maxHP: state.maxHP
                        )
                        filteredIndex = idx + 1
                    }
                }
            // 自傷ダメージ
            case .damageSelf:
                if let actorId = indexToId[action.actor],
                   var state = stateMap[actorId] {
                    let beforeHP = state.currentHP
                    state.currentHP = max(0, state.currentHP - value)
                    stateMap[actorId] = state

                    if let idx = matchingFilteredIndex {
                        actionHPChanges[idx] = ActionHPChange(
                            targetId: actorId,
                            targetName: state.name,
                            beforeHP: beforeHP,
                            afterHP: state.currentHP,
                            maxHP: state.maxHP
                        )
                        filteredIndex = idx + 1
                    }
                }
            // 回復（ターゲットのHPを増やす）
            case .magicHeal, .healParty:
                if let target = action.target,
                   let targetId = indexToId[target],
                   var state = stateMap[targetId] {
                    let beforeHP = state.currentHP
                    state.currentHP = min(state.maxHP, state.currentHP + value)
                    stateMap[targetId] = state

                    if let idx = matchingFilteredIndex {
                        actionHPChanges[idx] = ActionHPChange(
                            targetId: targetId,
                            targetName: state.name,
                            beforeHP: beforeHP,
                            afterHP: state.currentHP,
                            maxHP: state.maxHP
                        )
                        filteredIndex = idx + 1
                    }
                }
            // 自己回復
            case .healAbsorb, .healVampire, .healSelf, .enemySpecialHeal:
                if let actorId = indexToId[action.actor],
                   var state = stateMap[actorId] {
                    let beforeHP = state.currentHP
                    state.currentHP = min(state.maxHP, state.currentHP + value)
                    stateMap[actorId] = state

                    if let idx = matchingFilteredIndex {
                        actionHPChanges[idx] = ActionHPChange(
                            targetId: actorId,
                            targetName: state.name,
                            beforeHP: beforeHP,
                            afterHP: state.currentHP,
                            maxHP: state.maxHP
                        )
                        filteredIndex = idx + 1
                    }
                }
            // 戦闘不能
            case .physicalKill:
                if let target = action.target,
                   let targetId = indexToId[target],
                   var state = stateMap[targetId] {
                    let beforeHP = state.currentHP
                    state.currentHP = 0
                    stateMap[targetId] = state

                    if let idx = matchingFilteredIndex {
                        actionHPChanges[idx] = ActionHPChange(
                            targetId: targetId,
                            targetName: state.name,
                            beforeHP: beforeHP,
                            afterHP: 0,
                            maxHP: state.maxHP
                        )
                        filteredIndex = idx + 1
                    }
                }
            default:
                break
            }
        }

        return (actionHPChanges, stateMap)
    }

    /// rawActionに対応するfilteredActionのインデックスを探す
    private func findMatchingFilteredIndex(
        action: BattleAction,
        kind: ActionKind,
        filteredActions: [BattleLogEntry],
        startFrom: Int,
        indexToId: [UInt16: String]
    ) -> Int? {
        // damage/healタイプのみ対応
        let expectedType: BattleLogEntry.LogType
        switch kind {
        case .physicalDamage, .magicDamage, .breathDamage, .statusTick,
             .enemySpecialDamage, .damageSelf:
            expectedType = .damage
        case .magicHeal, .healParty, .healAbsorb, .healVampire, .healSelf, .enemySpecialHeal:
            expectedType = .heal
        case .physicalKill:
            expectedType = .defeat
        default:
            return nil
        }

        // 対象のIDを特定
        let targetIndex: UInt16
        switch kind {
        case .damageSelf, .healAbsorb, .healVampire, .healSelf, .enemySpecialHeal:
            targetIndex = action.actor
        default:
            guard let target = action.target else { return nil }
            targetIndex = target
        }
        let targetId = String(targetIndex)

        // startFromから順に探す
        for idx in startFrom..<filteredActions.count {
            let entry = filteredActions[idx]
            if entry.type == expectedType && entry.targetId == targetId {
                return idx
            }
        }

        return nil
    }

    private func shouldDisplayAction(_ entry: BattleLogEntry) -> Bool {
        if entry.turn == 0 { return false }
        if entry.message.isEmpty { return false }
        if entry.type == .system {
            if entry.message.hasPrefix("---") { return false }
            if entry.message.contains("戦闘開始") { return false }
            if entry.message.hasSuffix("が現れた！") { return false }
        }
        return true
    }

    /// エントリをアクション単位でグループ化
    /// アクション宣言（攻撃、魔法等）と、それに続く結果（ダメージ、回復等）をまとめる
    private func groupEntries(
        _ entries: [BattleLogEntry],
        actionHPChanges: [Int: ActionHPChange],
        participants: [String: ParticipantState]
    ) -> [GroupedBattleAction] {
        var groups: [GroupedBattleAction] = []
        var currentPrimary: BattleLogEntry?
        var currentResults: [BattleLogEntry] = []
        var currentHPChanges: [ActionHPChange] = []
        var groupId = 0

        func finishGroup() {
            guard let primary = currentPrimary else {
                // アクション宣言なしの場合、各結果を個別グループとして追加
                for (idx, result) in currentResults.enumerated() {
                    // 対応するHPChangeがあれば含める
                    let hpChangeForResult = idx < currentHPChanges.count ? [currentHPChanges[idx]] : []
                    groups.append(GroupedBattleAction(
                        id: groupId,
                        primaryEntry: result,
                        results: [],
                        hpChanges: hpChangeForResult
                    ))
                    groupId += 1
                }
                currentResults = []
                currentHPChanges = []
                return
            }
            groups.append(GroupedBattleAction(
                id: groupId,
                primaryEntry: primary,
                results: currentResults,
                hpChanges: currentHPChanges
            ))
            groupId += 1
            currentPrimary = nil
            currentResults = []
            currentHPChanges = []
        }

        for (index, entry) in entries.enumerated() {
            let isActionDeclaration = entry.type == .action || entry.type == .guard
            // ダメージ、回復、ミス、敗北は結果としてグループに含める
            let isResult = entry.type == .damage || entry.type == .heal || entry.type == .miss || entry.type == .defeat
            // 勝利、撤退、システムはグループを終了して単独表示
            let isStandalone = entry.type == .victory || entry.type == .retreat || entry.type == .system

            if isActionDeclaration {
                // 前のグループを確定
                finishGroup()
                currentPrimary = entry
                } else if isResult {
                // actorIdが現在のprimaryと異なる場合は、別のキャラクターのアクション結果なので
                // 前のグループを確定して個別グループとして追加
                let belongsToCurrentGroup: Bool
                if let primary = currentPrimary {
                    // primaryと同じactorIdの結果のみグループに含める
                    belongsToCurrentGroup = entry.actorId == primary.actorId
                } else {
                    belongsToCurrentGroup = false
                }

                if !belongsToCurrentGroup && currentPrimary != nil {
                    // 前のグループを確定
                    finishGroup()
                }

                // 結果をグループに追加（敗北含む）
                // ただしdefeatはHP変動を持たないのでスキップ
                if entry.type != .defeat {
                    currentResults.append(entry)
                    if let hpChange = actionHPChanges[index] {
                        currentHPChanges.append(hpChange)
                    }
                }
                // defeatは表示しない（HP 0/maxで十分わかる）
            } else if isStandalone {
                // 勝利・撤退・システムは単独表示
                finishGroup()
                groups.append(GroupedBattleAction(
                    id: groupId,
                    primaryEntry: entry,
                    results: [],
                    hpChanges: []
                ))
                groupId += 1
            } else {
                // status等はそのままグループに追加
                currentResults.append(entry)
            }
        }

        // 最後のグループを確定
        finishGroup()

        return groups
    }

    @MainActor
    private func loadBattleLogIfNeeded() async {
        guard encounter.combatSummary?.battleLogId != nil else { return }
        guard battleLogEntries.isEmpty, !isLoadingBattleLog, battleLogError == nil else { return }

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

            for participant in archive.playerSnapshots {
                if let memberId = participant.partyMemberId {
                    allyNames[memberId] = participant.name
                    memberMap[participant.actorId] = memberId
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

            // BattleLogRenderer で変換
            battleLogEntries = BattleLogRenderer.render(
                battleLog: archive.battleLog,
                allyNames: allyNames,
                enemyNames: enemyNames,
                spellNames: spellNames
            )

            actorIdentifierToMemberId = memberMap
            actorIcons = iconMap
        } catch {
            battleLogError = error.localizedDescription
        }
        isLoadingBattleLog = false
    }

    private func fetchBattleLogArchive() throws -> BattleLogArchive? {
        guard let id = encounter.combatSummary?.battleLogId,
              let record = modelContext.model(for: id) as? BattleLogRecord else {
            return nil
        }
        return restoreBattleLogArchive(from: record)
    }

    private func restoreBattleLogArchive(from record: BattleLogRecord) -> BattleLogArchive {
        // initialHP復元
        var initialHP: [UInt16: UInt32] = [:]
        for hp in record.initialHPs {
            initialHP[hp.actorIndex] = hp.hp
        }

        // actions復元
        let actions = record.actions.sorted { $0.sortOrder < $1.sortOrder }.map { a in
            BattleAction(
                turn: a.turn,
                kind: a.kind,
                actor: a.actor,
                target: a.target == 0 ? nil : a.target,
                value: a.value == 0 ? nil : a.value,
                skillIndex: a.skillIndex == 0 ? nil : a.skillIndex,
                extra: a.extra == 0 ? nil : a.extra
            )
        }

        let battleLog = BattleLog(
            initialHP: initialHP,
            actions: actions,
            outcome: record.outcome,
            turns: record.turns
        )

        // participants復元
        let playerSnapshots = record.participants.filter { $0.isPlayer }.map { p in
            BattleParticipantSnapshot(
                actorId: p.actorId,
                partyMemberId: p.partyMemberId == 0 ? nil : p.partyMemberId,
                characterId: p.characterId == 0 ? nil : p.characterId,
                name: p.name,
                avatarIndex: p.avatarIndex == 0 ? nil : p.avatarIndex,
                level: p.level == 0 ? nil : Int(p.level),
                maxHP: Int(p.maxHP)
            )
        }
        let enemySnapshots = record.participants.filter { !$0.isPlayer }.map { p in
            BattleParticipantSnapshot(
                actorId: p.actorId,
                partyMemberId: p.partyMemberId == 0 ? nil : p.partyMemberId,
                characterId: p.characterId == 0 ? nil : p.characterId,
                name: p.name,
                avatarIndex: p.avatarIndex == 0 ? nil : p.avatarIndex,
                level: p.level == 0 ? nil : Int(p.level),
                maxHP: Int(p.maxHP)
            )
        }

        return BattleLogArchive(
            enemyId: record.enemyId,
            enemyName: record.enemyName,
            result: BattleService.BattleResult(rawValue: record.result) ?? .victory,
            turns: Int(record.turns),
            timestamp: record.timestamp,
            battleLog: battleLog,
            playerSnapshots: playerSnapshots,
            enemySnapshots: enemySnapshots
        )
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

                // 各結果（ダメージ/回復等）とHP変動を表示
                ForEach(Array(zip(group.results, group.hpChanges).enumerated()), id: \.offset) { _, pair in
                    let (result, hpChange) = pair
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.message)
                            .font(.caption)
                            .foregroundStyle(.primary)
                        HPBarView(
                            currentHP: hpChange.afterHP,
                            previousHP: hpChange.beforeHP,
                            maxHP: hpChange.maxHP
                        )
                        .frame(maxWidth: 120)
                    }
                }
                // HP変動がない結果（ミス等）を表示
                if group.results.count > group.hpChanges.count {
                    ForEach(Array(group.results.dropFirst(group.hpChanges.count).enumerated()), id: \.offset) { _, result in
                        Text(result.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
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
