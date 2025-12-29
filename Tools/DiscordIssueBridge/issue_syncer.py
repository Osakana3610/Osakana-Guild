from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import List, Optional

try:  # サブモジュール単体実行時のためのフォールバック
    from .bridge_config import BridgeConfig
    from .discord_client import DiscordClient, DiscordThread
    from .github_client import GitHubClient
    from .state_store import StateStore
    from .template_engine import render
except ImportError:  # pragma: no cover - パッケージ外から実行される場合
    from bridge_config import BridgeConfig  # type: ignore
    from discord_client import DiscordClient, DiscordThread  # type: ignore
    from github_client import GitHubClient  # type: ignore
    from state_store import StateStore  # type: ignore
    from template_engine import render  # type: ignore

logger = logging.getLogger(__name__)


class IssueSyncer:
    def __init__(
        self,
        config: BridgeConfig,
        discord_client: DiscordClient,
        github_client: GitHubClient,
        state_store: StateStore,
    ) -> None:
        self._config = config
        self._discord = discord_client
        self._github = github_client
        self._state = state_store

    def run(self, since: Optional[datetime], max_threads: Optional[int] = None) -> int:
        limit = max_threads or self._config.max_threads_per_run
        threads = self._discord.fetch_threads(since=since, limit=limit)
        logger.info("取得したスレッド: %d 件", len(threads))

        processed_count = 0
        for thread in threads:
            if self._state.has_processed(thread.id):
                logger.debug("既処理スレッド %s をスキップ", thread.id)
                continue
            issue_title = f"{self._config.issue_title_prefix}{thread.name}".strip()
            labels = self._build_labels(thread)
            body = self._build_body(thread)
            self._github.create_issue(issue_title, body, labels=labels, assignees=self._config.assignees)
            self._state.mark_processed(thread.id, thread.created_at)
            processed_count += 1
            logger.info("Issue 作成完了: %s", issue_title)

        if processed_count or self._state.last_synced_at is None:
            self._state.save()
        else:
            self._state.last_synced_at = datetime.now(timezone.utc).isoformat()
            self._state.save()
        logger.info("今回新規に作成した Issue: %d 件", processed_count)
        return processed_count

    def _build_labels(self, thread: DiscordThread) -> List[str]:
        labels: List[str] = []
        seen = set()
        for label in self._config.default_labels:
            if label not in seen:
                labels.append(label)
                seen.add(label)
        for tag_id in thread.applied_tag_ids:
            mapped = self._config.tag_label_map.get(tag_id)
            if mapped:
                for label in mapped:
                    if label not in seen:
                        labels.append(label)
                        seen.add(label)
            else:
                fallback_name = self._sanitize_label(self._discord.resolve_tag_name(tag_id))
                label_value = f"{self._config.fallback_label_prefix}{fallback_name}".strip()
                if label_value and label_value not in seen:
                    labels.append(label_value)
                    seen.add(label_value)
        return labels

    def _build_body(self, thread: DiscordThread) -> str:
        attachments_block = self._format_attachments(thread)
        context = {
            "title": thread.name,
            "author": thread.first_message.author_name,
            "message_url": thread.jump_url,
            "content": thread.first_message.content or "(本文なし)",
            "attachments": attachments_block,
            "created_at": thread.created_at.astimezone(timezone.utc).isoformat(),
            "thread_id": thread.id,
        }
        return render(self._config.issue_body_template, context)

    @staticmethod
    def _sanitize_label(value: str) -> str:
        normalized = value.strip().lower().replace(" ", "-")
        return normalized or "untitled"

    @staticmethod
    def _format_attachments(thread: DiscordThread) -> str:
        attachments = thread.first_message.attachments
        if not attachments:
            return "- なし"
        lines = []
        for attachment in attachments:
            filename = attachment.filename or "attachment"
            lines.append(f"- [{filename}]({attachment.url})")
        return "\n".join(lines)
