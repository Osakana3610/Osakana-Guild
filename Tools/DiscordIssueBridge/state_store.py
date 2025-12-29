from __future__ import annotations

import json
import shutil
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Optional


@dataclass
class StateStore:
    path: Path
    backup_enabled: bool = True
    processed: Dict[str, str] = field(default_factory=dict)
    last_synced_at: Optional[str] = None

    def load(self) -> None:
        if not self.path.exists():
            self.processed = {}
            self.last_synced_at = None
            return
        with self.path.open("r", encoding="utf-8") as fp:
            data = json.load(fp)
        processed = data.get("processed_thread_ids", {})
        if isinstance(processed, list):
            processed = {tid: data.get("last_synced_at") or "" for tid in processed}
        self.processed = {str(k): str(v) for k, v in processed.items()}
        self.last_synced_at = data.get("last_synced_at")

    def has_processed(self, thread_id: str) -> bool:
        return thread_id in self.processed

    def mark_processed(self, thread_id: str, processed_at: datetime) -> None:
        self.processed[thread_id] = processed_at.astimezone(timezone.utc).isoformat()
        self.last_synced_at = datetime.now(timezone.utc).isoformat()

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if self.backup_enabled and self.path.exists():
            backup_path = self.path.with_suffix(self.path.suffix + ".bak")
            shutil.copy2(self.path, backup_path)
        payload = {
            "processed_thread_ids": self.processed,
            "last_synced_at": self.last_synced_at,
        }
        with self.path.open("w", encoding="utf-8") as fp:
            json.dump(payload, fp, ensure_ascii=False, indent=2)
