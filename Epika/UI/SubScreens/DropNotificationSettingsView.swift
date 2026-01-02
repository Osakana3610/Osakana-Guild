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
        .navigationTitle("ドロップ通知設定")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - ノーマルアイテムセクション

    @ViewBuilder
    private var normalItemSection: some View {
        Section {
            Toggle("ノーマルアイテムを無視", isOn: Binding(
                get: { notificationService.settings.ignoreNormalItems },
                set: { newValue in
                    notificationService.updateSettings { $0.ignoreNormalItems = newValue }
                }
            ))

            if notificationService.settings.ignoreNormalItems {
                Toggle("常に", isOn: Binding(
                    get: { notificationService.settings.alwaysIgnore },
                    set: { newValue in
                        notificationService.updateSettings { $0.alwaysIgnore = newValue }
                    }
                ))
            }
        } footer: {
            if notificationService.settings.ignoreNormalItems && !notificationService.settings.alwaysIgnore {
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
            .map { title in
                if title.id == ItemDropNotificationService.noTitleId {
                    return TitleOption(id: title.id, name: "無称号")
                }
                return TitleOption(id: title.id, name: title.name)
            }
            .filter { !$0.name.isEmpty }
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
            Toggle("超レアを通知", isOn: Binding(
                get: { notificationService.settings.notifySuperRare },
                set: { newValue in
                    notificationService.updateSettings { $0.notifySuperRare = newValue }
                }
            ))
        }
    }
}
