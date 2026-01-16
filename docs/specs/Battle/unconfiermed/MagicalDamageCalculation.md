# 魔法ダメージ計算仕様

## 概要

魔法攻撃におけるダメージ計算の仕様を定義する。

## 基本計算式

```
attackPower = 魔力 × attackRoll
defensePower = 劣化後魔法防御 × defenseRoll × 0.5
baseDamage = max(1.0, attackPower - defensePower)

damage = baseDamage
       × spellPowerModifier
       × damageDealtModifier
       × damageTakenModifier
       × magicCriticalMultiplier（発動時）
       × spellResistance
       × barrierMultiplier
       × guardMultiplier

finalDamage = max(1, round(damage))
```

## 各要素の詳細

### 魔法防御の効果

```
effectiveDefense = magicalDefense × 0.5
```

魔法防御は物理防御と異なり、効果が半減（0.5倍）する。

### 劣化後魔法防御

```
劣化後魔法防御 = magicalDefense × (1.0 - 劣化% / 100.0)
```

### 魔法無効化

```
nullifyChance = magicNullifyChancePercent（0-100にクランプ）
percentChance(nullifyChance) が成功 → ダメージ0
```

魔法無効化スキルを持つ場合、確率でダメージを完全に無効化する。

### 必殺魔法（魔法必殺）

```
criticalChance = magicCriticalChancePercent（0-100にクランプ）
percentChance(criticalChance) が成功 → damage × magicCriticalMultiplier
```

物理の必殺とは別の判定。発動時に`magicCriticalMultiplier`が乗算される。

### 個別魔法耐性

```
damage × innateResistances.spells[spellId, default: 1.0]
```

特定の魔法に対する耐性を持つ場合、その魔法のダメージが軽減される。

### バリア / ガード

物理ダメージと同様に適用される。

```
バリアチャージがある場合: damage × (1/3)
バリアなし＆ガード中: damage × 0.5
```

## 計算例

### 基本ケース（luck=35）

入力:
- 攻撃者: magicalAttack=3000, luck=35
- 防御者: magicalDefense=2000, luck=35, 劣化0%

計算:
1. attackRoll = 1.0（luck=35）
2. defenseRoll = 1.0（luck=35）
3. attackPower = 3000 × 1.0 = 3000
4. defensePower = 2000 × 1.0 × 0.5 = 1000
5. baseDamage = max(1.0, 3000 - 1000) = 2000
6. 各種乗数 = 1.0（デフォルト）
7. finalDamage = 2000

期待値: 2000

### 魔法防御が低いケース

入力:
- 攻撃者: magicalAttack=3000, luck=35
- 防御者: magicalDefense=1000, luck=35

計算:
1. attackPower = 3000
2. defensePower = 1000 × 0.5 = 500
3. baseDamage = 3000 - 500 = 2500

期待値: 2500

### 魔法防御が高いケース

入力:
- 攻撃者: magicalAttack=3000, luck=35
- 防御者: magicalDefense=6000, luck=35

計算:
1. attackPower = 3000
2. defensePower = 6000 × 0.5 = 3000
3. baseDamage = max(1.0, 3000 - 3000) = 1.0（最低保証）

期待値: 1

## 物理ダメージとの違い

| 項目 | 物理 | 魔法 |
|------|------|------|
| 防御力効果 | 100% | 50% |
| 必殺判定 | shouldTriggerCritical | magicCriticalChancePercent |
| 防御力半減（必殺） | あり | なし（魔法必殺は乗数のみ） |
| 追加ダメージ | あり | なし |
| 累積ヒットボーナス | あり | なし |
| 初撃ボーナス | あり | なし |
