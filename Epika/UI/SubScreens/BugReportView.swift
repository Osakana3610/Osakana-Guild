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
//   - 報告者名入力
//   - 報告内容テキストエリア
//   - スクリーンショット添付
//   - 送信ボタン
//   - 送信中・完了・エラー状態表示
//
// 【使用箇所】
//   - SettingsView（その他タブ）
//
// ==============================================================================

import PhotosUI
import SwiftUI

struct BugReportView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.dismiss) private var dismiss

    @State private var reporterName: String = ""
    @State private var description: String = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var screenshotImages: [UIImage] = []
    @State private var sendUserData: Bool = true
    @State private var sendLogs: Bool = true
    @State private var isSending: Bool = false
    @State private var showingSuccess: Bool = false
    @State private var errorMessage: String?

    private let maxScreenshots = 5

    var body: some View {
        Form {
            reporterSection
            descriptionSection
            screenshotSection
            privacySection
            infoSection
            sendSection
        }
        .avoidBottomGameInfo()
        .navigationTitle("不具合報告")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedPhotos) { _, newItems in
            Task {
                await loadSelectedPhotos(newItems)
            }
        }
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
        .onAppear {
            reporterName = UserDefaults.standard.string(forKey: "BugReport.ReporterName") ?? ""
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var reporterSection: some View {
        Section {
            TextField("名前（任意）", text: $reporterName)
                .onChange(of: reporterName) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "BugReport.ReporterName")
                }
        } header: {
            Text("報告者")
        } footer: {
            Text("Discord等で連絡を取る際に使用します（空欄可）")
        }
    }

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

    @ViewBuilder
    private var screenshotSection: some View {
        Section {
            HStack {
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: maxScreenshots,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("スクリーンショットを選択")
                    }
                }
                Spacer()
                if !screenshotImages.isEmpty {
                    Text("\(screenshotImages.count)枚")
                        .foregroundStyle(.secondary)
                }
            }

            if !screenshotImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(screenshotImages.indices, id: \.self) { index in
                            Image(uiImage: screenshotImages[index])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("スクリーンショット（任意）")
        } footer: {
            Text("最大\(maxScreenshots)枚まで添付できます。動画はDiscordで直接送信してください")
        }
    }

    private var inventoryCount: Int {
        appServices.userDataLoad.subcategorizedItems.values.reduce(0) { $0 + $1.count }
    }

    @ViewBuilder
    private var privacySection: some View {
        Section {
            Toggle("ユーザーデータを送信", isOn: $sendUserData)
            Toggle("操作ログを送信", isOn: $sendLogs)
        } header: {
            Text("プライバシー設定")
        } footer: {
            Text("不具合の調査に役立ちますが、送信しなくても報告できます")
        }
    }

    @ViewBuilder
    private var infoSection: some View {
        if sendUserData || sendLogs {
            Section {
                if sendUserData {
                    HStack {
                        Text("ゴールド")
                        Spacer()
                        Text(Int(appServices.userDataLoad.cachedPlayer.gold).formattedWithComma())
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("キャラクター数")
                        Spacer()
                        Text(appServices.userDataLoad.characters.count.formattedWithComma())
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("パーティ数")
                        Spacer()
                        Text(appServices.userDataLoad.parties.count.formattedWithComma())
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("アイテム数")
                        Spacer()
                        Text(inventoryCount.formattedWithComma())
                            .foregroundStyle(.secondary)
                    }
                }
                if sendLogs {
                    HStack {
                        Text("操作ログ")
                        Spacer()
                        Text("直近24時間")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("戦闘ログ")
                        Spacer()
                        Text("直近200件")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("送信される情報")
            }
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

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        await MainActor.run {
            screenshotImages = images
        }
    }

    private func sendReport() async {
        isSending = true
        defer { isSending = false }

        do {
            let appInfo = BugReportService.gatherAppInfo()
            let playerId = getOrCreatePlayerId()

            // オプションに応じてログを取得（戦闘ログはSQLiteに含まれる）
            let logs: String
            if sendLogs {
                logs = await AppLogCollector.shared.getLogsAsText()
            } else {
                logs = ""
            }

            // オプションに応じてユーザーデータを設定
            let playerData: BugReport.PlayerReportData
            let databaseData: Data?
            if sendUserData {
                playerData = BugReport.PlayerReportData(
                    playerId: playerId,
                    gold: Int(appServices.userDataLoad.cachedPlayer.gold),
                    partyCount: appServices.userDataLoad.parties.count,
                    characterCount: appServices.userDataLoad.characters.count,
                    inventoryCount: inventoryCount,
                    currentScreen: "BugReportView"
                )
                databaseData = BugReportService.gatherDatabaseData()
            } else {
                playerData = BugReport.PlayerReportData(
                    playerId: playerId,
                    gold: 0,
                    partyCount: 0,
                    characterCount: 0,
                    inventoryCount: 0,
                    currentScreen: nil
                )
                databaseData = nil
            }

            // スクリーンショットをPNGデータに変換
            let screenshotData = screenshotImages.compactMap { $0.pngData() }

            let report = BugReport(
                reporterName: reporterName.isEmpty ? nil : reporterName,
                description: description,
                playerData: playerData,
                logs: logs,
                databaseData: databaseData,
                appInfo: appInfo,
                screenshots: screenshotData
            )

            try await BugReportService.shared.send(report)
            showingSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
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
}
