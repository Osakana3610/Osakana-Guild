# 反撃/追撃スキル仕様

## 概要

反撃・追撃スキル（リアクション）の発動条件と効果を定義する。

## 用語定義（English canonical）

英語名を正本とし、日本語表現は対応関係を固定する。

| 英語 | 日本語 | 定義 |
|------|--------|------|
| Reaction (system) | 反撃/追撃/報復/再攻撃（スキル名で表記） | ReactionTrigger を条件に発動する追加行動の総称 |
| CounterAttack | 反撃 | 被ダメージ/回避をトリガーに発動する Reaction |
| FollowUp | 追撃 | 撃破や味方魔法発動をトリガーに発動する Reaction |
| Retaliation | 報復 | 味方撃破（allyDefeated）をトリガーに発動する Reaction |
| ExtraAction | 再攻撃/追加行動 | 通常行動内で発生する追加行動（Reaction とは別系統） |
| MartialFollowUp | 格闘追撃 | 物理攻撃後の格闘追撃（Reaction とは別系統） |
| Rescue | 救出 | 味方撃破時の救出処理（Reaction とは別系統） |

※ Rescue は「撃破の取り消し/復帰」に関わるため Reaction とは別構造で扱う（詳細は本末尾）。

## リアクションの構造

```swift
struct Reaction {
    trigger: ReactionTrigger      // 発動トリガー
    chancePercent: Double?        // 固定発動率（固定確率の時に使用）
    baseChancePercent: Double?    // 発動率係数（scalingStat とセット）
    scalingStat: BaseStat?        // 発動率の参照ステータス（例: 力）
    damageType: BattleDamageType  // 物理/魔法/ブレス
    attackCountMultiplier: Double // 攻撃回数乗数
    criticalRateMultiplier: Double // 必殺率乗数
    accuracyMultiplier: Double    // 命中率乗数
    preferredTarget: ...          // 優先ターゲット
    requiresMartial: Bool         // 格闘攻撃が必要か
    requiresAllyBehind: Bool      // 後列の味方が必要か
}
```

## 発動トリガー

| トリガー | 説明 |
|----------|------|
| selfDamagedPhysical | 自分が物理ダメージを受けた時 |
| selfDamagedMagical | 自分が魔法ダメージを受けた時 |
| selfEvadePhysical | 自分が物理攻撃を回避した時（回避/ミスで命中0） |
| allyDamagedPhysical | 味方が物理ダメージを受けた時 |
| allyDefeated | 味方が倒された時 |
| selfKilledEnemy | 自分が敵を倒した時（最後の一撃でHPが0になった時） |
| allyMagicAttack | 味方が魔法攻撃をした時 |

### トリガーの分類

- CounterAttack: selfDamagedPhysical / selfDamagedMagical / selfEvadePhysical
- FollowUp: selfKilledEnemy / allyMagicAttack
- Retaliation: allyDefeated（報復）

## 発動確率

```
固定確率: percentChance(chancePercent)
能力依存: percentChance( scalingStat * baseChancePercent )
```

chancePercent が 100 なら必ず発動。

### ルール

- 固定確率は chancePercent を使う。
- 能力依存は baseChancePercent + scalingStat を使う（baseChancePercent は係数）。
- chancePercent と baseChancePercent を同時に使わない。

## 攻撃性能の乗数

### attackCountMultiplier

反撃/追撃時の攻撃回数を決定する。

```
baseHits = max(1.0, attackCount)
scaledHits = max(1, round(baseHits × attackCountMultiplier))
```

| 値 | 効果 |
|----|------|
| 1.0 | 通常と同じ攻撃回数 |
| 0.3 | 通常の30%の攻撃回数 |
| 0.5 | 通常の50%の攻撃回数 |

### criticalRateMultiplier

反撃/追撃時の必殺率を決定する。

```
scaledCritical = round(criticalRate × criticalRateMultiplier)
effectiveCritical = clamp(scaledCritical, 0, 100)
```

| 値 | 効果 |
|----|------|
| 1.0 | 通常と同じ必殺率 |
| 0.5 | 通常の50%の必殺率 |
| 0.0 | 必殺なし |

### accuracyMultiplier

反撃/追撃時の命中率を決定する。

```
hitChance = computeHitChance(...) × accuracyMultiplier
```

| 値 | 効果 |
|----|------|
| 1.0 | 通常と同じ命中率 |
| 0.8 | 通常の80%の命中率 |

## 制限事項

### requiresMartial

```
requiresMartial == true:
  格闘攻撃が使えない場合はリアクション不発動
```

### requiresAllyBehind

```
requiresAllyBehind == true:
  自分より後ろのフォーメーションの味方が攻撃された時のみ発動
```

### 自己ループ防止

- 自分への攻撃で自分に追撃しない（allyDamagedPhysical）
- 自分の魔法で自分に追撃しない（allyMagicAttack）

### 連鎖の制御ルール

リアクション/追撃/再攻撃の連鎖は、以下のルールで制御する。

- Reaction/FollowUp の結果から新しい ReactionEvent は発生しない
- ExtraAction（再攻撃）は通常行動の後にのみ判定される
- ExtraAction は Reaction/FollowUp からは発動しない
- 連続型の再攻撃/追撃は「同一行動内で条件を満たし続ける場合のみ」連鎖可能

## リアクション処理モデル（チェーン/キュー）

反撃・追撃は**同期実行しない**。トリガー処理が完了した後にキューへ積み、外側ループで順次消化する。

- Reaction は**アクション完了後**にキューへ追加する
- 反撃・追撃の実行は**キューの順次処理（FIFO）**で行う
- processReactionQueue の再入は行わない（外側ループで一括消化）
- 例外: **救出/即時蘇生**は撃破直後に同期判定する

### 優先順位（同時発火）

同時に条件を満たした場合、以下の順でキューに積む。

1. CounterAttack（反撃）
2. Retaliation（報復）
3. FollowUp（追撃）

### 同一優先度内の順序

同一優先度内の並びは**速度順（高→低）**で解決する。

#### 速度の参照元

- 速度値は**そのターンの actionOrder 計算結果を流用**する
- 同速のタイブレークも **actionOrder のタイブレーカー値を流用**する
    - リアクション処理のために速度を再抽選しない
- actionOrder の順位参照は **(ActorReference → (speed, tieBreaker)) のマップ**で保持する

## 再攻撃（ExtraAction）

通常行動の後にのみ判定される追加行動。

- 反撃/追撃（Reaction/FollowUp）からは発動しない
- 「回避時再攻撃」は攻撃が全て回避/ミス扱いの時のみ判定
- 連続判定を持つ場合は同ターン内で繰り返し判定する

### 回避・パリィ・盾防御の扱い

- 回避: 攻撃が全て回避された状態（命中0）
- ミス: 回避と同等に扱う（命中0）
- パリィ/盾防御: 命中した上で防御が発生したものとして扱う

## 格闘追撃（MartialFollowUp）

格闘攻撃のヒット後に発生する追加攻撃。ReactionTrigger には含めない。

```
発動判定: percentChance(strength)  // 0〜100にクランプ
追撃回数: max(1, floor(attackCount × 0.3))
命中補正: martialAccuracyMultiplier
```

## 救出（Rescue）

救出は Reaction とは別系統とし、リアクション深度に依存せず撃破直後に判定する。

- 味方が撃破された直後に判定される
- 撃破イベントは発生したものとして扱い、追撃/報復の発動は取り消されない
- 成功時は復帰（HP回復・状態異常解除など）を行う
- 行動コストや魔法の使用回数の消費など、通常攻撃とは異なる資源消費を伴う

## 未決事項（要決定）

- Retaliation（allyDefeated）の優先順位（CounterAttack / FollowUp との関係）
- 同一速度の場合のタイブレーク（陣形順/編成順/固定順など）
- 同一アクターが複数リアクションを持つ場合の順序規則（スキル定義順/ID順など）
- ReactionEvent の追加タイミング（アクション直後/ターン末）を仕様として固定するか

## 計算例

### 反撃（attackCountMultiplier=0.3, criticalRateMultiplier=0.5）

入力:
- 攻撃者: attackCount=10, criticalRate=30
- 反撃性能: attackCountMultiplier=0.3, criticalRateMultiplier=0.5

計算:
1. scaledHits = max(1, round(10 × 0.3)) = 3
2. scaledCritical = round(30 × 0.5) = 15

結果: 3回攻撃、必殺率15%で反撃
