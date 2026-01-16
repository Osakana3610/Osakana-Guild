# 戦闘ステータス正本（CombatStats）

## 目的

CharacterValues.Combat の各ステータスについて、意味・単位・合成ルール・戦闘での使われ方を定義する。
本書が正本であり、コード・テスト・説明文は本書に従う。

## 適用範囲

- 戦闘ステータス（13項目）
  - maxHP / physicalAttackScore / magicalAttackScore / physicalDefenseScore / magicalDefenseScore
  - hitScore / evasionScore / criticalChancePercent / attackCount
  - magicalHealingScore / trapRemovalScore / additionalDamageScore / breathDamageScore
- 現行の生成処理は CombatStatCalculator。
- 現行の戦闘中参照は BattleTurnEngine 系。
  - 本書の定義と異なる挙動は修正対象とする。

## 重要な用語

- **スコア**: 比率計算やダメージ計算に直接投入する値。%ではない。
- **％（パーセント）**: 0〜100 の確率・上限。
- **倍率**: 1.0=100% の乗数。

## 命名規約（正本の名称）

- 正本では **意味と単位に一致する名称**を使う。
- 名称は単位を直接示す（Score / Percent / Count / Multiplier）。
- 実装上の旧名称は **付記の対応表**に隔離し、本文には持ち込まない。

## 単位規約（値域と用途）

- **Percent**: 0〜100。%を意味する値。表示は「%」を付ける。
- **Probability**: 0.0〜1.0。**乱数判定に使う確率**。
- **Ratio**: 0.0〜1.0。**割合の計算に使う比率**（乱数には使わない）。
- **Multiplier**: 1.0が基準の乗数（1.41=141%）。
- **Score**: 上限のない加算値。%ではない。
- **Count**: 回数。原則0以上（小数を含む場合あり）。
- **HP**: 体力量。原則0以上。

補足:
- **Probability と Ratio は値域が同じでも用途が違う**ため、混用しない。
- **Percent → Probability** は `percent / 100.0` で変換する。

## 共通記号と前提（実装準拠）

- STR/WIS/SPR/VIT/AGI/LUK: CoreAttributes（BaseStatAccumulator後、負値は0にクランプ済み）
- LV: レベル
- raceId: 種族ID
- LF: levelDependentValue(raceId, LV) * growthMultiplier
- growthMultiplier: スキル効果の成長倍率（積、デフォルト1.0）
- c_stat: Job係数（JobCoefficientLookup(job)）
  - c_maxHP / c_physicalAttackScore / c_magicalAttackScore / c_physicalDefenseScore / c_magicalDefenseScore
  - c_hitScore / c_evasionScore / c_criticalChancePercent / c_attackCount / c_magicalHealingScore / c_trapRemovalScore
- T_stat: talent倍率
- P_stat: passive倍率
- A_stat: additive加算
- trunc(x): Int(x.rounded(.towardZero))
- fixedToOne(stat): statFixedToOne に含まれる場合 true
- conv_stat / E_stat: 対象ステータスに対応する変換加算 / 装備加算
- criticalFlatBonus / criticalCap / criticalCapDelta: 必殺関連のスキル効果値

変換（statConversion）:
- Percent変換: ratio = valuePercent / 100.0
- Linear変換: ratio = valuePerUnit
- target += sum(source * ratio) （トポロジカル順に適用）

装備戦闘ボーナス（combatBonuses）:
- cachedEquippedItems.combatBonuses は称号/超レア/宝石改造/パンドラ適用済み
- categoryMultiplier = equipmentMultipliers[category] ?? 1.0
- itemStatMultiplier = itemStatMultipliers[stat] ?? 1.0
- E_stat = sum(trunc(value_i * categoryMultiplier_i * itemStatMultiplier_stat) * quantity_i)
- E_attackCount = sum(value_i * categoryMultiplier_i * itemStatMultiplier_attackCount * quantity_i)
  - attackCount は Double で加算、他は Int 加算

格闘ボーナス:
- shouldApplyMartialBonuses = 装備に「物理攻撃スコアの正値ボーナス」が1つも無い場合のみ true
- martialPercent / martialMultiplier を physicalAttackScore にのみ適用

## 算出順序（実装準拠）

1) 各ステータスの基礎式を計算（下記の各ステータス）
2) statConversion を加算（conv_stat）
3) criticalChancePercent の上限補正（cap/capDelta）
4) statFixedToOne 指定があるステータスは raw = 1（attackCountは後述）
5) attackCount を確定（後述の条件分岐）
6) Int系は trunc で丸めて CharacterValues.Combat を生成
7) 装備戦闘ボーナスを加算（E_stat / E_attackCount）
8) 21以上ボーナスを適用
9) clamp: maxHP >= 1、attackCount >= 1、criticalChancePercent は 0〜100

## 共通関数・係数（実装準拠）

定数:
- maxHPCoefficient = 10.0（HPの基礎スケール）
- physicalAttackScoreCoefficient = 1.0（物理攻撃スコア係数、現状は等倍）
- magicalAttackScoreCoefficient = 1.0（魔法攻撃スコア係数、現状は等倍）
- physicalDefenseScoreCoefficient = 1.0（物理防御スコア係数、現状は等倍）
- magicalDefenseScoreCoefficient = 1.0（魔法防御スコア係数、現状は等倍）
- hitScoreCoefficient = 2.0（命中スコアの全体倍率）
- hitScoreBaseBonus = 50.0（命中スコアの基礎加算）
- evasionScoreCoefficient = 1.0（回避スコア係数、現状は等倍）
- criticalChanceCoefficient = 0.16（必殺率の変換係数）
- magicalHealingScoreCoefficient = 2.0（回復力の全体倍率）
- trapRemovalScoreCoefficient = 0.5（罠解除の係数）
- additionalDamageScoreScale = 0.32（追加ダメージの全体倍率）
- additionalDamageLevelCoefficient = 0.125（追加ダメージのレベル成長係数）
- attackCountCoefficient = 0.025（攻撃回数の最終スケール）
- attackCountLevelCoefficient = 0.025（攻撃回数のレベル成長係数）
- breathDamageScoreCoefficient = 1.0（ブレスダメージ係数、現状は等倍）

levelDependentValue(raceId, LV):
- isHuman = raceId in {1, 2}
- if LV <= 30: LV * 0.1
- else if 31 <= LV <= 60: LV * 0.15 - 1.5
- else if 61 <= LV <= 80: LV * 0.225 - 6.0
- else if 81 <= LV <= 100: isHuman ? (LV * 0.225 - 6.0) : (LV * 0.45 - 24.0)
- else if 101 <= LV <= 150: isHuman ? (LV * 0.1125 + 5.25) : (LV * 0.45 - 24.0)
- else if 151 <= LV <= 180: isHuman ? (LV * 0.16875 - 3.1875) : (LV * 0.45 - 24.0)
- else: isHuman ? (LV * 0.253125 - 18.375) : (LV * 0.45 - 24.0)

statBonusMultiplier(value):
- if value < 21: 1.0
- else: pow(1.04, value - 20)

resistancePercent(value):
- if value < 21: 1.0
- else: pow(0.96, value - 20)

strengthDependency(value):
- if value < 10: dep = 0.04
- else if 10 <= value <= 20: dep = 0.004 * value
- else if 20 <= value <= 25: dep = 0.008 * (value - 10)
- else if 25 <= value <= 30: dep = 0.024 * (value - 20)
- else if 30 <= value <= 33: dep = 0.040 * (value - 24)
- else if 33 <= value <= 35: dep = 0.060 * (value - 27)
- else: dep = 0.060 * (value - 27)
- return dep * 125.0

agilityDependency(value):
- if value <= 20: 20.0
- table: (21,20.84) (22,21.74) (23,22.72) (24,23.80) (25,25.00)
         (26,26.34) (27,27.82) (28,29.46) (29,31.26) (30,33.33)
         (31,35.70) (32,38.48) (33,41.68) (34,45.52) (35,50.00)
- if value >= 35: last two points 35/34 の傾きで外挿
- else: 区間線形補間

additionalDamageGrowth(LV, c_physicalAttackScore, growthMultiplier):
- (LV / 5.0) * additionalDamageLevelCoefficient * c_physicalAttackScore * growthMultiplier

finalAttackCount(AGI, LF, c_attackCount, T_attackCount, P_attackCount, A_attackCount):
- base = agilityDependency(max(AGI, 0))
- base *= (1 + LF * c_attackCount * attackCountLevelCoefficient)
- base *= T_attackCount
- base *= 0.5
- primary = round(base + 0.1)   // round: toNearestOrAwayFromZero
- secondary = round(base - 0.3) // round: toNearestOrAwayFromZero
- count = max(1.0, primary + secondary) * 2.0 * attackCountCoefficient
- count *= P_attackCount
- count += A_attackCount
- if count % 1.0 == 0.5: return floor(count)
- else: return max(1, Int(round(count)))

## 生成フロー（概要）

1) **基礎能力の算出**（Race + レベル補正 + Personality + 装備の基礎ボーナス）
2) **職業係数（JobMaster）×成長係数**で各ステータスの基礎値を生成
3) **スキル効果の集約**
   - Talent / Incompetence（才能・無能）
   - ステータス倍率補正 / 加算補正
   - 線形変換 / 百分率変換
   - 攻撃回数の加算 / 倍率補正
   - 追加ダメージの加算 / 倍率補正
   - ステータス固定（1固定）
4) **装備戦闘ボーナスの反映**
   - タイトル・超レア・宝石改造・パンドラは cachedEquippedItems 側で適用済み
   - ここでカテゴリ倍率とアイテム倍率を適用
5) **21以上ボーナス（耐性補正）**
   - strength: 物理攻撃/追加ダメージの増幅
   - wisdom: 魔法攻撃/魔法回復/ブレスの増幅
   - vitality: 物理防御の耐性補正
   - spirit: 魔法防御の耐性補正
   - luck: 必殺率の増幅
6) **丸め・クランプ**
   - maxHP >= 1
   - attackCount >= 1
   - criticalChancePercent は 0〜100

## 各ステータスの意味と使われ方

### maxHP（最大HP）
- **単位**: HP（整数）
- **生成**: vitality 由来 + Job係数 + 成長係数。talent/passive/additive適用。係数=10.0。
- **計算式（実装準拠）**:
```text
# VITとレベル成長(LF) + 職業係数で基礎HPを作る
raw = VIT * (1 + LF * c_maxHP)
# 10.0はHPの基礎スケール、T/P/Aはタレント/パッシブ/加算
raw = raw * T_maxHP * 10.0
raw *= P_maxHP
raw += A_maxHP
# 変換加算
raw += conv_maxHP
# statFixedToOne指定があれば強制1
if fixedToOne(maxHP): raw = 1
# truncは小数点切り捨て
value = trunc(raw)
# 装備ボーナスを加算
value += E_maxHP
# 最低1を保証
value = max(1, value)
```
- **用途**:
  - currentHP の上限
  - 回復量の上限（heal/absorption/resurrection 等）
  - %回復・%ダメージの基準
  - HP閾値判定

### physicalAttackScore（物理攻撃スコア）
- **単位**: 攻撃力スコア（整数）
- **生成**: strength 由来 + Job係数。talent/passive/additive適用。格闘ボーナスあり。
- **計算式（実装準拠）**:
```text
# STRとレベル成長(LF) + 職業係数で基礎攻撃を作る
raw = STR * (1 + LF * c_physicalAttackScore)
# 係数1.0は等倍、T/P/Aはタレント/パッシブ/加算
raw = raw * T_physicalAttackScore * 1.0
raw *= P_physicalAttackScore
raw += A_physicalAttackScore
# 格闘ボーナスは「正の物理攻撃ボーナス装備が無い時のみ」適用
if shouldApplyMartialBonuses:
  if martialPercent != 0: raw *= 1 + martialPercent / 100.0
  raw *= martialMultiplier
# 変換加算
raw += conv_physicalAttackScore
# statFixedToOne指定があれば強制1
if fixedToOne(physicalAttackScore): raw = 1
# truncは小数点切り捨て
value = trunc(raw)
# 装備ボーナスを加算
value += E_physicalAttackScore
# STR21以上は増幅
if STR >= 21: value = trunc(value * statBonusMultiplier(STR))
```
- **用途**:
  - 物理ダメージ計算の攻撃力
  - 初撃ボーナス（物理攻撃スコア - 物理防御スコア×3）に使用
  - 特殊攻撃で上書き・倍率化される場合あり
    - 例: 物理+魔法、物理+命中スコア、物理×2、物理×攻撃回数

### magicalAttackScore（魔法攻撃スコア）
- **単位**: 魔力スコア（整数）
- **生成**: wisdom 由来 + Job係数。talent/passive/additive適用。
- **計算式（実装準拠）**:
```text
# WISとレベル成長(LF) + 職業係数で基礎魔攻を作る
raw = WIS * (1 + LF * c_magicalAttackScore)
# 係数1.0は等倍、T/P/Aはタレント/パッシブ/加算
raw = raw * T_magicalAttackScore * 1.0
raw *= P_magicalAttackScore
raw += A_magicalAttackScore
# 変換加算
raw += conv_magicalAttackScore
# statFixedToOne指定があれば強制1
if fixedToOne(magicalAttackScore): raw = 1
# truncは小数点切り捨て
value = trunc(raw)
# 装備ボーナスを加算
value += E_magicalAttackScore
# WIS21以上は増幅
if WIS >= 21: value = trunc(value * statBonusMultiplier(WIS))
```
- **用途**:
  - 魔法ダメージ計算の攻撃力
  - 状態異常付与判定の比率（魔法攻撃スコア / 魔法防御スコア）
  - 特殊攻撃（物理攻撃スコア+魔法攻撃スコア）に使用

### physicalDefenseScore（物理防御スコア）
- **単位**: 防御スコア（整数）
- **生成**: vitality 由来 + Job係数。talent/passive/additive適用。
- **補正**: vitality >= 21 で耐性補正（数値低下）
- **計算式（実装準拠）**:
```text
# VITとレベル成長(LF) + 職業係数で基礎防御を作る
raw = VIT * (1 + LF * c_physicalDefenseScore)
# 係数1.0は等倍、T/P/Aはタレント/パッシブ/加算
raw = raw * T_physicalDefenseScore * 1.0
raw *= P_physicalDefenseScore
raw += A_physicalDefenseScore
# 変換加算
raw += conv_physicalDefenseScore
# statFixedToOne指定があれば強制1
if fixedToOne(physicalDefenseScore): raw = 1
# truncは小数点切り捨て
value = trunc(raw)
# 装備ボーナスを加算
value += E_physicalDefenseScore
# VIT21以上は耐性補正で数値を下げる
if VIT >= 21: value = trunc(value * resistancePercent(VIT))
```
- **用途**:
  - 物理ダメージ軽減（劣化%の影響を受ける）
  - 初撃ボーナス計算に使用
  - 特殊攻撃で無視される場合あり

### magicalDefenseScore（魔法防御スコア）
- **単位**: 防御スコア（整数）
- **生成**: spirit 由来 + Job係数。talent/passive/additive適用。
- **補正**: spirit >= 21 で耐性補正（数値低下）
- **計算式（実装準拠）**:
```text
# SPRとレベル成長(LF) + 職業係数で基礎防御を作る
raw = SPR * (1 + LF * c_magicalDefenseScore)
# 係数1.0は等倍、T/P/Aはタレント/パッシブ/加算
raw = raw * T_magicalDefenseScore * 1.0
raw *= P_magicalDefenseScore
raw += A_magicalDefenseScore
# 変換加算
raw += conv_magicalDefenseScore
# statFixedToOne指定があれば強制1
if fixedToOne(magicalDefenseScore): raw = 1
# truncは小数点切り捨て
value = trunc(raw)
# 装備ボーナスを加算
value += E_magicalDefenseScore
# SPR21以上は耐性補正で数値を下げる
if SPR >= 21: value = trunc(value * resistancePercent(SPR))
```
- **用途**:
  - 魔法ダメージ軽減（劣化%の影響を受ける）
  - 状態異常付与判定の比率に使用

### hitScore（命中スコア）
- **単位**: **スコア**（%ではない）
- **生成**: (strength + agility)/2 由来 + Job係数。基礎加算 + 係数適用。
- **計算式（実装準拠）**:
```text
# STR/AGI平均をベースに、レベル成長 + 職業係数を反映
raw = ((STR + AGI) / 2.0) * (1 + LF * c_hitScore)
# 50.0は基礎加算、2.0は全体倍率
raw = (raw + 50.0) * 2.0
# T/P/Aはタレント/パッシブ/加算
raw *= T_hitScore
raw *= P_hitScore
raw += A_hitScore
# 変換加算
raw += conv_hitScore
# statFixedToOne指定があれば強制1
if fixedToOne(hitScore): raw = 1
# truncは小数点切り捨て
value = trunc(raw)
# 装備ボーナスを加算
value += E_hitScore
```
- **用途**:
  - 命中判定の比率計算で attackerScore として使用
  - 特殊攻撃で物理攻撃力に合算されるケースあり
  - スキルによる累積命中ボーナスはスコア加算
- **注意**:
  - 命中判定の確率は上限・下限で制御する

### evasionScore（回避スコア）
- **単位**: **スコア**（%ではない）
- **生成**: (agility + luck)/2 由来 + Job係数。talent/passive/additive適用。
- **計算式（実装準拠）**:
```text
# AGI/LUK平均をベースに、レベル成長 + 職業係数を反映
raw = ((AGI + LUK) / 2.0) * (1 + LF * c_evasionScore) * 1.0
# 係数1.0は等倍、T/P/Aはタレント/パッシブ/加算
raw *= T_evasionScore
raw *= P_evasionScore
raw += A_evasionScore
# 変換加算
raw += conv_evasionScore
# statFixedToOne指定があれば強制1
if fixedToOne(evasionScore): raw = 1
# truncは小数点切り捨て
value = trunc(raw)
# 装備ボーナスを加算
value += E_evasionScore
```
- **用途**:
  - 命中判定の比率計算で defenderScore として使用
  - 劣化補正後の回避スコアを使用する
  - 回避上限は Percent 値で制御する

### criticalChancePercent（必殺率）
- **単位**: **Percent（0〜100）**
- **生成**: (agility + luck*2 - 45) 由来 + Job係数。talent/passive/additive適用。
- **補正**: 上限補正を適用後に 0〜100 にクランプ
- **計算式（実装準拠）**:
```text
# AGI + LUK*2 から基礎を作り、45.0を引いて下駄を引く
critSource = max(AGI + LUK * 2.0 - 45.0, 0.0)
# 0.16は必殺率への変換係数、職業係数を乗算
raw = critSource * 0.16 * c_criticalChancePercent
# T/Pはタレント/パッシブ、flatBonusは加算
raw *= T_criticalChancePercent
raw *= P_criticalChancePercent
raw += criticalFlatBonus
# 上限は cap と capDelta を反映（デフォルト100）
cap = criticalCap ?? 100.0
cap = max(0.0, cap + criticalCapDelta)
raw = min(raw, cap)
raw = max(0.0, min(raw, 100.0))
# statFixedToOne指定があれば強制1
if fixedToOne(criticalChancePercent): raw = 1
# truncは小数点切り捨て
value = trunc(raw)
# 装備ボーナスを加算
value += E_criticalChancePercent
# LUK21以上は増幅（上限100）
if LUK >= 21: value = trunc(min(value * statBonusMultiplier(LUK), 100.0))
value = max(0, min(100, value))
```
- **用途**:
  - 物理必殺判定に使用
  - 特殊攻撃・リアクションで倍率補正される場合あり
- **注意**:
  - 魔法必殺は別系統の Percent として管理

### attackCount（攻撃回数）
- **単位**: 回数（Double）
- **生成**: agility 由来の計算式で整数化 → タレント/倍率/加算 → 変換・装備加算
- **計算式（実装準拠）**:
```text
# finalAttackCountはAGIテーブル・丸め規則・係数を含む最終値（Int）
base = finalAttackCount(AGI, LF, c_attackCount, T_attackCount, P_attackCount, A_attackCount) // Int
raw = Double(base)
# 変換加算がある場合のみ Double として反映
rawConv = raw + conv_attackCount
if abs(rawConv - raw) < 0.0001:
  value = raw
else:
  value = max(1.0, rawConv)
# statFixedToOne指定があれば強制1
if fixedToOne(attackCount): value = 1.0
# 装備ボーナスを加算（Double）
value += E_attackCount
# 最低1を保証
value = max(1.0, value)
```
- **用途**:
  - 物理攻撃のヒット数（Intへ切り捨て、最低1）
  - 特殊攻撃で上書き・倍率化される場合あり
  - 連撃による命中/ダメージ減衰は hitIndex に応じて適用
- **注意**:
  - アイテムは小数加算（例: +0.3）
  - UIは小数1桁表示

### magicalHealingScore（魔法回復力スコア）
- **単位**: 回復パワースコア（整数）
- **生成**: spirit 由来 + Job係数。talent/passive/additive適用。
- **計算式（実装準拠）**:
```text
# SPRとレベル成長(LF) + 職業係数で基礎回復力を作る
raw = SPR * (1 + LF * c_magicalHealingScore)
# 2.0は回復力の全体倍率、T/P/Aはタレント/パッシブ/加算
raw = raw * T_magicalHealingScore * 2.0
raw *= P_magicalHealingScore
raw += A_magicalHealingScore
# 変換加算
raw += conv_magicalHealingScore
# statFixedToOne指定があれば強制1
if fixedToOne(magicalHealingScore): raw = 1
# truncは小数点切り捨て
value = trunc(raw)
# 装備ボーナスを加算
value += E_magicalHealingScore
# WIS21以上は増幅（SPRではなくWISが参照される）
if WIS >= 21: value = trunc(value * statBonusMultiplier(WIS))
```
- **用途**:
  - 回復呪文の基礎回復量
  - アンチ・ヒーリングのダメージ基準
  - 復活時の回復量の基準
  - 一部の自己回復効果の基準

### trapRemovalScore（罠解除スコア）
- **単位**: 解除スコア（整数）
- **生成**: (agility + luck)/2 由来 + Job係数。係数=0.5。
- **計算式（実装準拠）**:
```text
# AGI/LUK平均をベースに、レベル成長 + 職業係数を反映
raw = ((AGI + LUK) / 2.0) * (1 + LF * c_trapRemovalScore) * 0.5
# 0.5は罠解除の係数、T/P/Aはタレント/パッシブ/加算
raw *= T_trapRemovalScore
raw *= P_trapRemovalScore
raw += A_trapRemovalScore
# 変換加算
raw += conv_trapRemovalScore
# statFixedToOne指定があれば強制1
if fixedToOne(trapRemovalScore): raw = 1
# truncは小数点切り捨て
value = trunc(raw)
# 装備ボーナスを加算
value += E_trapRemovalScore
```
- **用途**:
  - 現時点の戦闘・探索ロジックでは参照されていない
  - UI表示・装備差分・通知でのみ使用

### additionalDamageScore（追加ダメージスコア）
- **単位**: 追加ダメージ（整数）
- **生成**: strength 依存 + 成長係数。talent/passive/additive適用。係数=0.32。
- **計算式（実装準拠）**:
```text
# STR依存テーブルから基礎を作る
dependency = strengthDependency(STR)
# レベル成長はLV/5と職業係数、成長倍率で増える
growth = (LV / 5.0) * 0.125 * c_physicalAttackScore * growthMultiplier
raw = dependency * (1 + growth)
# T/P/Aはタレント/パッシブ/加算
raw *= T_additionalDamageScore
raw *= P_additionalDamageScore
# 0.32は追加ダメージの全体倍率
raw *= 0.32
raw += A_additionalDamageScore
# 変換加算
raw += conv_additionalDamageScore
# statFixedToOne指定があれば強制1
if fixedToOne(additionalDamageScore): raw = 1
# truncは小数点切り捨て
value = trunc(raw)
# 装備ボーナスを加算
value += E_additionalDamageScore
# STR21以上は増幅
if STR >= 21: value = trunc(value * statBonusMultiplier(STR))
```
- **用途**:
  - 物理ダメージ計算のボーナス成分
  - パリィ/盾防御判定の増減に影響

### breathDamageScore（ブレスダメージスコア）
- **単位**: ブレス攻撃力（整数）
- **生成**: wisdom 由来（Job係数は magicalAttackScore を参照）。additive適用。
- **計算式（実装準拠）**:
```text
# WISとレベル成長(LF) + 職業係数で基礎ブレスを作る（係数1.0）
raw = WIS * (1 + LF * c_magicalAttackScore) * 1.0
# 加算のみ適用（T/Pはブレスに存在しない）
raw += A_breathDamageScore
# 変換加算
raw += conv_breathDamageScore
# statFixedToOne指定があれば強制1
if fixedToOne(breathDamageScore): raw = 1
# truncは小数点切り捨て
value = trunc(raw)
# 装備ボーナスを加算
value += E_breathDamageScore
# WIS21以上は増幅
if WIS >= 21: value = trunc(value * statBonusMultiplier(WIS))
```
- **用途**:
  - ブレス行動の可否判定
  - ブレスダメージ計算の基礎値

## 付記（レガシー名称との対応）

正本では本文に旧名称を持ち込まない。実装との対応が必要な場合のみ以下を参照する。

- maxHP → **maxHP**
- physicalAttackScore → **physicalAttack**
- magicalAttackScore → **magicalAttack**
- physicalDefenseScore → **physicalDefense**
- magicalDefenseScore → **magicalDefense**
- hitScore → **hitRate**
- evasionScore → **evasionRate**
- criticalChancePercent → **criticalRate**
- attackCount → **attackCount**
- magicalHealingScore → **magicalHealing**
- trapRemovalScore → **trapRemoval**
- additionalDamageScore → **additionalDamage**
- breathDamageScore → **breathDamage**
- 命中スコア加算 → **hitRatePercent / hitRatePerTurn**
- 回避スコア加算 → **evasionRatePerTurn**
- 魔法必殺Percent → **magicCriticalChancePercent**
