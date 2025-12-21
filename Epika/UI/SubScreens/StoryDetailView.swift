// ==============================================================================
// StoryDetailView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ストーリーノードの詳細情報を表示し、既読処理を実行
//
// 【View構成】
//   - ストーリー情報（章・セクション・タイトル・ステータス）
//   - ストーリー本文
//   - 報酬情報
//   - 解放条件一覧
//   - 解放されるコンテンツ一覧
//   - 「ストーリーを読む」ボタン
//
// 【使用箇所】
//   - ストーリー一覧画面からナビゲーション
//
// ==============================================================================

import SwiftUI

struct StoryDetailView: View {
    let story: RuntimeStoryNode
    let onUpdate: () -> Void

    @Environment(AppServices.self) private var appServices
    @State private var isProcessing = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        List {
            Section {
                StoryInfoContent(story: story)
            }

            Section("ストーリー") {
                Text(story.content)
                    .font(.body)
                    .lineSpacing(4)
            }

            if !story.rewardSummary.isEmpty {
                Section("報酬") {
                    Text(story.rewardSummary)
                        .font(.body)
                }
            }

            if !story.unlockConditions.isEmpty {
                Section("解放条件") {
                    ForEach(story.unlockConditions, id: \.self) { condition in
                        Label(condition, systemImage: "checkmark.circle")
                    }
                }
            }

            if !story.unlocksModules.isEmpty {
                Section("解放されるコンテンツ") {
                    ForEach(story.unlocksModules, id: \.self) { module in
                        Label(module, systemImage: "arrow.right.circle")
                    }
                }
            }

            if story.canRead || showError {
                Section {
                    if story.canRead {
                        Button("ストーリーを読む") {
                            Task { await markAsRead() }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if showError {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .avoidBottomGameInfo()
        .navigationTitle(story.title)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isProcessing)
    }

    @MainActor
    private func markAsRead() async {
        do {
            isProcessing = true
            _ = try await appServices.markStoryNodeAsRead(story.id)
            showError = false
            onUpdate()
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
        isProcessing = false
    }
}

private struct StoryInfoContent: View {
    let story: RuntimeStoryNode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("章\(story.chapterId)・セクション\(story.section)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                StoryStatusBadge(story: story)
            }
            Text(story.title)
                .font(.title2)
                .bold()
        }
    }
}

struct StoryStatusBadge: View {
    let story: RuntimeStoryNode

    var body: some View {
        Group {
            if story.isCompleted {
                Label("完了", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.primary)
            } else if story.isUnlocked {
                Label("解放済み", systemImage: "lock.open.fill")
                    .font(.caption)
                    .foregroundColor(.primary)
            } else {
                Label("未解放", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
