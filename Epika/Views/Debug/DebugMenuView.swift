#if DEBUG
import SwiftUI

enum ItemCreationType: String, CaseIterable {
    case basicOnly = "基本アイテムのみ"
    case withSuperRare = "基本＋超レア称号"
    case withGemModification = "基本＋超レア＋宝石改造"

    var description: String {
        switch self {
        case .basicOnly:
            return "通常称号付きアイテムのみ作成"
        case .withSuperRare:
            return "通常称号＋超レア称号付きアイテムを作成"
        case .withGemModification:
            return "全組み合わせ（通常＋超レア＋宝石改造）を作成"
        }
    }
}

private struct ItemSeed {
    let itemId: String
    let enhancement: ItemSnapshot.Enhancement
}

struct DebugMenuView: View {
    @EnvironmentObject private var progressService: ProgressService
    @State private var isCreatingItems = false
    @State private var creationProgress: Double = 0.0
    @State private var statusMessage = ""
    @State private var showAlert = false
    @State private var alertMessage = ""

    @State private var selectedCreationType: ItemCreationType = .basicOnly
    @State private var maxItemLimit: Int = 50_000
    @State private var showCreationSettings = false

    @State private var isPurgingCloudKit = false
    @State private var purgeStatus = ""

    private let masterDataService = MasterDataRuntimeService.shared
    private var inventoryService: InventoryProgressService { progressService.inventory }
    private var playerService: PlayerProgressService { progressService.player }

    private func debugLog(_ message: @autoclosure () -> String) {
        print(message())
    }

    var body: some View {
        NavigationStack {
            Form {
                itemCreationSection
                itemCleanupSection
                cloudKitSection
            }
            .avoidBottomGameInfo()
            .navigationTitle("デバッグメニュー")
            .navigationBarTitleDisplayMode(.inline)
            .alert("完了", isPresented: $showAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showCreationSettings) {
                ItemCreationSettingsView(selectedType: $selectedCreationType,
                                         maxLimit: $maxItemLimit)
            }
        }
    }

    private var itemCreationSection: some View {
        Section("アイテム作成") {
            if isCreatingItems {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: creationProgress)
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 12) {
                    Button("アイテム作成設定") { showCreationSettings = true }
                        .buttonStyle(.bordered)

                    Button("アイテムを作成開始") {
                        Task { await createAllItems() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("現在の設定: \(selectedCreationType.rawValue)")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("上限: \(maxItemLimit)種類")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(selectedCreationType.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var itemCleanupSection: some View {
        Section("アイテム削除") {
            Button("全てのアイテムを削除", role: .destructive) {
                Task { await deleteAllItems() }
            }
            .buttonStyle(.bordered)
        }
    }

    private var cloudKitSection: some View {
        Section("CloudKit操作") {
            if isPurgingCloudKit {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView()
                    Text(purgeStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("ローカル＋CloudKit進捗を完全消去", role: .destructive) {
                    Task { await purgeCloudKitAndReset() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func createAllItems() async {
        if isCreatingItems { return }
        await MainActor.run {
            isCreatingItems = true
            creationProgress = 0.0
            statusMessage = "マスターデータを読み込み中..."
        }

        do {
            let categoryPriority: [String: Int] = [
                "thin_sword": 0,
                "sword": 1,
                "katana": 2,
                "bow": 3,
                "rod": 4,
                "wand": 5,
                "grimoire": 6,
                "gauntlet": 7,
                "shield": 8,
                "armor": 9,
                "heavy_armor": 10,
                "robe": 11,
                "magic_material": 12,
                "gem": 13,
                "for_synthesis": 14,
                "race_specific": 15,
                "other": 16
            ]

            let allItems = try await masterDataService.getAllItems().sorted { lhs, rhs in
                let lhsKey = lhs.category.lowercased()
                let rhsKey = rhs.category.lowercased()
                let lhsPriority = categoryPriority[lhsKey] ?? Int.max
                let rhsPriority = categoryPriority[rhsKey] ?? Int.max
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                return lhs.name < rhs.name
            }

            let normalTitles = try await masterDataService.getAllTitles().map { $0.id }
            let effectiveNormalTitles = normalTitles.isEmpty ? ["normal"] : normalTitles
            let normalOptions: [String?] = effectiveNormalTitles.map { Optional($0) }

            let superRareTitles: [String]
            if selectedCreationType == .basicOnly {
                superRareTitles = []
            } else {
                superRareTitles = try await masterDataService.getAllSuperRareTitles().map { $0.id }
            }

            let gemItems: [ItemDefinition]
            if selectedCreationType == .withGemModification {
                gemItems = allItems.filter { $0.category.lowercased().contains("gem") }
            } else {
                gemItems = []
            }

            let estimatedTotal = estimateTotalCount(itemCount: allItems.count,
                                                    normalCount: normalOptions.count,
                                                    superRareCount: superRareTitles.count,
                                                    gemCount: gemItems.count)
            let targetLimit = max(1, maxItemLimit)
            let targetCount = estimatedTotal > 0 ? min(targetLimit, estimatedTotal) : targetLimit

        debugLog("[DebugMenu] itemCount=\(allItems.count), normalOptions=\(normalOptions.count), superRare=\(superRareTitles.count), gems=\(gemItems.count), estimate=\(estimatedTotal), limit=\(targetLimit), target=\(targetCount)")

            await MainActor.run {
                statusMessage = "アイテム作成開始 - \(selectedCreationType.rawValue)\n予定種類: \(targetCount) (設定上限 \(targetLimit))"
            }

            try await ensureStorageCapacity()

            let batchSize = 10_000
            var pendingSeeds: [ItemSeed] = []
            pendingSeeds.reserveCapacity(batchSize)
            var createdCount = 0

            let itemCount = allItems.count
            let baseQuota = itemCount > 0 ? targetCount / itemCount : 0
            let quotaRemainder = itemCount > 0 ? targetCount % itemCount : 0
            let itemQuotas: [Int] = allItems.enumerated().map { index, _ in
                baseQuota + (index < quotaRemainder ? 1 : 0)
            }

            outer: for (index, item) in allItems.enumerated() {
                try Task.checkCancellation()
                await MainActor.run {
                    statusMessage = "\(item.name) (\(index + 1)/\(allItems.count)) を生成中"
                }

                var remainingForItem = itemQuotas[index]
                guard remainingForItem > 0 else { continue }

                func appendSeed(normal: String?, superRare: String? = nil, gem: String? = nil) async throws -> Bool {
                    guard remainingForItem > 0 else { return true }
                    if createdCount + pendingSeeds.count >= targetCount { return true }
                    pendingSeeds.append(ItemSeed(itemId: item.id,
                                                 enhancement: .init(normalTitleId: normal,
                                                                    superRareTitleId: superRare,
                                                                    socketKey: gem)))
                    remainingForItem -= 1
                    if pendingSeeds.count >= batchSize || createdCount + pendingSeeds.count >= targetCount {
                        try await flushSeeds(&pendingSeeds,
                                             createdCount: &createdCount,
                                             totalCount: targetCount,
                                             batchSize: batchSize)
                    }
                    return remainingForItem == 0 || createdCount >= targetCount
                }

                for normal in normalOptions {
                    if try await appendSeed(normal: normal) { break }
                }
                if createdCount >= targetCount { break }
                if remainingForItem <= 0 { continue }

                if selectedCreationType != .basicOnly {
                    superLoop: for superRare in superRareTitles {
                        for normal in normalOptions {
                            if try await appendSeed(normal: normal, superRare: superRare) {
                                break superLoop
                            }
                        }
                        if createdCount >= targetCount || remainingForItem <= 0 { break }
                    }
                }
                if createdCount >= targetCount { break }
                if remainingForItem <= 0 { continue }

                if selectedCreationType == .withGemModification {
                    gemLoop: for gem in gemItems {
                        for normal in normalOptions {
                            if try await appendSeed(normal: normal, gem: gem.id) {
                                break gemLoop
                            }
                        }
                        if createdCount >= targetCount || remainingForItem <= 0 { break }
                        if selectedCreationType != .basicOnly {
                            for superRare in superRareTitles {
                                for normal in normalOptions {
                                    if try await appendSeed(normal: normal,
                                                            superRare: superRare,
                                                            gem: gem.id) {
                                        break gemLoop
                                    }
                                }
                                if createdCount >= targetCount || remainingForItem <= 0 { break }
                            }
                        }
                        if createdCount >= targetCount || remainingForItem <= 0 { break }
                    }
                }

                if createdCount >= targetCount { break }
            }

            if !pendingSeeds.isEmpty {
                try await flushSeeds(&pendingSeeds,
                                     createdCount: &createdCount,
                                     totalCount: targetCount,
                                     batchSize: batchSize)
                debugLog("[DebugMenu] final flush, total=\(createdCount)")
            }

            await MainActor.run {
                creationProgress = 1.0
                statusMessage = "生成が完了しました"
                alertMessage = "アイテム生成が完了しました (\(createdCount)種類)"
                showAlert = true
            }
        } catch {
            debugLog("[DebugMenu] creation error=\(error)")
            await MainActor.run {
                statusMessage = "エラー: \(error.localizedDescription)"
                alertMessage = "アイテム生成に失敗しました"
                showAlert = true
            }
        }

        await MainActor.run { isCreatingItems = false }
    }

    private func deleteAllItems() async {
        await MainActor.run {
            alertMessage = "デバッグ用の全削除機能は無効化しました。\n再インストールで対応してください。"
            showAlert = true
        }
    }

    private func purgeCloudKitAndReset() async {
        if isPurgingCloudKit { return }
        await MainActor.run {
            isPurgingCloudKit = true
            purgeStatus = "CloudKitのデータを削除中…"
        }

        do {
            try await progressService.resetAllProgressIncludingCloudKit()
            await MainActor.run {
                alertMessage = "CloudKitとローカルの進行データを初期化しました"
                showAlert = true
                purgeStatus = "初期化が完了しました"
            }
        } catch {
            await MainActor.run {
                alertMessage = "進行データの初期化に失敗しました"
                purgeStatus = error.localizedDescription
                showAlert = true
            }
        }

        await MainActor.run { isPurgingCloudKit = false }
    }

    private func estimateTotalCount(itemCount: Int,
                                    normalCount: Int,
                                    superRareCount: Int,
                                    gemCount: Int) -> Int {
        let normalCombinations = max(1, normalCount)
        switch selectedCreationType {
        case .basicOnly:
            return itemCount * normalCombinations
        case .withSuperRare:
            let base = itemCount * normalCombinations
            let superRare = itemCount * normalCombinations * superRareCount
            return base + superRare
        case .withGemModification:
            let base = itemCount * normalCombinations
            let superRare = itemCount * normalCombinations * superRareCount
            let gemOnly = itemCount * normalCombinations * gemCount
            let gemSuper = itemCount * normalCombinations * gemCount * superRareCount
            return base + superRare + gemOnly + gemSuper
        }
    }

    private func flushSeeds(_ seeds: inout [ItemSeed],
                            createdCount: inout Int,
                            totalCount: Int,
                            batchSize: Int) async throws {
        guard !seeds.isEmpty else { return }
        debugLog("[DebugMenu] flushSeeds begin createdCount=\(createdCount) seeds=\(seeds.count)")
        try await saveBatch(seeds, chunkSize: batchSize)
        debugLog("[DebugMenu] flushSeeds after save createdCount=\(createdCount)")
        createdCount += seeds.count
        debugLog("[DebugMenu] flushSeeds after increment createdCount=\(createdCount)")
        await updateProgress(current: createdCount,
                             total: totalCount,
                             message: "保存済み: \(createdCount)/\(totalCount)")
        debugLog("[DebugMenu] saveBatch count=\(seeds.count), cumulative=\(createdCount)/\(totalCount)")
        seeds.removeAll(keepingCapacity: true)
    }

    private func saveBatch(_ seeds: [ItemSeed], chunkSize: Int) async throws {
        guard !seeds.isEmpty else { return }
        let batchSeeds = seeds.map { seed in
            InventoryProgressService.BatchSeed(itemId: seed.itemId,
                                               quantity: 99,
                                               storage: .playerItem,
                                               enhancements: seed.enhancement)
        }
        try await inventoryService.addItems(batchSeeds, chunkSize: chunkSize)
    }

    private func updateProgress(current: Int, total: Int, message: String) async {
        await MainActor.run {
            let denominator = max(total, max(current, 1))
            creationProgress = Double(current) / Double(denominator)
            statusMessage = message
        }
    }

    private func ensureStorageCapacity() async throws {
        _ = try await playerService.loadCurrentPlayer()
    }
}

struct ItemCreationSettingsView: View {
    @Binding var selectedType: ItemCreationType
    @Binding var maxLimit: Int

    @Environment(\.dismiss) private var dismiss

    private let limitPresets = [1_000, 5_000, 10_000, 50_000, 100_000]

    var body: some View {
        NavigationView {
            Form {
                Section("作成タイプ") {
                    ForEach(ItemCreationType.allCases, id: \.self) { type in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(type.rawValue)
                                    .font(.body)
                                Text(type.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selectedType == type {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.primary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedType = type
                        }
                    }
                }

                Section("作成上限種類数") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("現在の上限: \(maxLimit)種類")
                            .font(.headline)

                        Text("プリセット")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(limitPresets, id: \.self) { limit in
                                Button("\(limit)") {
                                    maxLimit = limit
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.primary)
                                .background(maxLimit == limit ? Color.accentColor : Color.clear)
                                .cornerRadius(8)
                            }
                        }

                        HStack {
                            Text("カスタム:")
                            TextField("種類数", value: $maxLimit, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .avoidBottomGameInfo()
            .navigationTitle("アイテム作成設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }

}
#endif
