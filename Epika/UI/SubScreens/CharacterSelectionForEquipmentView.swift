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
    @State private var characters: [RuntimeCharacter] = []
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
            exploringIds = try await appServices.exploration.runningPartyMemberIds()
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }
}

/// キャラクター選択リストの行
private struct CharacterRowForEquipment: View {
    let character: RuntimeCharacter

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

            let equipCount = character.equippedItems.reduce(0) { $0 + $1.quantity }
            Text("\(equipCount)/\(character.equipmentCapacity)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// 装備編集画面
struct EquipmentEditorView: View {
    let character: RuntimeCharacter

    @Environment(AppServices.self) private var appServices
    @Environment(StatChangeNotificationService.self) private var statChangeService
    @State private var currentCharacter: RuntimeCharacter
    @State private var subcategorizedItems: [ItemDisplaySubcategory: [LightweightItemData]] = [:]
    @State private var orderedSubcategories: [ItemDisplaySubcategory] = []
    @State private var itemDefinitions: [UInt16: ItemDefinition] = [:]
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var equipError: String?
    @State private var selectedItemForDetail: LightweightItemData?
    @State private var selectedItemIdForDetail: UInt16?  // 装備中アイテム用（図鑑モード）
    @State private var searchText = ""
    @State private var showFilterSheet = false
    @State private var selectedCategories: Set<ItemSaleCategory> = Set(ItemSaleCategory.allCases)
        .subtracting(Self.excludedCategories)
    @State private var showEquippableOnly = false
    @State private var selectedNormalTitleIds: Set<UInt8>? = nil
    @State private var showSuperRareOnly = false
    @State private var showGemModifiedOnly = false
    @State private var cachedFilteredSections: [(subcategory: ItemDisplaySubcategory, items: [LightweightItemData])] = []
    @State private var cachedNormalTitleOptions: [TitleDefinition] = []
    @State private var cachedAllNormalTitleIds: Set<UInt8> = []

    private var characterService: CharacterProgressService { appServices.character }
    private var inventoryService: InventoryProgressService { appServices.inventory }
    private var displayService: UserDataLoadService { appServices.userDataLoad }

    /// 装備画面で除外するメインカテゴリ（合成素材・魔造素材）
    private static let excludedCategories: Set<ItemSaleCategory> = [.forSynthesis, .mazoMaterial]

    /// 装備数サマリー
    private var equippedItemsSummary: String {
        let count = currentCharacter.equippedItems.reduce(0) { $0 + $1.quantity }
        return "\(count)/\(currentCharacter.equipmentCapacity)"
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

    init(character: RuntimeCharacter) {
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
                            equippedItems: currentCharacter.equippedItems,
                            itemDefinitions: itemDefinitions,
                            equipmentCapacity: currentCharacter.equipmentCapacity,
                            onUnequip: { item in
                                try await performUnequip(item)
                            },
                            onDetail: { itemId in
                                selectedItemIdForDetail = itemId
                            }
                        )
                    }

                    ForEach(cachedFilteredSections, id: \.subcategory) { section in
                        buildSubcategorySection(for: section.subcategory, items: section.items)
                    }
                    if cachedFilteredSections.isEmpty {
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
        .onChange(of: searchText) { updateFilteredSections() }
        .onChange(of: selectedCategories) { updateFilteredSections() }
        .onChange(of: selectedNormalTitleIds) { updateFilteredSections() }
        .onChange(of: showEquippableOnly) { updateFilteredSections() }
        .onChange(of: showSuperRareOnly) { updateFilteredSections() }
        .onChange(of: showGemModifiedOnly) { updateFilteredSections() }
        .sheet(item: $selectedItemForDetail) { item in
            NavigationStack {
                ItemDetailView(item: item)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") {
                                selectedItemForDetail = nil
                            }
                        }
                    }
            }
        }
        .sheet(item: $selectedItemIdForDetail) { itemId in
            NavigationStack {
                ItemDetailView(itemId: itemId)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") {
                                selectedItemIdForDetail = nil
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

    /// フィルタ済みセクションを更新（フィルタ条件変更時に呼ぶ）
    private func updateFilteredSections() {
        cachedFilteredSections = orderedSubcategories.compactMap { subcategory in
            let items = subcategorizedItems[subcategory] ?? []
            let filtered = items.filter { matchesFilters($0) }
            return filtered.isEmpty ? nil : (subcategory, filtered)
        }
    }

    private func matchesFilters(_ item: LightweightItemData) -> Bool {
        if !selectedCategories.contains(item.category) { return false }
        let normalTitleSet = selectedNormalTitleIds ?? cachedAllNormalTitleIds
        if !normalTitleSet.contains(item.enhancement.normalTitleId) { return false }
        if !searchText.isEmpty &&
            !item.fullDisplayName.localizedCaseInsensitiveContains(searchText) {
            return false
        }
        if showSuperRareOnly && item.enhancement.superRareTitleId == 0 {
            return false
        }
        if showGemModifiedOnly && !item.hasGemModification {
            return false
        }
        if showEquippableOnly {
            let definition = itemDefinitions[item.itemId]
            if !validateEquipment(definition: definition).canEquip {
                return false
            }
        }
        return true
    }

    @ViewBuilder
    private func buildSubcategorySection(
        for subcategory: ItemDisplaySubcategory,
        items: [LightweightItemData]
    ) -> some View {
        if items.isEmpty {
            EmptyView()
        } else {
            Section {
                ForEach(items, id: \.stackKey) { item in
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

    private func equipmentCandidateRow(_ item: LightweightItemData) -> some View {
        let definition = itemDefinitions[item.itemId]
        let isEquipped = item.equippedByAvatarId != nil
        let validation = isEquipped ? (canEquip: false, reason: nil) : validateEquipment(definition: definition)
        let titleStyle: Color = isEquipped ? .primary : (validation.canEquip ? .primary : .secondary)

        return HStack(spacing: 8) {
            // 装備中アイテムにはキャラ画像を表示
            if let avatarId = item.equippedByAvatarId {
                CharacterImageView(avatarIndex: avatarId, size: 36)
            } else {
                Color.clear
                    .frame(width: 0)
            }

            Button {
                Task {
                    if isEquipped {
                        await performUnequipFromLightweight(item)
                    } else if validation.canEquip {
                        await performEquip(item)
                    }
                }
            } label: {
                HStack {
                    displayService.makeStyledDisplayText(for: item, includeSellValue: false)
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
        .listRowInsets(isEquipped
            ? EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
            : nil
        )
    }

    /// LightweightItemDataから装備解除を実行
    private func performUnequipFromLightweight(_ item: LightweightItemData) async {
        // stackKeyから_equippedサフィックスを除去して元のstackKeyを取得
        let baseStackKey = String(item.stackKey.dropLast("_equipped".count))

        // currentCharacter.equippedItemsから該当アイテムを探す
        guard let equippedItem = currentCharacter.equippedItems.first(where: { $0.stackKey == baseStackKey }) else {
            return
        }

        try? await performUnequip(equippedItem)
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

        // 起動時に既にロード済み（UserDataLoadService.loadAllで）
        // サブカテゴリ別アイテムを取得（合成素材・魔造素材を除く）
        let allSubcategorized = displayService.getSubcategorizedItems()
        var filtered = allSubcategorized.filter { !Self.excludedCategories.contains($0.key.mainCategory) }
        orderedSubcategories = displayService.getOrderedSubcategories()
            .filter { !Self.excludedCategories.contains($0.mainCategory) }

        // 装備候補と装備中アイテムの定義を取得（validateEquipmentに必要）
        let availableIds = filtered.values.flatMap { $0.map { $0.itemId } }
        let allItemIds = Set(availableIds)
            .union(Set(currentCharacter.equippedItems.map { $0.itemId }))
        let masterData = appServices.masterDataCache
        var definitions: [UInt16: ItemDefinition] = [:]
        for id in allItemIds {
            if let definition = masterData.item(id) {
                definitions[id] = definition
            }
        }
        itemDefinitions = definitions

        // 装備中アイテムをLightweightItemDataに変換して挿入
        insertEquippedItems(into: &filtered, masterData: masterData)
        subcategorizedItems = filtered

        // 称号オプションをキャッシュ（毎回ソートを避ける）
        cachedNormalTitleOptions = masterData.allTitles.sorted { $0.id < $1.id }
        cachedAllNormalTitleIds = Set(cachedNormalTitleOptions.map { $0.id })

        // フィルタ済みセクションを更新
        updateFilteredSections()

        isLoading = false
    }

    /// 装備中アイテムをsubcategorizedItemsに挿入する
    private func insertEquippedItems(
        into subcategorized: inout [ItemDisplaySubcategory: [LightweightItemData]],
        masterData: MasterDataCache
    ) {
        let avatarId = currentCharacter.resolvedAvatarId

        for equipped in currentCharacter.equippedItems {
            guard let definition = itemDefinitions[equipped.itemId],
                  let category = ItemSaleCategory(rawValue: definition.category) else { continue }

            let subcategory = ItemDisplaySubcategory(
                mainCategory: category,
                subcategory: definition.rarity
            )

            // 装備中アイテムからLightweightItemDataを生成
            let lightweightItem = createLightweightItem(
                from: equipped,
                definition: definition,
                masterData: masterData,
                avatarId: avatarId
            )

            // 正しいソート位置に挿入
            var items = subcategorized[subcategory] ?? []
            let insertIndex = findInsertIndex(for: lightweightItem, in: items)
            items.insert(lightweightItem, at: insertIndex)
            subcategorized[subcategory] = items
        }
    }

    /// 装備中アイテムからLightweightItemDataを生成
    private func createLightweightItem(
        from equipped: CharacterInput.EquippedItem,
        definition: ItemDefinition,
        masterData: MasterDataCache,
        avatarId: UInt16
    ) -> LightweightItemData {
        let normalTitleName = masterData.title(equipped.normalTitleId)?.name
        let superRareTitleName: String? = equipped.superRareTitleId > 0
            ? masterData.superRareTitle(equipped.superRareTitleId)?.name
            : nil
        let gemName: String? = equipped.socketItemId > 0
            ? masterData.item(equipped.socketItemId)?.name
            : nil

        return LightweightItemData(
            stackKey: equipped.stackKey + "_equipped",  // インベントリと区別
            itemId: equipped.itemId,
            name: definition.name,
            quantity: equipped.quantity,
            sellValue: definition.sellValue,
            category: ItemSaleCategory(rawValue: definition.category) ?? .other,
            enhancement: ItemSnapshot.Enhancement(
                superRareTitleId: equipped.superRareTitleId,
                normalTitleId: equipped.normalTitleId,
                socketSuperRareTitleId: equipped.socketSuperRareTitleId,
                socketNormalTitleId: equipped.socketNormalTitleId,
                socketItemId: equipped.socketItemId
            ),
            storage: .playerItem,
            rarity: definition.rarity,
            normalTitleName: normalTitleName,
            superRareTitleName: superRareTitleName,
            gemName: gemName,
            equippedByAvatarId: avatarId
        )
    }

    /// ソート順を維持して挿入位置を見つける
    private func findInsertIndex(for item: LightweightItemData, in items: [LightweightItemData]) -> Int {
        // 同じstackKeyのインベントリアイテムを探す（_equippedサフィックスを除去して比較）
        let baseStackKey = String(item.stackKey.dropLast("_equipped".count))
        if let matchIndex = items.firstIndex(where: { $0.stackKey == baseStackKey }) {
            return matchIndex + 1  // インベントリアイテムの直後
        }

        // 見つからない場合はソート順に従って挿入
        for (index, existing) in items.enumerated() {
            if displayService.isOrderedBefore(item, existing) {
                return index
            }
        }
        return items.count  // 末尾に追加
    }

    private func validateEquipment(definition: ItemDefinition?) -> (canEquip: Bool, reason: String?) {
        guard let definition else {
            return (false, "アイテム情報がありません")
        }

        guard let race = currentCharacter.race else {
            return (false, "キャラクターデータが不完全です")
        }

        let currentCount = currentCharacter.equippedItems.reduce(0) { $0 + $1.quantity }

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
    private func performEquip(_ item: LightweightItemData) async {
        equipError = nil
        let oldCharacter = currentCharacter

        do {
            let equippedItems = try await characterService.equipItem(
                characterId: currentCharacter.id,
                inventoryItemStackKey: item.stackKey,
                equipmentCapacity: currentCharacter.equipmentCapacity
            )
            // 装備変更専用の高速パスを使用（マスターデータ再取得をスキップ）
            let runtime = try characterService.runtimeCharacterWithEquipmentChange(
                current: currentCharacter,
                newEquippedItems: equippedItems
            )
            currentCharacter = runtime

            // ステータス変動を通知
            let changes = calculateStatChanges(old: oldCharacter, new: runtime)
            if !changes.isEmpty {
                statChangeService.publish(changes)
            }

            // キャラクターキャッシュを差分更新（他画面で最新状態を参照可能に）
            displayService.updateCharacter(runtime)

            // インベントリアイテムの数量を減らす（装備したので-1）
            updateInventoryItemQuantity(stackKey: item.stackKey, delta: -1)

            // 装備中アイテムの表示を差分更新（全データコピーを避ける）
            updateEquippedItemsDisplay()
        } catch {
            equipError = error.localizedDescription
        }
    }

    @MainActor
    private func performUnequip(_ item: CharacterInput.EquippedItem) async throws {
        equipError = nil
        let oldCharacter = currentCharacter

        let equippedItems = try await characterService.unequipItem(
            characterId: currentCharacter.id,
            equipmentStackKey: item.stackKey
        )
        // 装備変更専用の高速パスを使用（マスターデータ再取得をスキップ）
        let runtime = try characterService.runtimeCharacterWithEquipmentChange(
            current: currentCharacter,
            newEquippedItems: equippedItems
        )
        currentCharacter = runtime

        // ステータス変動を通知
        let changes = calculateStatChanges(old: oldCharacter, new: runtime)
        if !changes.isEmpty {
            statChangeService.publish(changes)
        }

        // キャラクターキャッシュを差分更新（他画面で最新状態を参照可能に）
        displayService.updateCharacter(runtime)

        // インベントリアイテムの数量を増やす（装備解除したので+1）
        updateInventoryItemQuantity(stackKey: item.stackKey, delta: +1)

        // 装備中アイテムの表示を差分更新（全データコピーを避ける）
        updateEquippedItemsDisplay()
    }

    /// 装備中アイテムの表示だけを差分更新（全データコピーを避ける）
    private func updateEquippedItemsDisplay() {
        // 古い装備中アイテム（_equippedサフィックス付き）を全て削除
        for key in subcategorizedItems.keys {
            subcategorizedItems[key]?.removeAll { $0.stackKey.hasSuffix("_equipped") }
        }

        // 新しい装備中アイテムを挿入
        let masterData = appServices.masterDataCache
        insertEquippedItems(into: &subcategorizedItems, masterData: masterData)

        // フィルタ済みセクションを更新
        updateFilteredSections()
    }

    /// インベントリアイテムの数量を差分更新
    /// - Parameters:
    ///   - stackKey: 対象アイテムのstackKey
    ///   - delta: 数量の変化（装備時: -1、解除時: +1）
    private func updateInventoryItemQuantity(stackKey: String, delta: Int) {
        // 全サブカテゴリを走査して該当アイテムを探す
        for (subcategory, items) in subcategorizedItems {
            if let index = items.firstIndex(where: { $0.stackKey == stackKey }) {
                var updatedItems = items
                var item = updatedItems[index]
                item.quantity += delta

                if item.quantity <= 0 {
                    // 数量が0以下になったら削除
                    updatedItems.remove(at: index)
                } else {
                    // 数量を更新
                    updatedItems[index] = item
                }
                subcategorizedItems[subcategory] = updatedItems
                return
            }
        }

        // 解除時にアイテムが見つからない場合（インベントリに存在しなかった場合）
        // → 新しいアイテムを追加する必要があるが、これは稀なケース
        // 　 その場合は全体更新にフォールバック
        if delta > 0 {
            refreshSubcategorizedItems()
        }
    }

    /// サブカテゴリ表示を全体更新（初回ロード時のみ使用）
    private func refreshSubcategorizedItems() {
        var filtered = displayService.getSubcategorizedItems()
            .filter { !Self.excludedCategories.contains($0.key.mainCategory) }
        orderedSubcategories = displayService.getOrderedSubcategories()
            .filter { !Self.excludedCategories.contains($0.mainCategory) }

        // 装備中アイテムを挿入
        let masterData = appServices.masterDataCache
        insertEquippedItems(into: &filtered, masterData: masterData)
        subcategorizedItems = filtered

        // フィルタ済みセクションを更新
        updateFilteredSections()
    }

    /// 装備変更前後のステータス差分を計算
    private func calculateStatChanges(
        old: RuntimeCharacter,
        new: RuntimeCharacter
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

        // ヘルパー関数（Double用、小数点1桁）
        func addIfChangedDouble(_ kind: StatKind, oldVal: Double, newVal: Double) {
            if oldVal != newVal {
                let delta = newVal - oldVal
                let sign = delta >= 0 ? "+" : ""
                changes.append(Notification(
                    kind: kind,
                    newValue: String(format: "%.1f", newVal),
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
        addIfChanged(.physicalAttack, oldVal: old.combat.physicalAttack, newVal: new.combat.physicalAttack)
        addIfChanged(.magicalAttack, oldVal: old.combat.magicalAttack, newVal: new.combat.magicalAttack)
        addIfChanged(.physicalDefense, oldVal: old.combat.physicalDefense, newVal: new.combat.physicalDefense)
        addIfChanged(.magicalDefense, oldVal: old.combat.magicalDefense, newVal: new.combat.magicalDefense)
        addIfChanged(.hitRate, oldVal: old.combat.hitRate, newVal: new.combat.hitRate)
        addIfChanged(.evasionRate, oldVal: old.combat.evasionRate, newVal: new.combat.evasionRate)
        addIfChanged(.criticalRate, oldVal: old.combat.criticalRate, newVal: new.combat.criticalRate)
        addIfChangedDouble(.attackCount, oldVal: old.combat.attackCount, newVal: new.combat.attackCount)
        addIfChanged(.magicalHealing, oldVal: old.combat.magicalHealing, newVal: new.combat.magicalHealing)
        addIfChanged(.trapRemoval, oldVal: old.combat.trapRemoval, newVal: new.combat.trapRemoval)
        addIfChanged(.additionalDamage, oldVal: old.combat.additionalDamage, newVal: new.combat.additionalDamage)
        addIfChanged(.breathDamage, oldVal: old.combat.breathDamage, newVal: new.combat.breathDamage)

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
