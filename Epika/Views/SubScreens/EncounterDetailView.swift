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
                                      actions: actions,
                                      actionHPChanges: actionHPChanges))

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
        // まずrawActionsからstateMapを更新し、各targetIdごとのHP変動を記録
        var hpChangesByTargetId: [String: (beforeHP: Int, afterHP: Int, maxHP: Int, name: String)] = [:]

        for action in rawActions {
            guard let kind = ActionKind(rawValue: action.kind) else { continue }
            let value = Int(action.value ?? 0)

            switch kind {
            // ダメージ（ターゲットのHPを減らす）
            case .physicalDamage, .magicDamage, .breathDamage, .statusTick,
                 .enemySpecialDamage:
                if let target = action.target,
                   let targetId = indexToId[target],
                   var state = stateMap[targetId] {
                    let beforeHP = hpChangesByTargetId[targetId]?.beforeHP ?? state.currentHP
                    state.currentHP = max(0, state.currentHP - value)
                    hpChangesByTargetId[targetId] = (beforeHP, state.currentHP, state.maxHP, state.name)
                    stateMap[targetId] = state
                }
            // 自傷ダメージ
            case .damageSelf:
                if let actorId = indexToId[action.actor],
                   var state = stateMap[actorId] {
                    let beforeHP = hpChangesByTargetId[actorId]?.beforeHP ?? state.currentHP
                    state.currentHP = max(0, state.currentHP - value)
                    hpChangesByTargetId[actorId] = (beforeHP, state.currentHP, state.maxHP, state.name)
                    stateMap[actorId] = state
                }
            // 回復（ターゲットのHPを増やす）
            case .magicHeal, .healParty:
                if let target = action.target,
                   let targetId = indexToId[target],
                   var state = stateMap[targetId] {
                    let beforeHP = hpChangesByTargetId[targetId]?.beforeHP ?? state.currentHP
                    state.currentHP = min(state.maxHP, state.currentHP + value)
                    hpChangesByTargetId[targetId] = (beforeHP, state.currentHP, state.maxHP, state.name)
                    stateMap[targetId] = state
                }
            // 自己回復
            case .healAbsorb, .healVampire, .healSelf, .enemySpecialHeal:
                if let actorId = indexToId[action.actor],
                   var state = stateMap[actorId] {
                    let beforeHP = hpChangesByTargetId[actorId]?.beforeHP ?? state.currentHP
                    state.currentHP = min(state.maxHP, state.currentHP + value)
                    hpChangesByTargetId[actorId] = (beforeHP, state.currentHP, state.maxHP, state.name)
                    stateMap[actorId] = state
                }
            // 戦闘不能
            case .physicalKill:
                if let target = action.target,
                   let targetId = indexToId[target],
                   var state = stateMap[targetId] {
                    let beforeHP = hpChangesByTargetId[targetId]?.beforeHP ?? state.currentHP
                    state.currentHP = 0
                    hpChangesByTargetId[targetId] = (beforeHP, 0, state.maxHP, state.name)
                    stateMap[targetId] = state
                }
            default:
                break
            }
        }

        // filteredActionsのうち、damage/healタイプのエントリにHP変動を対応付け
        var actionHPChanges: [Int: ActionHPChange] = [:]
        for (index, entry) in filteredActions.enumerated() {
            // damage または heal タイプのエントリのみ対象
            guard entry.type == .damage || entry.type == .heal else { continue }

            // targetIdを取得（ダメージ/回復の対象）
            guard let targetId = entry.targetId,
                  let change = hpChangesByTargetId[targetId] else { continue }

            actionHPChanges[index] = ActionHPChange(
                targetId: targetId,
                targetName: change.name,
                beforeHP: change.beforeHP,
                afterHP: change.afterHP,
                maxHP: change.maxHP
            )
        }

        return (actionHPChanges, stateMap)
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

    @MainActor
    private func loadBattleLogIfNeeded() async {
        guard encounter.combatSummary?.battleLogData != nil else { return }
        guard battleLogEntries.isEmpty, !isLoadingBattleLog, battleLogError == nil else { return }

        isLoadingBattleLog = true
        battleLogError = nil
        do {
            let archive = try fetchBattleLogArchive()
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
    let actions: [BattleLogEntry]
    let actionHPChanges: [Int: ActionHPChange]  // アクションindex → HP変動情報
}

/// アクション実行時のHP変動情報
struct ActionHPChange {
    let targetId: String
    let targetName: String
    let beforeHP: Int
    let afterHP: Int
    let maxHP: Int
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

            // 各アクションを個別の行として表示
            ForEach(Array(summary.actions.enumerated()), id: \.offset) { index, entry in
                let participant = summary.participants[entry.actorId ?? ""]
                BattleActionRowView(entry: entry,
                                    actor: participant,
                                    iconInfo: iconProvider(participant),
                                    hpChange: summary.actionHPChanges[index])
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

struct BattleActionRowView: View {
    let entry: BattleLogEntry
    let actor: ParticipantState?
    let iconInfo: CharacterIconInfo?
    let hpChange: ActionHPChange?

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

                // HP変動がある場合はHPバーを表示
                if let hpChange {
                    HStack(spacing: 4) {
                        Text(hpChange.targetName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        HPBarView(
                            currentHP: hpChange.afterHP,
                            previousHP: hpChange.beforeHP,
                            maxHP: hpChange.maxHP
                        )
                        .frame(maxWidth: 100)
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
