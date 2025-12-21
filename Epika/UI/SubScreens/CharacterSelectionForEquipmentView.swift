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
    @State private var loadError: String?
    @State private var isLoading = true

    private var characterService: CharacterProgressService { appServices.character }

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
                        .environment(appServices)
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
    @State private var currentCharacter: RuntimeCharacter
    @State private var subcategorizedItems: [ItemDisplaySubcategory: [LightweightItemData]] = [:]
    @State private var orderedSubcategories: [ItemDisplaySubcategory] = []
    @State private var itemDefinitions: [UInt16: ItemDefinition] = [:]
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var equipError: String?
    @State private var cacheVersion: Int = 0
    @State private var selectedItemForDetail: LightweightItemData?
    @State private var selectedItemIdForDetail: UInt16?  // 装備中アイテム用（図鑑モード）

    private var characterService: CharacterProgressService { appServices.character }
    private var inventoryService: InventoryProgressService { appServices.inventory }
    private var displayService: ItemPreloadService { appServices.itemPreload }

    /// 装備画面で除外するメインカテゴリ（合成素材・魔造素材）
    private static let excludedCategories: Set<ItemSaleCategory> = [.forSynthesis, .mazoMaterial]

    /// 装備数サマリー
    private var equippedItemsSummary: String {
        let count = currentCharacter.equippedItems.reduce(0) { $0 + $1.quantity }
        return "\(count)/\(currentCharacter.equipmentCapacity)"
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
                    // キャラクターヘッダー
                    Section {
                        CharacterHeaderSection(character: currentCharacter)
                    }

                    // 基本能力値
                    Section("基本能力値") {
                        CharacterBaseStatsSection(character: currentCharacter)
                    }

                    // 戦闘ステータス
                    Section("戦闘ステータス") {
                        CharacterCombatStatsSection(character: currentCharacter)
                    }

                    // 装備中アイテム
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

                    // 装備候補セクション（売却画面と同じSection構造）
                    ForEach(orderedSubcategories, id: \.self) { subcategory in
                        buildSubcategorySection(for: subcategory)
                    }

                    if let error = equipError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .id(cacheVersion)
                .avoidBottomGameInfo()
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
            Button {
                if validation.canEquip {
                    Task { await performEquip(item) }
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
            let masterData = appServices.masterDataCache
            for id in allItemIds {
                if let def = masterData.item(id) {
                    itemDefinitions[id] = def
                }
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

        do {
            let snapshot = try await characterService.equipItem(
                characterId: currentCharacter.id,
                inventoryItemStackKey: item.stackKey
            )
            let runtime = try await characterService.runtimeCharacter(from: snapshot)
            currentCharacter = runtime

            // インベントリキャッシュから装備した分を減らす（1個）
            _ = try? displayService.decrementQuantity(stackKey: item.stackKey, by: 1)
            subcategorizedItems = displayService.getSubcategorizedItems()
                .filter { !Self.excludedCategories.contains($0.key.mainCategory) }
            orderedSubcategories = displayService.getOrderedSubcategories()
                .filter { !Self.excludedCategories.contains($0.mainCategory) }
            cacheVersion = displayService.version
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

        // インベントリキャッシュを再構築（解除したアイテムが戻るため）
        try await displayService.reload(inventoryService: inventoryService)
        subcategorizedItems = displayService.getSubcategorizedItems()
            .filter { !Self.excludedCategories.contains($0.key.mainCategory) }
        orderedSubcategories = displayService.getOrderedSubcategories()
            .filter { !Self.excludedCategories.contains($0.mainCategory) }
        cacheVersion = displayService.version
    }
}
