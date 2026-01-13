# クリティカル判定仕様

## 概要

クリティカル（必殺）判定の仕様を定義する。

## クリティカル発動判定

### 計算式

```
chance = clamp(criticalRate, 0, 100)
発動判定: percentChance(chance)
```

- criticalRateが0以下の場合は発動しない
- criticalRateが100以上の場合は必ず発動する

## クリティカル時の効果

### 防御力半減

```
criticalDefenseRetainedFactor = 0.5
effectiveDefense = baseDeffense × 0.5
```

クリティカル発動時、防御者の防御力が半減する。

### ダメージボーナス

```
percentBonus = max(0.0, 1.0 + criticalPercent / 100.0)
multiplierBonus = max(0.0, criticalMultiplier)
criticalDamageBonus = percentBonus × multiplierBonus
```

スキル効果がない場合：
- criticalPercent = 0 → percentBonus = 1.0
- criticalMultiplier = 1.0 → multiplierBonus = 1.0
- criticalDamageBonus = 1.0（追加ボーナスなし）

### クリティカル耐性

```
finalDamage = baseDamage × criticalTakenMultiplier
```

- criticalTakenMultiplier = 1.0: 耐性なし
- criticalTakenMultiplier = 0.5: クリティカルダメージ半減

## 計算例

### 基本ケース（criticalRate=100、luck=35）

入力:
- 攻撃者: criticalRate=100, luck=35
- 防御者: physicalDefense=2000, luck=35

計算:
1. chance = clamp(100, 0, 100) = 100
2. 100%で発動 → クリティカル確定
3. 防御者の防御力: 2000 × 0.5 = 1000
4. ダメージ増加（スキル効果なし）: 1.0倍

### criticalRate=0のケース

入力:
- 攻撃者: criticalRate=0

計算:
1. chance = clamp(0, 0, 100) = 0
2. chance > 0 が false なので即 return false
3. クリティカル発動しない

### クリティカルダメージボーナス

入力:
- criticalPercent = 50（50%ボーナス）
- criticalMultiplier = 1.2

計算:
1. percentBonus = 1.0 + 50/100 = 1.5
2. multiplierBonus = 1.2
3. criticalDamageBonus = 1.5 × 1.2 = 1.8

ダメージが1.8倍になる。
