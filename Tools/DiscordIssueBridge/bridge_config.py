from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Any


@dataclass
class BridgeConfig:
    discord_channel_id: str
    github_repo: str
    issue_title_prefix: str
    issue_body_template: str
    default_labels: List[str]
    tag_label_map: Dict[str, List[str]]
    fallback_label_prefix: str
    assignees: List[str]
    state_file: Path
    state_backup_enabled: bool
    max_threads_per_run: int

    @classmethod
    def load(cls, path: Path) -> "BridgeConfig":
        data = cls._read_json(path)
        required = [
            "discord_channel_id",
            "github_repo",
            "issue_title_prefix",
            "issue_body_template",
        ]
        missing = [key for key in required if key not in data]
        if missing:
            raise ValueError(f"設定ファイルに不足項目があります: {', '.join(missing)}")

        state_file = Path(data.get("state_file", "tmp/discord_issue_bridge_state.json"))
        if not state_file.is_absolute():
            state_file = (path.parent / state_file).resolve()

        return cls(
            discord_channel_id=str(data["discord_channel_id"]),
            github_repo=str(data["github_repo"]),
            issue_title_prefix=str(data.get("issue_title_prefix", "")),
            issue_body_template=str(data.get("issue_body_template", "{{content}}")),
            default_labels=list(data.get("default_labels", [])),
            tag_label_map={str(k): list(v) for k, v in data.get("tag_label_map", {}).items()},
            fallback_label_prefix=str(data.get("fallback_label_prefix", "discord/tag/")),
            assignees=list(data.get("assignees", [])),
            state_file=state_file,
            state_backup_enabled=bool(data.get("state_backup_enabled", True)),
            max_threads_per_run=int(data.get("max_threads_per_run", 20)),
        )

    @staticmethod
    def _read_json(path: Path) -> Dict[str, Any]:
        with path.open("r", encoding="utf-8") as fp:
            return json.load(fp)
