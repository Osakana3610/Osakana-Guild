# ブレスダメージ計算仕様

## 概要

ブレス攻撃におけるダメージ計算の仕様を定義する。

## 基本計算式

```
variance = speedMultiplier(luck)
baseDamage = breathDamage × variance

damage = baseDamage
       × damageDealtModifier
       × damageTakenModifier
       × breathResistance
       × barrierMultiplier
       × guardMultiplier

finalDamage = max(1, round(damage))
```

## 各要素の詳細

### speedMultiplier

ブレスダメージのバラつきを決定する乗数。

```
validLuck = clamp(luck, 1, 35)
lowerPercent = min(100, max((validLuck - 10) × 2, 0))
percent = random(lowerPercent...100)
speedMultiplier = percent / 100.0
```

| luck | lowerPercent | 範囲 |
|------|--------------|------|
| 1 | 0 | 0.00〜1.00 |
| 10 | 0 | 0.00〜1.00 |
| 18 | 16 | 0.16〜1.00 |
| 35 | 50 | 0.50〜1.00 |

**注意**: statMultiplierとは異なり、luck=35でも固定値にならない。

### breathResistance

防御者のブレス耐性。

```
damage × innateResistances.breath
```

- 1.0: 耐性なし（通常ダメージ）
- 0.5: 50%軽減
- 0.0: 完全耐性

### バリア / ガード

物理・魔法と同様に適用される。

```
バリアチャージがある場合: damage × (1/3)
バリアなし＆ガード中: damage × 0.5
```

## 計算例

### 基本ケース（luck=35）

入力:
- 攻撃者: breathDamage=1000, luck=35
- 防御者: breathResistance=1.0

計算:
1. lowerPercent = (35 - 10) × 2 = 50
2. variance = 0.50〜1.00（乱数）
3. baseDamage = 1000 × variance = 500〜1000
4. 各種乗数 = 1.0
5. finalDamage = 500〜1000

期待値: 500〜1000の範囲

### ブレス耐性ありのケース

入力:
- 攻撃者: breathDamage=1000, luck=35
- 防御者: breathResistance=0.5

計算:
1. baseDamage = 1000 × variance
2. damage = baseDamage × 0.5
3. finalDamage = 250〜500の範囲

## 物理・魔法との違い

| 項目 | 物理/魔法 | ブレス |
|------|----------|--------|
| 防御力 | あり | なし |
| 乱数乗数 | statMultiplier | speedMultiplier |
| 乱数範囲（luck=35） | 0.75〜1.00 | 0.50〜1.00 |
| クリティカル | あり | なし |
| 追加ダメージ | 物理のみ | なし |
