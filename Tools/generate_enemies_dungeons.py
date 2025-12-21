#!/usr/bin/env python3
"""
敵マスターとダンジョンマスターを生成するスクリプト
72ダンジョン × 6体/ダンジョン = 432体の敵
"""

import json
import random
from pathlib import Path

random.seed(42)  # 再現性のため

# 敵種族ID (EnemyRaceMaster.json)
RACE_HUMANOID = 1  # 人型
RACE_MONSTER = 2   # 魔物
RACE_UNDEAD = 3    # 不死
RACE_DRAGON = 4    # 竜族
RACE_DIVINE = 5    # 神魔

# 職業ID (JobMaster.json)
# 1=戦士, 2=剣士, 3=盗賊, 4=騎士, 5=僧兵, 6=僧侶, 7=魔法使い, 8=狩人
# 9=修道者, 10=侍, 11=剣聖, 12=秘法剣士, 13=賢者, 14=忍者, 15=君主, 16=ロイヤルライン

# 種族別の職業マッピング
JOBS_BY_RACE = {
    RACE_HUMANOID: {
        "normal": [1, 2, 3, 6, 7, 8],      # 戦士, 剣士, 盗賊, 僧侶, 魔法使い, 狩人
        "elite": [9, 10, 11, 12, 13, 14],  # 修道者, 侍, 剣聖, 秘法剣士, 賢者, 忍者
        "boss": [15, 16],                   # 君主, ロイヤルライン
    },
    RACE_MONSTER: {  # 獣・魔物 - 野性的・物理寄り
        "normal": [1, 3, 8],               # 戦士, 盗賊, 狩人
        "elite": [10, 14],                 # 侍, 忍者
        "boss": [15],                      # 君主
    },
    RACE_UNDEAD: {  # 不死 - 暗黒魔法・呪い
        "normal": [6, 7],                  # 僧侶, 魔法使い
        "elite": [9, 12, 13],              # 修道者, 秘法剣士, 賢者
        "boss": [16],                      # ロイヤルライン
    },
    RACE_DRAGON: {  # 竜族 - 強力な戦闘力
        "normal": [1, 2, 4],               # 戦士, 剣士, 騎士
        "elite": [10, 11],                 # 侍, 剣聖
        "boss": [15, 16],                  # 君主, ロイヤルライン
    },
    RACE_DIVINE: {  # 神魔 - 魔法と神聖/邪悪
        "normal": [6, 7, 5],               # 僧侶, 魔法使い, 僧兵
        "elite": [9, 12, 13],              # 修道者, 秘法剣士, 賢者
        "boss": [16],                      # ロイヤルライン
    },
}

# 章別テーマと敵種族の傾向
CHAPTER_THEMES = {
    1: {"name": "森・洞窟", "races": [RACE_HUMANOID, RACE_MONSTER], "level_range": (1, 15)},
    2: {"name": "山・峠", "races": [RACE_HUMANOID, RACE_MONSTER], "level_range": (15, 30)},
    3: {"name": "遺跡・廃墟", "races": [RACE_UNDEAD, RACE_HUMANOID], "level_range": (30, 45)},
    4: {"name": "沼・毒地", "races": [RACE_MONSTER, RACE_UNDEAD], "level_range": (45, 60)},
    5: {"name": "火山・灼熱", "races": [RACE_DRAGON, RACE_MONSTER], "level_range": (60, 80)},
    6: {"name": "氷原・凍土", "races": [RACE_MONSTER, RACE_UNDEAD], "level_range": (80, 100)},
    7: {"name": "魔界・深淵", "races": [RACE_UNDEAD, RACE_DIVINE], "level_range": (100, 130)},
    8: {"name": "天空・神域", "races": [RACE_DIVINE, RACE_DRAGON], "level_range": (130, 170)},
    9: {"name": "超越領域", "races": [RACE_DIVINE, RACE_DRAGON], "level_range": (170, 200)},  # Extra
}

# 敵名テンプレート（章・テーマ別）
ENEMY_TEMPLATES = {
    1: {
        "normal": ["ゴブリン", "コボルド", "野犬", "毒蛇", "大蜘蛛"],
        "elite": ["ゴブリンリーダー", "洞窟熊"],
        "boss": ["森の主"],
    },
    2: {
        "normal": ["山賊", "ハーピー", "岩猿", "鷲獅子", "山狼"],
        "elite": ["山賊頭目", "風使い"],
        "boss": ["峠の魔獣"],
    },
    3: {
        "normal": ["スケルトン", "ゾンビ", "幽霊", "石像兵", "呪われた騎士"],
        "elite": ["死霊術師", "古代の番人"],
        "boss": ["遺跡の守護者"],
    },
    4: {
        "normal": ["毒蛙", "沼の触手", "腐食獣", "毒蛾", "スライム"],
        "elite": ["沼の魔女", "腐敗の王"],
        "boss": ["沼の主"],
    },
    5: {
        "normal": ["火炎犬", "マグマゴーレム", "火の精", "溶岩蛇", "炎の鳥"],
        "elite": ["火竜の子", "炎の巨人"],
        "boss": ["炎の王"],
    },
    6: {
        "normal": ["氷狼", "フロストゴーレム", "雪女", "氷の精", "凍結獣"],
        "elite": ["氷竜の子", "吹雪の使者"],
        "boss": ["氷の女王"],
    },
    7: {
        "normal": ["悪魔兵", "堕天使", "魔界の獣", "影の従者", "深淵の眼"],
        "elite": ["魔将", "深淵の使者"],
        "boss": ["魔王"],
    },
    8: {
        "normal": ["天使兵", "聖獣", "光の精", "天空の番人", "神の使い"],
        "elite": ["大天使", "神竜の子"],
        "boss": ["神竜"],
    },
    9: {
        "normal": ["超越者", "混沌の獣", "虚無の眼", "終焉の使者", "始原の精"],
        "elite": ["神殺し", "世界の敵"],
        "boss": ["超越神"],
    },
}

# 敵専用技ID (EnemySkillMaster.json)
ENEMY_SKILLS = {
    "physical_weak": [1],           # 強撃
    "physical_medium": [1, 2],      # 強撃、剛撃
    "physical_strong": [2, 3],      # 剛撃、烈撃
    "physical_boss": [3, 4],        # 烈撃、必殺撃
    "magical_weak": [11],           # 魔弾
    "magical_medium": [11, 12],     # 魔弾、魔砲
    "magical_strong": [12, 13],     # 魔砲、滅砲
    "magical_boss": [13, 14],       # 滅砲、極砲
    "breath_fire": [21, 22],        # 火炎息、業火息
    "breath_ice": [23, 24],         # 冷気息、凍結息
    "breath_boss": [29, 30],        # 滅息、神滅息
    "status_sleep": [41],           # 睡眠撃
    "status_confuse": [42],         # 混乱撃
    "status_stone": [43],           # 石化撃
    "status_death": [44],           # 即死撃
    "heal": [51, 52],               # 自己回復、大回復
    "buff": [61, 62, 63],           # 攻撃/防御/魔力強化
}


def generate_stat(base: int, variance: int = 3) -> int:
    """基本値から±varianceの範囲でステータスを生成"""
    return max(5, min(35, base + random.randint(-variance, variance)))


def select_job(race_id: int, enemy_type: str) -> int:
    """敵の種族とタイプに応じて職業を選択"""
    race_jobs = JOBS_BY_RACE.get(race_id, JOBS_BY_RACE[RACE_HUMANOID])
    job_list = race_jobs.get(enemy_type, race_jobs["normal"])
    return random.choice(job_list)


def generate_enemy(enemy_id: int, chapter: int, stage: int, enemy_type: str, index: int) -> dict:
    """敵データを生成"""
    theme = CHAPTER_THEMES[chapter]
    templates = ENEMY_TEMPLATES[chapter]

    # 名前を決定
    if enemy_type == "boss":
        name_base = templates["boss"][0]
        suffix = f"{stage}章" if chapter <= 8 else f"EX{stage}"
        name = f"{name_base}【{suffix}】"
    elif enemy_type == "elite":
        name_base = random.choice(templates["elite"])
        name = f"{name_base}・{stage}"
    else:
        name_base = random.choice(templates["normal"])
        name = f"{name_base}・{stage}-{index}"

    # 種族を決定
    race_id = random.choice(theme["races"])

    # 章に応じた基本ステータス (5-35の範囲)
    base_stat = min(35, 5 + chapter * 3)
    stat_bonus = {"boss": 5, "elite": 3, "normal": 0}[enemy_type]

    # ステータス生成
    stats = {
        "strength": generate_stat(base_stat + stat_bonus),
        "wisdom": generate_stat(base_stat + stat_bonus),
        "spirit": generate_stat(base_stat + stat_bonus - 1),
        "vitality": generate_stat(base_stat + stat_bonus + 1),
        "agility": generate_stat(base_stat + stat_bonus),
        "luck": generate_stat(base_stat),
    }

    # 経験値 (章と種類に応じて)
    base_exp = chapter * 100
    exp_multiplier = {"boss": 10, "elite": 3, "normal": 1}[enemy_type]
    base_experience = base_exp * exp_multiplier

    # 耐性（ダメージ倍率: 1.0=通常, 0.5=半減, 2.0=弱点）
    # 章が進むと耐性が上がる（倍率が下がる）
    base_resist = max(0.5, 1.0 - chapter * 0.03)  # 1章=0.97, 9章=0.73
    resistances = {
        "physical": round(base_resist + random.uniform(-0.05, 0.05), 2),
        "piercing": round(base_resist + random.uniform(-0.05, 0.05), 2),
        "critical": round(base_resist + random.uniform(-0.05, 0.05), 2),
        "breath": 1.0,  # デフォルトはブレス等倍
    }

    # 種族別の耐性調整
    # spell.0 = マジックアロー, spell.2 = ファイヤーボール, spell.3 = ブリザード
    # spell.5 = サンダーボルト, spell.6 = ニュークリア
    if race_id == RACE_DRAGON:
        # 竜族: 炎耐性、氷弱点、ブレス耐性
        resistances["spell.2"] = round(0.5 - chapter * 0.02, 2)   # ファイヤーボール耐性
        resistances["spell.3"] = round(1.5 + chapter * 0.05, 2)   # ブリザード弱点
        resistances["breath"] = round(0.7 - chapter * 0.02, 2)    # ブレス耐性
    elif race_id == RACE_DIVINE:
        # 神魔: 高レベル魔法耐性、物理弱点
        resistances["physical"] = round(1.2 + chapter * 0.02, 2)  # 物理弱点
        resistances["spell.6"] = round(0.4 - chapter * 0.02, 2)   # ニュークリア耐性
        resistances["critical"] = round(0.5 - chapter * 0.02, 2)  # クリティカル耐性
    elif race_id == RACE_UNDEAD:
        # 不死: 物理耐性、マジックアロー弱点
        resistances["physical"] = round(0.6 - chapter * 0.02, 2)  # 物理耐性
        resistances["spell.0"] = round(1.3 + chapter * 0.03, 2)   # マジックアロー弱点

    # スキル決定
    skills = []
    if enemy_type == "boss":
        if race_id == RACE_DRAGON:
            skills = ENEMY_SKILLS["breath_boss"] + ENEMY_SKILLS["physical_boss"]
        elif race_id == RACE_DIVINE:
            skills = ENEMY_SKILLS["magical_boss"] + ENEMY_SKILLS["status_death"]
        else:
            skills = ENEMY_SKILLS["physical_boss"] + ENEMY_SKILLS["heal"]
    elif enemy_type == "elite":
        if chapter >= 5:
            skills = ENEMY_SKILLS["physical_strong"] + ENEMY_SKILLS["status_confuse"]
        else:
            skills = ENEMY_SKILLS["physical_medium"]
    else:
        if chapter >= 7:
            skills = ENEMY_SKILLS["physical_medium"]
        elif chapter >= 4:
            skills = ENEMY_SKILLS["physical_weak"]
        else:
            skills = []

    # ドロップアイテム (仮にアイテムID 1-100の範囲)
    drops = [random.randint(1, 100) for _ in range(random.randint(1, 3))]

    # 職業を設定（人型敵のみ）
    job_id = select_job(race_id, enemy_type)

    return {
        "id": enemy_id,
        "baseName": name,
        "race": race_id,
        "baseExperience": base_experience,
        "specialSkillIds": skills,
        "resistances": resistances,
        "isBoss": enemy_type == "boss",
        "baseStats": stats,
        "drops": drops,
        "category": "enemy",
        "job": job_id,
        # groupSizeRange は削除: ダンジョンのfloorEnemyMappingで管理
        "actionRates": {
            "attack": 70 if enemy_type != "boss" else 50,
            "priestMagic": 0,
            "mageMagic": 20 if race_id in [RACE_DIVINE, RACE_UNDEAD] else 0,
            "breath": 30 if race_id == RACE_DRAGON else 0,
        }
    }


def get_group_size_range(chapter: int, floor_type: str, enemy_type: str) -> tuple[int, int]:
    """章・フロアタイプ・敵タイプに応じたグループサイズを返す"""
    if enemy_type == "boss":
        return (1, 1)
    if enemy_type == "elite":
        return (1, 2)

    # normalの場合、章とフロアで変動
    base_min = 1 + (chapter - 1) // 3  # 1→1→1→2→2→2→3→3→3
    base_max = 2 + (chapter - 1) // 2  # 2→2→3→3→4→4→5→5→5

    if floor_type == "early":
        return (base_min, min(base_max, base_min + 1))
    elif floor_type == "mid":
        return (base_min, base_max)
    else:  # late
        return (base_min, min(base_max + 1, 5))


def generate_dungeon(dungeon_id: int, chapter: int, stage: int, enemy_start_id: int) -> tuple:
    """ダンジョンと敵リストを生成"""
    theme = CHAPTER_THEMES[chapter]
    level_min, level_max = theme["level_range"]

    # ステージ内でのレベル進行
    stage_progress = (stage - 1) / 7  # 0.0 ~ 1.0
    dungeon_level_min = int(level_min + (level_max - level_min) * stage_progress * 0.8)
    dungeon_level_max = int(level_min + (level_max - level_min) * (stage_progress + 0.2))

    # ダンジョン名
    if chapter <= 8:
        dungeon_name = f"{theme['name']}・{stage}"
    else:
        dungeon_name = f"超越領域・EX{stage}"

    # フロア数
    floor_count = 3 + chapter + (stage - 1) // 2

    # 敵生成 (6体: 雑魚4 + エリート1 + ボス1)
    enemies = []
    enemy_id = enemy_start_id

    # 雑魚4体
    for i in range(4):
        enemies.append(generate_enemy(enemy_id, chapter, stage, "normal", i + 1))
        enemy_id += 1

    # エリート1体
    enemies.append(generate_enemy(enemy_id, chapter, stage, "elite", 1))
    enemy_id += 1

    # ボス1体
    enemies.append(generate_enemy(enemy_id, chapter, stage, "boss", 1))
    enemy_id += 1

    # 敵配置 (floorEnemyMapping) - groupMin/groupMaxを追加
    floor_enemy_mapping = []

    # 序盤フロア: 雑魚のみ
    early_floors = floor_count // 3
    early_group = get_group_size_range(chapter, "early", "normal")
    floor_enemy_mapping.append({
        "floorRange": [1, early_floors],
        "enemyGroups": [
            {
                "enemyId": enemies[i]["id"],
                "minLevel": dungeon_level_min,
                "maxLevel": dungeon_level_min + 5,
                "weight": 25.0,
                "groupMin": early_group[0],
                "groupMax": early_group[1],
            }
            for i in range(4)
        ]
    })

    # 中盤フロア: 雑魚 + エリート
    mid_floors = floor_count * 2 // 3
    mid_group = get_group_size_range(chapter, "mid", "normal")
    elite_group = get_group_size_range(chapter, "mid", "elite")
    floor_enemy_mapping.append({
        "floorRange": [early_floors + 1, mid_floors],
        "enemyGroups": [
            {
                "enemyId": enemies[i]["id"],
                "minLevel": dungeon_level_min + 3,
                "maxLevel": dungeon_level_max - 3,
                "weight": 20.0,
                "groupMin": mid_group[0],
                "groupMax": mid_group[1],
            }
            for i in range(4)
        ] + [
            {
                "enemyId": enemies[4]["id"],
                "minLevel": dungeon_level_min + 5,
                "maxLevel": dungeon_level_max,
                "weight": 20.0,
                "groupMin": elite_group[0],
                "groupMax": elite_group[1],
            }
        ]
    })

    # 終盤フロア: エリート + ボス
    late_elite_group = get_group_size_range(chapter, "late", "elite")
    boss_group = get_group_size_range(chapter, "late", "boss")
    floor_enemy_mapping.append({
        "floorRange": [mid_floors + 1, floor_count],
        "enemyGroups": [
            {
                "enemyId": enemies[4]["id"],
                "minLevel": dungeon_level_max - 5,
                "maxLevel": dungeon_level_max,
                "weight": 60.0,
                "groupMin": late_elite_group[0],
                "groupMax": late_elite_group[1],
            },
            {
                "enemyId": enemies[5]["id"],
                "minLevel": dungeon_level_max,
                "maxLevel": dungeon_level_max + 5,
                "weight": 40.0,
                "groupMin": boss_group[0],
                "groupMax": boss_group[1],
            }
        ]
    })

    dungeon = {
        "id": dungeon_id,
        "name": dungeon_name,
        "chapter": chapter,
        "stage": stage,
        "description": f"{theme['name']}の{stage}番目のダンジョン",
        "recommendedLevel": dungeon_level_min,
        "explorationTime": 1,  # 仮データ: テスト用に1秒
        "eventsPerFloor": 2 + chapter // 3,
        "floorCount": floor_count,
        "storyText": None,
        "unlockConditions": [f"storyRead:{dungeon_id}"],  # ストーリーNを読むとダンジョンNが解放
        "floorEnemyMapping": floor_enemy_mapping,
    }

    return dungeon, enemies


def main():
    all_enemies = []
    all_dungeons = []
    enemy_id = 0
    dungeon_id = 1  # ストーリーIDと対応させるため1から開始

    # 8章 × 8ステージ
    for chapter in range(1, 9):
        for stage in range(1, 9):
            dungeon, enemies = generate_dungeon(dungeon_id, chapter, stage, enemy_id)
            all_dungeons.append(dungeon)
            all_enemies.extend(enemies)
            enemy_id += 6
            dungeon_id += 1

    # Extra 8ステージ (chapter=9として扱う)
    for stage in range(1, 9):
        dungeon, enemies = generate_dungeon(dungeon_id, 9, stage, enemy_id)
        all_dungeons.append(dungeon)
        all_enemies.extend(enemies)
        enemy_id += 6
        dungeon_id += 1

    # EnemyMaster.json出力
    enemy_master = {"enemyTemplates": all_enemies}
    enemy_path = Path(__file__).parent.parent / "MasterData" / "EnemyMaster.json"
    with open(enemy_path, "w", encoding="utf-8") as f:
        json.dump(enemy_master, f, ensure_ascii=False, indent=2)
    print(f"Generated {len(all_enemies)} enemies to {enemy_path}")

    # DungeonMaster.json出力
    dungeon_master = {"dungeons": all_dungeons}
    dungeon_path = Path(__file__).parent.parent / "MasterData" / "DungeonMaster.json"
    with open(dungeon_path, "w", encoding="utf-8") as f:
        json.dump(dungeon_master, f, ensure_ascii=False, indent=2)
    print(f"Generated {len(all_dungeons)} dungeons to {dungeon_path}")


if __name__ == "__main__":
    main()
