// ==============================================================================
// SwiftDataContextProvider.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - SwiftData の ModelContext 生成を一元化
//   - autosaveEnabled = false を強制し、明示的な save() を要求
//   - サービス層が MainActor から独立して動作できる基盤を提供
//
// 【使い方】
//   let context = contextProvider.makeContext()
//   // ... データ操作 ...
//   try context.save()
//
// ==============================================================================

import Foundation
import SwiftData

/// SwiftData コンテキストの生成を一元化するプロバイダ
///
/// 各 ProgressService は `ModelContainer` を直接保持せず、
/// このプロバイダ経由でコンテキストを取得する。
/// これにより、コンテキスト生成時の設定（autosave無効化など）を統一できる。
struct SwiftDataContextProvider: Sendable {
    nonisolated let container: ModelContainer

    /// 新しいコンテキストを生成する
    ///
    /// - Returns: autosaveEnabled = false に設定された ModelContext
    ///
    /// このメソッドで生成されたコンテキストは自動保存されないため、
    /// 変更を永続化するには明示的に `context.save()` を呼ぶ必要がある。
    nonisolated func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }
}
