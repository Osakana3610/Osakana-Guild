# 状態異常仕様

## 概要

戦闘中の状態異常の付与、効果、解除に関する仕様を定義する。

## 状態異常の種類

| ID | タグ | 名称 | 効果 |
|----|------|------|------|
| 1 | 3 | 混乱（Confusion） | 行動がランダムに |

## 暴走

### 発動条件

```
berserkChancePercent != nil && berserkChancePercent > 0
```

スキルで暴走確率が設定されている場合に判定される。

### 発動確率

```
scaled = berserkChancePercent × procChanceMultiplier
capped = clamp(round(scaled), 0, 100)
判定: percentChance(capped)
```

### 効果

暴走発動時、混乱状態（3ターン）が付与される。
既に混乱状態の場合は重ね掛けされない。

```
alreadyConfused == false:
  statusEffects.append(AppliedStatusEffect(
    id: confusionStatusId,
    remainingTurns: 3,
    source: actor.identifier,
    stackValue: 0.0
  ))
```

## 状態異常付与確率

### 計算式

```
scaledSource = basePercent × sourceProcMultiplier
resistance = target.skillEffects.status.resistances[statusId]

resistance:
  .immune → chance = 0
  .resistant → chance = scaledSource × 0.5
  .neutral → chance = scaledSource × 1.0
  .vulnerable → chance = scaledSource × 1.5

finalChance = clamp(round(chance × targetProcMultiplier), 0, 100)
```

### 耐性タイプ

| 耐性 | 倍率 |
|------|------|
| immune | 0%（無効） |
| resistant | 50%（軽減） |
| neutral | 100%（通常） |
| vulnerable | 150%（脆弱） |

## 状態異常の持続

### ターン経過処理

毎ターン終了時に以下が行われる:

1. **継続効果の適用**: 毒ダメージ等
2. **残りターン減少**: remainingTurns -= 1
3. **解除判定**: remainingTurns <= 0 なら削除

## 計算例

### 暴走発動率30%

入力:
- berserkChancePercent = 30
- procChanceMultiplier = 1.0

計算:
1. scaled = 30 × 1.0 = 30
2. capped = clamp(30, 0, 100) = 30
3. percentChance(30) → 30%で発動

### 状態異常付与（耐性50%軽減）

入力:
- basePercent = 40
- sourceProcMultiplier = 1.0
- resistance = .resistant

計算:
1. scaledSource = 40 × 1.0 = 40
2. chance = 40 × 0.5 = 20
3. finalChance = 20%
