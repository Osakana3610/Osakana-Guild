#!/usr/bin/env python3
"""Generate SkillMaster.json from attack skill dataset."""

from __future__ import annotations

import json
import math
import re
import sys
from collections import OrderedDict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATASET = REPO_ROOT / "Documents" / "WikiSkillData" / "attack_skills_dataset.json"
STATUS_DATASET = REPO_ROOT / "Documents" / "WikiSkillData" / "status_skills_dataset.json"
RACE_JOB_DATASET = REPO_ROOT / "Documents" / "WikiSkillData" / "race_job_skills_dataset.json"
DEFAULT_OUTPUT = REPO_ROOT / "Epika" / "Resources" / "SkillMaster.json"

SpellNameToId = {
    "マジックアロー": "magic_arrow",
    "スリープクラウド": "sleep_cloud",
    "ファイヤーボール": "fireball",
    "ブリザード": "blizzard",
    "アタックアップ": "attack_up",
    "サンダーボルト": "thunderbolt",
    "ニュークリア": "nuclear",
    "ヒール": "heal",
    "シールドバリア": "shield_barrier",
    "キュア": "cure",
    "ヒールプラス": "heal_plus",
    "マジックバリア": "magic_barrier",
    "フルヒール": "full_heal",
    "パーティヒール": "party_heal",
}

StatForHeader = {
    "physical": "physicalAttack",
    "magical": "magicalAttack",
    "additional": "additionalDamage",
    "breath": "breathDamage",
}


def load_dataset(path: Path) -> List[Dict[str, Any]]:
    return json.loads(path.read_text(encoding="utf-8"))


def percent_to_multiplier(percent: float) -> float:
    return 1.0 + percent / 100.0


def format_sources(details: List[str]) -> Optional[str]:
    return None


def quantize(value: float) -> float:
    if math.isclose(value, round(value)):
        return float(round(value))
    return value


def slug_from_value(value: float, suffix: str) -> str:
    value = quantize(value)
    if value.is_integer():
        core = str(int(value)).replace('-', 'minus_').replace('+', '')
    else:
        core = (
            str(value)
            .replace('-', 'minus_')
            .replace('.', '_')
            .replace('+', '')
        )
    core = core.strip('_')
    return f"{core}_{suffix}" if suffix else core


def normalize_percent_slug(value: float) -> str:
    prefix = "plus" if value >= 0 else "minus"
    abs_value = abs(quantize(value))
    tail = str(int(abs_value)) if abs_value.is_integer() else str(abs_value).replace('.', '_')
    return f"{prefix}_{tail}_percent"


def normalize_multiplier_slug(value: float) -> str:
    val = quantize(value)
    tail = str(int(val)) if val.is_integer() else str(val).replace('.', '_')
    return f"{tail}x"


def format_multiplier_label(value: float) -> str:
    number = quantize(value)
    text = format(number, "g")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return text


def format_signed_integer(value: float) -> int:
    number = quantize(value)
    return int(round(number))


def parse_numeric(raw: str) -> Optional[float]:
    text = raw.strip().replace('％', '%')
    frac_match = re.fullmatch(r"\(?([+-]?\d+)/(\d+)\)?", text)
    if frac_match:
        num, denom = frac_match.groups()
        return float(num) / float(denom)
    cleaned = re.sub(r"[^0-9+\-\.]+", "", text)
    if not cleaned:
        return None
    try:
        return float(cleaned)
    except ValueError:
        return None


def parse_percent_entry(entry: Dict[str, Any]) -> Optional[float]:
    if entry.get("value_type") == "percent":
        return entry.get("numeric_value")
    raw = entry.get("raw", "")
    match = re.search(r"([+-]?\d+(?:\.\d+)?)%", raw)
    if match:
        return float(match.group(1))
    return parse_numeric(raw)


def parse_multiplier_entry(entry: Dict[str, Any]) -> Optional[float]:
    if entry.get("value_type") in {"multiplier", "fraction"}:
        return entry.get("numeric_value")
    raw = entry.get("raw", "")
    match = re.search(r"([+-]?\d+(?:\.\d+)?)倍", raw)
    if match:
        return float(match.group(1))
    return parse_numeric(raw)


def parse_level_coefficient(raw: str) -> Optional[float]:
    match = re.search(r"Lv(?:x|×)([0-9]+(?:\.[0-9]+)?)", raw, re.IGNORECASE)
    if match:
        return float(match.group(1))
    return None


@dataclass
class SkillEffect:
    kind: str
    parameters: Optional[Dict[str, Any]] = None
    stat: Optional[str] = None
    value: Optional[float] = None
    value_percent: Optional[float] = None
    damage_type: Optional[str] = None

    def to_json(self) -> Dict[str, Any]:
        effect: Dict[str, Any] = {"type": self.kind}
        if self.stat is not None:
            effect["statType"] = self.stat
        if self.parameters is not None:
            effect["parameters"] = self.parameters
        if self.value is not None:
            effect["value"] = self.value
        if self.value_percent is not None:
            effect["valuePercent"] = self.value_percent
        if self.damage_type is not None:
            effect["damageType"] = self.damage_type
        return effect


@dataclass
class SkillDefinitionData:
    skill_id: str
    name: str
    description: str
    effects: List[SkillEffect]
    sources: Optional[str] = None
    category: str = "attack"
    skill_type: str = "passive"

    acquisition: Optional[Dict[str, Any]] = None

    def to_json(self) -> Dict[str, Any]:
        acquisition: Dict[str, Any] = {}
        if self.acquisition:
            acquisition.update(self.acquisition)
        if self.sources:
            acquisition["sources"] = self.sources
        return {
            "id": self.skill_id,
            "name": self.name,
            "description": self.description,
            "type": self.skill_type,
            "category": self.category,
            "acquisitionConditions": acquisition,
            "effects": [effect.to_json() for effect in self.effects],
        }


class AttackSkillGenerator:
    def __init__(self, dataset: List[Dict[str, Any]]):
        self.blocks = dataset
        self.skills: Dict[str, SkillDefinitionData] = {}

    def block(self, header: str, section: Optional[str] = None) -> Dict[str, Any]:
        for block in self.blocks:
            if block["header"] == header and (section is None or block["section"] == section):
                return block
        raise KeyError(f"block not found: header={header} section={section}")

    def add_skill(self, data: SkillDefinitionData) -> None:
        if data.skill_id in self.skills:
            raise ValueError(f"duplicate skill id {data.skill_id}")
        self.skills[data.skill_id] = data

    def build(self) -> Dict[str, Any]:
        self.build_attack_power_modifiers()
        self.build_attack_power_multipliers()
        self.build_additional_damage()
        self.build_critical_damage()
        self.build_critical_rate_bounds()
        self.build_critical_rate_boosts()
        self.build_magic_power_modifiers()
        self.build_magic_power_multipliers()
        self.build_spell_specific_multipliers()
        self.build_healing_spell_multipliers()
        self.build_breath_power_modifiers()
        self.build_breath_power_multipliers()
        return {key: data.to_json() for key, data in sorted(self.skills.items())}

    def build_attack_power_modifiers(self) -> None:
        block = self.block("[±X%] 攻撃威力の増減(%)")
        for entry in block["entries"]:
            percent = parse_percent_entry(entry)
            if percent is None:
                continue
            slug = normalize_percent_slug(percent)
            skill_id = f"attack_power_modifier_{slug}"
            description = f"物理攻撃ダメージが{percent:+g}%変化します。"
            params = {"additive": percent}
            sources = format_sources(entry["details"])
            effect = SkillEffect("attackPowerModifier", params)
            self.add_skill(SkillDefinitionData(skill_id, f"{entry['raw']} 攻撃威力補正", description, [effect], sources))

    def build_attack_power_multipliers(self) -> None:
        block = self.block("[X倍] 攻撃威力")
        for entry in block["entries"]:
            raw = entry["raw"]
            coefficient = parse_level_coefficient(raw)
            if coefficient is not None:
                slug = f"level_{str(coefficient).replace('.', '_')}"
                skill_id = f"attack_power_level_multiplier_{slug}"
                description = f"物理攻撃ダメージに(1+Lv×{coefficient})倍を乗算します。"
                params = {
                    "stat": StatForHeader["physical"],
                    "base": 1.0,
                    "perLevel": coefficient,
                }
                effect = SkillEffect("statLevelMultiplier", params, stat=StatForHeader["physical"])
            else:
                multiplier = parse_multiplier_entry(entry)
                if multiplier is None:
                    continue
                slug = normalize_multiplier_slug(multiplier)
                skill_id = f"attack_power_multiplier_{slug}"
                description = f"物理攻撃ダメージに{multiplier}倍の乗算補正を付与します。"
                params = {"multiplier": multiplier}
                effect = SkillEffect("attackPowerMultiplier", params)
            sources = format_sources(entry["details"])
            self.add_skill(SkillDefinitionData(skill_id, f"{raw} 攻撃威力", description, [effect], sources))

    def build_additional_damage(self) -> None:
        block = self.block("[+X] 追加ダメージ")
        for entry in block["entries"]:
            value = parse_numeric(entry["raw"])
            if value is None:
                continue
            slug = slug_from_value(value, "bonus")
            skill_id = f"additional_damage_add_{slug}"
            description = f"追加ダメージの基礎値が{value:+g}されます。"
            params = {"stat": StatForHeader["additional"], "additive": value}
            effect = SkillEffect("statAdditive", params, stat=StatForHeader["additional"])
            sources = format_sources(entry["details"])
            self.add_skill(SkillDefinitionData(skill_id, f"追加ダメージ {entry['raw']}", description, [effect], sources))

        block = self.block("[X倍] 追加ダメージの威力")
        for entry in block["entries"]:
            multiplier = parse_multiplier_entry(entry)
            if multiplier is None:
                continue
            slug = normalize_multiplier_slug(multiplier)
            skill_id = f"additional_damage_multiplier_{slug}"
            description = f"追加ダメージ計算に{multiplier}倍の補正を適用します。"
            params = {"stat": StatForHeader["additional"], "multiplier": multiplier}
            effect = SkillEffect("statMultiplier", params, stat=StatForHeader["additional"])
            sources = format_sources(entry["details"])
            self.add_skill(SkillDefinitionData(skill_id, f"追加ダメージ {entry['raw']}", description, [effect], sources))

    def build_critical_damage(self) -> None:
        block = self.block("[±X%] 必殺威力の増減(%)")
        for entry in block["entries"]:
            percent = parse_percent_entry(entry)
            if percent is None:
                continue
            slug = normalize_percent_slug(percent)
            skill_id = f"critical_damage_modifier_{slug}"
            description = f"必殺時の与ダメージが{percent:+g}%変動します。"
            params = {"percent": percent}
            effect = SkillEffect("criticalDamageModifier", params)
            sources = format_sources(entry["details"])
            self.add_skill(SkillDefinitionData(skill_id, f"必殺威力 {entry['raw']}", description, [effect], sources))

        block = self.block("[X倍] 必殺威力")
        for entry in block["entries"]:
            multiplier = parse_multiplier_entry(entry)
            if multiplier is None:
                continue
            slug = normalize_multiplier_slug(multiplier)
            skill_id = f"critical_damage_multiplier_{slug}"
            description = f"必殺時の与ダメージに{multiplier}倍の補正を乗算します。"
            params = {"multiplier": multiplier}
            effect = SkillEffect("criticalDamageMultiplier", params)
            sources = format_sources(entry["details"])
            self.add_skill(SkillDefinitionData(skill_id, f"必殺威力 {entry['raw']}", description, [effect], sources))

    def build_critical_rate_bounds(self) -> None:
        block = self.block("[最大X] 必殺率最大値")
        for entry in block["entries"]:
            value = parse_numeric(entry["raw"].replace("最大", ""))
            if value is None:
                continue
            skill_id = f"critical_rate_cap_{int(value)}"
            description = f"必殺率の上限値を{int(value)}%に設定します。"
            params = {"cap": int(value)}
            effect = SkillEffect("criticalRateMax", params)
            sources = format_sources(entry["details"])
            self.add_skill(SkillDefinitionData(skill_id, entry["raw"], description, [effect], sources))

        block = self.block("[最大+X] 必殺率最大値上昇・[最大-X] 必殺率最大値減少")
        for entry in block["entries"]:
            raw = entry["raw"].replace("最大", "")
            value = parse_numeric(raw)
            if value is None:
                continue
            base_cap = 100 + value
            skill_id = f"critical_rate_cap_offset_{normalize_percent_slug(value)}"
            description = f"必殺率上限値を{value:+g}し、実質{base_cap}%にします。"
            params = {"cap": base_cap}
            effect = SkillEffect("criticalRateMax", params)
            sources = format_sources(entry["details"])
            self.add_skill(SkillDefinitionData(skill_id, entry["raw"], description, [effect], sources))

    def build_critical_rate_boosts(self) -> None:
        block = self.block("[+X] 必殺率アップ")
        for entry in block["entries"]:
            value = parse_numeric(entry["raw"])
            if value is None:
                continue
            slug = slug_from_value(value, "crit")
            skill_id = f"critical_rate_boost_{slug}"
            description = f"必殺率が{value:+g}ポイント上昇します。"
            params = {"additive": value}
            effect = SkillEffect("criticalRateBoost", params)
            sources = format_sources(entry["details"])
            self.add_skill(SkillDefinitionData(skill_id, entry["raw"], description, [effect], sources))

    def build_magic_power_modifiers(self) -> None:
        block = self.block("[±X%] 魔法威力の増減(%)")
        for entry in block["entries"]:
            raw = entry["raw"]
            if "Lv" in raw:
                coefficient = parse_level_coefficient(raw)
                if coefficient is None:
                    continue
                skill_id = f"magical_power_percent_per_level_{str(coefficient).replace('.', '_')}"
                description = f"魔法威力にLv×{coefficient}%の乗算補正を付与します。"
                params = {
                    "stat": StatForHeader["magical"],
                    "percentPerLevel": coefficient,
                }
                effect = SkillEffect("statPercentPerLevel", params, stat=StatForHeader["magical"])
            elif "精神" in raw:
                coefficient = parse_numeric(raw)
                if coefficient is None:
                    continue
                skill_id = f"magical_power_spirit_{str(coefficient).replace('.', '_')}"
                description = f"精神値×{coefficient}%を魔法威力の乗算補正として適用します。"
                params = {
                    "stat": StatForHeader["magical"],
                    "attribute": "spirit",
                    "percentPerPoint": coefficient,
                }
                effect = SkillEffect("statPercentFromAttribute", params, stat=StatForHeader["magical"])
            elif "必殺率" in raw:
                coefficient = 0.5
                skill_id = "magical_power_from_critical_rate"
                description = "最終必殺率×0.5%を魔法威力の乗算補正として適用します。"
                params = {
                    "stat": StatForHeader["magical"],
                    "sourceStat": "criticalRate",
                    "percentPerPoint": coefficient,
                }
                effect = SkillEffect("statPercentFromStat", params, stat=StatForHeader["magical"])
            else:
                percent = parse_percent_entry(entry)
                if percent is None:
                    continue
                multiplier = percent_to_multiplier(percent)
                slug = normalize_percent_slug(percent)
                skill_id = f"magical_power_multiplier_{slug}"
                description = f"魔法威力が{percent:+g}%変化します。"
                params = {"stat": StatForHeader["magical"], "multiplier": multiplier}
                effect = SkillEffect("statMultiplier", params, stat=StatForHeader["magical"])
            sources = format_sources(entry["details"])
            self.add_skill(SkillDefinitionData(skill_id, raw, description, [effect], sources))

    def build_magic_power_multipliers(self) -> None:
        block = self.block("[X倍] 魔法威力")
        for entry in block["entries"]:
            multiplier = parse_multiplier_entry(entry)
            if multiplier is None:
                continue
            slug = normalize_multiplier_slug(multiplier)
            skill_id = f"magical_power_multiplier_{slug}"
            description = f"魔法威力に{multiplier}倍を乗算します。"
            params = {"stat": StatForHeader["magical"], "multiplier": multiplier}
            effect = SkillEffect("statMultiplier", params, stat=StatForHeader["magical"])
            sources = format_sources(entry["details"])
            self.add_skill(SkillDefinitionData(skill_id, entry["raw"], description, [effect], sources))

    def build_spell_specific_multipliers(self) -> None:
        for header, spell_id in SpellNameToId.items():
            try:
                block = self.block(header)
            except KeyError:
                continue
            for entry in block["entries"]:
                multiplier = parse_multiplier_entry(entry)
                if multiplier is None:
                    continue
                slug = normalize_multiplier_slug(multiplier)
                skill_id = f"spell_{spell_id}_{slug}"
                description = f"{header}の威力が{multiplier}倍になります。"
                params = {"spellIds": [spell_id], "multiplier": multiplier}
                effect = SkillEffect("spellPowerMultiplier", params)
                sources = format_sources(entry["details"])
                self.add_skill(SkillDefinitionData(skill_id, f"{header} {entry['raw']}", description, [effect], sources))

    def build_healing_spell_multipliers(self) -> None:
        try:
            block = self.block("回復魔法")
        except KeyError:
            return
        current_spell: Optional[str] = None
        current_name: Optional[str] = None
        for entry in block["entries"]:
            if entry["value_type"] is None:
                spell_id = SpellNameToId.get(entry["raw"])
                if spell_id:
                    current_spell = spell_id
                    current_name = entry["raw"]
                continue
            if current_spell is None:
                continue
            multiplier = parse_multiplier_entry(entry)
            if multiplier is None:
                continue
            slug = normalize_multiplier_slug(multiplier)
            skill_id = f"spell_{current_spell}_{slug}"
            description = f"{current_name}の効果量を{multiplier}倍にします。"
            params = {"spellIds": [current_spell], "multiplier": multiplier}
            effect = SkillEffect("spellPowerMultiplier", params)
            sources = format_sources(entry["details"])
            name = f"{current_name} {entry['raw']}"
            self.add_skill(SkillDefinitionData(skill_id, name, description, [effect], sources))

    def build_breath_power_modifiers(self) -> None:
        block = self.block("[±X%] ブレス威力の増減(%)")
        for entry in block["entries"]:
            percent = parse_percent_entry(entry)
            if percent is None:
                continue
            multiplier = percent_to_multiplier(percent)
            slug = normalize_percent_slug(percent)
            skill_id = f"breath_power_multiplier_{slug}"
            description = f"ブレス威力が{percent:+g}%変化します。"
            params = {"stat": StatForHeader["breath"], "multiplier": multiplier}
            effect = SkillEffect("statMultiplier", params, stat=StatForHeader["breath"])
            sources = format_sources(entry["details"])
            self.add_skill(SkillDefinitionData(skill_id, entry["raw"], description, [effect], sources))

    def build_breath_power_multipliers(self) -> None:
        block = self.block("[X倍] ブレス強化・[X/X] ブレス弱化")
        for entry in block["entries"]:
            multiplier = parse_multiplier_entry(entry)
            if multiplier is None:
                continue
            slug = normalize_multiplier_slug(multiplier)
            skill_id = f"breath_power_multiplier_{slug}"
            description = f"ブレス威力に{multiplier}倍の補正を乗算します。"
            params = {"stat": StatForHeader["breath"], "multiplier": multiplier}
            effect = SkillEffect("statMultiplier", params, stat=StatForHeader["breath"])
            sources = format_sources(entry["details"])
            self.add_skill(SkillDefinitionData(skill_id, entry["raw"], description, [effect], sources))


class StatusSkillGenerator:
    CATEGORY_MAPPING: "OrderedDict[str, str]" = OrderedDict(
        [
            ("細剣", "thin_sword"),
            ("剣", "sword"),
            ("刀", "katana"),
            ("弓", "bow"),
            ("鎧", "armor"),
            ("重鎧", "heavy_armor"),
            ("盾", "shield"),
            ("小手", "gauntlet"),
            ("ワンド", "wand"),
            ("ロッド", "rod"),
            ("魔道書", "grimoire"),
            ("法衣", "robe"),
            ("宝石", "gem"),
            ("その他", "other"),
        ]
    )

    def __init__(self, dataset: List[Dict[str, Any]]):
        self.blocks = dataset
        self.skills: "OrderedDict[str, SkillDefinitionData]" = OrderedDict()

    def block(self, header: str) -> Dict[str, Any]:
        for block in self.blocks:
            if block["header"] == header:
                return block
        raise KeyError(f"status block not found: {header}")

    def add_skill(self, data: SkillDefinitionData) -> None:
        if data.skill_id in self.skills:
            raise ValueError(f"duplicate skill id {data.skill_id}")
        self.skills[data.skill_id] = data

    def build(self) -> "OrderedDict[str, Dict[str, Any]]":
        self.build_equipment_category_multipliers()
        self.build_equipment_capacity()
        ordered = OrderedDict()
        for key, data in self.skills.items():
            ordered[key] = data.to_json()
        return ordered

    def build_equipment_category_multipliers(self) -> None:
        for header, category in self.CATEGORY_MAPPING.items():
            try:
                block = self.block(header)
            except KeyError:
                continue
            multipliers: List[float] = []
            seen: set[float] = set()
            for entry in block["entries"]:
                raw = entry.get("raw", "")
                if "倍" not in raw and entry.get("value_type") not in {"multiplier", "fraction"}:
                    continue
                multiplier = parse_multiplier_entry(entry)
                if multiplier is None:
                    continue
                value = quantize(multiplier)
                if value in seen:
                    continue
                seen.add(value)
                multipliers.append(value)
            for value in sorted(multipliers):
                label = format_multiplier_label(value)
                slug = normalize_multiplier_slug(value)
                skill_id = f"equipment_category_{category}_multiplier_{slug}"
                name = f"[{label}倍] {header}補正"
                description = (
                    f"{header}カテゴリの装備が持つ基礎ステータスに{label}倍の補正を掛けます。"
                    "装備が付与するスキル効果には影響しません。"
                )
                params = {"category": category, "multiplier": value}
                effect = SkillEffect("equipmentCategoryMultiplier", parameters=params)
                data = SkillDefinitionData(
                    skill_id,
                    name,
                    description,
                    [effect],
                    category="passive",
                )
                self.add_skill(data)

    def build_equipment_capacity(self) -> None:
        try:
            block = self.block("アイテム装備可能数")
        except KeyError:
            return

        additive_values: set[int] = set()
        multiplier_values: set[float] = set()
        has_talent = False
        has_halving = False

        for entry in block["entries"]:
            raw = entry.get("raw", "")
            if "才能" in raw:
                has_talent = True
                continue
            if "半減" in raw:
                has_halving = True
                continue
            multiplier = None
            if "倍" in raw or entry.get("value_type") in {"multiplier", "fraction"}:
                multiplier = parse_multiplier_entry(entry)
            if multiplier is not None:
                multiplier_values.add(quantize(multiplier))
                continue
            numeric = parse_numeric(raw)
            if numeric is None:
                continue
            additive_values.add(format_signed_integer(numeric))

        for value in sorted(additive_values):
            if value == 0:
                continue
            if value > 0:
                slug = f"plus_{value}"
                display = f"+{value}"
                description = f"装備できるアイテムの数が{value}増えます。"
            else:
                slug = f"minus_{abs(value)}"
                display = f"{value}"
                description = f"装備できるアイテムの数が{abs(value)}減ります。"
            skill_id = f"equipment_capacity_add_{slug}"
            name = f"[{display}] アイテム装備可能数"
            effect = SkillEffect("equipmentCapacityAdditive", value=value)
            data = SkillDefinitionData(
                skill_id,
                name,
                description,
                [effect],
                category="passive",
            )
            self.add_skill(data)

        for value in sorted(multiplier_values):
            if math.isclose(value, 1.0):
                continue
            label = format_multiplier_label(value)
            slug = normalize_multiplier_slug(value)
            skill_id = f"equipment_capacity_multiplier_{slug}"
            name = f"[{label}倍] アイテム装備可能数"
            description = "装備枠の基本値に乗算補正を適用します。"
            effect = SkillEffect("equipmentCapacityMultiplier", value=value)
            data = SkillDefinitionData(
                skill_id,
                name,
                description,
                [effect],
                category="passive",
            )
            self.add_skill(data)

        if has_halving:
            skill_id = "equipment_capacity_halving"
            if skill_id not in self.skills:
                effect = SkillEffect("equipmentCapacityHalving")
                data = SkillDefinitionData(
                    skill_id,
                    "[半減] アイテム装備可能数",
                    "装備枠の成長係数が低下します。",
                    [effect],
                    category="passive",
                )
                self.add_skill(data)

        if has_talent:
            skill_id = "equipment_capacity_talent"
            if skill_id not in self.skills:
                effect = SkillEffect("equipmentCapacityTalent")
                data = SkillDefinitionData(
                    skill_id,
                    "[才能] アイテム装備可能数",
                    "装備枠の成長係数が上昇します。",
                    [effect],
                    category="passive",
                )
                self.add_skill(data)


class RaceJobSkillGenerator:
    _BRACKET_PATTERN = re.compile(r"\[([^\]]+)\]")

    COUNTER_SPECS: List[Dict[str, Any]] = [
        {
            "category": "race",
            "group": "ドワーフ",
            "raw": "[地族Lv50]反骨精神",
            "skill_id": "race_dwarf_lv50_counter_physical",
            "name": "[Lv50] 反撃率強化(物理)",
            "description": "物理攻撃を受けた際、15%の確率で反撃します。反撃時は攻撃回数が30%に、必殺率が50%になります。",
            "trigger": "physical",
            "chance": {"base": 15.0},
            "action": {
                "mode": "physical",
                "target": "attacker",
                "attackCountMultiplier": 0.3,
                "criticalRateMultiplier": 0.5
            }
        },
        {
            "category": "job",
            "group": "剣士",
            "raw": "[剣士Lv15]打ち合い",
            "skill_id": "job_swordsman_lv15_counter_duel",
            "name": "[Lv15] 反撃率強化(力依存)",
            "description": "攻撃を受けた際、力×0.9(%)の確率で反撃します。反撃時は攻撃回数が30%、必殺率が50%になります。",
            "trigger": "physical",
            "chance": {"attribute": "strength", "scale": 0.9},
            "action": {
                "mode": "physical",
                "target": "attacker",
                "attackCountMultiplier": 0.3,
                "criticalRateMultiplier": 0.5
            }
        },
        {
            "category": "job",
            "group": "剣士",
            "raw": "[剣士マスターLv15]打ち合い",
            "skill_id": "job_swordsman_master_lv15_counter_duel",
            "name": "[Lv15] 反撃率強化(力依存・上位)",
            "description": "攻撃を受けた際、力×1.2(%)の確率で反撃します。反撃時は攻撃回数が40%、必殺率が70%になります。",
            "trigger": "physical",
            "chance": {"attribute": "strength", "scale": 1.2},
            "action": {
                "mode": "physical",
                "target": "attacker",
                "attackCountMultiplier": 0.4,
                "criticalRateMultiplier": 0.7
            }
        },
        {
            "category": "job",
            "group": "忍者",
            "raw": "[忍者Lv30]達人",
            "skill_id": "job_ninja_lv30_counter_evasion",
            "name": "[Lv30] 回避反撃",
            "description": "攻撃を回避した際、敏捷×0.8(%)の確率で反撃します。反撃時は攻撃回数が30%、必殺率が50%になります。",
            "trigger": "dodge",
            "chance": {"attribute": "agility", "scale": 0.8},
            "action": {
                "mode": "physical",
                "target": "attacker",
                "attackCountMultiplier": 0.3,
                "criticalRateMultiplier": 0.5
            }
        },
        {
            "category": "job",
            "group": "忍者",
            "raw": "[忍者マスターLv30]達人",
            "skill_id": "job_ninja_master_lv30_counter_evasion",
            "name": "[Lv30] 回避反撃(上位)",
            "description": "攻撃を回避した際、敏捷×1.0(%)の確率で反撃します。反撃時は攻撃回数が40%、必殺率が70%になります。",
            "trigger": "dodge",
            "chance": {"attribute": "agility", "scale": 1.0},
            "action": {
                "mode": "physical",
                "target": "attacker",
                "attackCountMultiplier": 0.4,
                "criticalRateMultiplier": 0.7
            }
        },
        {
            "category": "race",
            "group": "吸血鬼",
            "raw": "[魔族Lv50]魔法反撃",
            "skill_id": "race_vampire_lv50_counter_magic_arrow",
            "name": "[Lv50] 魔法反撃",
            "description": "攻撃を受けた時、15%の確率でマジックアローで反撃します。反撃時は攻撃回数と必殺率が低下しますが、回数制限はありません。",
            "trigger": "damageAny",
            "chance": {"base": 15.0},
            "action": {
                "mode": "spell",
                "spellId": "magic_arrow",
                "target": "attacker",
                "attackCountMultiplier": 0.3,
                "criticalRateMultiplier": 0.5
            }
        },
        {
            "category": "race",
            "group": "アマゾネス",
            "raw": "[女傑Lv50]勇猛果敢",
            "skill_id": "race_amazon_lv50_counter_magic",
            "name": "[Lv50] 魔法反撃(物理)",
            "description": "魔法攻撃を受けた時、15%の確率で物理反撃を行います。反撃時は攻撃回数が30%、必殺率が50%になります。",
            "trigger": "damageMagical",
            "chance": {"base": 15.0},
            "action": {
                "mode": "physical",
                "target": "attacker",
                "attackCountMultiplier": 0.3,
                "criticalRateMultiplier": 0.5
            }
        },
        {
            "category": "race",
            "group": "ドラゴニュート",
            "raw": "[竜族Lv50]ブレス反撃",
            "skill_id": "race_dragonewt_lv50_counter_breath",
            "name": "[Lv50] ブレス反撃",
            "description": "攻撃を受けた際、15%の確率でブレス反撃を行います。",
            "trigger": "damageAny",
            "chance": {"base": 15.0},
            "action": {
                "mode": "breath",
                "target": "attacker",
                "damageMultiplier": 1.0
            }
        },
    ]

    REPEAT_SPECS: List[Dict[str, Any]] = [
        {
            "category": "race",
            "group": "ダークエルフ",
            "raw": "[黒精Lv50]殺意",
            "skill_id": "race_darkelf_lv50_repeat_on_kill",
            "name": "[Lv50] 再攻撃(撃破時)",
            "description": "敵を倒した際、敏捷×1.0(%)の確率で追加攻撃を行います。追加攻撃でも敵を倒せば再度判定が続きます。",
            "condition": "onKill",
            "chance": {"attribute": "agility", "scale": 1.0},
            "modifiers": {},
            "chainOnSuccess": True,
            "disallowOrigins": ["reaction", "followUp"]
        },
        {
            "category": "race",
            "group": "鬼",
            "raw": "[鬼神Lv50]闘争心",
            "skill_id": "race_oni_lv50_repeat_on_fail",
            "name": "[Lv50] 再攻撃(未撃破)",
            "description": "攻撃で敵を倒せなかった際、力×1.0(%)の確率で追加攻撃を行います。",
            "condition": "onNoKill",
            "chance": {"attribute": "strength", "scale": 1.0},
            "modifiers": {},
            "chainOnSuccess": False,
            "disallowOrigins": ["reaction", "followUp"]
        },
        {
            "category": "job",
            "group": "忍者",
            "raw": "[忍者Lv70]必殺連撃",
            "skill_id": "job_ninja_lv70_repeat_on_critical",
            "name": "[Lv70] 再攻撃(必殺時)",
            "description": "必殺攻撃の威力が1.3倍になり、必殺発生時は敏捷×1.0(%)の確率で追加攻撃を行います。",
            "condition": "onCritical",
            "chance": {"attribute": "agility", "scale": 1.0},
            "modifiers": {},
            "chainOnSuccess": True,
            "disallowOrigins": ["reaction"]
        },
        {
            "category": "job",
            "group": "忍者",
            "raw": "[忍者マスターLv70]必殺連撃",
            "skill_id": "job_ninja_master_lv70_repeat_on_critical",
            "name": "[Lv70] 再攻撃(必殺時・上位)",
            "description": "必殺攻撃の威力が1.4倍になり、必殺発生時は敏捷×1.1(%)の確率で追加攻撃を行います。",
            "condition": "onCritical",
            "chance": {"attribute": "agility", "scale": 1.1},
            "modifiers": {},
            "chainOnSuccess": True,
            "disallowOrigins": ["reaction"]
        },
    ]

    FOLLOW_UP_SPECS: List[Dict[str, Any]] = [
        {
            "category": "race",
            "group": "ダークエルフ",
            "raw": "[黒精Lv99]群れ追う者",
            "skill_id": "race_darkelf_lv99_follow_magic",
            "name": "[Lv99] 追撃(味方魔法)",
            "description": "味方の魔法攻撃の後に追撃を行います。必殺率・攻撃回数・命中率が半減します。",
            "trigger": "allySpell",
            "chance": {"attribute": "wisdom", "scale": 1.0},
            "spellSchool": "arcane",
            "modifiers": {
                "attackCountMultiplier": 0.5,
                "criticalRateMultiplier": 0.5,
                "accuracyMultiplier": 0.5
            },
            "disallowOrigins": ["reaction", "followUp"]
        },
        {
            "category": "job",
            "group": "剣士",
            "raw": "[剣士Lv30]魔法支援",
            "skill_id": "job_swordsman_lv30_follow_magic",
            "name": "[Lv30] 魔法追撃",
            "description": "味方の魔法攻撃の後に追撃を行います。攻撃回数・必殺率は半減し、攻撃力は60%になります。",
            "trigger": "allySpell",
            "chance": {"base": 10.0, "attribute": "agility", "scale": 1.0},
            "spellSchool": "arcane",
            "modifiers": {
                "attackCountMultiplier": 0.5,
                "criticalRateMultiplier": 0.5,
                "damageMultiplier": 0.6,
                "accuracyMultiplier": 0.5
            },
            "disallowOrigins": ["reaction", "followUp"]
        },
        {
            "category": "job",
            "group": "剣士",
            "raw": "[剣士マスターLv30]魔法支援",
            "skill_id": "job_swordsman_master_lv30_follow_magic",
            "name": "[Lv30] 魔法追撃(上位)",
            "description": "味方の魔法攻撃の後に追撃を行います。攻撃回数・必殺率は半減し、攻撃力は80%になります。",
            "trigger": "allySpell",
            "chance": {"base": 20.0, "attribute": "agility", "scale": 1.2},
            "spellSchool": "arcane",
            "modifiers": {
                "attackCountMultiplier": 0.5,
                "criticalRateMultiplier": 0.5,
                "damageMultiplier": 0.8,
                "accuracyMultiplier": 0.5
            },
            "disallowOrigins": ["reaction", "followUp"]
        },
        {
            "category": "job",
            "group": "狩人",
            "raw": "[狩人Lv15]追撃",
            "skill_id": "job_hunter_lv15_follow_critical",
            "name": "[Lv15] 追撃(味方必殺)",
            "description": "味方の必殺攻撃の後に追撃を行います。攻撃回数・必殺率は半減し、攻撃力は60%になります。",
            "trigger": "allyCritical",
            "chance": {"base": 8.0, "attribute": "agility", "scale": 0.5},
            "modifiers": {
                "attackCountMultiplier": 0.5,
                "criticalRateMultiplier": 0.5,
                "damageMultiplier": 0.6,
                "accuracyMultiplier": 0.5
            },
            "disallowOrigins": ["reaction", "followUp"]
        },
        {
            "category": "job",
            "group": "狩人",
            "raw": "[狩人マスターLv15]追撃",
            "skill_id": "job_hunter_master_lv15_follow_critical",
            "name": "[Lv15] 追撃(味方必殺・上位)",
            "description": "味方の必殺攻撃の後に追撃を行います。攻撃回数・必殺率は半減し、攻撃力は80%になります。",
            "trigger": "allyCritical",
            "chance": {"base": 16.0, "attribute": "agility", "scale": 0.6},
            "modifiers": {
                "attackCountMultiplier": 0.5,
                "criticalRateMultiplier": 0.5,
                "damageMultiplier": 0.8,
                "accuracyMultiplier": 0.5
            },
            "disallowOrigins": ["reaction", "followUp"]
        },
    ]

    JOB_SKILL_SPECS: List[Dict[str, Any]] = [
        {
            "category": "job",
            "group": "戦士",
            "raw": "[戦士Lv15]鉄壁",
            "skill_id": "job.warrior.ironWall",
            "name": "鉄壁",
            "description": "自分より後列にいる仲間が受ける通常攻撃のダメージを2/3に減少します。",
            "effects": [
                {
                    "type": "allyDamageProtection",
                    "value": 2.0 / 3.0,
                    "damageType": "physical",
                    "parameters": {"scope": "behind", "priority": 0}
                }
            ]
        },
        {
            "category": "job",
            "group": "戦士",
            "raw": "[戦士マスターLv15]鉄壁",
            "skill_id": "job.warrior.ironWall.master",
            "name": "鉄壁・極",
            "description": "自分より後列にいる仲間が受ける通常攻撃のダメージを1/2に減少します。",
            "effects": [
                {
                    "type": "allyDamageProtection",
                    "value": 0.5,
                    "damageType": "physical",
                    "parameters": {"scope": "behind", "priority": 1}
                }
            ]
        },
        {
            "category": "job",
            "group": "戦士",
            "raw": "[戦士Lv30]不死身",
            "skill_id": "job.warrior.immortal",
            "name": "不死身",
            "description": "自分の防御力の数値分だけ最大HPが増大します。",
            "effects": [
                {
                    "type": "maxHPFromStats",
                    "parameters": {
                        "sources": [
                            {"stat": "physicalDefense", "scale": 1.0}
                        ]
                    }
                }
            ]
        },
        {
            "category": "job",
            "group": "戦士",
            "raw": "[戦士マスターLv30]不死身",
            "skill_id": "job.warrior.immortal.master",
            "name": "不死身・極",
            "description": "自分の防御力と回避能力の数値分だけ最大HPが増大します。",
            "effects": [
                {
                    "type": "maxHPFromStats",
                    "parameters": {
                        "sources": [
                            {"stat": "physicalDefense", "scale": 1.0},
                            {"stat": "evasionRate", "scale": 1.0}
                        ]
                    }
                }
            ]
        },
        {
            "category": "job",
            "group": "戦士",
            "raw": "[戦士Lv70]完全武装",
            "skill_id": "job.warrior.fullArmor",
            "name": "完全武装",
            "description": "装備している「盾」と「法衣」の性能が1.3倍になります。",
            "effects": [
                {
                    "type": "equipmentCategoryMultiplier",
                    "parameters": {"category": "shield", "multiplier": 1.3}
                },
                {
                    "type": "equipmentCategoryMultiplier",
                    "parameters": {"category": "robe", "multiplier": 1.3}
                }
            ]
        },
        {
            "category": "job",
            "group": "戦士",
            "raw": "[戦士マスターLv70]完全武装",
            "skill_id": "job.warrior.fullArmor.master",
            "name": "完全武装・極",
            "description": "装備している「盾」と「法衣」の性能が1.4倍になります。",
            "effects": [
                {
                    "type": "equipmentCategoryMultiplier",
                    "parameters": {"category": "shield", "multiplier": 1.4}
                },
                {
                    "type": "equipmentCategoryMultiplier",
                    "parameters": {"category": "robe", "multiplier": 1.4}
                }
            ]
        }
    ]

    def __init__(self, dataset: Dict[str, Any]):
        self.dataset = dataset
        self.skills: "OrderedDict[str, SkillDefinitionData]" = OrderedDict()
        self.race_mapping = self._build_race_mapping()
        self.job_mapping = self._build_job_mapping()

    def build(self) -> "OrderedDict[str, Dict[str, Any]]":
        self.build_experience_skills()
        self.build_job_skill_specs()
        self.build_counter_skills()
        self.build_repeat_skills()
        self.build_follow_up_skills()
        ordered = OrderedDict()
        for key, data in self.skills.items():
            ordered[key] = data.to_json()
        return ordered

    def add_skill(self, data: SkillDefinitionData) -> None:
        if data.skill_id in self.skills:
            raise ValueError(f"duplicate skill id {data.skill_id}")
        self.skills[data.skill_id] = data

    def build_experience_skills(self) -> None:
        for block in self.dataset.get("race", []):
            group_name = block.get("group", "")
            normalized_name = self._normalize_name(group_name)
            race_ids = self.race_mapping.get(normalized_name)
            slug = self._race_slug(race_ids)
            if not race_ids or not slug:
                continue
            for entry in block.get("entries", []):
                description = entry.get("description", "")
                if "経験" not in description:
                    continue
                parsed = self._parse_bracket(entry.get("raw", ""))
                if not parsed:
                    continue
                base_name, level, is_master = parsed
                if level is None:
                    continue
                multiplier = self._extract_experience_multiplier(description)
                if multiplier is None:
                    continue
                label = format_multiplier_label(multiplier)
                multiplier_value = quantize(multiplier)
                skill_id = "_".join([
                    "race",
                    slug,
                    f"lv{level}",
                    "experience",
                    normalize_multiplier_slug(multiplier_value)
                ])
                name = f"[Lv{level}] 種族経験値倍率×{label}"
                description_text = f"対象種族が獲得する経験値が{label}倍になります。"
                acquisition = {
                    "grantedBy": {
                        "type": "race",
                        "raceIds": race_ids,
                        "level": level,
                        "isMaster": is_master
                    }
                }
                effect = SkillEffect("experienceMultiplier", value=multiplier_value)
                skill = SkillDefinitionData(
                    skill_id=skill_id,
                    name=name,
                    description=description_text,
                    effects=[effect],
                    sources=entry.get("raw"),
                    category="race",
                    skill_type="passive",
                    acquisition=acquisition
                )
                self.add_skill(skill)

        for block in self.dataset.get("job", []):
            group_name = block.get("group", "")
            normalized_name = self._normalize_name(group_name)
            job_id = self.job_mapping.get(normalized_name)
            if not job_id:
                continue
            slug = job_id
            for entry in block.get("entries", []):
                description = entry.get("description", "")
                if "経験" not in description:
                    continue
                parsed = self._parse_bracket(entry.get("raw", ""))
                if not parsed:
                    continue
                base_name, level, is_master = parsed
                if level is None:
                    continue
                exp_multiplier = self._extract_experience_multiplier(description)
                if exp_multiplier is None:
                    continue
                label = format_multiplier_label(exp_multiplier)
                multiplier_value = quantize(exp_multiplier)
                skill_id = "_".join(filter(None, [
                    "job",
                    slug,
                    "master" if is_master else None,
                    f"lv{level}",
                    "experience",
                    normalize_multiplier_slug(multiplier_value)
                ]))
                name = f"[Lv{level}] 職業経験値倍率×{label}"
                description_text = f"パーティ全員の取得経験値が{label}倍になります。"
                acquisition = {
                    "grantedBy": {
                        "type": "job",
                        "jobId": job_id,
                        "level": level,
                        "isMaster": is_master
                    }
                }
                parameters = {
                    "exclusiveGroup": f"job_{job_id}_experience"
                }
                effects = [
                    SkillEffect("experienceMultiplier",
                                value=multiplier_value,
                                parameters=parameters)
                ]
                equipment_multiplier = self._extract_equipment_multiplier(description)
                if equipment_multiplier:
                    equip_label, equip_value = equipment_multiplier
                    category_code = StatusSkillGenerator.CATEGORY_MAPPING.get(equip_label)
                    if category_code:
                        effect = SkillEffect(
                            "equipmentCategoryMultiplier",
                            parameters={
                                "category": category_code,
                                "multiplier": equip_value
                            }
                        )
                        effects.append(effect)
                skill = SkillDefinitionData(
                    skill_id=skill_id,
                    name=name,
                    description=description_text,
                    effects=effects,
                    sources=entry.get("raw"),
                    category="job",
                    skill_type="passive",
                    acquisition=acquisition
                )
                self.add_skill(skill)

    @staticmethod
    def _normalize_name(name: str) -> str:
        if not name:
            return ""
        return name.split("（", 1)[0].strip()

    @classmethod
    def _parse_bracket(cls, raw: str) -> Optional[tuple[str, Optional[int], bool]]:
        if not raw:
            return None
        match = cls._BRACKET_PATTERN.search(raw)
        if not match:
            return None
        label = match.group(1)
        is_master = "マスター" in label
        cleaned = label.replace("マスター", "")
        level_match = re.search(r"Lv(\d+)", cleaned)
        level = int(level_match.group(1)) if level_match else None
        base = re.sub(r"Lv\d+", "", cleaned)
        base = base.strip()
        return base, level, is_master

    @staticmethod
    def _extract_experience_multiplier(description: str) -> Optional[float]:
        if not description:
            return None
        sentences = re.split(r"[。]", description)
        for sentence in sentences:
            if "経験" not in sentence:
                continue
            match = re.search(r"([0-9]+(?:\.[0-9]+)?)倍", sentence)
            if match:
                try:
                    return float(match.group(1))
                except ValueError:
                    continue
        return None

    @staticmethod
    def _extract_equipment_multiplier(description: str) -> Optional[tuple[str, float]]:
        if not description:
            return None
        match = re.search(r"装備している「([^」]+)」の性能が([0-9]+(?:\.[0-9]+)?)倍", description)
        if not match:
            return None
        label = match.group(1).strip()
        try:
            multiplier = float(match.group(2))
        except ValueError:
            return None
        return label, quantize(multiplier)

    @staticmethod
    def _race_slug(race_ids: Optional[List[str]]) -> Optional[str]:
        if not race_ids:
            return None
        tokens = {race_id.split("_")[0] for race_id in race_ids}
        if not tokens:
            return None
        if len(tokens) == 1:
            return next(iter(tokens))
        return "_".join(sorted(tokens))

    @staticmethod
    def _build_race_mapping() -> Dict[str, List[str]]:
        path = REPO_ROOT / "Epika" / "Resources" / "RaceDataMaster.json"
        if not path.exists():
            return {}
        data = json.loads(path.read_text(encoding="utf-8"))
        race_data = data.get("raceData", {})
        mapping: Dict[str, List[str]] = {}
        for race_id, body in race_data.items():
            name = body.get("name", "")
            normalized = RaceJobSkillGenerator._normalize_name(name)
            if not normalized:
                continue
            mapping.setdefault(normalized, []).append(race_id)
        return mapping

    @staticmethod
    def _build_job_mapping() -> Dict[str, str]:
        path = REPO_ROOT / "Epika" / "Resources" / "JobMaster.json"
        if not path.exists():
            return {}
        data = json.loads(path.read_text(encoding="utf-8"))
        jobs = data.get("jobs", [])
        mapping: Dict[str, str] = {}
        for body in jobs:
            name = body.get("name", "")
            job_id = body.get("id")
            if not name or not job_id:
                continue
            normalized = RaceJobSkillGenerator._normalize_name(name)
            mapping[normalized] = job_id
        return mapping

    def _find_entry(self, category: str, group: str, raw: str) -> Optional[Dict[str, Any]]:
        blocks = self.dataset.get(category, [])
        for block in blocks:
            if block.get("group") != group:
                continue
            for entry in block.get("entries", []):
                if entry.get("raw") == raw:
                    return entry
        return None

    def build_counter_skills(self) -> None:
        for spec in self.COUNTER_SPECS:
            category = spec["category"]
            group = spec["group"]
            entry = self._find_entry(category, group, spec["raw"])
            if entry is None:
                continue
            parsed = self._parse_bracket(entry["raw"])
            if not parsed:
                continue
            _, level, is_master = parsed
            if level is None:
                continue
            acquisition = self._make_acquisition(category, group, level, is_master)
            if acquisition is None:
                continue
            parameters = {
                "trigger": spec["trigger"],
                "chance": spec["chance"],
                "action": spec["action"]
            }
            effect = SkillEffect("counterAttack", parameters=parameters)
            skill = SkillDefinitionData(
                skill_id=spec["skill_id"],
                name=spec["name"],
                description=spec["description"],
                effects=[effect],
                sources=entry["raw"],
                category=category,
                skill_type="passive",
                acquisition=acquisition
            )
            self.add_skill(skill)

    def build_repeat_skills(self) -> None:
        for spec in self.REPEAT_SPECS:
            category = spec["category"]
            group = spec["group"]
            entry = self._find_entry(category, group, spec["raw"])
            if entry is None:
                continue
            parsed = self._parse_bracket(entry["raw"])
            if not parsed:
                continue
            _, level, is_master = parsed
            if level is None:
                continue
            acquisition = self._make_acquisition(category, group, level, is_master)
            if acquisition is None:
                continue
            parameters = {
                "condition": spec["condition"],
                "chance": spec["chance"],
                "modifiers": spec["modifiers"],
                "chainOnSuccess": spec["chainOnSuccess"],
                "disallowOrigins": spec["disallowOrigins"]
            }
            effect = SkillEffect("repeatAttack", parameters=parameters)
            effects = [effect]
            if spec["raw"] in ("[忍者Lv70]必殺連撃", "[忍者マスターLv70]必殺連撃"):
                multiplier = 1.3 if "マスター" not in spec["raw"] else 1.4
                effects.insert(0, SkillEffect("criticalDamageMultiplier", value=multiplier))
            skill = SkillDefinitionData(
                skill_id=spec["skill_id"],
                name=spec["name"],
                description=spec["description"],
                effects=effects,
                sources=entry["raw"],
                category=category,
                skill_type="passive",
                acquisition=acquisition
            )
            self.add_skill(skill)

    def build_follow_up_skills(self) -> None:
        for spec in self.FOLLOW_UP_SPECS:
            category = spec["category"]
            group = spec["group"]
            entry = self._find_entry(category, group, spec["raw"])
            if entry is None:
                continue
            parsed = self._parse_bracket(entry["raw"])
            if not parsed:
                continue
            _, level, is_master = parsed
            if level is None:
                continue
            acquisition = self._make_acquisition(category, group, level, is_master)
            if acquisition is None:
                continue
            parameters = {
                "trigger": spec["trigger"],
                "chance": spec["chance"],
                "modifiers": spec.get("modifiers", {}),
                "disallowOrigins": spec.get("disallowOrigins", [])
            }
            if "spellSchool" in spec:
                parameters["spellSchool"] = spec["spellSchool"]
            if "spellIds" in spec:
                parameters["spellIds"] = spec["spellIds"]
            effect = SkillEffect("followUpAttack", parameters=parameters)
            skill = SkillDefinitionData(
                skill_id=spec["skill_id"],
                name=spec["name"],
                description=spec["description"],
                effects=[effect],
                sources=entry["raw"],
                category=category,
                skill_type="passive",
                acquisition=acquisition
            )
            self.add_skill(skill)

    def build_job_skill_specs(self) -> None:
        for spec in self.JOB_SKILL_SPECS:
            category = spec["category"]
            group = spec["group"]
            raw = spec["raw"]
            entry = self._find_entry(category, group, raw)
            parsed = self._parse_bracket(raw)
            if not parsed:
                continue
            _, level, is_master = parsed
            if level is None:
                continue
            acquisition = self._make_acquisition(category, group, level, is_master)
            if acquisition is None:
                continue
            effects = [self._make_skill_effect(effect_spec) for effect_spec in spec["effects"]]
            description = spec.get("description") or (entry.get("description") if entry else "")
            sources = entry.get("raw") if entry else raw
            skill = SkillDefinitionData(
                skill_id=spec["skill_id"],
                name=spec["name"],
                description=description,
                effects=effects,
                sources=sources,
                category=category,
                skill_type="passive",
                acquisition=acquisition
            )
            self.add_skill(skill)

    @staticmethod
    def _make_skill_effect(spec: Dict[str, Any]) -> SkillEffect:
        kind = spec["type"]
        parameters = spec.get("parameters")
        value = spec.get("value")
        value_percent = spec.get("valuePercent")
        stat = spec.get("statType")
        damage_type = spec.get("damageType")
        return SkillEffect(kind,
                           parameters=parameters,
                           stat=stat,
                           value=value,
                           value_percent=value_percent,
                           damage_type=damage_type)

    def _make_acquisition(self,
                          category: str,
                          group: str,
                          level: int,
                          is_master: bool) -> Optional[Dict[str, Any]]:
        if category == "race":
            race_ids = self.race_mapping.get(self._normalize_name(group))
            if not race_ids:
                return None
            return {
                "grantedBy": {
                    "type": "race",
                    "raceIds": race_ids,
                    "level": level,
                    "isMaster": is_master
                }
            }
        if category == "job":
            job_id = self.job_mapping.get(self._normalize_name(group))
            if not job_id:
                return None
            return {
                "grantedBy": {
                    "type": "job",
                    "jobId": job_id,
                    "level": level,
                    "isMaster": is_master
                }
            }
        return None


def main() -> None:
    dataset_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DATASET
    output_path = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_OUTPUT
    dataset = load_dataset(dataset_path)
    generator = AttackSkillGenerator(dataset)
    attack_skills = generator.build()

    status_dataset = load_dataset(STATUS_DATASET)
    status_generator = StatusSkillGenerator(status_dataset)
    status_skills = status_generator.build()

    race_job_dataset = load_dataset(RACE_JOB_DATASET)
    race_job_generator = RaceJobSkillGenerator(race_job_dataset)
    race_job_skills = race_job_generator.build()

    combined = OrderedDict()
    for key, value in attack_skills.items():
        combined[key] = value
    for key, value in status_skills.items():
        if key in combined:
            raise ValueError(f"duplicate skill id detected: {key}")
        combined[key] = value
    for key, value in race_job_skills.items():
        if key in combined:
            raise ValueError(f"duplicate skill id detected: {key}")
        combined[key] = value

    output_path.write_text(
        json.dumps(combined, ensure_ascii=False, indent=2, sort_keys=False),
        encoding="utf-8",
    )
    print(f"generated {len(combined)} skills -> {output_path}")


if __name__ == "__main__":
    main()
