import SwiftUI

enum DropNotificationMode: String, CaseIterable {
    case bulk = "一気に表示"
    case sequential = "1つずつ表示"
}

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

/// アイテムカテゴリの定義
enum ItemCategory: String, CaseIterable, Identifiable {
    case thin_sword = "thin_sword"
    case sword = "sword"
    case katana = "katana"
    case bow = "bow"
    case rod = "rod"
    case wand = "wand"
    case grimoire = "grimoire"
    case gauntlet = "gauntlet"
    case shield = "shield"
    case armor = "armor"
    case heavy_armor = "heavy_armor"
    case super_heavy_armor = "super_heavy_armor"
    case robe = "robe"
    case accessory = "accessory"
    case gem = "gem"
    case synthesis = "synthesis"
    case race_specific = "race_specific"
    case magic_sword = "magic_sword"
    case advanced_magic_sword = "advanced_magic_sword"
    case guardian_sword = "guardian_sword"
    case homunculus = "homunculus"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thin_sword: return "細剣"
        case .sword: return "剣"
        case .katana: return "刀"
        case .bow: return "弓"
        case .rod: return "杖"
        case .wand: return "短杖"
        case .grimoire: return "魔導書"
        case .gauntlet: return "籠手"
        case .shield: return "盾"
        case .armor: return "鎧"
        case .heavy_armor: return "重鎧"
        case .super_heavy_armor: return "超重鎧"
        case .robe: return "ローブ"
        case .accessory: return "装飾品"
        case .gem: return "宝石"
        case .synthesis: return "合成素材"
        case .race_specific: return "種族専用"
        case .magic_sword: return "魔剣"
        case .advanced_magic_sword: return "上級魔剣"
        case .guardian_sword: return "守護剣"
        case .homunculus: return "ホムンクルス"
        }
    }
}

private struct ItemSeed {
    let itemId: UInt16
    let enhancement: ItemSnapshot.Enhancement
}

struct DebugMenuView: View {
    @Environment(AppServices.self) private var appServices
    @State private var isCreatingItems = false
    @State private var creationProgress: Double = 0.0
    @State private var statusMessage = ""
    @State private var showAlert = false
    @State private var alertMessage = ""

    @State private var selectedCreationType: ItemCreationType = .basicOnly
    @State private var maxItemLimit: Int = 50_000
    @State private var showCreationSettings = false

    // カテゴリ選択（全選択がデフォルト）
    @State private var selectedCategories: Set<ItemCategory> = Set(ItemCategory.allCases)
    // 通常称号選択（0-8）
    @State private var selectedNormalTitleIds: Set<UInt8> = Set(0...8)
    // 超レア称号選択（1-100）
    @State private var selectedSuperRareTitleIds: Set<UInt8> = Set(1...100)

    // ドロップ通知テスト
    @State private var dropNotificationCount: Int = 5
    @State private var superRareRate: Double = 0.1
    @State private var dropNotificationMode: DropNotificationMode = .bulk
    @State private var isSendingDropNotifications = false

    // データ削除（別画面に移動したため削除）

    private var masterData: MasterDataCache { appServices.masterDataCache }
    private var inventoryService: InventoryProgressService { appServices.inventory }
    private var gameStateService: GameStateService { appServices.gameState }

    private func debugLog(_ message: @autoclosure () -> String) {
        print(message())
    }

    var body: some View {
        NavigationStack {
            Form {
                itemCreationSection
                dropNotificationTestSection
                dataResetSection
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
                ItemCreationSettingsView(
                    selectedType: $selectedCreationType,
                    maxLimit: $maxItemLimit,
                    selectedCategories: $selectedCategories,
                    selectedNormalTitleIds: $selectedNormalTitleIds,
                    selectedSuperRareTitleIds: $selectedSuperRareTitleIds
                )
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
                Text("カテゴリ: \(selectedCategories.count)/\(ItemCategory.allCases.count)種")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("通常称号: \(selectedNormalTitleIds.count)/9種, 超レア: \(selectedSuperRareTitleIds.count)/100種")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dropNotificationTestSection: some View {
        Section("ドロップ通知テスト") {
            Stepper("通知数: \(dropNotificationCount)", value: $dropNotificationCount, in: 1...20)

            VStack(alignment: .leading) {
                Text("超レア出現率: \(Int(superRareRate * 100))%")
                Slider(value: $superRareRate, in: 0...1)
            }

            Picker("表示モード", selection: $dropNotificationMode) {
                ForEach(DropNotificationMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Button("テスト通知を送信") {
                Task { await sendTestDropNotifications() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSendingDropNotifications)
        }
    }

    private var dataResetSection: some View {
        Section("データ操作") {
            NavigationLink {
                DangerousOperationsView()
            } label: {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("危険な操作")
                }
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
            // 選択されたカテゴリのrawValueセット
            let selectedCategoryRawValues = Set(selectedCategories.map { $0.rawValue })

            // カテゴリ優先順位（選択されたもののみ）
            let categoryPriority: [String: Int] = Dictionary(
                uniqueKeysWithValues: ItemCategory.allCases.enumerated().map { ($1.rawValue, $0) }
            )

            let allItems = masterData.allItems
                .filter { selectedCategoryRawValues.contains(ItemSaleCategory(rawValue: $0.category)?.identifier ?? "") }
                .sorted { lhs, rhs in
                    let lhsId = ItemSaleCategory(rawValue: lhs.category)?.identifier ?? ""
                    let rhsId = ItemSaleCategory(rawValue: rhs.category)?.identifier ?? ""
                    let lhsPriority = categoryPriority[lhsId] ?? Int.max
                    let rhsPriority = categoryPriority[rhsId] ?? Int.max
                    if lhsPriority != rhsPriority {
                        return lhsPriority < rhsPriority
                    }
                    return lhs.name < rhs.name
                }

            // 選択された通常称号のみ
            let normalOptions: [UInt8] = selectedNormalTitleIds.isEmpty
                ? [0]
                : selectedNormalTitleIds.sorted()

            // 選択された超レア称号のみ（basicOnly時は空）
            let superRareTitleIds: [UInt8]
            if selectedCreationType == .basicOnly {
                superRareTitleIds = []
            } else {
                superRareTitleIds = selectedSuperRareTitleIds.sorted()
            }

            let gemItems: [ItemDefinition]
            if selectedCreationType == .withGemModification {
                gemItems = allItems.filter { $0.category == ItemSaleCategory.gem.rawValue }
            } else {
                gemItems = []
            }

            let estimatedTotal = estimateTotalCount(itemCount: allItems.count,
                                                    normalCount: normalOptions.count,
                                                    superRareCount: superRareTitleIds.count,
                                                    gemCount: gemItems.count)
            let targetLimit = max(1, maxItemLimit)
            let targetCount = estimatedTotal > 0 ? min(targetLimit, estimatedTotal) : targetLimit

        debugLog("[DebugMenu] itemCount=\(allItems.count), normalOptions=\(normalOptions.count), superRare=\(superRareTitleIds.count), gems=\(gemItems.count), estimate=\(estimatedTotal), limit=\(targetLimit), target=\(targetCount)")

            await MainActor.run {
                statusMessage = "アイテム作成開始 - \(selectedCreationType.rawValue)\n予定種類: \(targetCount) (設定上限 \(targetLimit))"
            }

            try await ensureStorageCapacity()

            let batchSize = 50_000
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

                func appendSeed(normalTitleId: UInt8, superRareTitleId: UInt8 = 0, gemItemId: UInt16 = 0) async throws -> Bool {
                    guard remainingForItem > 0 else { return true }
                    if createdCount + pendingSeeds.count >= targetCount { return true }
                    pendingSeeds.append(ItemSeed(itemId: item.id,
                                                 enhancement: .init(superRareTitleId: superRareTitleId,
                                                                    normalTitleId: normalTitleId,
                                                                    socketSuperRareTitleId: 0,
                                                                    socketNormalTitleId: 0,
                                                                    socketItemId: gemItemId)))
                    remainingForItem -= 1
                    if pendingSeeds.count >= batchSize || createdCount + pendingSeeds.count >= targetCount {
                        try await flushSeeds(&pendingSeeds,
                                             createdCount: &createdCount,
                                             totalCount: targetCount,
                                             batchSize: batchSize)
                    }
                    return remainingForItem == 0 || createdCount >= targetCount
                }

                for normalId in normalOptions {
                    if try await appendSeed(normalTitleId: normalId) { break }
                }
                if createdCount >= targetCount { break }
                if remainingForItem <= 0 { continue }

                if selectedCreationType != .basicOnly {
                    superLoop: for superRareId in superRareTitleIds {
                        for normalId in normalOptions {
                            if try await appendSeed(normalTitleId: normalId, superRareTitleId: superRareId) {
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
                        for normalId in normalOptions {
                            if try await appendSeed(normalTitleId: normalId, gemItemId: gem.id) {
                                break gemLoop
                            }
                        }
                        if createdCount >= targetCount || remainingForItem <= 0 { break }
                        if selectedCreationType != .basicOnly {
                            for superRareId in superRareTitleIds {
                                for normalId in normalOptions {
                                    if try await appendSeed(normalTitleId: normalId,
                                                            superRareTitleId: superRareId,
                                                            gemItemId: gem.id) {
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
        // デバッグ用高速INSERT（既存チェックなし）
        try await inventoryService.addItemsUnchecked(batchSeeds, chunkSize: chunkSize)
    }

    private func updateProgress(current: Int, total: Int, message: String) async {
        await MainActor.run {
            let denominator = max(total, max(current, 1))
            creationProgress = Double(current) / Double(denominator)
            statusMessage = message
        }
    }

    private func ensureStorageCapacity() async throws {
        _ = try await gameStateService.loadCurrentPlayer()
    }

    private func sendTestDropNotifications() async {
        if isSendingDropNotifications { return }
        await MainActor.run { isSendingDropNotifications = true }
        defer { Task { @MainActor in isSendingDropNotifications = false } }

        do {
            let allItems = masterData.allItems
            guard !allItems.isEmpty else {
                debugLog("[DebugMenu] No items found for drop notification test")
                return
            }

            let allSuperRareTitles = masterData.allSuperRareTitles
            let superRareCount = max(1, allSuperRareTitles.count)

            switch dropNotificationMode {
            case .bulk:
                var dropResults: [ItemDropResult] = []
                for _ in 0..<dropNotificationCount {
                    dropResults.append(makeRandomDropResult(allItems: allItems, superRareCount: superRareCount))
                }
                appServices.dropNotifications.publish(results: dropResults)
                debugLog("[DebugMenu] Sent \(dropResults.count) test drop notifications (bulk)")

            case .sequential:
                for i in 0..<dropNotificationCount {
                    let result = makeRandomDropResult(allItems: allItems, superRareCount: superRareCount)
                    appServices.dropNotifications.publish(results: [result])
                    debugLog("[DebugMenu] Sent test drop notification \(i + 1)/\(dropNotificationCount)")
                    if i < dropNotificationCount - 1 {
                        try await Task.sleep(for: .milliseconds(500))
                    }
                }
            }
        } catch {
            debugLog("[DebugMenu] Drop notification test error: \(error)")
        }
    }

    private func makeRandomDropResult(allItems: [ItemDefinition], superRareCount: Int) -> ItemDropResult {
        let randomItem = allItems.randomElement()!
        let normalTitleId: UInt8 = UInt8.random(in: 0...8)
        let isSuperRare = Double.random(in: 0...1) < superRareRate
        let superRareTitleId: UInt8? = isSuperRare ? UInt8.random(in: 1...UInt8(min(100, superRareCount))) : nil

        return ItemDropResult(
            item: randomItem,
            quantity: 1,
            sourceEnemyId: nil,
            normalTitleId: normalTitleId,
            superRareTitleId: superRareTitleId
        )
    }
}

struct ItemCreationSettingsView: View {
    @Binding var selectedType: ItemCreationType
    @Binding var maxLimit: Int
    @Binding var selectedCategories: Set<ItemCategory>
    @Binding var selectedNormalTitleIds: Set<UInt8>
    @Binding var selectedSuperRareTitleIds: Set<UInt8>

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

                categorySelectionSection
                normalTitleSelectionSection
                superRareTitleSelectionSection
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

    private var categorySelectionSection: some View {
        Section {
            HStack {
                Text("選択中: \(selectedCategories.count)/\(ItemCategory.allCases.count)")
                    .font(.subheadline)
                Spacer()
                Button(selectedCategories.count == ItemCategory.allCases.count ? "全解除" : "全選択") {
                    if selectedCategories.count == ItemCategory.allCases.count {
                        selectedCategories.removeAll()
                    } else {
                        selectedCategories = Set(ItemCategory.allCases)
                    }
                }
                .font(.caption)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                ForEach(ItemCategory.allCases) { category in
                    Button {
                        if selectedCategories.contains(category) {
                            selectedCategories.remove(category)
                        } else {
                            selectedCategories.insert(category)
                        }
                    } label: {
                        Text(category.displayName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .background(selectedCategories.contains(category) ? Color.accentColor : Color.gray.opacity(0.3))
                            .foregroundColor(selectedCategories.contains(category) ? .white : .primary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("カテゴリ選択")
        }
    }

    private var normalTitleSelectionSection: some View {
        Section {
            HStack {
                Text("選択中: \(selectedNormalTitleIds.count)/9")
                    .font(.subheadline)
                Spacer()
                Button(selectedNormalTitleIds.count == 9 ? "全解除" : "全選択") {
                    if selectedNormalTitleIds.count == 9 {
                        selectedNormalTitleIds.removeAll()
                    } else {
                        selectedNormalTitleIds = Set(0...8)
                    }
                }
                .font(.caption)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 50), spacing: 8)], spacing: 8) {
                ForEach(Array(0...8 as ClosedRange<UInt8>), id: \.self) { id in
                    Button {
                        if selectedNormalTitleIds.contains(id) {
                            selectedNormalTitleIds.remove(id)
                        } else {
                            selectedNormalTitleIds.insert(id)
                        }
                    } label: {
                        Text("\(id)")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .background(selectedNormalTitleIds.contains(id) ? Color.accentColor : Color.gray.opacity(0.3))
                            .foregroundColor(selectedNormalTitleIds.contains(id) ? .white : .primary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("通常称号選択")
        }
    }

    private var superRareTitleSelectionSection: some View {
        Section {
            HStack {
                Text("選択中: \(selectedSuperRareTitleIds.count)/100")
                    .font(.subheadline)
                Spacer()
                Button(selectedSuperRareTitleIds.count == 100 ? "全解除" : "全選択") {
                    if selectedSuperRareTitleIds.count == 100 {
                        selectedSuperRareTitleIds.removeAll()
                    } else {
                        selectedSuperRareTitleIds = Set(1...100)
                    }
                }
                .font(.caption)
            }

            Text("ID範囲で選択:")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach([("1-25", 1...25), ("26-50", 26...50), ("51-75", 51...75), ("76-100", 76...100)], id: \.0) { label, range in
                    Button(label) {
                        let rangeSet = Set(range.map { UInt8($0) })
                        if rangeSet.isSubset(of: selectedSuperRareTitleIds) {
                            selectedSuperRareTitleIds.subtract(rangeSet)
                        } else {
                            selectedSuperRareTitleIds.formUnion(rangeSet)
                        }
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                }
            }
        } header: {
            Text("超レア称号選択")
        } footer: {
            Text("超レア称号は「基本＋超レア称号」以上のモード時のみ使用されます")
                .font(.caption2)
        }
    }

}

// MARK: - 危険な操作画面

struct DangerousOperationsView: View {
    @Environment(AppServices.self) private var appServices
    @State private var isResettingData = false
    @State private var isUnequippingAll = false
    @State private var showResetConfirmAlert = false
    @State private var showResetCompleteAlert = false
    @State private var showUnequipCompleteAlert = false
    @State private var unequipResultMessage = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        Form {
            equipmentRecoverySection

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                            .foregroundStyle(.red)
                        Text("警告")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.red)
                    }

                    Text("この操作は取り消せません。\n全ての進行データ（キャラクター、アイテム、進行状況など）が完全に削除されます。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section {
                if isResettingData {
                    HStack {
                        ProgressView()
                        Text("削除中...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button(role: .destructive) {
                        showResetConfirmAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("進行データを完全に削除")
                        }
                    }
                }
            } footer: {
                Text("削除後はアプリの再起動が必要です")
                    .font(.caption2)
            }
        }
        .navigationTitle("危険な操作")
        .navigationBarTitleDisplayMode(.inline)
        .alert("本当に削除しますか？", isPresented: $showResetConfirmAlert) {
            Button("キャンセル", role: .cancel) { }
            Button("削除する", role: .destructive) {
                Task { await resetAllData() }
            }
        } message: {
            Text("全ての進行データが完全に削除されます。\nこの操作は取り消せません。")
        }
        .alert("データ削除完了", isPresented: $showResetCompleteAlert) {
            Button("OK") { }
        } message: {
            Text("進行データを削除しました。\nアプリを再起動してください。")
        }
        .alert("エラー", isPresented: $showErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("装備解除完了", isPresented: $showUnequipCompleteAlert) {
            Button("OK") { }
        } message: {
            Text(unequipResultMessage)
        }
    }

    private var equipmentRecoverySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("装備バグ復旧")
                    .font(.headline)
                Text("全キャラクターの装備を外してインベントリに戻します。転職バグで装備が外せなくなった場合の復旧用です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            if isUnequippingAll {
                HStack {
                    ProgressView()
                    Text("処理中...")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await unequipAllCharacters() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.uturn.backward.circle")
                        Text("全キャラクターの装備を外す")
                    }
                }
            }
        } header: {
            Text("復旧操作")
        }
    }

    private func unequipAllCharacters() async {
        if isUnequippingAll { return }
        await MainActor.run { isUnequippingAll = true }

        do {
            let characters = try await appServices.character.allCharacters()
            var unequippedCount = 0
            var totalItemCount = 0

            for character in characters {
                let equipped = try await appServices.character.equippedItems(characterId: character.id)
                if !equipped.isEmpty {
                    for item in equipped {
                        _ = try await appServices.character.unequipItem(
                            characterId: character.id,
                            equipmentStackKey: item.stackKey,
                            quantity: item.quantity
                        )
                        totalItemCount += item.quantity
                    }
                    unequippedCount += 1
                }
            }

            // インベントリキャッシュをリロード
            try await appServices.itemPreload.reload(inventoryService: appServices.inventory)

            await MainActor.run {
                isUnequippingAll = false
                unequipResultMessage = "\(unequippedCount)人のキャラクターから\(totalItemCount)個の装備を外しました"
                showUnequipCompleteAlert = true
            }
        } catch {
            await MainActor.run {
                isUnequippingAll = false
                errorMessage = "装備解除に失敗しました: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }

    private func resetAllData() async {
        if isResettingData { return }
        await MainActor.run { isResettingData = true }

        do {
            try await appServices.resetAllProgress()
            await MainActor.run {
                isResettingData = false
                showResetCompleteAlert = true
            }
        } catch {
            await MainActor.run {
                isResettingData = false
                errorMessage = "データ削除に失敗しました: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }
}
