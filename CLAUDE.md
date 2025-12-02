# Epika プロジェクト

複雑な機能や大規模リファクタリングには ExecPlan（.agent/PLANS.md参照）を使用する。

## プロジェクト固有
- 元ネタに忠実に。オリジナル要素は追加しない
- リリース前のため互換性・マイグレーションは考慮不要
- 質問には作業前に回答する

## アーキテクチャ
- 三層設計: UI=@MainActor / サービス=状態・I/O / 計算=純関数
- Swift 6の構造化並行性・Observationを前提にRuntimeベースで実装
- `@unchecked Sendable`、`@preconcurrency`、`nonisolated(unsafe)` は使用禁止

## 命名規約
- 拡張ファイルは `Type.Feature.swift` 形式（`+`は使用しない）
- 例: `SQLiteMasterDataManager.Item.swift`

## ビルド・コミット
- コミット前にXcodeビルド（Debug/シミュレータ）でエラー・警告0を確認
- 一時ログファイルは作業完了時に削除

## エラー処理詳細
詳細は `agent_docs/error-handling.md` を参照
