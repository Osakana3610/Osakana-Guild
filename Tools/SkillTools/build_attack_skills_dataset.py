#!/usr/bin/env python3
"""
Parse attack_skills.html and emit a structured JSON dataset used by the
SkillMaster generator.

The output captures the heading hierarchy, each table row's value, and basic
classification (percent/multiplier/etc.) so later stages can decide how to map
those values onto concrete skill definitions.
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import List, Optional

from bs4 import BeautifulSoup

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_HTML_PATH = REPO_ROOT / "Documents" / "WikiSkillData" / "attack_skills.html"
DEFAULT_OUTPUT_PATH = REPO_ROOT / "Documents" / "WikiSkillData" / "attack_skills_dataset.json"

SECTION_TAGS = {"h2", "h3"}
SUBSECTION_TAGS = {"h4"}

VALUE_TYPES = {
    "percent": re.compile(r"^[+-]?\d+(?:\.\d+)?%$"),
    "multiplier": re.compile(r"^\(?[+-]?\d+(?:\.\d+)?倍\)?$"),
    "level_multiplier": re.compile(r"^\(1\+Lv[xx]?\d+(?:\.\d+)?倍\)$", re.IGNORECASE),
    "fraction": re.compile(r"^[+-]?\d+(?:\.\d+)?/[+-]?\d+(?:\.\d+)?$"),
    "integer": re.compile(r"^[+-]?\d+$"),
    "max": re.compile(r"^最大[+-]?\d+$"),
    "level": re.compile(r"^Lv\d+$", re.IGNORECASE),
}


@dataclass
class Entry:
    raw: str
    details: List[str] = field(default_factory=list)
    value_type: Optional[str] = None
    numeric_value: Optional[float] = None


@dataclass
class Block:
    section: Optional[str]
    header: str
    entries: List[Entry]


def classify(raw: str) -> tuple[Optional[str], Optional[float]]:
    text = raw.strip()
    for label, pattern in VALUE_TYPES.items():
        if pattern.match(text):
            if label == "percent":
                return label, float(text.rstrip("%"))
            if label in {"multiplier", "level_multiplier"}:
                cleaned = text.replace("倍", "").replace("(", "").replace(")", "")
                if cleaned.upper().startswith("1+LV"):
                    return label, None
                try:
                    return label, float(cleaned)
                except ValueError:
                    return label, None
            if label == "fraction":
                num, denom = text.split("/", 1)
                try:
                    return label, float(num) / float(denom)
                except ValueError:
                    return label, None
            if label == "integer":
                return label, float(text)
            if label == "max":
                try:
                    return label, float(text.removeprefix("最大"))
                except ValueError:
                    return label, None
            if label == "level":
                try:
                    return label, float(text[2:])
                except ValueError:
                    return label, None
    return None, None


def normalise_lines(text: str) -> List[str]:
    return [line.strip() for line in text.replace("\r", "").splitlines() if line.strip()]


def parse_table(table) -> List[Entry]:
    entries: List[Entry] = []
    for tr in table.find_all("tr"):
        th = tr.find("th")
        if th is None:
            continue
        raw = th.get_text(" ", strip=True)
        if not raw or raw in {"倍率", "詳細"}:
            continue
        td = tr.find("td")
        details = normalise_lines(td.get_text("\n", strip=True)) if td else []
        value_type, numeric = classify(raw)
        entries.append(Entry(raw=raw, details=details, value_type=value_type, numeric_value=numeric))
    return entries


def extract_blocks(html_path: Path) -> List[Block]:
    soup = BeautifulSoup(html_path.read_text(encoding="utf-8"), "html.parser")
    blocks: List[Block] = []
    current_section: Optional[str] = None
    pending_header: Optional[str] = None

    body = soup.find("body")
    for node in body.find_all(["h2", "h3", "h4", "table"], recursive=True):
        tag = node.name.lower()
        text = node.get_text(strip=True)
        if tag in SECTION_TAGS:
            current_section = text or current_section
            pending_header = text
            continue
        if tag in SUBSECTION_TAGS:
            pending_header = text
            continue
        if tag == "table" and pending_header:
            entries = parse_table(node)
            if entries:
                blocks.append(Block(section=current_section, header=pending_header, entries=entries))
            continue
    return blocks


def main() -> None:
    html_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_HTML_PATH
    output_path = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_OUTPUT_PATH
    if not html_path.exists():
        raise SystemExit(f"missing source HTML: {html_path}")
    blocks = extract_blocks(html_path)
    payload = [
        {
            "section": block.section,
            "header": block.header,
            "entries": [asdict(entry) for entry in block.entries],
        }
        for block in blocks
    ]
    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"wrote {len(payload)} blocks -> {output_path}")


if __name__ == "__main__":
    main()
