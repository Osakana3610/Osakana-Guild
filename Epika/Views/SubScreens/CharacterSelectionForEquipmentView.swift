import SwiftUI

/// 装備変更画面
/// キャラクター選択 → 装備編集の2段階UI
struct CharacterSelectionForEquipmentView: View {
    @EnvironmentObject private var progressService: ProgressService
    @State private var characters: [RuntimeCharacter] = []
    @State private var loadError: String?
    @State private var isLoading = true

    private var characterService: CharacterProgressService { progressService.character }

    var body: some View {
        NavigationStack {
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
    }

    private var characterList: some View {
        List {
            ForEach(characters) { character in
                NavigationLink {
                    EquipmentEditorView(character: character)
                        .environmentObject(progressService)
                } label: {
                    CharacterRowForEquipment(character: character)
                }
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
            let snapshots = try await characterService.allCharacters()
            var runtimeCharacters: [RuntimeCharacter] = []
            for snapshot in snapshots {
                let runtime = try await characterService.runtimeCharacter(from: snapshot)
                runtimeCharacters.append(runtime)
            }
            characters = runtimeCharacters
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
            Text("\(equipCount)/\(EquipmentProgressService.maxEquippedItems)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// 装備編集画面
struct EquipmentEditorView: View {
    let character: RuntimeCharacter

    @EnvironmentObject private var progressService: ProgressService
    @State private var currentCharacter: RuntimeCharacter
    @State private var subcategorizedItems: [ItemDisplaySubcategory: [LightweightItemData]] = [:]
    @State private var orderedSubcategories: [ItemDisplaySubcategory] = []
    @State private var itemDefinitions: [UInt16: ItemDefinition] = [:]
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var equipError: String?
    @State private var statDeltas: [(label: String, value: Int)] = []
    @State private var cacheVersion: Int = 0

    private var characterService: CharacterProgressService { progressService.character }
    private var inventoryService: InventoryProgressService { progressService.inventory }
    private var displayService: ItemPreloadService { ItemPreloadService.shared }

    /// 装備画面で除外するメインカテゴリ（合成素材・魔造素材）
    private static let excludedCategories: Set<ItemSaleCategory> = [.forSynthesis, .mazoMaterial]

    init(character: RuntimeCharacter) {
        self.character = character
        _currentCharacter = State(initialValue: character)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
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
                    // キャラクター情報セクション
                    Section {
                        CharacterHeaderSection(character: currentCharacter)
                        CharacterBaseStatsSection(character: currentCharacter)
                        CharacterCombatStatsSection(character: currentCharacter)
                    }

                    // 装備中アイテムセクション
                    Section("装備中") {
                        CharacterEquippedItemsSection(
                            equippedItems: currentCharacter.equippedItems,
                            itemDefinitions: itemDefinitions,
                            onUnequip: { item in
                                try await performUnequip(item)
                            }
                        )
                    }

                    // 装備候補セクション（サブカテゴリ別）
                    ForEach(orderedSubcategories, id: \.self) { subcategory in
                        buildSubcategorySection(for: subcategory)
                    }

                    if let error = equipError {
                        Section {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .id(cacheVersion)
                .avoidBottomGameInfo()
            }

            // 差分プレビュー（左下）
            EquipmentStatDeltaView(deltas: statDeltas)
                .padding(.leading, 8)
                .padding(.bottom, 80) // GameInfoBarの上
        }
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadData()
        }
    }

    @ViewBuilder
    private func buildSubcategorySection(for subcategory: ItemDisplaySubcategory) -> some View {
        let items = subcategorizedItems[subcategory] ?? []
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
            displayService.makeStyledDisplayText(for: item, includeSellValue: false)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            if validation.canEquip {
                Button {
                    Task { await performEquip(item) }
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.gray)
            }
        }
        .frame(height: AppConstants.UI.listRowHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            if let def = definition {
                showStatPreview(for: def, isEquipping: true)
            }
        }
    }

    private func loadData() async {
        isLoading = true
        loadError = nil

        do {
            // プリロードが完了していなければ待機
            if !displayService.loaded {
                displayService.startPreload(inventoryService: inventoryService)
                try await displayService.waitForPreload()
            }

            // サブカテゴリ別アイテムを取得（合成素材・魔造素材を除く）
            let allSubcategorized = displayService.getSubcategorizedItems()
            subcategorizedItems = allSubcategorized.filter { !Self.excludedCategories.contains($0.key.mainCategory) }
            orderedSubcategories = displayService.getOrderedSubcategories()
                .filter { !Self.excludedCategories.contains($0.mainCategory) }
            cacheVersion = displayService.version

            // 装備候補と装備中アイテムの定義を取得（validateEquipmentに必要）
            let availableIds = subcategorizedItems.values.flatMap { $0.map { $0.itemId } }
            let allItemIds = Set(availableIds)
                .union(Set(currentCharacter.equippedItems.map { $0.itemId }))
            if !allItemIds.isEmpty {
                let definitions = try await MasterDataRuntimeService.shared.getItemMasterData(ids: Array(allItemIds))
                itemDefinitions = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
            }
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    private func validateEquipment(definition: ItemDefinition?) -> (canEquip: Bool, reason: String?) {
        guard let definition else {
            return (false, "アイテム情報がありません")
        }

        let currentCount = currentCharacter.equippedItems.reduce(0) { $0 + $1.quantity }

        // 装備数上限チェック
        if currentCount >= EquipmentProgressService.maxEquippedItems {
            return (false, "装備数が上限に達しています")
        }

        // 除外カテゴリチェック
        if EquipmentProgressService.excludedCategories.contains(definition.category) {
            return (false, "このアイテムは装備できません")
        }

        // 種族制限チェック
        if !definition.allowedRaces.isEmpty {
            let raceCategory = currentCharacter.race?.category ?? ""
            let canBypass = definition.bypassRaceRestrictions.contains(raceCategory)
            let isAllowed = definition.allowedRaces.contains(raceCategory)
            if !canBypass && !isAllowed {
                return (false, "種族制限により装備できません")
            }
        }

        // 職業制限チェック
        if !definition.allowedJobs.isEmpty {
            let jobCategory = currentCharacter.job?.category ?? ""
            if !definition.allowedJobs.contains(jobCategory) {
                return (false, "職業制限により装備できません")
            }
        }

        // 性別制限チェック
        if !definition.allowedGenders.isEmpty {
            let gender = currentCharacter.race?.gender ?? ""
            if !definition.allowedGenders.contains(gender) {
                return (false, "性別制限により装備できません")
            }
        }

        return (true, nil)
    }

    @MainActor
    private func performEquip(_ item: LightweightItemData) async {
        equipError = nil

        do {
            let snapshot = try await characterService.equipItem(
                characterId: currentCharacter.id,
                inventoryItemStackKey: item.stackKey
            )
            let runtime = try await characterService.runtimeCharacter(from: snapshot)
            currentCharacter = runtime
            await loadData() // リフレッシュ
            clearStatPreview()
        } catch {
            equipError = error.localizedDescription
        }
    }

    @MainActor
    private func performUnequip(_ item: CharacterInput.EquippedItem) async throws {
        equipError = nil

        let snapshot = try await characterService.unequipItem(
            characterId: currentCharacter.id,
            equipmentStackKey: item.stackKey
        )
        let runtime = try await characterService.runtimeCharacter(from: snapshot)
        currentCharacter = runtime

        await loadData() // リフレッシュ
        clearStatPreview()
    }

    private func showStatPreview(for definition: ItemDefinition, isEquipping: Bool) {
        // 同一ベースIDの重複ペナルティを考慮した差分計算
        let delta = EquipmentProgressService.calculateStatDelta(
            adding: isEquipping ? definition : nil,
            removing: isEquipping ? nil : definition,
            currentEquippedItems: currentCharacter.equippedItems
        )

        statDeltas = delta.map { (StatLabelResolver.label(for: $0.key), $0.value) }
            .sorted { abs($0.1) > abs($1.1) }
    }

    private func clearStatPreview() {
        statDeltas = []
    }
}
