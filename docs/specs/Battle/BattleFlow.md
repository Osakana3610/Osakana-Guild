# 戦闘フロー仕様

## 概要

戦闘の開始から終了までのフローを定義する。

## 戦闘フロー

```
1. 戦闘開始
   - 初期HP記録
   - battleStartエントリ追加

2. メインループ
   while (戦闘継続):
     a. ターン開始
        - ターン数インクリメント
        - turnStartエントリ追加

     b. 行動順決定
        - 敏捷+乱数でソート

     c. 各アクターの行動
        - 状態異常チェック
        - 行動選択
        - 行動実行
        - リアクション処理

     d. ターン終了
        - 状態異常ターン減少
        - turnEndエントリ追加

     e. 勝敗判定

3. 戦闘終了
   - battleEndエントリ追加
   - 結果返却
```

## 勝敗条件

| 結果 | 条件 |
|------|------|
| victory | 敵全員のHP <= 0 |
| defeat | 味方全員のHP <= 0 |
| escaped | 逃走成功 |
| timeout | ターン数上限到達 |

## 行動順決定

```
シャッフルスキルあり:
  speed = random(0...10000)

シャッフルスキルなし:
  speed = agility × speedMultiplier(luck) × actionOrderMultiplier
  tiebreaker = random(0.0...1.0)

speedMultiplier(luck):
  lowerPercent = (luck - 10) × 2  // 0〜100にクランプ
  return random(lowerPercent...100) / 100

ソート順:
  1. firstStrike（先制）持ちを優先
  2. speed降順
  3. tiebreaker降順
```

敏捷と運乱数の積が大きいほど先に行動する。

### 計算例（行動順）

入力:
- プレイヤーA: agility=100, luck=35
- プレイヤーB: agility=80, luck=35

計算:
1. プレイヤーA: speedMultiplier = random(50...100)/100（luck=35で下限50%）
   - 最低: speed = 100 × 0.5 × 1.0 = 50
   - 最大: speed = 100 × 1.0 × 1.0 = 100
2. プレイヤーB: speedMultiplier = random(50...100)/100（luck=35で下限50%）
   - 最低: speed = 80 × 0.5 × 1.0 = 40
   - 最大: speed = 80 × 1.0 × 1.0 = 80

結果: プレイヤーAが高確率で先に行動（50〜100 vs 40〜80）

## ターン上限

```
maxTurns = 20
```

20ターン経過で強制終了（timeout）。

## 結果構造

```swift
struct Result {
    outcome: Outcome    // victory/defeat/escaped/timeout
    log: [ActionEntry]  // 全アクションログ
    turns: Int          // 経過ターン数
}
```

## 計算例

### 1対1戦闘（プレイヤー勝利）

入力:
- プレイヤー: HP=10000, 攻撃力=5000
- 敵: HP=3000, 防御力=2000

計算:
1. ターン1: プレイヤー攻撃 → 敵に3000ダメージ（5000-2000）
2. 敵HP <= 0 → 戦闘終了
3. 結果: victory, turns=1

### 複数ターン戦闘

入力:
- プレイヤー: HP=10000, 攻撃力=3000
- 敵: HP=10000, 防御力=2000, 攻撃力=1000

計算:
1. ターン1: プレイヤー攻撃 → 敵に1000ダメージ
2. ターン1: 敵攻撃 → プレイヤーにダメージ
3. ... （繰り返し）
4. 敵HP <= 0 → 戦闘終了
5. 結果: victory
