// ==============================================================================
// DropNotificationSettingsView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ドロップ通知のフィルタリング設定UI
//
// 【View構成】
//   - ノーマルアイテムを無視トグル
//   - 常にトグル（ノーマル無視オン時のみ表示）
//   - 称号フィルター（個別チェック）
//   - 超レア通知トグル
//
// 【使用箇所】
//   - SettingsView（その他タブ）
//
// ==============================================================================

import SwiftUI

struct DropNotificationSettingsView: View {
    @Environment(AppServices.self) private var appServices

    private var notificationService: ItemDropNotificationService { appServices.dropNotifications }
    private var masterDataCache: MasterDataCache { appServices.masterDataCache }

    var body: some View {
        Form {
            normalItemSection
            titleFilterSection
            superRareSection
        }
        .avoidBottomGameInfo()
        .navigationTitle("ドロップ通知設定")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - ノーマルアイテムセクション

    @ViewBuilder
    private var normalItemSection: some View {
        let ignoreNormalItems = notificationService.settings.ignoreNormalItems
        let alwaysIgnore = notificationService.settings.alwaysIgnore

        Section {
            Toggle("ノーマルアイテムを無視", isOn: settingsBinding(\.ignoreNormalItems))

            if ignoreNormalItems {
                Toggle("常に", isOn: settingsBinding(\.alwaysIgnore))
            }
        } footer: {
            if ignoreNormalItems && !alwaysIgnore {
                Text("常にがオフだと、以下のメニューで設定した称号がついた場合は通知が表示されます")
            }
        }
    }

    // MARK: - 称号フィルターセクション

    @ViewBuilder
    private var titleFilterSection: some View {
        Section("称号") {
            ForEach(sortedTitles, id: \.id) { title in
                titleRow(title)
            }
        }
    }

    private var sortedTitles: [TitleOption] {
        masterDataCache.allTitles
            .sorted { $0.id < $1.id }
            .compactMap { title in
                let name = title.id == ItemDropNotificationService.noTitleId ? "無称号" : title.name
                return name.isEmpty ? nil : TitleOption(id: title.id, name: name)
            }
    }

    private struct TitleOption: Identifiable {
        let id: UInt8
        let name: String
    }

    @ViewBuilder
    private func titleRow(_ title: TitleOption) -> some View {
        let isSelected = notificationService.settings.notifyTitleIds.contains(title.id)
        Button {
            notificationService.updateSettings { settings in
                if isSelected {
                    settings.notifyTitleIds.remove(title.id)
                } else {
                    settings.notifyTitleIds.insert(title.id)
                }
            }
        } label: {
            HStack {
                Text(title.name)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 超レアセクション

    @ViewBuilder
    private var superRareSection: some View {
        Section {
            Toggle("超レアを通知", isOn: settingsBinding(\.notifySuperRare))
        }
    }

    private func settingsBinding(
        _ keyPath: WritableKeyPath<ItemDropNotificationService.Settings, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { notificationService.settings[keyPath: keyPath] },
            set: { newValue in
                notificationService.updateSettings { $0[keyPath: keyPath] = newValue }
            }
        )
    }
}
