# 戦闘乱数システム仕様

## 概要

戦闘における乱数生成の仕様を定義する。

## GameRandomSource

### アルゴリズム

SplitMix64を使用。シード値から決定的な乱数列を生成する。

```
state += 0x9E3779B97F4A7C15
z = state
z = (z ^ (z >> 30)) × 0xBF58476D1CE4E5B9
z = (z ^ (z >> 27)) × 0x94D049BB133111EB
return z ^ (z >> 31)
```

### 決定性

同じシードからは常に同じ乱数列が生成される。

## BattleRandomSystem

戦闘用の乱数ユーティリティ。

### statMultiplier

運ステータスに基づく能力値乱数。

```
下限% = min(100, max(40 + 運, 0))
乱数% = random(下限%...100)
return 乱数% / 100
```

| 運 | 下限 | 上限 | 備考 |
|----|------|------|------|
| 0 | 0.40 | 1.00 | 最低保証40% |
| 10 | 0.50 | 1.00 | |
| 30 | 0.70 | 1.00 | |
| 50 | 0.90 | 1.00 | |
| 60 | 1.00 | 1.00 | 固定値 |
| 99 | 1.00 | 1.00 | 固定値 |

運60以上で乱数が排除され、常に1.0になる。

### speedMultiplier

速度計算用の乱数。statMultiplierより下限が低い。

```
下限% = min(100, max((運 - 10) × 2, 0))
乱数% = random(下限%...100)
return 乱数% / 100
```

| 運 | 下限 | 上限 |
|----|------|------|
| 0 | 0.00 | 1.00 |
| 10 | 0.00 | 1.00 |
| 30 | 0.40 | 1.00 |
| 50 | 0.80 | 1.00 |
| 60 | 1.00 | 1.00 |

### percentChance

パーセント確率判定。

```
percent ≤ 0: 常にfalse
percent ≥ 100: 常にtrue
それ以外: random(1...100) ≤ percent
```

| 入力 | 結果 |
|------|------|
| 0 | 常にfalse |
| 50 | 50%でtrue |
| 100 | 常にtrue |

### probability

0.0〜1.0の確率判定。

```
probability ≤ 0: 常にfalse
probability ≥ 1: 常にtrue
それ以外: random(0.0...1.0) < probability
```

## 乱数消費順序

戦闘中の乱数は以下の順序で消費される（物理攻撃の場合）:

1. 命中判定
   - attacker statMultiplier
   - defender statMultiplier
2. ダメージ計算
   - attacker statMultiplier
   - defender statMultiplier
3. クリティカル判定（criticalRate > 0の場合）
   - percentChance

シード固定テストでは、この消費順序を考慮する必要がある。
