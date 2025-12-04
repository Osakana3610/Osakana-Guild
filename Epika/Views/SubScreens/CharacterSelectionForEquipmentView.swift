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
            .refreshable {
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
            CharacterImageView(avatarIdentifier: character.avatarIdentifier, size: 44)
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

            let equipCount = character.progress.equippedItems.reduce(0) { $0 + $1.quantity }
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
    @State private var availableItems: [LightweightItemData] = []
    @State private var itemDefinitions: [String: ItemDefinition] = [:]
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var equipError: String?
    @State private var statDeltas: [(label: String, value: Int)] = []

    private var characterService: CharacterProgressService { progressService.character }
    private var inventoryService: InventoryProgressService { progressService.inventory }
    private var displayService: UniversalItemDisplayService { UniversalItemDisplayService.shared }

    init(character: RuntimeCharacter) {
        self.character = character
        _currentCharacter = State(initialValue: character)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // ヘッダー（読み取り専用）
                    CharacterHeaderSection(character: currentCharacter)

                    // 基本ステータス（読み取り専用）
                    CharacterBaseStatsSection(character: currentCharacter)

                    // 戦闘ステータス（読み取り専用）
                    CharacterCombatStatsSection(character: currentCharacter)

                    // 装備中アイテム（編集可能）
                    CharacterEquippedItemsSection(
                        equippedItems: currentCharacter.progress.equippedItems,
                        itemDefinitions: itemDefinitions,
                        onUnequip: { item in
                            try await performUnequip(item)
                        }
                    )

                    // 装備候補
                    equipmentCandidatesSection

                    if let error = equipError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
            .avoidBottomGameInfo()

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
    private var equipmentCandidatesSection: some View {
        GroupBox("装備候補") {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let error = loadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if availableItems.isEmpty {
                Text("装備可能なアイテムがありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(availableItems, id: \.progressId) { item in
                        equipmentCandidateRow(item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func equipmentCandidateRow(_ item: LightweightItemData) -> some View {
        let definition = itemDefinitions[item.masterDataId]
        let validation = validateEquipment(definition: definition)

        HStack {
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
            // アイテムを取得してキャッシュに登録
            let items = try await inventoryService.allItems(storage: .playerItem)
            try await displayService.stagedGroupAndSortLightweightByCategory(for: items)

            // 装備可能カテゴリのみ取得（宝石・合成素材・魔法素材を除く）
            let equipCategories = Set(ItemSaleCategory.allCases).subtracting([.forSynthesis, .magicMaterial, .gem])
            availableItems = displayService.getCachedItemsFlat(categories: equipCategories)

            // 装備候補と装備中アイテムの定義を取得（validateEquipmentに必要）
            let allItemIds = Set(availableItems.map { $0.masterDataId })
                .union(Set(currentCharacter.progress.equippedItems.map { $0.itemId }))
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

        let currentCount = currentCharacter.progress.equippedItems.reduce(0) { $0 + $1.quantity }

        // 装備数上限チェック
        if currentCount >= EquipmentProgressService.maxEquippedItems {
            return (false, "装備数が上限に達しています")
        }

        // 除外カテゴリチェック
        if EquipmentProgressService.excludedCategories.contains(definition.category) {
            return (false, "このアイテムは装備できません")
        }

        // equipableフラグチェック
        if let equipable = definition.equipable, !equipable {
            return (false, "このアイテムは装備できません")
        }

        // 種族制限チェック
        if !definition.allowedRaces.isEmpty {
            let canBypass = definition.bypassRaceRestrictions.contains(currentCharacter.progress.raceId)
            let isAllowed = definition.allowedRaces.contains(currentCharacter.progress.raceId)
            if !canBypass && !isAllowed {
                return (false, "種族制限により装備できません")
            }
        }

        // 職業制限チェック
        if !definition.allowedJobs.isEmpty {
            if !definition.allowedJobs.contains(currentCharacter.progress.jobId) {
                return (false, "職業制限により装備できません")
            }
        }

        // 性別制限チェック
        if !definition.allowedGenders.isEmpty {
            if !definition.allowedGenders.contains(currentCharacter.progress.gender) {
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
                inventoryItemId: item.progressId
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
    private func performUnequip(_ item: RuntimeCharacterProgress.EquippedItem) async throws {
        equipError = nil

        let snapshot = try await characterService.unequipItem(
            characterId: currentCharacter.id,
            equipmentRecordId: item.id
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
            currentEquippedItems: currentCharacter.progress.equippedItems
        )

        statDeltas = delta.map { (StatLabelResolver.label(for: $0.key), $0.value) }
            .sorted { abs($0.1) > abs($1.1) }
    }

    private func clearStatPreview() {
        statDeltas = []
    }
}
