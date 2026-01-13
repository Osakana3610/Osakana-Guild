# 命中判定仕様

## 概要

物理攻撃・魔法攻撃における命中判定の仕様を定義する。

## 基本計算式

```
attackerScore = max(1.0, 命中率)
defenderScore = max(1.0, 劣化後回避率)
baseRatio = attackerScore / (attackerScore + defenderScore)

attackerRoll = statMultiplier(攻撃者の運)
defenderRoll = statMultiplier(防御者の運)
randomFactor = attackerRoll / max(0.01, defenderRoll)

luckModifier = (攻撃者の運 - 防御者の運) × 0.002

rawChance = (baseRatio × randomFactor + luckModifier) × hitAccuracyModifier × accuracyMultiplier
finalChance = clampProbability(rawChance)
```

## 各要素の詳細

### 劣化後回避率

```
劣化後回避率 = 回避率 × (1.0 - 劣化% / 100.0)
```

回避率は戦闘中に劣化する。劣化%が増えると回避率が下がる。

### statMultiplier

運に基づく乱数乗数。詳細は RandomSystem.md を参照。

| 運 | 範囲 |
|----|------|
| 1 | 0.41〜1.00 |
| 18 | 0.58〜1.00 |
| 35 | 0.75〜1.00 |
| 60以上 | 1.00（固定） |

### hitAccuracyModifier（ヒット減衰）

連続攻撃時の命中率減衰。

```
hitIndex <= 1: 1.0
hitIndex > 1: 0.6 × pow(0.9, hitIndex - 2)
```

| hitIndex | 倍率 |
|----------|------|
| 1 | 1.0 |
| 2 | 0.6 |
| 3 | 0.54 |
| 4 | 0.486 |

### clampProbability（命中率クランプ）

最終命中率を一定範囲に制限する。

```
minHit = 0.05（5%、最低保証）
maxHit = 0.95（95%、上限）
finalChance = min(maxHit, max(minHit, rawChance))
```

スキル効果や敏捷によってminHit/maxHitが変動する場合がある。

## 計算例

### 基本ケース（乱数なし、luck=35）

入力:
- 攻撃者: 命中率100, luck=35
- 防御者: 回避率50, luck=35, 劣化0%

計算:
1. attackerScore = max(1.0, 100) = 100
2. defenderScore = max(1.0, 50 × 1.0) = 50
3. baseRatio = 100 / (100 + 50) = 0.667
4. attackerRoll = 1.0（luck=35）
5. defenderRoll = 1.0（luck=35）
6. randomFactor = 1.0 / 1.0 = 1.0
7. luckModifier = (60 - 60) × 0.002 = 0
8. hitAccuracyModifier = 1.0（hitIndex=1）
9. rawChance = (0.667 × 1.0 + 0) × 1.0 × 1.0 = 0.667
10. finalChance = min(0.95, max(0.05, 0.667)) = 0.667

期待値: 約66.7%

### 命中率0のケース

入力:
- 攻撃者: 命中率0, luck=35
- 防御者: 回避率100, luck=35

計算:
1. attackerScore = max(1.0, 0) = 1.0
2. defenderScore = max(1.0, 100) = 100
3. baseRatio = 1.0 / (1.0 + 100) = 0.0099
4. rawChance ≈ 0.0099
5. finalChance = max(0.05, 0.0099) = 0.05

期待値: 5%（最低保証）
