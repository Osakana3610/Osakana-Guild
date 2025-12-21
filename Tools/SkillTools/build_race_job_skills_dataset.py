#!/usr/bin/env python3
"""Parse race_job_skills.html and emit structured dataset for skill generation."""

from __future__ import annotations

import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import List, Optional

from bs4 import BeautifulSoup

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_HTML_PATH = REPO_ROOT / "Documents" / "WikiSkillData" / "race_job_skills.html"
DEFAULT_OUTPUT_PATH = REPO_ROOT / "Documents" / "WikiSkillData" / "race_job_skills_dataset.json"


def normalise(text: str) -> str:
    return re.sub(r"\s+", " ", text.replace("\u3000", " ")).strip()


@dataclass
class Entry:
    raw: str
    description: str


@dataclass
class Group:
    group: str
    entries: List[Entry]


def parse_table(table) -> List[Group]:
    groups: List[Group] = []
    current_group: Optional[Group] = None

    rows = table.find_all("tr")
    for row in rows[1:]:  # skip header
        cells = row.find_all(["th", "td"])
        texts = [normalise(cell.get_text(" ", strip=True)) for cell in cells]
        texts = [text for text in texts if text]
        if not texts:
            continue

        if len(texts) == 3:
            group_name, raw, description = texts
            current_group = Group(group=group_name, entries=[Entry(raw=raw, description=description)])
            groups.append(current_group)
        elif len(texts) == 2 and current_group is not None:
            raw, description = texts
            current_group.entries.append(Entry(raw=raw, description=description))
        else:
            # Fallback: treat first value as new group name
            group_name = texts[0]
            current_group = Group(group=group_name, entries=[])
            groups.append(current_group)
            remaining = texts[1:]
            for index in range(0, len(remaining), 2):
                raw = remaining[index]
                description = remaining[index + 1] if index + 1 < len(remaining) else ""
                if raw and description:
                    current_group.entries.append(Entry(raw=raw, description=description))

    return groups


def main() -> None:
    html_path = DEFAULT_HTML_PATH
    output_path = DEFAULT_OUTPUT_PATH
    if not html_path.exists():
        raise SystemExit(f"missing source HTML: {html_path}")

    soup = BeautifulSoup(html_path.read_text(encoding="utf-8"), "html.parser")
    tables = soup.find_all("table")
    if len(tables) < 3:
        raise SystemExit("expected at least 3 tables in race_job_skills.html")

    race_groups = parse_table(tables[0])
    job_groups = parse_table(tables[2])

    payload = {
        "race": [
            {
                "group": group.group,
                "entries": [asdict(entry) for entry in group.entries],
            }
            for group in race_groups
        ],
        "job": [
            {
                "group": group.group,
                "entries": [asdict(entry) for entry in group.entries],
            }
            for group in job_groups
        ],
    }

    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"wrote dataset -> {output_path}")


if __name__ == "__main__":
    main()
