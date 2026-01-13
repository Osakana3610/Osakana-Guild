# 物理ダメージ計算仕様

## 概要

物理攻撃によるダメージ計算の仕様を定義する。

## 基本計算式

```
attackPower = 攻撃力 × attackRoll
defensePower = 劣化後防御力 × defenseRoll
effectiveDefensePower = クリティカル時 ? defensePower × 0.5 : defensePower
baseDamage = max(1, attackPower - effectiveDefensePower)
```

クリティカル判定は baseDamage 計算前に行われ、防御力半減が先に適用される。

### attackRoll / defenseRoll

`statMultiplier` 関数で計算される乱数乗数。

```
下限% = min(100, max(40 + 運, 0))
乱数% = random(下限%...100)
結果 = 乱数% / 100
```

| 運 | 下限% | 範囲 |
|----|-------|------|
| 0 | 40 | 0.40〜1.00 |
| 50 | 90 | 0.90〜1.00 |
| 60以上 | 100 | 1.00（固定） |

## 乗数の適用

### 適用順序

```
coreDamage = baseDamage
coreDamage *= initialStrikeBonus  （hitIndex=1の場合のみ）
coreDamage *= damageModifier

bonusDamage = 追加ダメージ × damageModifier × 貫通被乗数 × 貫通耐性

totalDamage = (coreDamage × 物理耐性 + bonusDamage)
            × 列補正 × dealt乗数 × taken乗数 × 累積ヒットボーナス
```

クリティカル時は追加で:
```
totalDamage *= クリティカルダメージボーナス
totalDamage *= クリティカル被ダメ乗数
totalDamage *= クリティカル耐性
```

※クリティカルによる防御力半減は baseDamage 計算時に既に適用済み

最終ダメージ:
```
finalDamage = max(1, round(totalDamage))
```

### initialStrikeBonus（初撃ボーナス）

hitIndex=1（最初の攻撃）でのみ適用。

```
差分 = 攻撃力 - 防御力 × 3
差分 ≤ 0 の場合: 1.0
差分 > 0 の場合:
  段階数 = floor(差分 / 1000)
  倍率 = 1.0 + 段階数 × 0.1
  結果 = min(3.4, max(1.0, 倍率))
```

| 攻撃力 | 防御力 | 差分 | 段階数 | 倍率 |
|--------|--------|------|--------|------|
| 5000 | 2000 | -1000 | - | 1.0 |
| 10000 | 2000 | 4000 | 4 | 1.4 |
| 20000 | 2000 | 14000 | 14 | 2.4 |
| 30000 | 2000 | 24000 | 24 | 3.4（上限） |

### damageModifier（ヒット減衰）

連続攻撃時のダメージ減衰。

```
hitIndex ≤ 2: 1.0
hitIndex > 2: pow(0.9, hitIndex - 2)
```

| hitIndex | 倍率 |
|----------|------|
| 1 | 1.0 |
| 2 | 1.0 |
| 3 | 0.9 |
| 4 | 0.81 |
| 5 | 0.729 |

### dealt乗数（与ダメージ）

攻撃者の `skillEffects.damage.dealt.physical` を適用。

- デフォルト: 1.0
- 例: 1.5 = +50%ダメージ

### taken乗数（被ダメージ）

防御者の `skillEffects.damage.taken.physical` を適用。

- デフォルト: 1.0
- 例: 0.8 = -20%ダメージ（軽減）

## クリティカル

### 発動条件

```
発動確率 = min(100, max(0, criticalRate))
発動確率 > 0 かつ random(1...100) ≤ 発動確率 → クリティカル
```

### クリティカル時の効果

1. 防御力が半減（baseDamage計算前に適用）
2. ダメージボーナス適用（totalDamage計算後）
3. 被クリティカル乗数適用
4. クリティカル耐性適用

## 最低ダメージ保証

計算結果が0以下でも、最終ダメージは最低1が保証される。

```
finalDamage = max(1, round(totalDamage))
```

## バリアとガード

### バリア

ダメージタイプ別にチャージを持ち、消費すると1/3ダメージになる。

### ガード

ガード状態の場合、バリアが無ければダメージ半減。

```
if バリア発動:
  totalDamage *= 1/3
else if ガード中:
  totalDamage *= 0.5
```

## 防御力劣化

戦闘中に蓄積する防御力低下。

```
実効防御力 = 防御力 × (1.0 - 劣化% / 100)
```

劣化は0%〜100%の範囲。
