import SwiftUI

struct StoryDetailView: View {
    let story: RuntimeStoryNode
    let onUpdate: () -> Void

    @EnvironmentObject private var progressService: ProgressService
    @State private var isProcessing = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StoryInfoCard(story: story)
                StoryContentCard(story: story)

                if !story.rewardSummary.isEmpty {
                    StoryRewardsCard(story: story)
                }

                if !story.unlockConditions.isEmpty {
                    UnlockConditionsCard(story: story)
                }

                if !story.unlocksModules.isEmpty {
                    UnlockedModulesCard(story: story)
                }

                if story.canRead {
                    Button("ストーリーを読む") {
                        Task { await markAsRead() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                if showError {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
            .padding()
        }
        .avoidBottomGameInfo()
        .navigationTitle(story.title)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isProcessing)
    }

    @MainActor
    private func markAsRead() async {
        do {
            isProcessing = true
            _ = try await progressService.markStoryNodeAsRead(story.id)
            showError = false
            onUpdate()
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
        isProcessing = false
    }
}

struct StoryInfoCard: View {
    let story: RuntimeStoryNode

    var body: some View {
        GroupBox {
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
}

struct StoryContentCard: View {
    let story: RuntimeStoryNode

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "book.fill")
                        .foregroundColor(.primary)
                    Text("ストーリー")
                        .font(.headline)
                }

                Text(story.content)
                    .font(.body)
                    .lineSpacing(4)
            }
        }
    }
}

struct StoryRewardsCard: View {
    let story: RuntimeStoryNode

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "gift.fill")
                        .foregroundColor(.primary)
                    Text("報酬")
                        .font(.headline)
                }

                Text(story.rewardSummary)
                    .font(.body)
                    .foregroundColor(.primary)
            }
        }
    }
}

struct UnlockConditionsCard: View {
    let story: RuntimeStoryNode

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundColor(.primary)
                    Text("解放条件")
                        .font(.headline)
                }

                ForEach(story.unlockConditions, id: \.self) { condition in
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.primary)
                        Text(condition)
                            .font(.body)
                    }
                }
            }
        }
    }
}

struct UnlockedModulesCard: View {
    let story: RuntimeStoryNode

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "lock.open.fill")
                        .foregroundColor(.primary)
                    Text("解放されるコンテンツ")
                        .font(.headline)
                }

                ForEach(story.unlocksModules, id: \.self) { module in
                    HStack {
                        Image(systemName: "arrow.right.circle")
                            .foregroundColor(.primary)
                        Text(module)
                            .font(.body)
                    }
                }
            }
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
