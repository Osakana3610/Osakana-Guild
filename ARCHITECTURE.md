# Epika Architecture

Epikaはダンジョン探索RPGのiOSアプリです。このドキュメントは各ファイルの責務を一覧化し、コントリビューターがコードベースを理解するための参照資料です。

## 設計方針

- **三層設計**: UI (@MainActor) / サービス (状態・I/O) / 計算 (純関数)
- **Swift 6 Concurrency**: actor, @Observable, 構造化並行性を活用
- **SwiftData**: プレイヤー進行データの永続化
- **SQLite**: マスターデータ（読み取り専用）

---

## App Entry Point

| ファイル | 責務 |
|---------|------|
| EpikaApp.swift | アプリエントリーポイント、起動シーケンス制御、ModelContainer/AppServicesのライフサイクル管理 |

---

## Models/MasterData

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

## Progress/Application

プレイヤー進行データを管理するアプリケーション層。

### AppServices（ファサード）

| ファイル | 責務 |
|---------|------|
| AppServices.swift | 全サービスへのアクセス提供、サービス間依存関係の管理 |
| AppServices.ExplorationResume.swift | 中断探索の再開、乱数状態・HP・ドロップ状態の復元 |
| AppServices.ExplorationRun.swift | 探索セッションの開始・キャンセル、パーティ出撃準備 |
| AppServices.ExplorationRuntime.swift | 探索イベントストリーム処理、報酬適用、ドロップ追加 |
| AppServices.ItemSale.swift | アイテム売却、在庫整理、ソケット宝石分離 |
| AppServices.Reset.swift | ゲームデータの完全リセット |
| AppServices.StoryUnlocks.swift | ストーリー・ダンジョン解放管理、難易度解放 |

### Notifications

| ファイル | 責務 |
|---------|------|
| ItemDropNotificationService.swift | ドロップ通知の管理、UI表示用データ変換 |

### Runtime

| ファイル | 責務 |
|---------|------|
| ProgressRuntimeService.swift | Progress層とGameRuntime層のブリッジ、探索セッション管理 |

### Services

| ファイル | 責務 |
|---------|------|
| ArtifactExchangeProgressService.swift | 神器交換機能 |
| AutoTradeProgressService.swift | 自動売却ルール管理 |
| CharacterProgressService.swift | キャラクターCRUD・装備・転職・戦闘結果・RuntimeCharacter生成 |
| DungeonProgressService.swift | ダンジョン進行状態・解放・クリア・難易度管理 |
| EquipmentProgressService.swift | 装備制限バリデーション（純粋関数） |
| ExplorationProgressService.swift | 探索履歴永続化、レコード作成・更新・終了 |
| GameStateService.swift | プレイヤー資産（ゴールド/チケット）・リセット・超レア日次状態 |
| GemModificationProgressService.swift | 宝石改造（ソケット装着・分離） |
| InventoryProgressService.swift | インベントリ管理（追加・削除・数量変更） |
| ItemPreloadService.swift | アイテム表示データのプリロード・キャッシュ |
| ItemSynthesisProgressService.swift | アイテム合成機能 |
| PartyProgressService.swift | パーティ編成永続化 |
| ShopProgressService.swift | 商店機能（購入・在庫管理・在庫整理） |
| StoryProgressService.swift | ストーリー進行状態永続化 |
| TitleInheritanceProgressService.swift | 称号継承機能 |

---

## Progress/Domain

ドメインモデル・スナップショット・値オブジェクト。

### Leveling

| ファイル | 責務 |
|---------|------|
| CharacterExperienceTable.swift | 経験値テーブルの管理、レベル・経験値の相互変換計算 |

### Models

| ファイル | 責務 |
|---------|------|
| CharacterInput.swift | Progress層からRuntime層へのキャラクターデータ受け渡し |
| ExplorationLogModels.swift | 探索ログの永続化用データ構造、戦闘結果・イベントログのCodable型 |

### Snapshots

| ファイル | 責務 |
|---------|------|
| CharacterSnapshot.swift | キャラクターデータのイミュータブルスナップショット、永続化層とUI/サービス層の橋渡し |
| DungeonSnapshot.swift | ダンジョン進行状態のイミュータブルスナップショット、解放・難易度・クリア状況の表現 |
| ExplorationSnapshot.swift | 探索セッションのイミュータブルスナップショット、探索状態・報酬・エンカウントログの表現 |
| ItemSnapshot.swift | インベントリアイテムのイミュータブルスナップショット、スタック・称号・ソケット情報の表現 |
| LightweightItemData.swift | UI表示用の軽量アイテムデータ、アイテムカテゴリ・レアリティの分類 |
| PartySnapshot.swift | パーティ編成のイミュータブルスナップショット、永続化層とUI/サービス層の橋渡し |
| PlayerSnapshot.swift | プレイヤー資産のイミュータブルスナップショット、ゴールド・チケット・パーティスロット・パンドラボックスの表現 |
| ProgressMetadata.swift | 進行データ共通のメタデータ、作成日時・更新日時の管理 |
| RuntimeDungeon.swift | ダンジョン定義と進行状態の統合ビュー、UI表示用のランタイムダンジョン情報 |
| RuntimeEquipment.swift | 装備アイテムの統合ビュー（マスター+インベントリ+価格）、UI表示・装備選択用のランタイム装備情報 |
| RuntimeParty.swift | RuntimeParty型エイリアスの定義、後方互換性のためのPartySnapshotへのエイリアス |
| RuntimeStoryNode.swift | ストーリーノード定義と進行状態の統合ビュー、UI表示用のランタイムストーリー情報 |
| ShopSnapshot.swift | 商店在庫のイミュータブルスナップショット、在庫状態・プレイヤー売却品の表現 |
| StorySnapshot.swift | ストーリー進行状態のイミュータブルスナップショット、解放・既読・報酬受取状態の管理 |

### Values

| ファイル | 責務 |
|---------|------|
| CharacterValues.swift | キャラクター関連値型の名前空間、CharacterSnapshot/RuntimeCharacterで共有される構造体の定義 |

---

## Progress/Persistence

SwiftDataモデル（永続化レコード）。

| ファイル | 責務 |
|---------|------|
| AutoTradeRecords.swift | 自動売却ルールのSwiftData永続化モデル、アイテム構成要素（称号・ソケット含む）の保存 |
| CharacterRecords.swift | キャラクターデータのSwiftData永続化モデル、キャラクター基本情報・装備の保存 |
| DungeonRecords.swift | ダンジョン進行状態のSwiftData永続化モデル、解放・クリア・到達階層の保存 |
| ExplorationRecords.swift | 探索セッションのSwiftData永続化モデル、探索実行・イベント履歴の保存 |
| GameStateRecords.swift | ゲーム状態のSwiftData永続化モデル、プレイヤー資産・日次処理状態・パンドラボックスの保存 |
| InventoryItemRecord.swift | インベントリアイテムのSwiftData永続化モデル、アイテムスタック（称号・ソケット・数量）の保存 |
| PartyRecords.swift | パーティ編成のSwiftData永続化モデル、パーティ基本情報・メンバー構成の保存 |
| ProgressModelSchema.swift | SwiftDataモデル型の一括登録、ModelContainerへの全永続化モデル提供 |
| ShopRecords.swift | 商店在庫のSwiftData永続化モデル、在庫数・プレイヤー売却品フラグの保存 |
| StackKeyComponents.swift | stackKey文字列のパース・生成、アイテム識別用6要素コンポーネントの管理 |
| StoryRecords.swift | ストーリー進行状態のSwiftData永続化モデル、ノードごとの解放・既読・報酬受取状態の保存 |

---

## Progress/Support

進行データ関連のユーティリティ。

| ファイル | 責務 |
|---------|------|
| DungeonDisplayNameFormatter.swift | ダンジョン表示名のフォーマット、難易度システムの定義・管理 |
| ProgressBootstrapper.swift | SwiftData ModelContainerの初期化、進行データストアのライフサイクル管理・マイグレーション処理 |
| ProgressError.swift | Progress層のドメインエラー定義、ユーザー向けローカライズエラーメッセージ |
| ProgressPersistenceError.swift | 永続化層固有のエラー定義、SwiftData操作エラーの表現 |

---

## Services/Configuration

| ファイル | 責務 |
|---------|------|
| AppConstants.swift | アプリケーション全体の定数定義、UIサイズ・進行データ上限・コスト計算 |

---

## Services/GameRuntime/Battle

戦闘システム。

| ファイル | 責務 |
|---------|------|
| BattleContext.swift | 戦闘実行時のコンテキスト管理、参照データ・可変状態の保持 |
| BattleContextBuilder.swift | プレイヤーパーティから戦闘用BattleActorを構築、キャラクターのステータス・スキル効果・装備等を戦闘用に変換 |
| BattleEnemyGroupBuilder.swift | 敵グループの生成と敵BattleActorの構築、ダンジョン設定に基づく敵エンカウントの生成 |
| BattleEnemyGroupConfigService.swift | ダンジョンの敵グループ構成ルールに基づくエンカウント生成、フロア別敵プールとノーマルプールの混合制御 |
| BattleLog.swift | 戦闘ログのデータ構造定義（数値形式）、行動種別（ActionKind）の定義 |
| BattleLogEntry.swift | 表示用の戦闘ログエントリ定義、ログタイプの分類（システム、行動、ダメージ、回復等） |
| BattleLogRenderer.swift | 数値形式のBattleLogを表示用BattleLogEntryに変換、アクターインデックスからキャラクター名への解決 |
| BattleModels.swift | 戦闘関連の値型・列挙型定義、アクター・行動・ダメージの表現 |
| BattleRandomSystem.swift | 戦闘用の乱数計算ユーティリティ、運ステータスに基づく乱数範囲の計算 |
| BattleRewardCalculator.swift | 戦闘報酬（経験値、ゴールド）の計算、レベル差による倍率調整、スキルによる報酬倍率の適用 |
| BattleService.swift | 戦闘の実行と結果の管理、戦闘前準備から結果解決までの統合API |
| BattleTurnEngine.swift | 戦闘ターン処理の実行、勝敗判定・ターン終了処理 |
| BattleTurnEngine.Damage.swift | ダメージ計算全般（物理、魔法、ブレス、回復）、命中判定と回避計算、クリティカル判定 |
| BattleTurnEngine.EnemySpecialSkill.swift | 敵専用スキルの実行処理、スキルタイプ別の処理分岐、スキル使用回数管理 |
| BattleTurnEngine.Logging.swift | 戦闘ログ出力のヘルパー関数、各種行動・結果のログ記録 |
| BattleTurnEngine.Magic.swift | 魔法攻撃と回復魔法の実行、ブレス攻撃の実行、呪文の選択とチャージ消費 |
| BattleTurnEngine.PhysicalAttack.swift | 物理攻撃の実行と結果適用、特殊攻撃の処理、格闘戦と追撃処理、先制攻撃の実行 |
| BattleTurnEngine.Reactions.swift | 反撃と反応スキルの処理、受け流し・盾ブロックの判定、ダメージ吸収 |
| BattleTurnEngine.StatusEffects.swift | 状態異常の付与と判定、状態異常の継続ダメージ処理、状態異常の自然回復 |
| BattleTurnEngine.Targeting.swift | 戦闘中のターゲット選択ロジック、重み付きランダムターゲット選択、かばう処理 |
| BattleTurnEngine.TurnEnd.swift | ターン終了時の処理全般、状態異常のティック処理、自動蘇生とネクロマンサー、時限バフの管理 |
| BattleTurnEngine.TurnLoop.swift | 戦闘ターンのメインループ制御、行動順序の決定、行動選択（AI）、撤退処理 |
| CombatSnapshotBuilder.swift | 敵のCombatスナップショット生成、敵定義から戦闘用ステータスへの変換 |

---

## Services/GameRuntime/Core

ゲームランタイムのコア処理。

| ファイル | 責務 |
|---------|------|
| CombatFormulas.swift | 戦闘ステータス計算式の定義、レベル依存・ステータス依存の係数計算 |
| CombatStatCalculator.swift | キャラクター戦闘ステータスの計算、種族・職業・装備・スキル効果の統合 |
| GameRuntimeService.swift | ランタイム系サービスのエントリーポイント、探索セッション開始・再開・キャンセル管理 |
| RuntimeCharacterFactory.swift | CharacterInputからRuntimeCharacterを生成、マスターデータ取得と戦闘ステータス計算の統合 |
| RuntimeCharacterModels.swift | ランタイムキャラクターの型定義、ゲームロジックで使用する完全なキャラクター表現 |
| RuntimeError.swift | ランタイム層のエラー定義、ユーザー向けローカライズエラーメッセージ |

---

## Services/GameRuntime/Drop

アイテムドロップシステム。

| ファイル | 責務 |
|---------|------|
| DropModels.swift | ドロップシステムで使用するモデル型の定義、パーティのドロップ補正値の計算ロジック |
| DropService.swift | 敵撃破時の戦利品計算の統合処理、レアアイテムとノーマルアイテムのドロップ判定 |
| ItemDropRateCalculator.swift | アイテムのドロップ率計算と判定ロジック、カテゴリ別の基本閾値の算出 |
| ItemDropResult.swift | ドロップ結果の表現 |
| NormalItemDropGenerator.swift | 敵種族とダンジョン章に基づいてノーマルアイテムの候補を動的生成 |
| TitleAssignmentEngine.swift | アイテムドロップ時の称号付与判定、通常称号の抽選とランク選択 |

---

## Services/GameRuntime/Exploration

ダンジョン探索システム。

| ファイル | 責務 |
|---------|------|
| CombatExecutionService.swift | 探索中の戦闘実行と結果の統合、戦闘後の報酬計算とドロップ処理 |
| ExplorationEngine.swift | ダンジョン探索の準備と進行管理、フロア・イベント単位での探索ステップ実行 |
| ExplorationEventScheduler.swift | 探索イベントカテゴリの重み付き抽選、「何も起こらない」「スクリプトイベント」「戦闘」の選択 |
| ExplorationMasterDataProvider.swift | 探索で必要なマスターデータの取得インターフェース定義、MasterDataCacheからの探索データ取得実装 |
| ExplorationModels.swift | 探索システムで使用するモデル型の定義 |

---

## Services/GameRuntime/Party

パーティ管理。

| ファイル | 責務 |
|---------|------|
| PartyAssembler.swift | パーティスナップショットとキャラクターデータからランタイムパーティ状態を組み立て |
| RuntimePartyState.swift | 探索・戦闘で使用するランタイムパーティ状態の管理、パーティメンバーのステータスに基づく補正値の計算 |

---

## Services/GameRuntime/Random

乱数生成。

| ファイル | 責務 |
|---------|------|
| GameRandomSource.swift | ゲーム内のランダム性を供給する乱数生成器、シード付き初期化による決定的な乱数列の提供 |

---

## Services/GameRuntime/Skills

スキルエフェクトシステム。

| ファイル | 責務 |
|---------|------|
| ActorEffectsAccumulator.swift | スキルエフェクト蓄積、BattleActor.SkillEffects構築 |
| SkillEffectFamily.swift | スキルエフェクトファミリーID管理、378種のエフェクト分類 |
| SkillEffectHandler.swift | ハンドラプロトコル定義、レジストリ管理、コンテキスト提供 |
| SkillEffectHandlers.Combat.swift | 戦闘関連ハンドラ実装（Proc・追加行動・バリア・特殊攻撃等） |
| SkillEffectHandlers.Damage.swift | ダメージ関連ハンドラ実装（与ダメ・被ダメ・クリティカル・武術等） |
| SkillEffectHandlers.Misc.swift | 雑多なハンドラ実装（列プロ・回復・敵対・装備補正・逃走等） |
| SkillEffectHandlers.Passthrough.swift | 他のCompilerで処理されるが登録が必要なハンドラ |
| SkillEffectHandlers.Resurrection.swift | 復活関連ハンドラ実装（救出・自動復活・強制復活・ネクロ等） |
| SkillEffectHandlers.Spell.swift | 呪文関連ハンドラ実装（威力・チャージ・習得・クリティカル等） |
| SkillEffectHandlers.Status.swift | ステータス効果関連ハンドラ実装（耐性・付与・バフトリガー等） |
| SkillEffectPayloadEnums.swift | パラメータ・値・配列タイプの定義（42+65+3種類） |
| SkillEffectPayloadSchema.swift | ペイロード値の型安全な共通スキーマ |
| SkillEffectType.swift | スキルエフェクトタイプ定義（UInt8 enum、カテゴリ別分類） |
| SkillRuntimeEffectCompiler.Actor.swift | BattleActor.SkillEffects構築、statScaling計算対応 |
| SkillRuntimeEffectCompiler.Equipment.swift | 装備スロット情報抽出（additive・multiplier処理） |
| SkillRuntimeEffectCompiler.Exploration.swift | 探索モディファイア情報抽出（ダンジョン別時間倍率） |
| SkillRuntimeEffectCompiler.Reward.swift | 報酬コンポーネント情報抽出（経験値・ゴールド・アイテム・称号） |
| SkillRuntimeEffectCompiler.Spell.swift | 呪文帳・呪文ロードアウト構築（習得・忘却・ティア解放） |
| SkillRuntimeEffectCompiler.Validation.swift | ペイロードデコード・バリデーション処理 |
| SkillRuntimeEffects.Models.swift | Compilerの戻り値型（Spellbook・Loadout・Slots・Reward・Exploration等） |
| SkillRuntimeEffects.swift | スキル効果コンパイラの名前空間定義 |

---

## Services/GameRuntime (root)

| ファイル | 責務 |
|---------|------|
| ItemPriceCalculator.swift | アイテム売買価格の計算、称号・ソケット・数量に基づく価格算出 |

---

## Services/MasterData

マスターデータ読み込み。

| ファイル | 責務 |
|---------|------|
| MasterDataCache.swift | メモリキャッシュ提供、全マスターデータ保持、スレッドセーフアクセス |
| MasterDataLoader.swift | SQLiteからMasterDataCache構築（約10,700レコード、1.6MB） |

### SQLite

| ファイル | 責務 |
|---------|------|
| SkillEffectReverseMappings.swift | SQLiteテーブル整数値を文字列に逆変換 |
| SQLiteMasterDataManager.swift | SQLiteデータベース基本操作（接続・スキーマ検証・トランザクション） |
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

## Services/System

システムサービス。

| ファイル | 責務 |
|---------|------|
| NotificationRuntimeManager.swift | プッシュ通知管理、権限リクエスト、カテゴリー設定 |
| TimeIntegrityRuntimeService.swift | 時刻改ざん検知、操作履歴記録、時系列管理 |

---

## Services/UserContent

ユーザーコンテンツ管理。

| ファイル | 責務 |
|---------|------|
| UserAvatarStore.swift | アバター画像ファイル管理、リサイズ・モノクロ加工処理 |

---

## Views/Components

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
| RuntimePartyMemberEditView.swift | パーティメンバーの編集画面（最大6名）を提供 |

### CharacterSections

| ファイル | 責務 |
|---------|------|
| CharacterActionPreferencesSection.swift | キャラクターの行動優先度（攻撃/僧侶魔法/魔法使い魔法/ブレス）を表示・編集 |
| CharacterBaseStatsSection.swift | キャラクターの基本能力値（力・知恵・精神・体力・敏捷・運）を表示 |
| CharacterCombatStatsSection.swift | キャラクターの戦闘ステータス（HP、攻撃力、防御力等）を表示 |
| CharacterEquippedItemsSection.swift | キャラクターの装備中アイテム一覧を表示 |
| CharacterHeaderSection.swift | キャラクターのヘッダー情報（名前、アバター画像）を表示・編集 |
| CharacterIdentitySection.swift | キャラクターのプロフィール情報（種族、職業、性別）を表示 |
| CharacterLevelSection.swift | キャラクターのレベル・経験値情報を表示 |
| CharacterSectionType.swift | キャラクターセクション種別の定義 |
| CharacterSkillsSection.swift | キャラクターの習得スキル一覧を表示 |

---

## Views/Debug

デバッグ機能。

| ファイル | 責務 |
|---------|------|
| DebugMenuView.swift | 開発用デバッグ機能（アイテム大量生成、ドロップ通知テスト、データリセット）の提供 |

---

## Views/Encyclopedia

図鑑機能。

| ファイル | 責務 |
|---------|------|
| ItemEncyclopediaView.swift | アイテム図鑑の表示 |
| MonsterEncyclopediaView.swift | モンスター図鑑の表示 |
| SuperRareTitleEncyclopediaView.swift | 超レア称号図鑑の表示 |

---

## Views/Main

メイン画面。

| ファイル | 責務 |
|---------|------|
| AdventureView.swift | パーティ一覧の表示とダンジョン探索の管理 |
| AdventureViewState.swift | 探索状態の管理（進行中の探索ハンドル、タスク管理） |
| BattleStatsView.swift | 全キャラクターの戦闘能力を一覧表示 |
| CharacterCreationView.swift | 新規キャラクターの作成（酒場での求人） |
| CharacterJobChangeView.swift | キャラクターの転職処理 |
| CharacterReviveView.swift | 戦闘不能キャラクター（HP 0）の蘇生 |
| GuildView.swift | ギルド機能のハブ画面 |
| MainTabView.swift | アプリのメインタブバー構成 |
| SettingsView.swift | 図鑑とデバッグメニューへのナビゲーション |
| ShopView.swift | 商店機能のハブ画面 |
| StoryView.swift | 解放済みストーリーノードの一覧表示 |

---

## Views/RootView

| ファイル | 責務 |
|---------|------|
| RootView.swift | アプリのルートビュー、初期化完了までのローディング表示 |

---

## Views/States

画面状態管理。

| ファイル | 責務 |
|---------|------|
| CharacterViewState.swift | キャラクター一覧とサマリ情報の管理 |
| PartyViewState.swift | パーティ一覧の管理 |

---

## Views/SubScreens

サブ画面・モーダル。

| ファイル | 責務 |
|---------|------|
| ArtifactExchangeView.swift | 所持している神器を他の神器と交換する機能を提供 |
| AutoTradeView.swift | 自動売却ルールの一覧表示、ルールの削除管理 |
| CharacterAvatarSelectionSheet.swift | キャラクターのアバター画像選択機能を提供 |
| CharacterSelectionForEquipmentView.swift | 装備変更用キャラクター選択、装備編集画面への遷移 |
| EncounterDetailView.swift | 探索中の特定の遭遇（戦闘・イベント）の詳細を表示 |
| ExplorationResultViews.swift | 探索結果のサマリーと履歴表示用のView群を提供 |
| GemModificationView.swift | 装備アイテムに宝石を装着してステータスを追加する宝石改造機能を提供 |
| InventoryCleanupView.swift | 在庫整理画面の表示、99個超過アイテムの整理、キャット・チケット獲得処理 |
| ItemPurchaseView.swift | 商店からアイテムを購入する機能を提供 |
| ItemSaleView.swift | アイテム売却画面の表示、複数選択による一括売却 |
| ItemSynthesisView.swift | アイテム合成機能を提供（親アイテムと子アイテムを組み合わせ） |
| LazyDismissCharacterView.swift | キャラクター解雇画面の表示、解雇対象キャラクターの選択 |
| PandoraBoxView.swift | パンドラボックス登録アイテムの管理 |
| PartySlotExpansionView.swift | ギルド改造（パーティスロット拡張）機能を提供 |
| RecentExplorationLogsView.swift | パーティの最近の探索ログ（最大2件）を表示 |
| RuntimeCharacterDetailView.swift | キャラクターの詳細情報を表示するシートとコンテンツを提供 |
| RuntimePartyDetailView.swift | パーティの詳細情報と探索開始・管理機能を提供 |
| StoryDetailView.swift | ストーリーノードの詳細情報を表示し、既読処理を実行 |
| TitleInheritanceView.swift | アイテムの称号継承機能を提供（称号を他のアイテムに移す） |
