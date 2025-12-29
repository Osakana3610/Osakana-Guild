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
            let snapshots = try characterService.allCharacters()
            var runtimeCharacters: [RuntimeCharacter] = []
            for snapshot in snapshots {
                let runtime = try characterService.runtimeCharacter(from: snapshot)
                runtimeCharacters.append(runtime)
            }
            characters = runtimeCharacters
            exploringIds = try appServices.exploration.runningPartyMemberIds()
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
                                try performUnequip(item)
                            },
                            onDetail: { itemId in
                                selectedItemIdForDetail = itemId
                            }
                        )
                    }

                    ForEach(filteredCandidateSections, id: \.subcategory) { section in
                        buildSubcategorySection(for: section.subcategory, items: section.items)
                    }
                    if filteredCandidateSections.isEmpty {
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
                        normalTitleOptions: normalTitleOptions,
                        allNormalTitleIds: allNormalTitleIds,
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

    private var normalTitleOptions: [TitleDefinition] {
        appServices.masterDataCache.allTitles.sorted { $0.id < $1.id }
    }

    private var allNormalTitleIds: Set<UInt8> {
        Set(normalTitleOptions.map { $0.id })
    }

    private var filteredCandidateSections: [(subcategory: ItemDisplaySubcategory, items: [LightweightItemData])] {
        orderedSubcategories.compactMap { subcategory in
            guard let items = subcategorizedItems[subcategory] else { return nil }
            let filtered = items.filter { matchesFilters($0) }
            return filtered.isEmpty ? nil : (subcategory, filtered)
        }
    }

    private func matchesFilters(_ item: LightweightItemData) -> Bool {
        if !selectedCategories.contains(item.category) { return false }
        let normalTitleSet = selectedNormalTitleIds ?? allNormalTitleIds
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
        let validation = validateEquipment(definition: definition)

        return HStack {
            Button {
                if validation.canEquip {
                    performEquip(item)
                }
            } label: {
                HStack {
                    displayService.makeStyledDisplayText(for: item, includeSellValue: false)
                        .font(.body)
                        .lineLimit(1)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(validation.canEquip ? .primary : .secondary)

            Button {
                selectedItemForDetail = item
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
    }

    private func loadData() async {
        isLoading = true
        loadError = nil

        // 起動時に既にロード済み（UserDataLoadService.loadAllで）
        // サブカテゴリ別アイテムを取得（合成素材・魔造素材を除く）
        let allSubcategorized = displayService.getSubcategorizedItems()
        subcategorizedItems = allSubcategorized.filter { !Self.excludedCategories.contains($0.key.mainCategory) }
        orderedSubcategories = displayService.getOrderedSubcategories()
            .filter { !Self.excludedCategories.contains($0.mainCategory) }

        // 装備候補と装備中アイテムの定義を取得（validateEquipmentに必要）
        let availableIds = subcategorizedItems.values.flatMap { $0.map { $0.itemId } }
        let allItemIds = Set(availableIds)
            .union(Set(currentCharacter.equippedItems.map { $0.itemId }))
        let masterData = appServices.masterDataCache
        for id in allItemIds {
            if let definition = masterData.item(id) {
                itemDefinitions[id] = definition
            }
        }

        isLoading = false
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
    private func performEquip(_ item: LightweightItemData) {
        equipError = nil
        let oldCharacter = currentCharacter

        do {
            let equippedItems = try characterService.equipItem(
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

            // インベントリキャッシュから装備した分を減らす（1個）
            _ = try? displayService.decrementQuantity(stackKey: item.stackKey, by: 1)
            refreshSubcategorizedItems()
        } catch {
            equipError = error.localizedDescription
        }
    }

    @MainActor
    private func performUnequip(_ item: CharacterInput.EquippedItem) throws {
        equipError = nil
        let oldCharacter = currentCharacter

        let equippedItems = try characterService.unequipItem(
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

        // キャッシュに同じstackKeyがあれば数量を増やす、なければ新規追加
        updateCacheForUnequippedItem(item)
    }

    /// 解除したアイテムをキャッシュに反映
    private func updateCacheForUnequippedItem(_ item: CharacterInput.EquippedItem) {
        // 既存アイテムがあれば数量を増やす
        displayService.incrementQuantity(stackKey: item.stackKey, by: 1)

        // incrementQuantityは既存アイテムがない場合何もしないので、
        // キャッシュを確認して存在しなければ新規追加
        let allItems = displayService.getAllItems()
        if allItems.contains(where: { $0.stackKey == item.stackKey }) {
            // 既に存在する（incrementで更新済み）
            refreshSubcategorizedItems()
            return
        }

        // 新規追加: LightweightItemDataを構築
        guard let definition = itemDefinitions[item.itemId] else { return }
        let masterData = appServices.masterDataCache

        let superRareTitleName: String? = item.superRareTitleId > 0
            ? masterData.superRareTitle(item.superRareTitleId)?.name
            : nil
        let normalTitleName: String? = masterData.title(item.normalTitleId)?.name

        let gemName: String? = item.socketItemId > 0
            ? masterData.item(item.socketItemId)?.name
            : nil

        let lightweightItem = LightweightItemData(
            stackKey: item.stackKey,
            itemId: item.itemId,
            name: definition.name,
            quantity: 1,
            sellValue: definition.sellValue,
            category: ItemSaleCategory(rawValue: definition.category) ?? .other,
            enhancement: ItemSnapshot.Enhancement(
                superRareTitleId: item.superRareTitleId,
                normalTitleId: item.normalTitleId,
                socketSuperRareTitleId: item.socketSuperRareTitleId,
                socketNormalTitleId: item.socketNormalTitleId,
                socketItemId: item.socketItemId
            ),
            storage: .playerItem,
            rarity: definition.rarity,
            normalTitleName: normalTitleName,
            superRareTitleName: superRareTitleName,
            gemName: gemName
        )

        displayService.addItem(lightweightItem)
        refreshSubcategorizedItems()
    }

    /// サブカテゴリ表示を更新
    private func refreshSubcategorizedItems() {
        subcategorizedItems = displayService.getSubcategorizedItems()
            .filter { !Self.excludedCategories.contains($0.key.mainCategory) }
        orderedSubcategories = displayService.getOrderedSubcategories()
            .filter { !Self.excludedCategories.contains($0.mainCategory) }
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
