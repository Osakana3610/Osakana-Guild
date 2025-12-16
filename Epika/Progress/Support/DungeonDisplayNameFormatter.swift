import Foundation

enum DungeonDisplayNameFormatter {
    /// 難易度として使用する TitleMaster の normalTitle ID（昇順）
    /// - 2: 無称号 (statMultiplier: 1.0)
    /// - 4: 魔性の (statMultiplier: 1.7411)
    /// - 5: 宿った (statMultiplier: 2.2974)
    /// - 6: 伝説の (statMultiplier: 3.0314)
    /// ※ id=3（名工の）は statMultiplier の差が小さいためスキップ
    static let difficultyTitleIds: [UInt8] = [2, 4, 5, 6]

    /// 初期難易度（無称号）
    static let initialDifficulty: UInt8 = 2

    /// 最高難易度
    static let maxDifficulty: UInt8 = 6

    /// タイトルキャッシュ（起動時に preloadTitles() で初期化）
    @MainActor
    private static var titlesById: [UInt8: TitleDefinition] = [:]

    /// 起動時に呼び出してタイトルをキャッシュする
    @MainActor
    static func preloadTitles() async {
        guard titlesById.isEmpty else { return }
        let titles = (try? await MasterDataRuntimeService.shared.getAllTitles()) ?? []
        titlesById = Dictionary(uniqueKeysWithValues: titles.map { ($0.id, $0) })
    }

    /// 指定した難易度の次の難易度を返す（最高難易度の場合は nil）
    static func nextDifficulty(after current: UInt8) -> UInt8? {
        guard let index = difficultyTitleIds.firstIndex(of: current),
              index + 1 < difficultyTitleIds.count else { return nil }
        return difficultyTitleIds[index + 1]
    }

    /// ダンジョン名に難易度プレフィックスを付けた表示名を返す（同期版、要事前 preloadTitles）
    @MainActor
    static func displayName(for dungeon: DungeonDefinition, difficultyTitleId: UInt8) -> String {
        if let prefix = difficultyPrefix(for: difficultyTitleId) {
            return "\(prefix)\(dungeon.name)"
        }
        return dungeon.name
    }

    /// 難易度 title ID からプレフィックス（"魔性の" など）を取得（同期版）
    @MainActor
    static func difficultyPrefix(for titleId: UInt8) -> String? {
        guard let title = titlesById[titleId], !title.name.isEmpty else { return nil }
        return title.name
    }

    /// 難易度 title ID から statMultiplier を取得（敵レベル計算用）
    @MainActor
    static func statMultiplier(for titleId: UInt8) -> Double {
        titlesById[titleId]?.statMultiplier ?? 1.0
    }

    // MARK: - Async versions (for non-MainActor contexts)

    /// ダンジョン名に難易度プレフィックスを付けた表示名を返す（非同期版）
    static func displayNameAsync(for dungeon: DungeonDefinition, difficultyTitleId: UInt8) async -> String {
        if let prefix = await difficultyPrefixAsync(for: difficultyTitleId) {
            return "\(prefix)\(dungeon.name)"
        }
        return dungeon.name
    }

    /// 難易度 title ID からプレフィックス（"魔性の" など）を取得（非同期版）
    static func difficultyPrefixAsync(for titleId: UInt8) async -> String? {
        guard let title = try? await MasterDataRuntimeService.shared.getTitleMasterData(id: titleId),
              !title.name.isEmpty else { return nil }
        return title.name
    }

    /// 難易度 title ID から statMultiplier を取得（非同期版）
    static func statMultiplierAsync(for titleId: UInt8) async -> Double {
        guard let title = try? await MasterDataRuntimeService.shared.getTitleMasterData(id: titleId) else {
            return 1.0
        }
        return title.statMultiplier ?? 1.0
    }
}
