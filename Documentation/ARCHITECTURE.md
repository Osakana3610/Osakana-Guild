# Epika Architecture

Epikaはダンジョン探索RPGのiOSアプリです。このドキュメントは各ファイルの責務を一覧化し、コントリビューターがコードベースを理解するための参照資料です。

## 設計方針

- **4層アーキテクチャ**: UI / Application / Domain / Persistence
- **Swift 6 Concurrency**: actor, @Observable, 構造化並行性を活用
- **SwiftData**: プレイヤー進行データの永続化
- **SQLite**: マスターデータ（読み取り専用）

## フォルダ構造

```
Epika/
├── UI/              # SwiftUI View層（@MainActor）
├── Application/     # サービス・ビジネスロジック層
├── Domain/          # ドメインモデル層
└── Persistence/     # SwiftData永続化層
```

---

## App Entry Point

| ファイル | 責務 |
|---------|------|
| EpikaApp.swift | アプリエントリーポイント、起動シーケンス制御、ModelContainer/AppServicesのライフサイクル管理 |

---

## Domain/MasterData

マスターデータ（SQLiteから読み込む読み取り専用データ）の型定義。

| ファイル | 責務 |
|---------|------|
| CharacterNameMasterModels.swift | キャラクター名候補の型定義 |
| DungeonMasterModels.swift | ダンジョン・フロア・エンカウントテーブルの型定義 |
| EnemyMasterModels.swift | 敵キャラクター（モンスター）の型定義 |
| EnemyRaceMasterModels.swift | 敵種族の型定義 |
| EnemySkillMasterModels.swift | 敵スキル・属性・バフ種別の型定義 |
| ExplorationEventModels.swift | 探索イベントの型定義 |
| ItemMasterModels.swift | アイテムの型定義 |
| JobMasterModels.swift | 職業・戦闘係数の型定義 |
| PersonalityMasterModels.swift | 性格（パーソナリティ）の型定義 |
| RaceMasterModels.swift | キャラクター種族・基礎ステータスの型定義 |
| ShopMasterModels.swift | 商店品揃えの型定義 |
| SkillMasterModels.swift | スキル（アクティブ/パッシブ/リアクション）の型定義 |
| SpellMasterModels.swift | 呪文（魔法）の型定義 |
| StatusEffectModels.swift | 状態異常・バフ/デバフの型定義 |
| StoryMasterModels.swift | ストーリー（シナリオ）の型定義 |
| SynthesisMasterModels.swift | アイテム合成レシピの型定義 |
| TitleMasterModels.swift | アイテム称号の型定義 |

---

## Domain/Snapshots

永続化レコードからUIに渡すためのSendable値型。Swift並行性でactor境界を越えて渡すために必要。

| ファイル | 責務 |
|---------|------|
| CharacterSnapshot.swift | キャラクターデータのイミュータブルスナップショット |
| DungeonSnapshot.swift | ダンジョン進行状態のイミュータブルスナップショット |
| ExplorationSnapshot.swift | 探索セッションのイミュータブルスナップショット |
| ItemSnapshot.swift | インベントリアイテムのイミュータブルスナップショット |
| LightweightItemData.swift | UI表示用の軽量アイテムデータ |
| PartySnapshot.swift | パーティ編成のイミュータブルスナップショット |
| PlayerSnapshot.swift | プレイヤー資産のイミュータブルスナップショット |
| ProgressMetadata.swift | 進行データ共通のメタデータ |
| RuntimeDungeon.swift | ダンジョン定義と進行状態の統合ビュー |
| RuntimeEquipment.swift | 装備アイテムの統合ビュー（マスター+インベントリ+価格） |
| RuntimeStoryNode.swift | ストーリーノード定義と進行状態の統合ビュー |
| ShopSnapshot.swift | 商店在庫のイミュータブルスナップショット |
| StorySnapshot.swift | ストーリー進行状態のイミュータブルスナップショット |

---

## Domain/Leveling

| ファイル | 責務 |
|---------|------|
| CharacterExperienceTable.swift | 経験値テーブルの管理、レベル・経験値の相互変換計算 |

---

## Domain/Models

| ファイル | 責務 |
|---------|------|
| CharacterInput.swift | Progress層からRuntime層へのキャラクターデータ受け渡し |
| ExplorationLogModels.swift | 探索ログの永続化用データ構造 |

---

## Domain/Values

| ファイル | 責務 |
|---------|------|
| CharacterValues.swift | キャラクター関連値型の名前空間 |

---

## Persistence/Models

SwiftDataモデル（永続化レコード）。

| ファイル | 責務 |
|---------|------|
| AutoTradeRecords.swift | 自動売却ルールのSwiftData永続化モデル |
| CharacterRecords.swift | キャラクターデータのSwiftData永続化モデル |
| DungeonRecords.swift | ダンジョン進行状態のSwiftData永続化モデル |
| ExplorationRecords.swift | 探索セッションのSwiftData永続化モデル |
| GameStateRecords.swift | ゲーム状態のSwiftData永続化モデル |
| InventoryItemRecord.swift | インベントリアイテムのSwiftData永続化モデル |
| PartyRecords.swift | パーティ編成のSwiftData永続化モデル |
| ProgressModelSchema.swift | SwiftDataモデル型の一括登録 |
| ShopRecords.swift | 商店在庫のSwiftData永続化モデル |
| StackKeyComponents.swift | stackKey文字列のパース・生成 |
| StoryRecords.swift | ストーリー進行状態のSwiftData永続化モデル |

---

## Application/Core

アプリケーション層の中核サービス。

| ファイル | 責務 |
|---------|------|
| AppConstants.swift | アプリケーション全体の定数定義 |
| AppServices.swift | 全サービスへのアクセス提供、サービス間依存関係の管理 |
| AppServices.ExplorationResume.swift | 中断探索の再開 |
| AppServices.ExplorationRun.swift | 探索セッションの開始・キャンセル |
| AppServices.ExplorationRuntime.swift | 探索イベントストリーム処理 |
| AppServices.ItemSale.swift | アイテム売却、在庫整理 |
| AppServices.Reset.swift | ゲームデータの完全リセット |
| AppServices.StoryUnlocks.swift | ストーリー・ダンジョン解放管理 |
| ProgressBootstrapper.swift | SwiftData ModelContainerの初期化 |

---

## Application/Progress

プレイヤー進行データを管理するサービス群。

| ファイル | 責務 |
|---------|------|
| ArtifactExchangeProgressService.swift | 神器交換機能 |
| AutoTradeProgressService.swift | 自動売却ルール管理 |
| CharacterProgressService.swift | キャラクターCRUD・装備・転職 |
| DungeonDisplayNameFormatter.swift | ダンジョン表示名のフォーマット |
| DungeonProgressService.swift | ダンジョン進行状態管理 |
| EquipmentProgressService.swift | 装備制限バリデーション |
| ExplorationProgressService.swift | 探索履歴永続化 |
| GameStateService.swift | プレイヤー資産管理 |
| GemModificationProgressService.swift | 宝石改造 |
| InventoryProgressService.swift | インベントリ管理 |
| ItemDropNotificationService.swift | ドロップ通知の管理 |
| UserDataLoadService.swift | ユーザーデータ一括ロード・キャッシュ |
| ItemSynthesisProgressService.swift | アイテム合成機能 |
| PartyProgressService.swift | パーティ編成永続化 |
| ProgressError.swift | Progress層のドメインエラー定義 |
| ProgressPersistenceError.swift | 永続化層固有のエラー定義 |
| ProgressRuntimeService.swift | Progress層とGameRuntime層のブリッジ |
| ShopProgressService.swift | 商店機能 |
| StoryProgressService.swift | ストーリー進行状態永続化 |
| TitleInheritanceProgressService.swift | 称号継承機能 |

---

## Application/GameRuntime/Battle

戦闘システム。

| ファイル | 責務 |
|---------|------|
| BattleContext.swift | 戦闘実行時のコンテキスト管理 |
| BattleContextBuilder.swift | プレイヤーパーティから戦闘用BattleActorを構築 |
| BattleEnemyGroupBuilder.swift | 敵グループの生成と敵BattleActorの構築 |
| BattleEnemyGroupConfigService.swift | ダンジョンの敵グループ構成ルールに基づくエンカウント生成 |
| BattleLog.swift | 戦闘ログのデータ構造定義 |
| BattleLogEntry.swift | 表示用の戦闘ログエントリ定義 |
| BattleLogRenderer.swift | 数値形式のBattleLogを表示用BattleLogEntryに変換 |
| BattleModels.swift | 戦闘関連の値型・列挙型定義 |
| BattleRandomSystem.swift | 戦闘用の乱数計算ユーティリティ |
| BattleRewardCalculator.swift | 戦闘報酬（経験値、ゴールド）の計算 |
| BattleService.swift | 戦闘の実行と結果の管理 |
| BattleTurnEngine.swift | 戦闘ターン処理の実行 |
| BattleTurnEngine.Damage.swift | ダメージ計算全般 |
| BattleTurnEngine.EnemySpecialSkill.swift | 敵専用スキルの実行処理 |
| BattleTurnEngine.Logging.swift | 戦闘ログ出力のヘルパー関数 |
| BattleTurnEngine.Magic.swift | 魔法攻撃と回復魔法の実行 |
| BattleTurnEngine.PhysicalAttack.swift | 物理攻撃の実行と結果適用 |
| BattleTurnEngine.Reactions.swift | 反撃と反応スキルの処理 |
| BattleTurnEngine.StatusEffects.swift | 状態異常の付与と判定 |
| BattleTurnEngine.Targeting.swift | 戦闘中のターゲット選択ロジック |
| BattleTurnEngine.TurnEnd.swift | ターン終了時の処理全般 |
| BattleTurnEngine.TurnLoop.swift | 戦闘ターンのメインループ制御 |
| CombatSnapshotBuilder.swift | 敵のCombatスナップショット生成 |

---

## Application/GameRuntime/Core

ゲームランタイムのコア処理。

| ファイル | 責務 |
|---------|------|
| CombatFormulas.swift | 戦闘ステータス計算式の定義 |
| CombatStatCalculator.swift | キャラクター戦闘ステータスの計算 |
| GameRuntimeService.swift | ランタイム系サービスのエントリーポイント |
| RuntimeCharacterFactory.swift | CharacterInputからRuntimeCharacterを生成 |
| RuntimeCharacterModels.swift | ランタイムキャラクターの型定義 |
| RuntimeError.swift | ランタイム層のエラー定義 |

---

## Application/GameRuntime/Drop

アイテムドロップシステム。

| ファイル | 責務 |
|---------|------|
| DropModels.swift | ドロップシステムで使用するモデル型の定義 |
| DropService.swift | 敵撃破時の戦利品計算の統合処理 |
| ItemDropRateCalculator.swift | アイテムのドロップ率計算と判定ロジック |
| ItemDropResult.swift | ドロップ結果の表現 |
| NormalItemDropGenerator.swift | ノーマルアイテムの候補を動的生成 |
| TitleAssignmentEngine.swift | アイテムドロップ時の称号付与判定 |

---

## Application/GameRuntime/Exploration

ダンジョン探索システム。

| ファイル | 責務 |
|---------|------|
| CombatExecutionService.swift | 探索中の戦闘実行と結果の統合 |
| ExplorationEngine.swift | ダンジョン探索の準備と進行管理 |
| ExplorationEventScheduler.swift | 探索イベントカテゴリの重み付き抽選 |
| ExplorationMasterDataProvider.swift | 探索で必要なマスターデータの取得 |
| ExplorationModels.swift | 探索システムで使用するモデル型の定義 |

---

## Application/GameRuntime/Party

パーティ管理。

| ファイル | 責務 |
|---------|------|
| PartyAssembler.swift | パーティスナップショットからランタイムパーティ状態を組み立て |
| RuntimePartyState.swift | 探索・戦闘で使用するランタイムパーティ状態の管理 |

---

## Application/GameRuntime/Random

乱数生成。

| ファイル | 責務 |
|---------|------|
| GameRandomSource.swift | ゲーム内のランダム性を供給する乱数生成器 |

---

## Application/GameRuntime/Skills

スキルエフェクトシステム。

| ファイル | 責務 |
|---------|------|
| ActorEffectsAccumulator.swift | スキルエフェクト蓄積 |
| SkillEffectFamily.swift | スキルエフェクトファミリーID管理 |
| SkillEffectHandler.swift | ハンドラプロトコル定義 |
| SkillEffectHandlers.Combat.swift | 戦闘関連ハンドラ実装 |
| SkillEffectHandlers.Damage.swift | ダメージ関連ハンドラ実装 |
| SkillEffectHandlers.Misc.swift | 雑多なハンドラ実装 |
| SkillEffectHandlers.Passthrough.swift | パススルーハンドラ |
| SkillEffectHandlers.Resurrection.swift | 復活関連ハンドラ実装 |
| SkillEffectHandlers.Spell.swift | 呪文関連ハンドラ実装 |
| SkillEffectHandlers.Status.swift | ステータス効果関連ハンドラ実装 |
| SkillEffectPayloadEnums.swift | パラメータ・値・配列タイプの定義 |
| SkillEffectPayloadSchema.swift | ペイロード値の型安全な共通スキーマ |
| SkillEffectType.swift | スキルエフェクトタイプ定義 |
| SkillRuntimeEffectCompiler.Actor.swift | BattleActor.SkillEffects構築 |
| SkillRuntimeEffectCompiler.Equipment.swift | 装備スロット情報抽出 |
| SkillRuntimeEffectCompiler.Exploration.swift | 探索モディファイア情報抽出 |
| SkillRuntimeEffectCompiler.Reward.swift | 報酬コンポーネント情報抽出 |
| SkillRuntimeEffectCompiler.Spell.swift | 呪文帳・呪文ロードアウト構築 |
| SkillRuntimeEffectCompiler.Validation.swift | ペイロードデコード・バリデーション処理 |
| SkillRuntimeEffects.Models.swift | Compilerの戻り値型 |
| SkillRuntimeEffects.swift | スキル効果コンパイラの名前空間定義 |

---

## Application/GameRuntime (root)

| ファイル | 責務 |
|---------|------|
| ItemPriceCalculator.swift | アイテム売買価格の計算 |

---

## Application/MasterData

マスターデータ読み込み。

| ファイル | 責務 |
|---------|------|
| MasterDataCache.swift | メモリキャッシュ提供、全マスターデータ保持 |
| MasterDataLoader.swift | SQLiteからMasterDataCache構築 |

### SQLite

| ファイル | 責務 |
|---------|------|
| SQLiteMasterDataManager.swift | SQLiteデータベース基本操作 |
| SQLiteMasterDataQueries.swift | クエリメソッド群の索引ファイル |
| SQLiteMasterDataQueries.CharacterNames.swift | 名前データ取得 |
| SQLiteMasterDataQueries.Dungeons.swift | ダンジョン・フロア・エンカウンター取得 |
| SQLiteMasterDataQueries.Enemies.swift | 敵・敵スキル取得 |
| SQLiteMasterDataQueries.ExplorationEvents.swift | 探索イベント取得 |
| SQLiteMasterDataQueries.Items.swift | アイテムデータ取得 |
| SQLiteMasterDataQueries.Jobs.swift | ジョブ・スキル解放・メタデータ取得 |
| SQLiteMasterDataQueries.Personality.swift | 性格データ取得 |
| SQLiteMasterDataQueries.Races.swift | 種族・パッシブ・スキル解放取得 |
| SQLiteMasterDataQueries.Shops.swift | ショップアイテム取得 |
| SQLiteMasterDataQueries.Skills.swift | スキル・エフェクト取得 |
| SQLiteMasterDataQueries.Spells.swift | 呪文データ取得 |
| SQLiteMasterDataQueries.StatusEffects.swift | ステータス効果取得 |
| SQLiteMasterDataQueries.Stories.swift | ストーリーノード取得 |
| SQLiteMasterDataQueries.Synthesis.swift | 合成レシピ取得 |
| SQLiteMasterDataQueries.Titles.swift | 称号・スーパーレア称号取得 |

---

## Application/System

システムサービス。

| ファイル | 責務 |
|---------|------|
| NotificationRuntimeManager.swift | プッシュ通知管理 |
| TimeIntegrityRuntimeService.swift | 時刻改ざん検知 |
| UserAvatarStore.swift | アバター画像ファイル管理 |

---

## UI/Components

再利用可能なUIコンポーネント。

| ファイル | 責務 |
|---------|------|
| BottomGameInfoView.swift | 画面下部に固定表示されるゲーム情報バーの表示 |
| CharacterImageView.swift | キャラクターのアバター画像を統一的に表示 |
| EnemyImageView.swift | 敵キャラクターの画像を表示 |
| EquipmentStatDeltaView.swift | 装備変更時のステータス差分を視覚的に表示 |
| ErrorView.swift | エラー発生時の汎用エラー表示画面 |
| HPBarView.swift | HPバーを3層構造で表示 |
| ItemDropNotificationView.swift | アイテムドロップ時の通知を画面上部に表示 |
| PartyCharacterSilhouettesView.swift | パーティメンバーを最大6枠のグリッドで簡易表示 |
| PartySlotCardView.swift | パーティスロットをカード形式で表示 |
| PriceView.swift | 価格を通貨種別に応じて表示 |
| RuntimeEquipmentRow.swift | 装備品を行形式で表示 |
| RuntimePartyMemberEditView.swift | パーティメンバーの編集画面を提供 |

### CharacterSections

| ファイル | 責務 |
|---------|------|
| CharacterActionPreferencesSection.swift | キャラクターの行動優先度を表示・編集 |
| CharacterBaseStatsSection.swift | キャラクターの基本能力値を表示 |
| CharacterCombatStatsSection.swift | キャラクターの戦闘ステータスを表示 |
| CharacterEquippedItemsSection.swift | キャラクターの装備中アイテム一覧を表示 |
| CharacterHeaderSection.swift | キャラクターのヘッダー情報を表示・編集 |
| CharacterIdentitySection.swift | キャラクターのプロフィール情報を表示 |
| CharacterLevelSection.swift | キャラクターのレベル・経験値情報を表示 |
| CharacterSectionType.swift | キャラクターセクション種別の定義 |
| CharacterSkillsSection.swift | キャラクターの習得スキル一覧を表示 |

---

## UI/Debug

デバッグ機能。

| ファイル | 責務 |
|---------|------|
| DebugMenuView.swift | 開発用デバッグ機能の提供 |

---

## UI/Encyclopedia

図鑑機能。

| ファイル | 責務 |
|---------|------|
| ItemEncyclopediaView.swift | アイテム図鑑の表示 |
| MonsterEncyclopediaView.swift | モンスター図鑑の表示 |
| SuperRareTitleEncyclopediaView.swift | 超レア称号図鑑の表示 |

---

## UI/Main

メイン画面。

| ファイル | 責務 |
|---------|------|
| AdventureView.swift | パーティ一覧の表示とダンジョン探索の管理 |
| AdventureViewState.swift | 探索状態の管理 |
| BattleStatsView.swift | 全キャラクターの戦闘能力を一覧表示 |
| CharacterCreationView.swift | 新規キャラクターの作成 |
| CharacterJobChangeView.swift | キャラクターの転職処理 |
| CharacterReviveView.swift | 戦闘不能キャラクターの蘇生 |
| GuildView.swift | ギルド機能のハブ画面 |
| MainTabView.swift | アプリのメインタブバー構成 |
| SettingsView.swift | 図鑑とデバッグメニューへのナビゲーション |
| ShopView.swift | 商店機能のハブ画面 |
| StoryView.swift | 解放済みストーリーノードの一覧表示 |

---

## UI/RootView

| ファイル | 責務 |
|---------|------|
| RootView.swift | アプリのルートビュー、初期化完了までのローディング表示 |

---

## UI/States

画面状態管理。

| ファイル | 責務 |
|---------|------|
| CharacterViewState.swift | キャラクター一覧とサマリ情報の管理 |
| PartyViewState.swift | パーティ一覧の管理 |

---

## UI/SubScreens

サブ画面・モーダル。

| ファイル | 責務 |
|---------|------|
| ArtifactExchangeView.swift | 神器交換機能を提供 |
| AutoTradeView.swift | 自動売却ルールの一覧表示 |
| CharacterAvatarSelectionSheet.swift | キャラクターのアバター画像選択機能 |
| CharacterSelectionForEquipmentView.swift | 装備変更用キャラクター選択 |
| EncounterDetailView.swift | 遭遇の詳細を表示 |
| ExplorationResultViews.swift | 探索結果のサマリーと履歴表示 |
| GemModificationView.swift | 宝石改造機能を提供 |
| InventoryCleanupView.swift | 在庫整理画面の表示 |
| ItemPurchaseView.swift | アイテム購入機能を提供 |
| ItemSaleView.swift | アイテム売却画面の表示 |
| ItemSynthesisView.swift | アイテム合成機能を提供 |
| LazyDismissCharacterView.swift | キャラクター解雇画面の表示 |
| PandoraBoxView.swift | パンドラボックス登録アイテムの管理 |
| PartySlotExpansionView.swift | パーティスロット拡張機能を提供 |
| RecentExplorationLogsView.swift | 最近の探索ログを表示 |
| RuntimeCharacterDetailView.swift | キャラクターの詳細情報を表示 |
| RuntimePartyDetailView.swift | パーティの詳細情報と探索管理機能を提供 |
| StoryDetailView.swift | ストーリーノードの詳細情報を表示 |
| TitleInheritanceView.swift | 称号継承機能を提供 |
