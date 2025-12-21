#!/usr/bin/env python3

"""
Extract the spell list from the wiki HTML dump into structured JSON.

The script targets two main tables in spell_list.html:
  1. 攻撃魔法（魔法使い）: rows use rowspan=2 for level/name.
  2. 回復・支援魔法（僧侶）: simple rows.

Output format:
{
  "attack": [
     {"level": 1, "name": "...", "description": "...", "note": "..."}
  ],
  "support": [
     {"level": 1, "name": "...", "description": "..."}
  ]
}
"""

from __future__ import annotations

import html
import json
import re
from pathlib import Path
from typing import List, Dict, Any


DATA_DIR = Path(__file__).resolve().parents[2] / "Documents" / "WikiSkillData"
HTML_PATH = DATA_DIR / "spell_list.html"
OUTPUT_PATH = DATA_DIR / "spell_list.json"

ATTACK_PATTERN = re.compile(
    r"<tr><td rowspan=\"2\">(Lv\d+)</td><td rowspan=\"2\">([^<]+)</td><td>(.*?)</td></tr>"
    r"<tr><td>(.*?)</td></tr>",
    re.S,
)

SUPPORT_PATTERN = re.compile(
    r"<tr><td>(Lv\d+)</td><td>([^<]+)</td><td>(.*?)</td></tr>",
    re.S,
)

BR_RE = re.compile(r"<br[^>]*>", re.I)
TAG_RE = re.compile(r"<[^>]+>")
SPACE_RE = re.compile(r"[ \\t]+")


def clean_html(raw: str) -> str:
    replaced = BR_RE.sub("\n", raw)
    no_tags = TAG_RE.sub("", replaced)
    normalised = SPACE_RE.sub(" ", no_tags)
    return html.unescape(normalised.strip(" \n　"))


def parse_level(text: str) -> int:
    return int(text.replace("Lv", "").strip())


def load_html() -> str:
    if not HTML_PATH.exists():
        raise FileNotFoundError(f"spell list HTML not found: {HTML_PATH}")
    return HTML_PATH.read_text(encoding="utf-8")


def extract_attack_spells(html_text: str) -> List[Dict[str, Any]]:
    spells: List[Dict[str, Any]] = []
    for level_text, name, desc1, desc2 in ATTACK_PATTERN.findall(html_text):
        spells.append(
            {
                "level": parse_level(level_text),
                "name": clean_html(name),
                "description": clean_html(desc1),
                "note": clean_html(desc2),
            }
        )
    return spells


def extract_support_spells(html_text: str) -> List[Dict[str, Any]]:
    spells: List[Dict[str, Any]] = []
    for level_text, name, desc in SUPPORT_PATTERN.findall(html_text):
        spells.append(
            {
                "level": parse_level(level_text),
                "name": clean_html(name),
                "description": clean_html(desc),
            }
        )
    return spells


def main() -> None:
    html_text = load_html()
    attack = extract_attack_spells(html_text)
    support = extract_support_spells(html_text)
    payload = {
        "attack": attack,
        "support": support,
    }
    OUTPUT_PATH.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"attack spells: {len(attack)}, support spells: {len(support)} -> {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
