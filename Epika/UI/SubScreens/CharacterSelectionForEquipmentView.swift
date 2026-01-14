// ==============================================================================
// CharacterSelectionForEquipmentView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 装備変更用キャラクター選択
//   - 装備編集画面への遷移
//   - 装備の着脱処理
//
// 【View構成】
//   - CharacterSelectionForEquipmentView: キャラクター選択画面
//   - CharacterRowForEquipment: キャラクター行表示
//   - EquipmentEditorView: 装備編集画面
//     - キャラクターステータス表示
//     - 装備中アイテム一覧
//     - 装備候補アイテム一覧（サブカテゴリ別）
//
// 【使用箇所】
//   - ShopView: ショップ画面から遷移
//
// ==============================================================================

import SwiftUI

/// 装備変更画面
/// キャラクター選択 → 装備編集の2段階UI
struct CharacterSelectionForEquipmentView: View {
    @Environment(AppServices.self) private var appServices
    @State private var characters: [CachedCharacter] = []
    @State private var exploringIds: Set<UInt8> = []
    @State private var loadError: String?
    @State private var isLoading = true

    private var characterService: CharacterProgressService { appServices.character }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("読み込み中...")
            } else if let error = loadError {
                ContentUnavailableView {
                    Label("エラー", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else if characters.isEmpty {
                ContentUnavailableView {
                    Label("キャラクターがいません", systemImage: "person.slash")
                } description: {
                    Text("ギルドにキャラクターを作成してください")
                }
            } else {
                characterList
            }
        }
        .navigationTitle("アイテムを装備")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCharacters()
        }
    }

    private var characterList: some View {
        List {
            ForEach(characters) { character in
                NavigationLink {
                    EquipmentEditorView(character: character)
                        .environment(appServices)
                } label: {
                    CharacterRowForEquipment(character: character)
                }
                .disabled(exploringIds.contains(character.id))
            }
        }
        .listStyle(.insetGrouped)
        .avoidBottomGameInfo()
    }

    @MainActor
    private func loadCharacters() async {
        isLoading = true
        loadError = nil

        do {
            // キャッシュからキャラクターを取得（DB直接アクセスではなく）
            characters = try await appServices.userDataLoad.getCharacters()
            exploringIds = try await appServices.userDataLoad.runningCharacterIds()
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }
}

/// キャラクター選択リストの行
private struct CharacterRowForEquipment: View {
    let character: CachedCharacter

    var body: some View {
        HStack(spacing: 12) {
            CharacterImageView(avatarIndex: character.resolvedAvatarId, size: 44)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(character.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    Text("Lv.\(character.level)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(character.jobName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            let equipCount = character.equippedItems.reduce(0) { $0 + Int($1.quantity) }
            Text("\(equipCount)/\(character.equipmentCapacity)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// 装備画面で表示するアイテムの種類
enum EquipmentDisplayItem: Identifiable, Hashable {
    case inventory(CachedInventoryItem)
    case equipped(CachedInventoryItem, avatarId: UInt16)

    var id: String {
        switch self {
        case .inventory(let item): return item.stackKey
        case .equipped(let item, _): return item.stackKey + "_equipped"
        }
    }

    var stackKey: String { cachedItem.stackKey }
    var itemId: UInt16 { cachedItem.itemId }
    var quantity: Int { Int(cachedItem.quantity) }
    var normalTitleId: UInt8 { cachedItem.normalTitleId }
    var superRareTitleId: UInt8 { cachedItem.superRareTitleId }
    var socketItemId: UInt16 { cachedItem.socketItemId }
    var displayName: String { cachedItem.displayName }

    var isEquipped: Bool {
        if case .equipped = self { return true }
        return false
    }

    var equippedAvatarId: UInt16? {
        if case .equipped(_, let avatarId) = self { return avatarId }
        return nil
    }

    var cachedItem: CachedInventoryItem {
        switch self {
        case .inventory(let item): return item
        case .equipped(let item, _): return item
        }
    }
}

/// 装備編集画面
struct EquipmentEditorView: View {
    let character: CachedCharacter

    @Environment(AppServices.self) private var appServices
    @Environment(StatChangeNotificationService.self) private var statChangeService
    @State private var currentCharacter: CachedCharacter
    @State private var orderedSubcategories: [ItemDisplaySubcategory] = []
    @State private var itemDefinitions: [UInt16: ItemDefinition] = [:]
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var equipError: String?
    @State private var selectedItemForDetail: EquipmentDisplayItem?
    @State private var searchText = ""
    @State private var showFilterSheet = false
    @State private var selectedCategories: Set<ItemSaleCategory> = Set(ItemSaleCategory.allCases)
        .subtracting(Self.excludedCategories)
    @State private var showEquippableOnly = false
    @State private var selectedNormalTitleIds: Set<UInt8>? = nil
    @State private var showSuperRareOnly = false
    @State private var showGemModifiedOnly = false
    @State private var cachedNormalTitleOptions: [TitleDefinition] = []
    @State private var cachedAllNormalTitleIds: Set<UInt8> = []

    private var characterService: CharacterProgressService { appServices.character }
    private var inventoryService: InventoryProgressService { appServices.inventory }
    private var displayService: UserDataLoadService { appServices.userDataLoad }

    /// 装備画面で除外するメインカテゴリ（合成素材・魔造素材）
    private static let excludedCategories: Set<ItemSaleCategory> = [.forSynthesis, .mazoMaterial]

    /// 装備中アイテムをサブカテゴリ別に分類（キャッシュから取得）
    private var equippedItemsBySubcategory: [ItemDisplaySubcategory: [EquipmentDisplayItem]] {
        let cachedEquipped = displayService.equippedItemsByCharacter[character.id] ?? []
        let avatarId = currentCharacter.resolvedAvatarId
        var result: [ItemDisplaySubcategory: [EquipmentDisplayItem]] = [:]
        for equipped in cachedEquipped {
            let subcategory = ItemDisplaySubcategory(
                mainCategory: equipped.category,
                subcategory: equipped.rarity
            )
            let displayItem = EquipmentDisplayItem.equipped(equipped, avatarId: avatarId)
            result[subcategory, default: []].append(displayItem)
        }
        return result
    }

    /// 装備数サマリー
    private var equippedItemsSummary: String {
        let cachedEquipped = displayService.equippedItemsByCharacter[character.id] ?? []
        let count = cachedEquipped.reduce(0) { $0 + Int($1.quantity) }
        return "\(count)/\(currentCharacter.equipmentCapacity)"
    }

    /// 装備中アイテムをソート順でフラット化（CharacterEquippedItemsSection用）
    private var sortedEquippedItemsForDisplay: [EquipmentDisplayItem] {
        equippedItemsBySubcategory.values
            .flatMap { $0 }
            .sorted { isOrderedBefore($0, $1) }
    }

    private var raceSkillUnlocks: [(level: Int, skill: SkillDefinition)] {
        let masterData = appServices.masterDataCache
        let unlocks = masterData.raceSkillUnlocks[currentCharacter.raceId] ?? []
        return unlocks.compactMap { unlock in
            guard let skill = masterData.skill(unlock.skillId) else { return nil }
            return (level: unlock.level, skill: skill)
        }
    }

    private var jobSkillUnlocks: [(level: Int, skill: SkillDefinition)] {
        let masterData = appServices.masterDataCache
        let unlocks = masterData.jobSkillUnlocks[currentCharacter.jobId] ?? []
        return unlocks.compactMap { unlock in
            guard let skill = masterData.skill(unlock.skillId) else { return nil }
            return (level: unlock.level, skill: skill)
        }
    }

    init(character: CachedCharacter) {
        self.character = character
        _currentCharacter = State(initialValue: character)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("読み込み中...")
            } else if let error = loadError {
                ContentUnavailableView {
                    Label("エラー", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else {
                List {
                    Section {
                        CharacterHeaderSection(character: currentCharacter)
                    }

                    Section("プロフィール") {
                        CharacterIdentitySection(character: currentCharacter)
                    }

                    Section("レベル / 経験値") {
                        CharacterLevelSection(character: currentCharacter)
                    }

                    Section("基本能力値") {
                        CharacterBaseStatsSection(character: currentCharacter)
                    }

                    Section("戦闘ステータス") {
                        CharacterCombatStatsSection(character: currentCharacter)
                    }

                    Section("種族スキル") {
                        CharacterRaceSkillsSection(skillUnlocks: raceSkillUnlocks, characterLevel: currentCharacter.level)
                    }

                    Section("職業スキル") {
                        CharacterJobSkillsSection(skillUnlocks: jobSkillUnlocks, characterLevel: currentCharacter.level)
                    }

                    Section("習得スキル") {
                        CharacterSkillsSection(character: currentCharacter)
                    }

                    Section("魔法使い魔法") {
                        CharacterMageSpellsSection(character: currentCharacter)
                    }

                    Section("僧侶魔法") {
                        CharacterPriestSpellsSection(character: currentCharacter)
                    }

                    Section("装備中 (\(equippedItemsSummary))") {
                        CharacterEquippedItemsSection(
                            equippedItems: sortedEquippedItemsForDisplay,
                            equipmentCapacity: currentCharacter.equipmentCapacity,
                            onUnequip: { displayItem, completion in
                                Task {
                                    if displayItem.isEquipped {
                                        do {
                                            try await performUnequip(displayItem.cachedItem)
                                            await MainActor.run { completion(.success(())) }
                                        } catch {
                                            await MainActor.run { completion(.failure(error)) }
                                        }
                                    } else {
                                        await MainActor.run { completion(.success(())) }
                                    }
                                }
                            },
                            onDetail: { displayItem in
                                selectedItemForDetail = displayItem
                            }
                        )
                    }

                    ForEach(filteredSections, id: \.subcategory) { section in
                        buildSubcategorySection(for: section.subcategory, items: section.items)
                    }
                    if filteredSections.isEmpty {
                        Section {
                            Text("条件に一致する装備候補がありません。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("行動優先度") {
                        CharacterActionPreferencesSection(character: currentCharacter,
                                                          onActionPreferencesChange: nil)
                    }

                    if let error = equipError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .avoidBottomGameInfo()
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showFilterSheet = true
                        } label: {
                            Label("フィルター", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                .sheet(isPresented: $showFilterSheet) {
                    EquipmentFilterSheet(
                        selectedCategories: $selectedCategories,
                        selectedNormalTitleIds: $selectedNormalTitleIds,
                        showEquippableOnly: $showEquippableOnly,
                        availableCategories: availableCategories,
                        normalTitleOptions: cachedNormalTitleOptions,
                        allNormalTitleIds: cachedAllNormalTitleIds,
                        showSuperRareOnly: $showSuperRareOnly,
                        showGemModifiedOnly: $showGemModifiedOnly
                    )
                }
            }
        }
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadData()
        }
        .sheet(item: $selectedItemForDetail) { displayItem in
            NavigationStack {
                ItemDetailView(cachedItem: displayItem.cachedItem)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") {
                                selectedItemForDetail = nil
                            }
                        }
                    }
            }
        }
    }

    private var availableCategories: [ItemSaleCategory] {
        ItemSaleCategory.allCases
            .filter { !Self.excludedCategories.contains($0) }
            .sorted { $0.rawValue < $1.rawValue }
    }

    /// フィルタ済みセクション（computed property - @Observableで自動更新）
    private var filteredSections: [(subcategory: ItemDisplaySubcategory, items: [EquipmentDisplayItem])] {
        // キャッシュから直接参照
        let cachedItems = displayService.getSubcategorizedItems()

        return orderedSubcategories.compactMap { subcategory in
            // キャッシュのアイテム（除外カテゴリは既にorderedSubcategoriesでフィルタ済み）
            let inventoryItems = cachedItems[subcategory] ?? []
            // 装備中アイテム
            let equippedItems = equippedItemsBySubcategory[subcategory] ?? []

            // マージしてソート（装備中アイテムはインベントリアイテムの直後に配置）
            var merged: [EquipmentDisplayItem] = []
            var equippedQueue = equippedItems

            for cachedItem in inventoryItems {
                let item = EquipmentDisplayItem.inventory(cachedItem)
                merged.append(item)
                // 同じstackKeyの装備中アイテムがあれば直後に挿入
                if let idx = equippedQueue.firstIndex(where: { $0.stackKey == cachedItem.stackKey }) {
                    merged.append(equippedQueue[idx])
                    equippedQueue.remove(at: idx)
                }
            }
            // 残った装備中アイテム（インベントリに対応がないもの）を正しいソート位置に挿入
            for equippedItem in equippedQueue {
                let insertIndex = findInsertIndex(for: equippedItem, in: merged)
                merged.insert(equippedItem, at: insertIndex)
            }

            let filtered = merged.filter { matchesFilters($0) }
            return filtered.isEmpty ? nil : (subcategory, filtered)
        }
    }

    /// ソート順を維持して挿入位置を見つける
    private func findInsertIndex(for item: EquipmentDisplayItem, in items: [EquipmentDisplayItem]) -> Int {
        for (index, existing) in items.enumerated() {
            if isOrderedBefore(item, existing) {
                return index
            }
        }
        return items.count  // 末尾に追加
    }

    /// EquipmentDisplayItemのソート順比較
    private func isOrderedBefore(_ lhs: EquipmentDisplayItem, _ rhs: EquipmentDisplayItem) -> Bool {
        if lhs.itemId != rhs.itemId {
            return lhs.itemId < rhs.itemId
        }
        let lhsHasSuperRare = lhs.superRareTitleId > 0
        let rhsHasSuperRare = rhs.superRareTitleId > 0
        if lhsHasSuperRare != rhsHasSuperRare {
            return !lhsHasSuperRare
        }
        let lhsHasSocket = lhs.socketItemId > 0
        let rhsHasSocket = rhs.socketItemId > 0
        if lhsHasSocket != rhsHasSocket {
            return !lhsHasSocket
        }
        if lhs.normalTitleId != rhs.normalTitleId {
            return lhs.normalTitleId < rhs.normalTitleId
        }
        if lhs.superRareTitleId != rhs.superRareTitleId {
            return lhs.superRareTitleId < rhs.superRareTitleId
        }
        return lhs.socketItemId < rhs.socketItemId
    }

    private func matchesFilters(_ item: EquipmentDisplayItem) -> Bool {
        guard let category = displayService.subcategory(for: item.stackKey)?.mainCategory ?? {
            // 装備中アイテムの場合はitemDefinitionsから取得
            if let def = itemDefinitions[item.itemId] {
                return ItemSaleCategory(rawValue: def.category)
            }
            return nil
        }() else { return false }
        if !selectedCategories.contains(category) { return false }
        let normalTitleSet = selectedNormalTitleIds ?? cachedAllNormalTitleIds
        if !normalTitleSet.contains(item.normalTitleId) { return false }
        if !searchText.isEmpty && !item.displayName.localizedCaseInsensitiveContains(searchText) { return false }
        if showSuperRareOnly && item.superRareTitleId == 0 {
            return false
        }
        if showGemModifiedOnly && item.socketItemId == 0 {
            return false
        }
        if showEquippableOnly && !validateEquipment(definition: itemDefinitions[item.itemId]).canEquip { return false }
        return true
    }

    @ViewBuilder
    private func buildSubcategorySection(
        for subcategory: ItemDisplaySubcategory,
        items: [EquipmentDisplayItem]
    ) -> some View {
        if items.isEmpty {
            EmptyView()
        } else {
            Section {
                ForEach(items, id: \.id) { item in
                    equipmentCandidateRow(item)
                }
            } header: {
                HStack {
                    Text(subcategory.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(items.count)個")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .headerProminence(.increased)
        }
    }

    private func equipmentCandidateRow(_ item: EquipmentDisplayItem) -> some View {
        let definition = itemDefinitions[item.itemId]
        let validation = item.isEquipped ? (canEquip: false, reason: nil) : validateEquipment(definition: definition)
        let titleStyle: Color = item.isEquipped ? .primary : (validation.canEquip ? .primary : .secondary)

        return HStack(spacing: 8) {
            // 装備中アイテムにはキャラ画像を表示（タップで装備解除）
            if let avatarId = item.equippedAvatarId, item.isEquipped {
                Button {
                    Task {
                        try? await performUnequip(item.cachedItem)
                    }
                } label: {
                    CharacterImageView(avatarIndex: avatarId, size: 36)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 0)
            }

            Button {
                Task {
                    if item.isEquipped {
                        try? await performUnequip(item.cachedItem)
                    } else if validation.canEquip {
                        await performEquip(item.cachedItem)
                    }
                }
            } label: {
                HStack {
                    makeStyledDisplayText(for: item)
                        .font(.body)
                        .lineLimit(1)
                        .foregroundStyle(titleStyle)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                selectedItemForDetail = item
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    /// スタイル付き表示テキストを生成
    private func makeStyledDisplayText(for item: EquipmentDisplayItem) -> Text {
        let isSuperRare = item.superRareTitleId != 0
        let content = Text(item.displayName)
        let quantitySegment = Text("x\(item.quantity)")

        let display = quantitySegment + Text("  ") + content

        if isSuperRare {
            return display.bold()
        }
        return display
    }

    private func loadData() async {
        isLoading = true
        loadError = nil

        // 最新のキャラクターデータをキャッシュから取得
        do {
            let allCharacters = try await displayService.getCharacters()
            if let latest = allCharacters.first(where: { $0.id == character.id }) {
                currentCharacter = latest
            }
        } catch {
            // キャッシュ取得に失敗した場合は元のデータを使用
        }

        // サブカテゴリの順序だけ取得（キャッシュはコピーしない）
        orderedSubcategories = displayService.getOrderedSubcategories()
            .filter { !Self.excludedCategories.contains($0.mainCategory) }

        // 装備候補と装備中アイテムの定義を取得（validateEquipmentに必要）
        let cachedItems = displayService.getSubcategorizedItems()
        let availableIds = cachedItems.values.flatMap { $0.map { $0.itemId } }
        let cachedEquipped = displayService.equippedItemsByCharacter[character.id] ?? []
        let allItemIds = Set(availableIds)
            .union(Set(cachedEquipped.map { $0.itemId }))
        let masterData = appServices.masterDataCache
        var definitions: [UInt16: ItemDefinition] = [:]
        for id in allItemIds {
            if let definition = masterData.item(id) {
                definitions[id] = definition
            }
        }
        itemDefinitions = definitions

        // 装備中アイテムをキャッシュに設定（初期ロード時）
        if displayService.equippedItemsByCharacter[character.id] == nil {
            displayService.equippedItemsByCharacter[character.id] = currentCharacter.equippedItems
        }

        // 称号オプションをキャッシュ（毎回ソートを避ける）
        cachedNormalTitleOptions = masterData.allTitles.sorted { $0.id < $1.id }
        cachedAllNormalTitleIds = Set(cachedNormalTitleOptions.map { $0.id })

        isLoading = false
    }

    private func validateEquipment(definition: ItemDefinition?) -> (canEquip: Bool, reason: String?) {
        guard let definition else {
            return (false, "アイテム情報がありません")
        }

        guard let race = currentCharacter.race else {
            return (false, "キャラクターデータが不完全です")
        }

        let currentCount = currentCharacter.equippedItems.reduce(0) { $0 + Int($1.quantity) }

        let result = EquipmentProgressService.validateEquipment(
            itemDefinition: definition,
            characterRaceId: race.id,
            characterGenderCode: race.genderCode,
            currentEquippedCount: currentCount,
            equipmentCapacity: currentCharacter.equipmentCapacity
        )

        return (result.canEquip, result.reason)
    }

    @MainActor
    private func performEquip(_ item: CachedInventoryItem) async {
        equipError = nil
        let oldCharacter = currentCharacter

        do {
            // 装備処理を実行（通知経由でキャッシュが自動更新される）
            let result = try await characterService.equipItem(
                characterId: currentCharacter.id,
                inventoryItemStackKey: item.stackKey,
                equipmentCapacity: currentCharacter.equipmentCapacity
            )
            // 装備変更専用の高速パスを使用（マスターデータ再取得をスキップ）
            let pandoraBoxItems = Set(displayService.cachedPlayer.pandoraBoxItems)
            let runtime = try characterService.runtimeCharacterWithEquipmentChange(
                current: currentCharacter,
                newEquippedItems: result.equippedItems,
                pandoraBoxItems: pandoraBoxItems
            )
            currentCharacter = runtime

            // ステータス変動を通知
            let changes = calculateStatChanges(old: oldCharacter, new: runtime)
            if !changes.isEmpty {
                statChangeService.publish(changes)
            }

            // キャラクターキャッシュを差分更新（他画面で最新状態を参照可能に）
            displayService.updateCharacter(runtime)
            // 装備中アイテムキャッシュはCharacterProgressServiceからの通知経由で自動更新される
        } catch {
            equipError = error.localizedDescription
        }
    }

    @MainActor
    private func performUnequip(_ item: CachedInventoryItem) async throws {
        equipError = nil
        let oldCharacter = currentCharacter

        // 解除処理を実行（通知経由でキャッシュが自動更新される）
        let result = try await characterService.unequipItem(
            characterId: currentCharacter.id,
            equipmentStackKey: item.stackKey
        )
        // 装備変更専用の高速パスを使用（マスターデータ再取得をスキップ）
        let pandoraBoxItems = Set(displayService.cachedPlayer.pandoraBoxItems)
        let runtime = try characterService.runtimeCharacterWithEquipmentChange(
            current: currentCharacter,
            newEquippedItems: result.equippedItems,
            pandoraBoxItems: pandoraBoxItems
        )
        currentCharacter = runtime

        // ステータス変動を通知
        let changes = calculateStatChanges(old: oldCharacter, new: runtime)
        if !changes.isEmpty {
            statChangeService.publish(changes)
        }

        // キャラクターキャッシュを差分更新（他画面で最新状態を参照可能に）
        displayService.updateCharacter(runtime)
        // 装備中アイテムキャッシュはCharacterProgressServiceからの通知経由で自動更新される
    }

    /// 装備変更前後のステータス差分を計算
    private func calculateStatChanges(
        old: CachedCharacter,
        new: CachedCharacter
    ) -> [StatChangeNotificationService.StatChangeNotification] {
        typealias Notification = StatChangeNotificationService.StatChangeNotification
        typealias StatKind = StatChangeNotificationService.StatKind
        var changes: [Notification] = []

        // ヘルパー関数（Int用）
        func addIfChanged(_ kind: StatKind, oldVal: Int, newVal: Int) {
            if oldVal != newVal {
                let delta = newVal - oldVal
                let sign = delta >= 0 ? "+" : ""
                changes.append(Notification(
                    kind: kind,
                    newValue: "\(newVal)",
                    delta: "\(sign)\(delta)"
                ))
            }
        }

        // ヘルパー関数（Double用、小数点1桁・切り捨て）
        func addIfChangedDouble(_ kind: StatKind, oldVal: Double, newVal: Double) {
            // 表示値は切り捨てで計算（CharacterCombatStatsSectionと統一）
            let oldDisplay = floor(oldVal * 10) / 10
            let newDisplay = floor(newVal * 10) / 10
            if oldDisplay != newDisplay {
                let delta = newDisplay - oldDisplay
                let sign = delta >= 0 ? "+" : ""
                changes.append(Notification(
                    kind: kind,
                    newValue: String(format: "%.1f", newDisplay),
                    delta: String(format: "%@%.1f", sign, delta)
                ))
            }
        }

        // 基本能力値
        addIfChanged(.strength, oldVal: old.attributes.strength, newVal: new.attributes.strength)
        addIfChanged(.wisdom, oldVal: old.attributes.wisdom, newVal: new.attributes.wisdom)
        addIfChanged(.spirit, oldVal: old.attributes.spirit, newVal: new.attributes.spirit)
        addIfChanged(.vitality, oldVal: old.attributes.vitality, newVal: new.attributes.vitality)
        addIfChanged(.agility, oldVal: old.attributes.agility, newVal: new.attributes.agility)
        addIfChanged(.luck, oldVal: old.attributes.luck, newVal: new.attributes.luck)

        // 戦闘ステータス
        addIfChanged(.maxHP, oldVal: old.combat.maxHP, newVal: new.combat.maxHP)
        addIfChanged(.physicalAttackScore, oldVal: old.combat.physicalAttackScore, newVal: new.combat.physicalAttackScore)
        addIfChanged(.magicalAttackScore, oldVal: old.combat.magicalAttackScore, newVal: new.combat.magicalAttackScore)
        addIfChanged(.physicalDefenseScore, oldVal: old.combat.physicalDefenseScore, newVal: new.combat.physicalDefenseScore)
        addIfChanged(.magicalDefenseScore, oldVal: old.combat.magicalDefenseScore, newVal: new.combat.magicalDefenseScore)
        addIfChanged(.hitScore, oldVal: old.combat.hitScore, newVal: new.combat.hitScore)
        addIfChanged(.evasionScore, oldVal: old.combat.evasionScore, newVal: new.combat.evasionScore)
        addIfChanged(.criticalChancePercent, oldVal: old.combat.criticalChancePercent, newVal: new.combat.criticalChancePercent)
        addIfChangedDouble(.attackCount, oldVal: old.combat.attackCount, newVal: new.combat.attackCount)
        addIfChanged(.magicalHealingScore, oldVal: old.combat.magicalHealingScore, newVal: new.combat.magicalHealingScore)
        addIfChanged(.trapRemovalScore, oldVal: old.combat.trapRemovalScore, newVal: new.combat.trapRemovalScore)
        addIfChanged(.additionalDamageScore, oldVal: old.combat.additionalDamageScore, newVal: new.combat.additionalDamageScore)
        addIfChanged(.breathDamageScore, oldVal: old.combat.breathDamageScore, newVal: new.combat.breathDamageScore)

        return changes
    }
}

private struct EquipmentFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCategories: Set<ItemSaleCategory>
    @Binding var selectedNormalTitleIds: Set<UInt8>?
    @Binding var showEquippableOnly: Bool
    let availableCategories: [ItemSaleCategory]
    let normalTitleOptions: [TitleDefinition]
    let allNormalTitleIds: Set<UInt8>
    @Binding var showSuperRareOnly: Bool
    @Binding var showGemModifiedOnly: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("一括操作") {
                    Button("すべて選択") {
                        selectedCategories = Set(availableCategories)
                        selectedNormalTitleIds = allNormalTitleIds
                    }
                    Button("全て解除") {
                        selectedCategories.removeAll()
                        selectedNormalTitleIds = []
                    }
                }

                Section("称号") {
                    ForEach(normalTitleOptions, id: \.id) { title in
                        Toggle(displayName(for: title), isOn: titleBinding(for: title.id))
                    }
                }

                Section("カテゴリ") {
                    ForEach(availableCategories, id: \.self) { category in
                        Toggle(category.displayName, isOn: binding(for: category))
                    }
                }

                Section("その他の条件") {
                    Toggle("装備可能なものだけ表示", isOn: $showEquippableOnly)
                    Toggle("超レア称号のみ表示", isOn: $showSuperRareOnly)
                    Toggle("宝石改造済みのみ表示", isOn: $showGemModifiedOnly)
                }
            }
            .navigationTitle("フィルター")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func binding(for category: ItemSaleCategory) -> Binding<Bool> {
        Binding(
            get: { selectedCategories.contains(category) },
            set: { isOn in
                if isOn {
                    selectedCategories.insert(category)
                } else {
                    selectedCategories.remove(category)
                }
            }
        )
    }

    private func titleBinding(for id: UInt8) -> Binding<Bool> {
        Binding(
            get: {
                (selectedNormalTitleIds ?? allNormalTitleIds).contains(id)
            },
            set: { isOn in
                var current = selectedNormalTitleIds ?? allNormalTitleIds
                if isOn {
                    current.insert(id)
                } else {
                    current.remove(id)
                }
                selectedNormalTitleIds = current
            }
        )
    }

    private func displayName(for title: TitleDefinition) -> String {
        title.name.isEmpty ? "称号なし" : title.name
    }
}
