# 戦闘ログ仕様

## 概要
戦闘中に発生した行動・結果を「BattleLog」として記録し、探索履歴で参照できるように永続化する。
ログは戦闘計算の副産物ではなく、**戦闘処理の各所で明示的に追加**される。

## 目的・存在意義
戦闘は自動進行であり、ユーザーが介入できるのは編成のみである。  
そのため戦闘ログは**敗因や惜しかった点、編成改善の判断材料を提供する唯一の手がかり**となる。  
このログが正しくない、欠落や矛盾がある、順序が崩れる、表示が不十分である場合、  
ユーザーは調整の手立てを失い、ゲームの中核体験が成立しない。  
よって本仕様は**ログの正確性・完全性・再現性を最優先**とし、  
「ログの確認と調整」が本ゲーム体験の核心であることを前提に設計する。

## スコープ
- 生成: BattleTurnEngine → BattleContext → BattleLog
- 永続化: BattleLogArchive → BattleLogRecord.logData（バイナリ）
- 表示: BattleLogRenderer → BattleLogEntry
- 付随: HP復元（BattleLogEffectInterpreter）

## 生成フロー（概略）
```
BattleTurnEngine.runBattle
  -> BattleContext.buildInitialHP
  -> BattleLog.entries を append
  -> BattleLog を Result にまとめる
  -> CombatExecutionService が BattleLogArchive を構築
  -> ExplorationProgressService が BattleLogRecord.logData を保存
```

## データ構造

### BattleLog（永続化の正本）
```swift
struct BattleLog {
  static let currentVersion: UInt8 = 1
  var version: UInt8
  var initialHP: [UInt16: UInt32]
  var entries: [BattleActionEntry]
  var outcome: UInt8        // 0=victory, 1=defeat, 2=retreat
  var turns: UInt8
}
```

### BattleActionEntry（1アクションの宣言＋結果）
```swift
struct BattleActionEntry {
  var turn: UInt8
  var actor: UInt16?
  var declaration: Declaration
  var effects: [Effect]
}

struct Declaration {
  var kind: ActionKind
  var skillIndex: UInt16?
  var extra: UInt16?
}

struct Effect {
  enum Kind: UInt8 { ... }
  var kind: Kind
  var target: UInt16?
  var value: UInt32?
  var statusId: UInt16?
  var extra: UInt16?
}
```

### BattleLogEntry（表示用）
```swift
struct BattleLogEntry {
  var turn: Int
  var message: String
  var type: LogType
  var actorId: String?
  var targetId: String?
}
```

補足:
- `actorId` / `targetId` は**UI表示用の補助キー**であり、永続化しない。
- 原則として **actorIndex を文字列化した値**を使用する（例: `"1001"`）。

## 表示文言とローカライズ
- BattleLog は**平文メッセージを保存しない**。表示文は BattleLogRenderer が生成する。
- 表示文言は `Localizable.strings` に集約し、**BattleLogRenderer でのハードコードは禁止**する。
- 内部処理は `ActionKind` / `Effect.Kind` / `Declaration` / `Effect` で完結させ、表示はキーから引く。
  - 宣言ログ: `battleLog.declaration.<actionKind>`
  - 効果ログ: `battleLog.effect.<effectKind>`
- 置換は `%@` などのテンプレート方式で行い、`{actor}` / `{target}` / `{amount}` / `{label}` / `{turn}` を差し込む。
  - 数値の整形は render 前に行い、`amount` は整形済み文字列として差し込む。
- `{label}` は**保存値ではなく、IDから解決した表示名**を指す（スキル名/呪文名/状態名/バフ名など）。
- 表示名は**必ず MasterData から解決**し、ログ本体に平文を保存しない。
  - 解決に必要なIDが欠ける場合は不正（エラー規則に従う）。
- 本仕様の表にある日本語文言は **Localizable の既定文言（defaultValue）** とみなす。

## ActorIndex の取り扱い
- プレイヤー側: `characterId` をそのまま `UInt16` にして使用（`actorIndex == characterId`）。`partyMemberId` は保持しない。
- 敵側: `(arrayIndex + 1) * 1000 + enemyMasterIndex`。
- ログ（`BattleActionEntry`）は **actorIndex を主キー**として保持する。
- 表示名は `BattleParticipantSnapshot` から **actorIndex → name** で解決する。

## 参加者スナップショット（BattleParticipantSnapshot）
- `actorIndex` は**戦闘内で一意**となる `UInt16`。
  - プレイヤー: `characterId` を使用（`actorIndex == characterId`）。`partyMemberId` は保持しない。
  - 敵: `actorIndex` を使用（上記規則）。
- `characterId` は**プレイヤーのみ保持**し、`actorIndex` と同値とする（敵は 0 を格納）。
- `name` は表示用の**確定名**とし、同名の敵が複数いる場合は **A/B/C... のサフィックス**を付与する。
- `playerSnapshots` は**パーティ順**を保持する。
- `enemySnapshots` は **enemyMasterIndex 昇順 → 同一ID内は出現順**で並べる。

## ログ追加の基本
- `BattleContext.appendActionEntry` を使って**アクション単位で追加**する。
- 1回の行動（スキル/魔法/効果）で複数対象に効果がある場合でも**1つの `BattleActionEntry` にまとめ**、`effects` に対象ごとの効果を並べる。
- `appendSimpleEntry` は「宣言＋1効果」を簡易追加するヘルパー。
- `appendSimpleEntry` で複数対象の行動を**分割記録してはならない**（複数対象は必ず `BattleActionEntry.Builder` で1件にまとめる）。

## 順序の規範（実装の指針）
- **処理順とログ順は常に一致させる**。後から並べ替えたり、前後関係を入れ替えてはならない。
- 1アクションの内部順序は以下を基準とする（例: 攻撃/魔法/スキル）  
  1) 行動者確定 → 対象確定  
  2) 命中/回避・効果の成否判定  
  3) ダメージ/回復/付与の量を確定・適用  
  4) 死亡判定  
  5) それに伴う処理（救出・蘇生・リアクション等）
- **ログ追加は 3)〜5) の処理が完了した後に行う**（途中で確定したログを先に出さない）。
- 反応・救出・追撃など**後続の処理は、必ず原因となった行動ログの後に並ぶ**。

## フィールド意味論（Declaration / Effect）

### Declaration（行動宣言）
- `turn`: ログが属するターン。`turnStart` 表示や探索履歴の区切りに使用する。
- `actor`: 行動者の `actorIndex`。**戦闘開始/終了などのシステムログ以外では必須**。
- `kind`: 行動種別（`ActionKind`）。rawValue は固定（互換性のため再割当しない）。
- `skillIndex`: 行動がスキル/呪文/敵専用技に由来する場合はそのID（必須）。
  - `priestMagic`/`mageMagic` は `spellId`（`UInt8`）を `UInt16` に格納。
  - `enemySpecialSkill` は `enemySkillId`。
  - その他のスキル由来行動は `skillId`。
- `buffApply` / `buffExpire` / `reactionAttack` / `followUp` は**発動元スキルの `skillId`**を必須とする。
  - **システム由来のみ**例外として `skillIndex` を省略でき、その場合は固定文言で表示する。
- `extra`: **明示的に用途が定義された `ActionKind` のみ使用**（例: `turnStart` の表示ターン）。
  - `turnStart` は `extra` を必須とし、`turn` と同じ値を設定する。

### Effect（結果）
- `kind`: 結果種別（`Effect.Kind`）。**宣言の `ActionKind` と整合する種類のみ使用**する。
- `target`: 影響を受けた `actorIndex`。HP変動や状態変化がある種別では必須。
- `value`: 数値結果。**HP変動を伴う種別では必須**。値は「適用後（クランプ後）」の量。
- `statusId`: 状態異常ID。`statusInflict` / `statusResist` / `statusRecover` / `statusTick` では必須。
- `extra`: 追加情報。**ダメージ系では生値（軽減前）を格納し、表示用途のみに使用**する。

#### Effect.Kind 必須フィールド
| Effect.Kind | target | value | statusId | extra | 意味 |
|---|---|---|---|---|---|
| physicalDamage | 必須 | 必須 | 不要 | 任意 | 物理ダメージ（value=適用後、extra=生値） |
| physicalEvade | 必須 | 不要 | 不要 | 不要 | 物理回避 |
| physicalParry | 必須 | 不要 | 不要 | 不要 | パリィ |
| physicalBlock | 必須 | 不要 | 不要 | 不要 | 盾防御 |
| physicalKill | 必須 | 不要 | 不要 | 不要 | 撃破（HP=0） |
| martial | 不要 | 不要 | 不要 | 不要 | 格闘戦表示専用 |
| magicDamage | 必須 | 必須 | 不要 | 任意 | 魔法ダメージ（value=適用後、extra=生値） |
| magicHeal | 必須 | 必須 | 不要 | 不要 | 魔法回復（value=適用後） |
| magicMiss | 不要 | 不要 | 不要 | 不要 | 魔法無効（メッセージのみ） |
| breathDamage | 必須 | 必須 | 不要 | 任意 | ブレスダメージ（value=適用後、extra=生値） |
| statusInflict | 必須 | 不要 | 必須 | 不要 | 状態異常付与 |
| statusResist | 必須 | 不要 | 必須 | 不要 | 状態異常抵抗 |
| statusRecover | 必須 | 不要 | 必須 | 不要 | 状態異常解除（解除した状態ID） |
| statusTick | 必須 | 必須 | 必須 | 任意 | 継続ダメージ（value=適用後、extra=生値） |
| statusConfusion | 必須 | 不要 | 不要 | 不要 | 暴走/混乱発生 |
| statusRampage | 必須 | 必須 | 不要 | 任意 | 暴走ダメージ（value=適用後、extra=生値） |
| reactionAttack | 必須 | 不要 | 不要 | 不要 | 反撃発動（target=反撃対象） |
| followUp | 必須 | 不要 | 不要 | 不要 | 追撃発動（target=追撃対象） |
| healAbsorb | 必須 | 必須 | 不要 | 不要 | 吸収回復（target=回復者） |
| healVampire | 必須 | 必須 | 不要 | 不要 | 吸血回復（target=回復者） |
| healParty | 必須 | 必須 | 不要 | 不要 | 全体回復の対象ごとの回復 |
| healSelf | 必須 | 必須 | 不要 | 不要 | 自己回復 |
| damageSelf | 必須 | 必須 | 不要 | 任意 | 自己ダメージ（value=適用後、extra=生値） |
| buffApply | 必須 | 不要 | 不要 | 不要 | バフ付与（対象ごと） |
| buffExpire | 必須 | 不要 | 不要 | 不要 | バフ解除（対象ごと） |
| resurrection | 必須 | 必須 | 不要 | 不要 | 蘇生（value=蘇生後HP） |
| necromancer | 必須 | 必須 | 不要 | 不要 | ネクロマンサー蘇生（value=蘇生後HP） |
| rescue | 必須 | 必須 | 不要 | 不要 | 救出（value=蘇生後HP） |
| actionLocked | 必須 | 不要 | 不要 | 不要 | 行動不能（target=行動不能者） |
| noAction | 必須 | 不要 | 不要 | 不要 | 何もしない（target=行動者） |
| withdraw | 必須 | 不要 | 不要 | 不要 | 戦線離脱（target=離脱者） |
| sacrifice | 必須 | 不要 | 不要 | 不要 | 供儀対象（target=供儀対象） |
| vampireUrge | 必須 | 不要 | 不要 | 不要 | 吸血衝動（target=襲撃対象） |
| enemySpecialDamage | 必須 | 必須 | 不要 | 任意 | 敵専用技ダメージ（value=適用後、extra=生値） |
| enemySpecialHeal | 必須 | 必須 | 不要 | 不要 | 敵専用技回復（value=適用後） |
| enemySpecialBuff | 必須 | 不要 | 不要 | 必須 | 敵専用技バフ（extra=バフ識別子） |
| spellChargeRecover | 不要 | 必須 | 不要 | 不要 | 呪文チャージ回復（value=spellId） |
| enemyAppear | 不要 | 不要 | 不要 | 不要 | 表示専用（空文字） |
| logOnly | 不要 | 不要 | 不要 | 不要 | 表示専用（空文字） |

## effects の並び順
- `effects` は**実際の適用順を保持**し、後から並べ替えない。
- 複数対象の場合は**対象選択順 → 各対象の適用順**で並べる。
- 表示側の要約/抑制は `effects` の順序を変更しない（表示上の集約のみ）。

## ActionKind と Effect.Kind の整合（許容セット）

### 宣言専用（効果行なし）
- `battleStart` / `turnStart` / `victory` / `defeat` / `retreat`  
  - `effects` は空（または `logOnly` のみ）。`actor` は `nil`。
- `enemyAppear`  
  - `actor` は敵の `actorIndex`。`effects` は空（または `enemyAppear` のみ）。

### 宣言に使用しない ActionKind（効果専用）
- `physicalDamage` / `physicalEvade` / `physicalParry` / `physicalBlock` / `martial`
- `magicDamage` / `magicHeal` / `magicMiss` / `breathDamage`
- `statusInflict` / `statusResist` / `statusConfusion` / `statusRampage`
- `healAbsorb` / `healVampire`
- `enemySpecialDamage` / `enemySpecialHeal` / `enemySpecialBuff`
- `physicalKill` は原則 **effect としてのみ使用**し、原因となる行動エントリが存在しない場合に限り宣言として使用してよい。
- `statusConfusion` / `statusRampage` は**発生原因の行動エントリ内の effects として記録**する（単独の ActionEntry は作らない）。

### 物理系
- `physicalAttack` / `reactionAttack` / `followUp`  
  - `actor` 必須。  
  - `physicalAttack` は**スキル由来の場合のみ** `skillIndex` を必須とし、通常攻撃は `nil` を許容する。
  - `reactionAttack` / `followUp` は**発動元スキルの `skillId`**を `skillIndex` に必ず設定する（**システム由来のみ**例外）。
  - `effects`: `physicalDamage` / `physicalEvade` / `physicalParry` / `physicalBlock` / `physicalKill`  
  - `reactionAttack` / `followUp` は同名の **マーカー効果** を1つ含める（target=攻撃対象、表示は抑制）。  
  - 付随: `healAbsorb` / `healVampire`（吸収/吸血が発動した場合）  
  - 状態異常判定を行う場合は `statusInflict` / `statusResist` を追加する。  
  - `physicalKill` は**撃破を起こした効果の直後**に追加する。  

### 魔法系（僧侶/魔法使い）
- `priestMagic` / `mageMagic`  
  - `skillIndex = spellId`。  
  - `healing`: `magicHeal`  
  - `damage`: `magicDamage`（撃破時は `physicalKill` を追加・直後に配置）  
  - `status`: `statusInflict` / `statusResist`  
  - `buff`: `buffApply`（対象ごとに追加）  
  - `cleanse`: `statusRecover`（解除した状態ごとに追加）  

### ブレス
- `breath`  
  - `effects`: `breathDamage`（撃破時は `physicalKill` を追加・直後に配置）  

### 敵専用技
- `enemySpecialSkill`  
  - `skillIndex = enemySkillId`。  
  - `damage`: `enemySpecialDamage`  
  - `heal`: `enemySpecialHeal`  
  - `buff`: `enemySpecialBuff`（対象ごと、`extra` にバフ識別子）  
  - `status`: `statusInflict` / `statusResist`  
  - 撃破時は `physicalKill` を追加（撃破を起こした効果の直後）。  

### 状態異常・経過
- `statusTick`: `statusTick` のみ（value=適用後ダメージ、extra=生値）  
  - `statusId` 必須（状態名は MasterData から解決）。  
- `statusRecover`: `statusRecover` のみ（解除した状態ごとに追加）  
  - `statusId` 必須（状態名は MasterData から解決）。  
- `actionLocked`: `actionLocked` のみ（actor=行動不能者、target=同一）  
- `noAction`: `noAction` のみ（actor=行動者、target=同一）  

### バフ
- `buffApply`: `buffApply`（対象ごと）  
  - **発動元スキルの `skillId` を `skillIndex` に必ず設定**する（**システム由来のみ**例外）。  
- `buffExpire`: `buffExpire`（対象ごと）  
  - **発動元スキルの `skillId` を `skillIndex` に必ず設定**する（**システム由来のみ**例外）。  

### 回復/蘇生/救出
- `healParty`: `healParty`（actor=回復者、target=各回復対象）  
- `healSelf`: `healSelf`（actor=回復者、target=行動者）  
- `healAbsorb` / `healVampire`: 物理系の行動内の `effects` として追加（target=回復者）  
- `damageSelf`: `damageSelf`（value=適用後ダメージ、extra=生値）  
- `resurrection`: `resurrection`（actor=蘇生者=対象、target=対象、value=蘇生後HP）  
- `necromancer` / `rescue`: 同名の `Effect.Kind` を対象ごとに追加（actor=発動者、target=対象、value=蘇生後HP）  

### その他
- `withdraw`: `withdraw`（actor=離脱者、target=離脱者）  
- `sacrifice`: `sacrifice`（actor=供儀対象、target=供儀対象）  
- `vampireUrge`: `vampireUrge`（actor=襲撃者、target=襲撃対象）  
- `spellChargeRecover`: `spellChargeRecover`（value=spellId、対象なし）  
  - 呪文名は `value`（spellId）から MasterData で解決する。  

## ActionKind（宣言ログ）
表の「表示文」は BattleLogRenderer の宣言メッセージ。**表示名はIDから解決**し、ログに平文を保存しない。
表示文のキーは `battleLog.declaration.<actionKind>` を正とし、表の文言は Localizable の既定文言とする。

| ActionKind | 表示文 | LogType | 備考 |
|---|---|---|---|
| defend | {actor}は防御態勢を取った | guard | |
| physicalAttack | {actor}の攻撃！ | action | 複数回攻撃はヒット数サマリ付与 |
| priestMagic | {actor}は{spell}を唱えた！ | action | spellName/skillIndex から解決 |
| mageMagic | {actor}は{spell}を唱えた！ | action | |
| breath | {actor}はブレスを吐いた！ | action | |
| battleStart | 戦闘開始！ | system | |
| turnStart | --- {turn}ターン目 --- | system | extra を使用（必須） |
| victory | 勝利！ 敵を倒した！ | victory | |
| defeat | 敗北… パーティは全滅した… | defeat | |
| retreat | 戦闘は長期化し、パーティは撤退を決断した | retreat | |
| physicalDamage | （効果専用。宣言では通常使用しない） | system | |
| physicalEvade | （効果専用。宣言では通常使用しない） | system | |
| physicalParry | （効果専用。宣言では通常使用しない） | system | |
| physicalBlock | （効果専用。宣言では通常使用しない） | system | |
| physicalKill | 戦闘不能が発生した | status | 例外的に宣言扱いになる場合がある |
| martial | （効果専用。宣言では通常使用しない） | system | |
| magicDamage | （効果専用。宣言では通常使用しない） | system | |
| magicHeal | （効果専用。宣言では通常使用しない） | system | |
| magicMiss | （効果専用。宣言では通常使用しない） | system | |
| breathDamage | （効果専用。宣言では通常使用しない） | system | |
| statusInflict | （効果専用。宣言では通常使用しない） | system | |
| statusResist | （効果専用。宣言では通常使用しない） | system | |
| statusRecover | {actor}の{label}が治った | status | |
| statusTick | {actor}は{label}の影響を受けている | status | |
| statusConfusion | （効果専用。宣言では通常使用しない） | system | |
| statusRampage | （効果専用。宣言では通常使用しない） | system | |
| reactionAttack | {actor}の{reaction}！ | action | |
| followUp | {actor}の{followUp}！ | action | |
| healAbsorb | {actor}は{label}で回復した | heal | |
| healVampire | {actor}は{label}で回復した | heal | |
| healParty | {actor}の{label}！ | heal | |
| healSelf | {actor}は{label}で自分を癒やした | heal | |
| damageSelf | {actor}は{label}でダメージを受けた | damage | |
| buffApply | {actor}に{label}の効果が付与された | status | |
| buffExpire | {actor}の{label}が切れた | status | |
| resurrection | {actor}は{label}を行った | status | |
| necromancer | {actor}は{label}で死者を蘇らせた | status | |
| rescue | {actor}は{label}を行った | status | |
| actionLocked | {actor}は{label}だ | status | |
| noAction | {actor}は何もしなかった | action | |
| withdraw | {actor}は戦線離脱した | status | |
| sacrifice | 古の儀：{actor}が供儀対象になった | status | |
| vampireUrge | {actor}は吸血衝動に駆られた | status | |
| enemyAppear | 敵が現れた！ | system | |
| enemySpecialSkill | {actor}の{skill}！ | action | enemySkillNames から解決 |
| enemySpecialDamage | （効果専用。宣言では通常使用しない） | system | |
| enemySpecialHeal | （効果専用。宣言では通常使用しない） | system | |
| enemySpecialBuff | （効果専用。宣言では通常使用しない） | system | |
| spellChargeRecover | {actor}は{label}を再装填した | status | |

補足:
- 表にない ActionKind は宣言メッセージが空文字となる。
- 表示文中の `{label}` / `{spell}` / `{skill}` / `{reaction}` / `{followUp}` は**MasterDataから解決した名称**を指す。
- `statusId` 必須の種別は **状態名を必ず解決**して `{label}` に差し込む。
- `buffApply` / `buffExpire` / `reactionAttack` / `followUp` は**発動元スキルの `skillId` 必須**。解決できない場合は不正。
- システム由来（`battleStart` / `turnStart` / `victory` / `defeat` / `retreat` / `enemyAppear`）は固定文言のみを表示する。

## Effect.Kind（効果ログ）
表の「表示文」は BattleLogRenderer の効果メッセージ。
補足: 表示文中の `{label}` は **MasterData から解決した表示名**を使用する（効果ごとの個別ラベルは持たない）。
表示文のキーは `battleLog.effect.<effectKind>` を正とし、表の文言は Localizable の既定文言とする。

| Effect.Kind | 表示文 | LogType | HP影響 |
|---|---|---|---|
| physicalDamage | {actor}の攻撃！{target}に{amount}のダメージ！ | damage | damage |
| physicalEvade | {actor}の攻撃！{target}は攻撃をかわした！ | miss | - |
| physicalParry | {target}のパリィ！ | action | - |
| physicalBlock | {target}の盾防御！ | action | - |
| physicalKill | {target}を倒した！ | defeat | setHP(0) |
| martial | {actor}の格闘戦！ | action | - |
| magicDamage | {actor}の魔法！{target}に{amount}のダメージ！ | damage | damage |
| magicHeal | {target}のHPが{amount}回復！ | heal | heal |
| magicMiss | しかし効かなかった | miss | - |
| breathDamage | {actor}のブレス！{target}に{amount}のダメージ！ | damage | damage |
| statusInflict | {target}は{label}になった！ | status | - |
| statusResist | {target}は{label}に抵抗した！ | status | - |
| statusRecover | {target}の{label}が治った | status | - |
| statusTick | {target}は{label}で{amount}のダメージ！ | damage | damage |
| statusConfusion | {actor}は暴走して混乱した！ | status | - |
| statusRampage | {actor}の暴走！{target}に{amount}のダメージ！ | damage | damage |
| reactionAttack | {actor}の{reaction}！ | action | - |
| followUp | {actor}の{followUp}！ | action | - |
| healAbsorb | {actor}は吸収能力で{amount}回復 | heal | heal |
| healVampire | {actor}は吸血で{amount}回復 | heal | heal |
| healParty | {target}のHPが{amount}回復！ | heal | heal |
| healSelf | {target}のHPが{amount}回復！ | heal | heal |
| damageSelf | {target}は自身の効果で{amount}ダメージ | damage | damage |
| buffApply | {label}が{target}に付与された / 効果が発動した | status | - |
| buffExpire | {target}の{label}が切れた / 効果が切れた | status | - |
| resurrection | {target}が蘇生した！ | heal | setHP |
| necromancer | {actor}のネクロマンサーで{target}が蘇生した！ | heal | setHP |
| rescue | {actor}は{target}を救出した！ | heal | setHP |
| actionLocked | {actor}は動けない | status | - |
| noAction | {actor}は何もしなかった | action | - |
| withdraw | {actor}は戦線離脱した | status | - |
| sacrifice | 古の儀：{target}が供儀対象になった | status | - |
| vampireUrge | {actor}は吸血衝動に駆られた | status | - |
| enemySpecialDamage | {target}に{amount}のダメージ！ | damage | damage |
| enemySpecialHeal | {actor}は{amount}回復した！ | heal | heal |
| enemySpecialBuff | {actor}は能力を強化した！ | status | - |
| spellChargeRecover | {actor}は魔法のチャージを回復した | status | - |
| enemyAppear | （空文字） | system | - |
| logOnly | （空文字） | system | - |

## レンダリング規則

### 1. 行動単位で表示
- `BattleLogRenderer.render` は `entries` を順に `RenderedAction` に変換する。
- `RenderedAction` には `declaration` と `results`（効果ログ）が含まれる。
- **1アクション=1セクション**とし、複数対象の効果でも同一 `RenderedAction` 内にまとめて表示する。
- `results` の順序は原則 `effects` の順序に従う（集約/抑制の規則はこの後に従う）。

### 2. 効果ログの抑制
以下の `ActionKind` は効果行を出さない。
- battleStart / turnStart / victory / defeat / retreat / enemyAppear

### 3. 物理系の集約表示
`physicalAttack` / `reactionAttack` / `followUp` は効果を集約して表示する。
- 対象ごとに合計ダメージを算出し「{actor}の攻撃！{target}に{合計}ダメージ！」を表示
- ダメージが 0 の場合「{target}は攻撃をかわした！」を表示
- 個別の `physicalEvade` / `physicalParry` / `physicalBlock` は効果行から除外
- `reactionAttack` / `followUp` のマーカー効果も効果行から除外

### 4. バフ魔法の要約
`mageMagic` / `priestMagic` で効果が全て `buffApply` の場合:
- 対象が複数なら「味方全体/敵全体に{label}の効果が付与された！」
- 単体なら「{target}に{label}の効果が付与された！」

### 5. 表示名の解決（MasterData）
- スキル/呪文/敵専用技の名称は **IDから必ず解決**する。
  - `priestMagic` / `mageMagic`: `skillIndex = spellId` → spellMaster
  - `enemySpecialSkill`: `skillIndex = enemySkillId` → enemySkillMaster
  - その他のスキル由来行動: `skillIndex = skillId` → skillMaster
- 状態名は `statusId` から解決する。
- `buffApply` / `buffExpire` / `reactionAttack` / `followUp` は**発動元スキルの `skillId`**を必須とし、そこから名称を解決する。
- `spellChargeRecover` は `value = spellId` から呪文名を解決する。
- システム由来（`battleStart` / `turnStart` / `victory` / `defeat` / `retreat` / `enemyAppear`）は固定文言のみを表示する。

### 6. エラー規則（マスター参照不可）
- 必須IDがあるのに MasterData から名称が取得できない場合は **不正ログ**とみなす。
  - DEBUG: `assertionFailure` で検知する。
  - RELEASE: **ログを出さずに**検知ログを残す（無音表示は避ける）。

### 7. ヒット数サマリ
複数回攻撃は宣言文の末尾に「（N回攻撃、Mヒット）」を付与する。

## HP復元（BattleLogEffectInterpreter）
戦闘ログから HP を再構成するためのインタプリタ。

- damage: physical/magic/breath/statusTick/statusRampage/damageSelf/enemySpecialDamage
- heal: magicHeal/healParty/healSelf/healAbsorb/healVampire/enemySpecialHeal
- setHP: resurrection/necromancer/rescue/physicalKill

用途:
- ExplorationProgressService.restorePartyHP
- EncounterDetailView の HP 差分表示

## 永続化（BattleLogRecord.logData）

### 格納先
- `BattleLogRecord.logData` にバイナリ形式で保存
- `BattleLogArchive` を通して取得

### バージョン運用
- フォーマットのバージョンは **1カ所に集約**し、仕様と実装が一致することをテストで担保する。
- 2026年オーバーホールの基準形式を **version=1** として固定する（以後は原則変更しない）。
- 旧形式（v1以前 / v2 / v3）は **互換対象外** とし、表示不可として扱う。
- バージョンを上げるのは **バイナリ形式の変更が発生した場合のみ**とし、理由と影響範囲を本仕様に明記する。
- 仕様に記載のないバージョン更新は禁止する。

### バイナリフォーマット
```
[Header]
  version(1) + outcome(1) + turns(1)
[InitialHP]
  count(2) + (actorIndex(2) + hp(4)) * count
[Entries]
  count(2) + entry payloads
    turn(1)
    actorFlag(1) + actor(2)?
    actionKind(1)
    skillFlag(1) + skillIndex(2)?
    extraFlag(1) + extra(2)?
    effectCount(1)
      kind(1)
      targetFlag(1) + target(2)?
      valueFlag(1) + value(4)?
      statusFlag(1) + statusId(2)?
      extraFlag(1) + extra(2)?
[Participants]
  playerCount(1) + enemyCount(1) + snapshots
    actorIndex(2)
    characterId(1)
    nameLen(1) + name(bytes)
    avatarIndex(2) + level(2) + maxHP(4)
```

### 形式の詳細（規範）
- 数値は**リトルエンディアン**で格納する。
- 文字列は**UTF-8**。長さは**バイト数**で表し、最大 255 バイト。
  - 長さ 0 は「未設定/空文字」を意味する。
- `InitialHP` は **actorIndex 昇順**で格納する（順序を固定する）。
- `Entries` は **ログ追加順**で格納し、後から並べ替えない。
- `Participants` は **player → enemy** の順で格納し、各配列の順序を保持する。

### デコード失敗
- バージョン不一致: `unsupportedVersion`
- データ破損: `malformedData`

## 不変条件（ログの正当性）
- **HPが変化する処理は必ず effect を記録する**（復元可能性の担保）。
- **戦闘中の全ての計算（命中/回避/ダメージ/回復/付与/解除/再装填など）は必ずログ化**し、暗黙の結果や欠落を許容しない。
- **ActionKind と Effect.Kind の整合規則を守る**（許容セット外の組み合わせは禁止）。
- **本仕様に記載のない種別・組み合わせは使用しない**（新規に使う場合は仕様を更新する）。
- **actorIndex は不変の識別子**として扱い、途中で再割当しない。
- **既存ログの順序は保持**し、後からまとめて挿入しない。
- **複数対象の行動を複数エントリに分割しない**（1アクション=1エントリ）。
