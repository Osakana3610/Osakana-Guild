// ==============================================================================
// BugReportView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 不具合報告の入力と送信UI
//   - ユーザーデータとログを自動添付
//
// 【View構成】
//   - 報告内容テキストエリア
//   - 送信ボタン
//   - 送信中・完了・エラー状態表示
//
// 【使用箇所】
//   - SettingsView（その他タブ）
//
// ==============================================================================

import SwiftUI

struct BugReportView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.dismiss) private var dismiss

    @State private var description: String = ""
    @State private var isSending: Bool = false
    @State private var showingSuccess: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            descriptionSection
            infoSection
            sendSection
        }
        .navigationTitle("不具合報告")
        .navigationBarTitleDisplayMode(.inline)
        .alert("送信完了", isPresented: $showingSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("不具合報告を送信しました。ご協力ありがとうございます。")
        }
        .alert("送信エラー", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var descriptionSection: some View {
        Section {
            TextEditor(text: $description)
                .frame(minHeight: 150)
        } header: {
            Text("不具合の内容")
        } footer: {
            Text("どのような操作をしたときに、何が起きたかを教えてください")
        }
    }

    private var inventoryCount: Int {
        appServices.userDataLoad.subcategorizedItems.values.reduce(0) { $0 + $1.count }
    }

    @ViewBuilder
    private var infoSection: some View {
        Section {
            HStack {
                Text("ゴールド")
                Spacer()
                Text(formatNumber(Int(appServices.userDataLoad.playerGold)))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("キャラクター数")
                Spacer()
                Text("\(appServices.userDataLoad.characters.count)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("パーティ数")
                Spacer()
                Text("\(appServices.userDataLoad.parties.count)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("アイテム数")
                Spacer()
                Text("\(inventoryCount)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("自動添付される情報")
        } footer: {
            Text("直近24時間の操作ログも添付されます")
        }
    }

    @ViewBuilder
    private var sendSection: some View {
        Section {
            Button {
                Task {
                    await sendReport()
                }
            } label: {
                HStack {
                    Spacer()
                    if isSending {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("送信中...")
                    } else {
                        Text("送信")
                    }
                    Spacer()
                }
            }
            .disabled(isSending)
        }
    }

    // MARK: - Actions

    private func sendReport() async {
        isSending = true
        defer { isSending = false }

        do {
            let logs = await AppLogCollector.shared.getLogsAsText()
            let battleLogs = BattleLogBuffer.shared.getLogsAsText()
            let appInfo = BugReportService.gatherAppInfo()

            let playerId = getOrCreatePlayerId()

            let playerData = BugReport.PlayerReportData(
                playerId: playerId,
                gold: Int(appServices.userDataLoad.playerGold),
                partyCount: appServices.userDataLoad.parties.count,
                characterCount: appServices.userDataLoad.characters.count,
                inventoryCount: inventoryCount,
                currentScreen: "BugReportView"
            )

            let userDataJson = buildUserDataJson(playerId: playerId)

            let report = BugReport(
                description: description,
                playerData: playerData,
                logs: logs,
                battleLogs: battleLogs,
                userDataJson: userDataJson,
                appInfo: appInfo
            )

            try await BugReportService.shared.send(report)
            showingSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildUserDataJson(playerId: String) -> String {
        let userDataLoad = appServices.userDataLoad

        let characterReports = userDataLoad.characters.map { char in
            UserDataReport.CharacterReport(
                id: char.id,
                name: char.displayName,
                raceId: char.raceId,
                raceName: char.raceName,
                jobId: char.jobId,
                jobName: char.jobName,
                level: char.level,
                experience: char.experience,
                currentHP: char.currentHP,
                maxHP: char.maxHP,
                equippedItemCount: char.equippedItems.count,
                equippedItems: char.equippedItems.map { $0.displayName }
            )
        }

        let partyReports = userDataLoad.parties.map { party in
            UserDataReport.PartyReport(
                id: party.id,
                name: party.displayName,
                memberIds: party.memberCharacterIds,
                lastSelectedDungeonId: party.lastSelectedDungeonId
            )
        }

        let allItems = userDataLoad.subcategorizedItems.values.flatMap { items -> [CachedInventoryItem] in items }
        let itemReports = allItems.map { item in
            UserDataReport.ItemReport(
                itemId: item.itemId,
                displayName: item.displayName,
                quantity: item.quantity,
                category: item.category.identifier,
                normalTitleId: item.normalTitleId,
                superRareTitleId: item.superRareTitleId,
                socketItemId: item.socketItemId
            )
        }

        let report = UserDataReport(
            playerId: playerId,
            gold: Int(userDataLoad.playerGold),
            characters: characterReports,
            parties: partyReports,
            inventory: itemReports
        )

        return report.toJsonString()
    }

    /// プレイヤーIDを取得または生成（UserDefaults簡易版）
    private func getOrCreatePlayerId() -> String {
        let key = "BugReport.PlayerId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    // MARK: - Helpers

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? String(n)
    }
}
