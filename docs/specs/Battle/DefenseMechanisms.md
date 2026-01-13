# 防御メカニズム仕様

## 概要

戦闘における防御メカニズム（受け流し、盾ブロック、バリア、ガード）の仕様を定義する。

## 受け流し（Parry）

### 発動条件

```
parryEnabled == true
```

スキルで受け流しが有効化されている必要がある。

### 発動確率

```
defenderBonus = additionalDamage × 0.25
attackerPenalty = attacker.additionalDamage × 0.5
base = 10.0 + defenderBonus - attackerPenalty + parryBonusPercent
chance = clamp(round(base × procChanceMultiplier), 0, 100)
```

基本発動率は10%。防御者の追加ダメージで上昇、攻撃者の追加ダメージで下降する。

### 効果

受け流し成功時、その攻撃は回避扱いとなり、ダメージを受けない。

## 盾ブロック（Shield Block）

### 発動条件

```
shieldBlockEnabled == true
```

スキルで盾ブロックが有効化されている必要がある。

### 発動確率

```
base = 30.0 - attacker.additionalDamage / 2.0 + shieldBlockBonusPercent
chance = clamp(round(base × procChanceMultiplier), 0, 100)
```

基本発動率は30%。攻撃者の追加ダメージで下降する。

### 効果

盾ブロック成功時、その攻撃は回避扱いとなり、ダメージを受けない。

## バリア

### バリアの種類

| キー | ダメージタイプ |
|------|---------------|
| 1 | 物理（physical） |
| 2 | 魔法（magical） |
| 3 | ブレス（breath） |

### チャージ管理

```
barrierCharges[key]: 通常バリアのチャージ数
guardBarrierCharges[key]: ガード時限定バリアのチャージ数
```

### 発動判定

```
ガード中 && guardBarrierCharges[key] > 0:
  guardBarrierCharges[key] -= 1
  ダメージ × (1/3)

barrierCharges[key] > 0:
  barrierCharges[key] -= 1
  ダメージ × (1/3)

それ以外:
  ダメージ × 1.0（バリアなし）
```

### 効果

バリア発動時、ダメージが1/3に軽減される。

## ガード

### 効果

```
guardActive == true && バリアなし:
  ダメージ × 0.5
```

ガード状態でバリアが発動しなかった場合、ダメージが半減する。

## 適用順序

1. **受け流し / 盾ブロック判定**（命中判定前）
   - 成功 → 攻撃回避、ダメージなし

2. **命中判定**
   - ミス → ダメージなし

3. **ダメージ計算**
   - 基本ダメージ計算
   - 各種乗数適用

4. **バリア判定**
   - バリアあり → ダメージ × (1/3)

5. **ガード判定**
   - ガード中 && バリアなし → ダメージ × 0.5

## 計算例

### 受け流し発動率（追加ダメージなし）

入力:
- 防御者: parryEnabled=true, additionalDamage=0, parryBonusPercent=0, procChanceMultiplier=1.0
- 攻撃者: additionalDamage=0

計算:
1. defenderBonus = 0 × 0.25 = 0
2. attackerPenalty = 0 × 0.5 = 0
3. base = 10.0 + 0 - 0 + 0 = 10.0
4. chance = clamp(10 × 1.0, 0, 100) = 10

発動率: 10%

### バリア適用例

入力:
- 防御者: barrierCharges[1] = 3（物理バリア3回）
- 基本ダメージ: 3000

計算:
1. バリアチャージあり → チャージを1消費
2. ダメージ = 3000 × (1/3) = 1000
3. barrierCharges[1] = 2（残りチャージ）

結果: 1000ダメージ、残りバリア2回
