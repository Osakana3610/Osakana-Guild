import SwiftUI
import Observation

@MainActor
@Observable
final class StoryViewModel {
    var nodes: [RuntimeStoryNode] = []
    var isLoading: Bool = false
    var error: Error?

    func load(using appServices: AppServices) async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        error = nil

        do {
            try await appServices.synchronizeStoryAndDungeonUnlocks()
            let definitions = appServices.masterDataCache.allStoryNodes
            let snapshot = try await appServices.story.currentStorySnapshot()
            let unlocked = snapshot.unlockedNodeIds
            let read = snapshot.readNodeIds
            let rewarded = snapshot.rewardedNodeIds

            nodes = definitions.compactMap { definition in
                guard unlocked.contains(definition.id) else { return nil }
                return RuntimeStoryNode(
                    definition: definition,
                    isUnlocked: unlocked.contains(definition.id),
                    isCompleted: read.contains(definition.id),
                    isRewardClaimed: rewarded.contains(definition.id)
                )
            }
            .sorted { lhs, rhs in
                if lhs.definition.chapter != rhs.definition.chapter {
                    return lhs.definition.chapter < rhs.definition.chapter
                }
                if lhs.section != rhs.section {
                    return lhs.section < rhs.section
                }
                return lhs.title < rhs.title
            }
        } catch {
            self.error = error
            nodes = []
        }
    }

    func groupedByChapter() -> [(chapter: String, nodes: [RuntimeStoryNode])] {
        let grouped = Dictionary(grouping: nodes) { node in
            node.chapterId
        }
        return grouped
            .sorted { lhs, rhs in
                if let lhsInt = Int(lhs.key), let rhsInt = Int(rhs.key) {
                    return lhsInt < rhsInt
                }
                return lhs.key < rhs.key
            }
            .map { (chapter: $0.key, nodes: $0.value) }
    }
}

struct StoryView: View {
    @Environment(AppServices.self) private var appServices
    @State private var viewModel = StoryViewModel()
    @State private var didLoadOnce = false

    var body: some View {
        NavigationStack {
            Group {
                if let error = viewModel.error {
                    errorState(error)
                } else if viewModel.isLoading && viewModel.nodes.isEmpty {
                    loadingState
                } else if viewModel.nodes.isEmpty {
                    emptyState
                } else {
                    contentList
                }
            }
            .navigationTitle("物語")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                if !didLoadOnce {
                    Task {
                        await viewModel.load(using: appServices)
                        didLoadOnce = true
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .progressUnlocksDidChange)) { _ in
                Task { await viewModel.load(using: appServices) }
            }
        }
    }

    private var contentList: some View {
        List {
            ForEach(viewModel.groupedByChapter(), id: \.chapter) { entry in
                Section(header: Text(chapterTitle(for: entry.chapter))) {
                    ForEach(entry.nodes) { node in
                        NavigationLink(value: node.id) {
                            StoryRow(node: node)
                        }
                    }
                }
            }
        }
        .navigationDestination(for: UInt16.self) { nodeId in
            if let node = viewModel.nodes.first(where: { $0.id == nodeId }) {
                StoryDetailView(story: node) {
                    Task { await viewModel.load(using: appServices) }
                }
            } else {
                Text("ストーリーが見つかりません")
                    .foregroundStyle(.secondary)
            }
        }
        .avoidBottomGameInfo()
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("ストーリーを読み込み中…")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("開放済みのストーリーがありません")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 48))
                .foregroundColor(.primary)
            Text("ストーリーの取得に失敗しました")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("再試行") {
                Task { await viewModel.load(using: appServices) }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chapterTitle(for chapterId: String) -> String {
        if let number = Int(chapterId) {
            return "第\(number)章"
        }
        return "Chapter \(chapterId)"
    }
}

private struct StoryRow: View {
    let node: RuntimeStoryNode

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(node.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("セクション \(node.section)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if node.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.primary)
            } else if node.isUnlocked {
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "lock.fill")
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
