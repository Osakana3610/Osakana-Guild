# スキル語彙（正本）

スキル名、説明、ログ、L10nで使う語彙の正本。
同じ効果には同じ語彙を使い、禁止同義語は使わない。

## 重要な前提

- **MPは使用しない**。魔法の使用回数は「魔法の使用回数」と表記し、「呪文チャージ」は使わない。
- 効果の種類が同じなら、表記も同じにする。
- 迷った語彙はここに追加してから使う。
- スキル名は略称を許容する場合がある（例: 与ダメ/被ダメ）。説明/ログ/L10nは正本表記に統一する。

## 用語一覧

| key | 正本表記 | 意味 | 適用範囲 | 禁止同義語 | 備考 |
| --- | --- | --- | --- | --- | --- |
| status.apply | 付与 | 状態異常を対象に与える行為 | status | 適用,追加 |  |
| status.remove | 解除 | 状態異常を対象から取り除く行為 | status | 除去,浄化,ペナルティ解除 |  |
| status.debuff | デバフ | 能力低下系の状態異常 | status | 弱体,低下効果 |  |
| stat.increase | 増加する | 数値が上がる効果 | stat | 上昇する,アップ,up,plus |  |
| stat.decrease | 減少する | 数値が下がる効果 | stat | 低下する,ダウン,down,minus |  |
| stat.damageReduce | 軽減する | 受けるダメージを減らす効果 | stat | 減少する,低下する |  |
| damage.dealt | 攻撃で与えるダメージ | 攻撃側が与えるダメージの表現 | damage | 与ダメージ,与ダメ,被ダメージ | スキル名の短縮表記として「与ダメ」は許容。説明/ログ/L10nでは禁止。 |
| damage.received | 受けるダメージ | 防御側が受けるダメージの表現 | damage | 被ダメージ,被ダメ,与ダメージ | スキル名の短縮表記として「被ダメ」は許容。説明/ログ/L10nでは禁止。 |
| chance.expression | X%の確率で | 確率を明示する表現 | chance | 確率で |  |
| chance.certain | 必ず | 100%の確率を表す表現 | chance | 確定で |  |
| chance.basePercent | 発動率係数 | baseChancePercent に対応する係数（参照ステータス1につき何%か） | chance | 初期確率,ベース確率 | scalingStat とセットで使用。固定確率には使わない |
| chance.percent | 発動率 | chancePercent に対応する固定の発動率 | chance | 確率,発動確率 | scalingStat を使わない固定確率 |
| chance.scalingStat | 発動率の参照ステータス | scalingStat に対応する参照能力値 | chance |  | baseChancePercent とセットで使用（例: 力） |
| battle.damage.physical | 物理攻撃/物理ダメージ | 物理属性の攻撃・ダメージ表現 | battle | 物理 |  |
| battle.damage.magical | 魔法攻撃/魔法ダメージ | 魔法属性の攻撃・ダメージ表現 | battle | 魔法 |  |
| battle.damage.breath | ブレス攻撃/ブレスダメージ | ブレス属性の攻撃・ダメージ表現 | battle | ブレス |  |
| battle.damage.all | すべての攻撃 | 属性を問わない攻撃表現 | battle | 全攻撃 |  |
| battle.term.barrier | 結界 | ダメージを無効化するバリア表現 | battle | バリア,シールド |  |
| battle.term.parry | パリィ | パリィの表現 | battle | 受け流し |  |
| battle.term.shieldBlock | 盾防御 | 盾防御の表現 | battle | 盾ブロック,ブロック |  |
| battle.term.critical | 必殺 | criticalの日本語表記 | battle | クリティカル |  |
| battle.term.proc | 特殊効果の発動 | procの日本語表記 | battle | プロック |  |
| battle.term.berserk | 暴走 | berserkの日本語表記 | battle | バーサーク |  |
| battle.term.evasion | 回避 | dodge/evasionの日本語表記 | battle | 回避率 |  |
| battle.term.accuracy | 命中 | accuracyの日本語表記 | battle | 命中率 |  |
| reaction.system | 反撃/追撃/報復/再攻撃（スキル名で表記） | ReactionTriggerで発動する追加行動の総称 | reaction | リアクション処理 |  |
| reaction.counter | 反撃 | 被ダメージ/回避をトリガーに発動するReaction | reaction | カウンター |  |
| reaction.followup | 追撃 | 撃破/味方魔法発動をトリガーに発動するReaction | reaction | フォローアップ |  |
| reaction.retaliation | 報復 | 味方撃破をトリガーに発動するReaction | reaction | リタリエーション |  |
| reaction.extraAction | 再攻撃 | 通常行動内で発生する追加行動（Reactionとは別系統） | reaction | 追加行動 |  |
| reaction.martialFollowUp | 格闘追撃 | 物理攻撃後の格闘追撃（Reactionとは別系統） | reaction | 格闘フォローアップ |  |
| reaction.rescue | 救出 | 味方撃破時の救出処理（Reactionとは別系統） | reaction | レスキュー |  |
| combat.unit.score | スコア | 比率計算やダメージ計算に直接投入する値 | combat | %値 |  |
| combat.unit.percent | ％（パーセント） | 0〜100の確率・上限を示す単位 | combat | パーセントのみ,percent |  |
| combat.unit.multiplier | 倍率 | 1.0が基準の乗数 | combat | 乗数 |  |
| combat.unit.count | 回数 | 回数を示す単位 | combat | 回数値 |  |
| trigger.selfDamagedPhysical | 物理攻撃を受けた時 | selfDamagedPhysicalの表現 | trigger | 被物理時 |  |
| trigger.selfDamagedMagical | 魔法攻撃を受けた時 | selfDamagedMagicalの表現 | trigger | 被魔法時 |  |
| trigger.selfEvadePhysical | 物理攻撃を回避した時 | selfEvadePhysicalの表現 | trigger | 回避時 |  |
| trigger.allyDamagedPhysical | 味方が物理攻撃を受けた時 | allyDamagedPhysicalの表現 | trigger | 味方被物理時 |  |
| trigger.allyDefeated | 味方が倒された時 | allyDefeatedの表現 | trigger | 味方撃破時 |  |
| trigger.selfKilledEnemy | 自分が敵を倒した時 | selfKilledEnemyの表現 | trigger | 撃破時 |  |
| trigger.allyMagicAttack | 味方が魔法攻撃をした時 | allyMagicAttackの表現 | trigger | 味方魔法時 |  |
| spell.usageCount | 魔法の使用回数 | 魔法の使用回数の表現 | spell | 呪文チャージ |  |
| breath.usageCount | ブレスの使用回数 | ブレスの使用回数の表現 | breath | 追加チャージ |  |
