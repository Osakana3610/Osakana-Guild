#!/usr/bin/env python3
"""Verify SkillMaster covers confirmed numeric Wiki skills.

対象:
- attack_skills_dataset.json の確定数値セクション（攻撃威力％・魔法威力％・魔法威力倍率）
- SkillMaster.json の既存ファミリ（damageDealtPercent.physical / spellPowerPercent.general / spellPowerMultiplier.general）

出力:
- セクションごとに不足している値と余分な値を列挙。
"""

from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ATTACK_DATASET = REPO_ROOT / "Documents" / "WikiSkillData" / "attack_skills_dataset.json"
SKILL_MASTER = REPO_ROOT / "Epika" / "Resources" / "SkillMaster.json"


def load_attack_values() -> dict[str, set[float]]:
    data = json.loads(ATTACK_DATASET.read_text(encoding="utf-8"))
    values: dict[str, set[float]] = defaultdict(set)
    for block in data:
        header = block.get("header", "")
        for entry in block.get("entries", []):
            value = entry.get("numeric_value")
            if value is None:
                continue
            if header == "[±X%] 攻撃威力の増減(%)":
                values["attack_percent"].add(float(value))
            if header == "[±X%] 魔法威力の増減(%)":
                values["spell_percent"].add(float(value))
            if header == "[X倍] 魔法威力":
                values["spell_multiplier"].add(float(value))
    return values


def load_skillmaster_values() -> dict[str, set[float]]:
    data = json.loads(SKILL_MASTER.read_text(encoding="utf-8"))
    values: dict[str, set[float]] = defaultdict(set)
    for section in data.values():
        for family in section.get("families", []):
            effect_type = family.get("effectType")
            params = family.get("parameters", {}) or {}
            for variant in family.get("variants", []):
                val = variant.get("value", {})
                if effect_type == "damageDealtPercent" and params.get("damageType") == "physical":
                    if "valuePercent" in val:
                        values["attack_percent"].add(float(val["valuePercent"]))
                if effect_type == "spellPowerPercent":
                    if "valuePercent" in val:
                        values["spell_percent"].add(float(val["valuePercent"]))
                if effect_type == "spellPowerMultiplier":
                    if "multiplier" in val:
                        values["spell_multiplier"].add(float(val["multiplier"]))
    return values


def main() -> None:
    wiki = load_attack_values()
    master = load_skillmaster_values()

    for key, wiki_vals in wiki.items():
        master_vals = master.get(key, set())
        missing = sorted(v for v in wiki_vals if v not in master_vals)
        extra = sorted(v for v in master_vals if v not in wiki_vals)
        print(f"[{key}] wiki={len(wiki_vals)} master={len(master_vals)}")
        if missing:
            print("  missing:", missing)
        if extra:
            print("  extra:", extra)
        if not missing and not extra:
            print("  OK (exact match)")


if __name__ == "__main__":
    main()
