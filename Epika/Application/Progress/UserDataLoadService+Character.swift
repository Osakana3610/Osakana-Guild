// ==============================================================================
// UserDataLoadService+Character.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクターデータのロードとキャッシュ管理
//   - キャラクターの差分更新
//   - キャラクター変更通知の購読
//
// ==============================================================================

import Foundation

// MARK: - Character Change Notification

extension UserDataLoadService {
    /// キャラクター変更通知用の構造体
    /// - Note: Progress層がsave()成功後に送信する
    struct CharacterChange: Sendable {
        /// 追加・更新されたキャラクターのID
        let upserted: [UInt8]
        /// 削除されたキャラクターのID
        let removed: [UInt8]

        static let fullReload = CharacterChange(upserted: [], removed: [])
    }
}

// MARK: - Character Loading

extension UserDataLoadService {
    func loadCharacters() async throws {
        let loadedCharacters = try await characterService.allCharacters()
        await MainActor.run {
            self.characters = loadedCharacters
            self.isCharactersLoaded = true
        }
    }

    // MARK: - Character Cache API

    /// キャラクターキャッシュを無効化（次回アクセス時に再ロード）
    @MainActor
    func invalidateCharacters() {
        isCharactersLoaded = false
    }

    /// 特定のキャラクターをキャッシュで差分更新
    /// - Note: 装備変更時に使用。全キャラクター再構築を避けるため、
    ///   characterProgressDidChange通知の代わりにこのメソッドを使う
    @MainActor
    func updateCharacter(_ character: CachedCharacter) {
        if let index = characters.firstIndex(where: { $0.id == character.id }) {
            characters[index] = character
        }
    }

    /// キャラクターを取得（キャッシュ不在時は再ロード）
    func getCharacters() async throws -> [CachedCharacter] {
        let needsLoad = await MainActor.run { !isCharactersLoaded }
        if needsLoad {
            try await loadCharacters()
        }
        return await characters
    }
}

// MARK: - Character Change Notification Handling

extension UserDataLoadService {
    /// キャラクター変更通知を購読開始
    @MainActor
    func subscribeCharacterChanges() {
        Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .characterProgressDidChange) {
                guard let self else { continue }

                // ペイロードがある場合は差分更新、ない場合は全件リロード
                if let change = notification.userInfo?["change"] as? CharacterChange {
                    await self.applyCharacterChange(change)
                } else {
                    // 後方互換性: ペイロードなしの通知は全件リロード
                    self.invalidateCharacters()
                }
            }
        }
    }

    /// キャラクター変更をキャッシュへ適用
    private func applyCharacterChange(_ change: CharacterChange) async {
        // fullReloadの場合は全件リロード
        if change.upserted.isEmpty && change.removed.isEmpty {
            await MainActor.run { self.invalidateCharacters() }
            return
        }

        // 削除されたキャラクターをキャッシュから除去
        if !change.removed.isEmpty {
            await MainActor.run {
                self.characters.removeAll { change.removed.contains($0.id) }
            }
        }

        // 更新されたキャラクターを再構築
        if !change.upserted.isEmpty {
            do {
                let updatedCharacters = try await characterService.characters(withIds: change.upserted)
                await MainActor.run {
                    for character in updatedCharacters {
                        if let index = self.characters.firstIndex(where: { $0.id == character.id }) {
                            self.characters[index] = character
                        } else {
                            self.characters.append(character)
                        }
                    }
                }
            } catch {
                // エラー時は全件リロードにフォールバック
                await MainActor.run { self.invalidateCharacters() }
            }
        }
    }
}
