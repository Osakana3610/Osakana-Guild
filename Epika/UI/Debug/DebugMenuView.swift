// ==============================================================================
// DebugMenuView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 開発用デバッグ機能の提供
//   - アイテム大量生成機能
//   - キャラクター大量生成機能
//   - ドロップ通知テスト機能
//   - データリセット・復旧機能
//
// 【View構成】
//   - アイテム作成セクション（種類・上限・カテゴリ・称号選択）
//   - キャラクター作成セクション（種族・職業・レベル・作成数）
//   - ドロップ通知テストセクション（通知数・超レア率・表示モード）
//   - データ操作セクション（危険な操作画面への遷移）
//
// 【使用箇所】
//   - SettingsView（ベータテスト用機能）
//
// ==============================================================================

import SwiftUI
import SwiftData

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
    let enhancement: ItemEnhancement
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

    // キャラクター作成
    @State private var isCreatingCharacters = false
    @State private var characterCreationProgress: Double = 0.0
    @State private var characterStatusMessage = ""
    @State private var showCharacterCreationSettings = false
    @State private var characterCount: Int = 10
    @State private var characterLevel: Int = 50
    @State private var selectedRaceId: UInt8? = nil  // nil = ランダム
    @State private var selectedJobId: UInt8? = nil   // nil = ランダム
    @State private var selectedPreviousJobId: UInt8? = nil  // nil = なし、0 = ランダム

    // ドロップ通知テスト
    @State private var dropNotificationCount: Int = 5
    @State private var superRareRate: Double = 0.1
    @State private var dropNotificationMode: DropNotificationMode = .bulk
    @State private var isSendingDropNotifications = false

    // データ削除（別画面に移動したため削除）

    private var masterData: MasterDataCache { appServices.masterDataCache }
    private var inventoryService: InventoryProgressService { appServices.inventory }
    private var gameStateService: GameStateService { appServices.gameState }
    private var characterService: CharacterProgressService { appServices.character }

    private func debugLog(_ message: @autoclosure () -> String) {
        print(message())
    }

    var body: some View {
        NavigationStack {
            Form {
                itemCreationSection
                characterCreationSection
                dropNotificationTestSection
                dataResetSection
            }
            .avoidBottomGameInfo()
            .navigationTitle("ベータテスト用機能")
            .navigationBarTitleDisplayMode(.inline)
            .alert("完了", isPresented: $showAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
#if DEBUG
            .sheet(isPresented: $showCreationSettings) {
                ItemCreationSettingsView(
                    selectedType: $selectedCreationType,
                    maxLimit: $maxItemLimit,
                    selectedCategories: $selectedCategories,
                    selectedNormalTitleIds: $selectedNormalTitleIds,
                    selectedSuperRareTitleIds: $selectedSuperRareTitleIds
                )
            }
#endif
            .sheet(isPresented: $showCharacterCreationSettings) {
                CharacterCreationDebugSettingsView(
                    masterData: masterData,
                    count: $characterCount,
                    level: $characterLevel,
                    selectedRaceId: $selectedRaceId,
                    selectedJobId: $selectedJobId,
                    selectedPreviousJobId: $selectedPreviousJobId
                )
            }
        }
    }

#if DEBUG
    @ViewBuilder
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
#else
    @ViewBuilder
    private var itemCreationSection: some View {
        EmptyView()
    }
#endif

    private var characterCreationSection: some View {
        Section("キャラクター作成") {
            if isCreatingCharacters {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: characterCreationProgress)
                    Text(characterStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 12) {
                    Button("キャラクター作成設定") { showCharacterCreationSettings = true }
                        .buttonStyle(.bordered)

                    Button("キャラクターを作成開始") {
                        Task { await createCharacters() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("作成数: \(characterCount)体, Lv.\(characterLevel)")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("種族: \(raceDisplayName), 職業: \(jobDisplayName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("転職後: \(previousJobDisplayName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var raceDisplayName: String {
        if let raceId = selectedRaceId {
            return masterData.race(raceId)?.name ?? "ID:\(raceId)"
        }
        return "ランダム"
    }

    private var jobDisplayName: String {
        if let jobId = selectedJobId {
            return masterData.job(jobId)?.name ?? "ID:\(jobId)"
        }
        return "ランダム"
    }

    private var previousJobDisplayName: String {
        guard let prevJobId = selectedPreviousJobId else { return "なし" }
        if prevJobId == 0 { return "ランダム" }
        return masterData.job(prevJobId)?.name ?? "ID:\(prevJobId)"
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

    private func createCharacters() async {
        if isCreatingCharacters { return }
        await MainActor.run {
            isCreatingCharacters = true
            characterCreationProgress = 0.0
            characterStatusMessage = "キャラクター作成準備中..."
        }

        do {
            let allRaces = masterData.allRaces
            let allJobs = masterData.allJobs.filter { $0.id <= 16 }  // 基本職のみ

            guard !allRaces.isEmpty, !allJobs.isEmpty else {
                throw ProgressError.invalidInput(description: "種族または職業のマスターデータがありません")
            }

            var requests: [CharacterProgressService.DebugCharacterCreationRequest] = []

            for i in 0..<characterCount {
                // 種族決定
                let raceId: UInt8
                if let selected = selectedRaceId {
                    raceId = selected
                } else {
                    raceId = allRaces.randomElement()!.id
                }

                // 職業決定（転職後の職業が指定されている場合は前職になる）
                let baseJobId: UInt8
                if let selected = selectedJobId {
                    baseJobId = selected
                } else {
                    baseJobId = allJobs.randomElement()!.id
                }

                // 転職後職業決定
                let jobId: UInt8
                let previousJobId: UInt8
                if let selected = selectedPreviousJobId {
                    if selected == 0 {
                        // ランダム（baseJob以外を現職に）
                        let candidates = allJobs.filter { $0.id != baseJobId }
                        jobId = candidates.randomElement()?.id ?? baseJobId
                        previousJobId = baseJobId
                    } else {
                        // 指定された職業を現職に、baseJobを前職に
                        jobId = selected
                        previousJobId = baseJobId
                    }
                } else {
                    // 転職なし
                    jobId = baseJobId
                    previousJobId = 0
                }

                let name = "デバッグ\(i + 1)"
                requests.append(.init(
                    displayName: name,
                    raceId: raceId,
                    jobId: jobId,
                    previousJobId: previousJobId,
                    level: characterLevel
                ))
            }

            await MainActor.run {
                characterStatusMessage = "キャラクターを作成中..."
            }

            let createdCount = try await characterService.createCharactersBatch(requests) { current, total in
                await MainActor.run {
                    characterCreationProgress = Double(current) / Double(total)
                    characterStatusMessage = "作成中: \(current)/\(total)"
                }
            }

            await MainActor.run {
                characterCreationProgress = 1.0
                characterStatusMessage = "完了"
                alertMessage = "キャラクター作成が完了しました (\(createdCount)体)"
                showAlert = true
            }
        } catch {
            debugLog("[DebugMenu] character creation error=\(error)")
            await MainActor.run {
                characterStatusMessage = "エラー: \(error.localizedDescription)"
                alertMessage = "キャラクター作成に失敗しました"
                showAlert = true
            }
        }

        await MainActor.run { isCreatingCharacters = false }
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
    @State private var isPurgingExplorationLogs = false
    @State private var showPurgeExplorationLogsConfirmAlert = false
    @State private var showPurgeExplorationLogsCompleteAlert = false
    @State private var purgeExplorationLogsResultMessage = ""

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
        .alert("探索ログを削除しますか？", isPresented: $showPurgeExplorationLogsConfirmAlert) {
            Button("キャンセル", role: .cancel) { }
            Button("削除する", role: .destructive) {
                Task { await purgeExplorationLogs() }
            }
        } message: {
            Text("全ての探索履歴が削除されます。キャラクターやアイテムなどの進行データには影響しません。")
        }
        .alert("探索ログ削除完了", isPresented: $showPurgeExplorationLogsCompleteAlert) {
            Button("OK") { }
        } message: {
            Text(purgeExplorationLogsResultMessage)
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

            VStack(alignment: .leading, spacing: 8) {
                Text("探索ログ削除")
                    .font(.headline)
                Text("全ての探索履歴を削除します。冒険タブでログが表示されない問題の復旧用です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            if isPurgingExplorationLogs {
                HStack {
                    ProgressView()
                    Text("削除中...")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    showPurgeExplorationLogsConfirmAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash.circle")
                        Text("探索ログを削除")
                    }
                }
            }
        } header: {
            Text("復旧操作")
        }
    }

    /// 装備バグ復旧用：全キャラクターの装備を直接DBから解除
    /// 通常のunequipItemはRuntimeCharacterFactory経由で装備枠チェックが入るため、
    /// 装備枠を超過した状態では使用できない。この処理は直接DBを操作してバイパスする。
    private func unequipAllCharacters() async {
        if isUnequippingAll { return }
        await MainActor.run { isUnequippingAll = true }

        do {
            let context = ModelContext(appServices.container)
            context.autosaveEnabled = false

            // 全キャラクターの装備を取得
            let allEquipment = try context.fetch(FetchDescriptor<CharacterEquipmentRecord>())
            guard !allEquipment.isEmpty else {
                await MainActor.run {
                    isUnequippingAll = false
                    unequipResultMessage = "解除する装備がありませんでした"
                    showUnequipCompleteAlert = true
                }
                return
            }

            // インベントリを取得
            let storage = ItemStorage.playerItem
            let storageTypeValue = storage.rawValue
            let allInventory = try context.fetch(FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
                $0.storageType == storageTypeValue
            }))

            // stackKeyでグループ化
            var groupedEquipment: [String: [CharacterEquipmentRecord]] = [:]
            for equip in allEquipment {
                groupedEquipment[equip.stackKey, default: []].append(equip)
            }

            // 装備を持っていたキャラクター数をカウント
            let characterIds = Set(allEquipment.map(\.characterId))
            let unequippedCount = characterIds.count
            let totalItemCount = allEquipment.count

            // 各グループをインベントリに戻す
            for (stackKey, equipments) in groupedEquipment {
                let quantity = equipments.count

                if let existingInventory = allInventory.first(where: { $0.stackKey == stackKey }) {
                    existingInventory.quantity = min(existingInventory.quantity + UInt16(quantity), 99)
                } else if let firstEquip = equipments.first {
                    let inventoryRecord = InventoryItemRecord(
                        superRareTitleId: firstEquip.superRareTitleId,
                        normalTitleId: firstEquip.normalTitleId,
                        itemId: firstEquip.itemId,
                        socketSuperRareTitleId: firstEquip.socketSuperRareTitleId,
                        socketNormalTitleId: firstEquip.socketNormalTitleId,
                        socketItemId: firstEquip.socketItemId,
                        quantity: UInt16(quantity),
                        storage: storage
                    )
                    context.insert(inventoryRecord)
                }

                // 装備レコードを削除
                for equip in equipments {
                    context.delete(equip)
                }
            }

            try context.save()

            // 通知を送信
            NotificationCenter.default.post(name: .characterProgressDidChange, object: nil)

            // インベントリキャッシュをリロードしてUI更新
            try await MainActor.run {
                try appServices.userDataLoad.reloadItems()
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

    /// 探索ログ削除：ExplorationRunRecordとExplorationEventRecordを明示的に全削除
    private func purgeExplorationLogs() async {
        if isPurgingExplorationLogs { return }
        await MainActor.run { isPurgingExplorationLogs = true }

        do {
            let context = ModelContext(appServices.container)
            context.autosaveEnabled = false

            // ExplorationEventRecordを先に全取得・削除（cascade削除に頼らない）
            let allEvents = try context.fetch(FetchDescriptor<ExplorationEventRecord>())
            let eventCount = allEvents.count
            for event in allEvents {
                context.delete(event)
            }

            // ExplorationRunRecordを全取得・削除
            let allRuns = try context.fetch(FetchDescriptor<ExplorationRunRecord>())
            let runCount = allRuns.count
            for run in allRuns {
                context.delete(run)
            }

            try context.save()

            await MainActor.run {
                isPurgingExplorationLogs = false
                purgeExplorationLogsResultMessage = "探索ログを削除しました（\(runCount)件の探索、\(eventCount)件のイベント）"
                showPurgeExplorationLogsCompleteAlert = true
            }
        } catch {
            await MainActor.run {
                isPurgingExplorationLogs = false
                errorMessage = "探索ログの削除に失敗しました: \(error.localizedDescription)"
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

// MARK: - キャラクター作成設定画面

struct CharacterCreationDebugSettingsView: View {
    let masterData: MasterDataCache

    @Binding var count: Int
    @Binding var level: Int
    @Binding var selectedRaceId: UInt8?
    @Binding var selectedJobId: UInt8?
    @Binding var selectedPreviousJobId: UInt8?

    @Environment(\.dismiss) private var dismiss

    private let countPresets = [1, 5, 10, 50, 100, 200]
    private let levelPresets = [1, 10, 25, 50, 100, 200]

    var body: some View {
        NavigationView {
            Form {
                countSection
                levelSection
                raceSection
                jobSection
                previousJobSection
            }
            .avoidBottomGameInfo()
            .navigationTitle("キャラクター作成設定")
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

    private var countSection: some View {
        Section("作成数") {
            VStack(alignment: .leading, spacing: 12) {
                Text("現在: \(count)体")
                    .font(.headline)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(countPresets, id: \.self) { preset in
                        Button("\(preset)") {
                            count = preset
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.primary)
                        .background(count == preset ? Color.accentColor : Color.clear)
                        .cornerRadius(8)
                    }
                }

                Stepper("細かく調整: \(count)", value: $count, in: 1...200)
            }
            .padding(.vertical, 8)
        }
    }

    private var levelSection: some View {
        Section("レベル") {
            VStack(alignment: .leading, spacing: 12) {
                Text("現在: Lv.\(level)")
                    .font(.headline)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(levelPresets, id: \.self) { preset in
                        Button("Lv.\(preset)") {
                            level = preset
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.primary)
                        .background(level == preset ? Color.accentColor : Color.clear)
                        .cornerRadius(8)
                    }
                }

                Stepper("細かく調整: Lv.\(level)", value: $level, in: 1...200)
            }
            .padding(.vertical, 8)
        }
    }

    private var raceSection: some View {
        Section {
            Button {
                selectedRaceId = nil
            } label: {
                HStack {
                    Text("ランダム")
                    Spacer()
                    if selectedRaceId == nil {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .foregroundColor(.primary)

            ForEach(masterData.allRaces, id: \.id) { race in
                Button {
                    selectedRaceId = race.id
                } label: {
                    HStack {
                        Text(race.name)
                        Spacer()
                        if selectedRaceId == race.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .foregroundColor(.primary)
            }
        } header: {
            Text("種族")
        }
    }

    private var jobSection: some View {
        Section {
            Button {
                selectedJobId = nil
            } label: {
                HStack {
                    Text("ランダム")
                    Spacer()
                    if selectedJobId == nil {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .foregroundColor(.primary)

            ForEach(masterData.allJobs.filter { $0.id <= 16 }, id: \.id) { job in
                Button {
                    selectedJobId = job.id
                } label: {
                    HStack {
                        Text(job.name)
                        Spacer()
                        if selectedJobId == job.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .foregroundColor(.primary)
            }
        } header: {
            Text("職業")
        }
    }

    private var previousJobSection: some View {
        Section {
            Button {
                selectedPreviousJobId = nil
            } label: {
                HStack {
                    Text("なし（転職しない）")
                    Spacer()
                    if selectedPreviousJobId == nil {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .foregroundColor(.primary)

            Button {
                selectedPreviousJobId = 0
            } label: {
                HStack {
                    Text("ランダム")
                    Spacer()
                    if selectedPreviousJobId == 0 {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .foregroundColor(.primary)

            ForEach(masterData.allJobs.filter { $0.id <= 16 }, id: \.id) { job in
                Button {
                    selectedPreviousJobId = job.id
                } label: {
                    HStack {
                        Text(job.name)
                        Spacer()
                        if selectedPreviousJobId == job.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .foregroundColor(.primary)
            }
        } header: {
            Text("転職後の職業（前職）")
        } footer: {
            Text("「転職後の職業」は現在の職業の前に就いていた職業です。転職済みキャラクターを作成する場合に設定してください。")
                .font(.caption2)
        }
    }
}
