# 反撃/追撃スキル仕様

## 概要

反撃・追撃スキル（リアクション）の発動条件と効果を定義する。

## リアクションの構造

```swift
struct Reaction {
    trigger: ReactionTrigger      // 発動トリガー
    chancePercent: Double         // 発動確率
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
| selfEvadePhysical | 自分が物理攻撃を回避した時 |
| allyDamagedPhysical | 味方が物理ダメージを受けた時 |
| allyDefeated | 味方が倒された時 |
| selfKilledEnemy | 自分が敵を倒した時 |
| allyMagicAttack | 味方が魔法攻撃をした時 |

## 発動確率

```
発動判定: percentChance(chancePercent)
```

chancePercent が 100 なら必ず発動。

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

### リアクション深度制限

```
depth >= maxReactionDepth: リアクション不発動
```

リアクションの連鎖を防ぐため、深度制限がある。

## 計算例

### 反撃（attackCountMultiplier=0.3, criticalRateMultiplier=0.5）

入力:
- 攻撃者: attackCount=10, criticalRate=30
- 反撃性能: attackCountMultiplier=0.3, criticalRateMultiplier=0.5

計算:
1. scaledHits = max(1, round(10 × 0.3)) = 3
2. scaledCritical = round(30 × 0.5) = 15

結果: 3回攻撃、必殺率15%で反撃
