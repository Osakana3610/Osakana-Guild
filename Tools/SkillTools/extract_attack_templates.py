#!/usr/bin/env python3

"""
Extracts effect template blocks from attack_skills.txt into structured JSON.

The script scans the plain text dump exported from the wiki page and groups
lines under template headers such as:

    [±X%] 攻撃威力の増減(%)

The resulting JSON is an array where each entry contains:
    - section: the coarse category (e.g., "物理攻撃関連")
    - header: the template header text
    - description: free-form description lines directly below the header
    - entries: list of raw lines following the description (typically source lists)

Only basic grouping is performed here; precise parameter parsing will be done
in downstream tooling.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import List, Dict, Any


REPO_ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = REPO_ROOT / "Documents" / "WikiSkillData"
TEXT_PATH = DATA_DIR / "attack_skills.txt"
OUTPUT_PATH = DATA_DIR / "attack_skills_templates.json"

HEADER_PATTERN = re.compile(r"^\[[^\]]+\]")
SECTION_PATTERN = re.compile(r"^[^\\[]+関連$")


def load_lines() -> List[str]:
    if not TEXT_PATH.exists():
        raise FileNotFoundError(f"text source not found: {TEXT_PATH}")
    return TEXT_PATH.read_text(encoding="utf-8").splitlines()


def sanitise(line: str) -> str:
    return line.rstrip()


def extract_blocks(lines: List[str]) -> List[Dict[str, Any]]:
    blocks: List[Dict[str, Any]] = []
    current_section: str | None = None
    current_block: Dict[str, Any] | None = None
    pending_desc: List[str] = []

    def flush_block() -> None:
        nonlocal current_block, pending_desc
        if current_block is None:
            return
        description = []
        entries = []
        for item in pending_desc:
            if not entries and item:
                description.append(item)
            else:
                entries.append(item)
        current_block["description"] = [line for line in description if line]
        current_block["entries"] = [line for line in entries if line]
        blocks.append(current_block)
        current_block = None
        pending_desc = []

    for raw_line in lines:
        line = sanitise(raw_line)
        stripped = line.strip()

        if not stripped:
            # blank line: treat as separator between entries
            if pending_desc:
                pending_desc.append("")
            continue

        section_match = SECTION_PATTERN.match(stripped)
        header_match = HEADER_PATTERN.match(stripped)

        if header_match:
            flush_block()
            current_block = {
                "section": current_section,
                "header": stripped,
            }
            pending_desc = []
            continue

        if section_match and current_block is None:
            current_section = stripped
            continue

        if current_block is None:
            # ignore text outside recognised sections
            continue

        pending_desc.append(stripped)

    flush_block()
    return blocks


def main() -> None:
    lines = load_lines()
    blocks = extract_blocks(lines)
    OUTPUT_PATH.write_text(
        json.dumps(blocks, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"extracted {len(blocks)} template blocks -> {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
