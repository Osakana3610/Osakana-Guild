from __future__ import annotations

import json
import logging
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Any
from urllib import error, request, parse

logger = logging.getLogger(__name__)
API_BASE = "https://discord.com/api/v10"


@dataclass
class DiscordAttachment:
    id: str
    url: str
    filename: str


@dataclass
class DiscordMessage:
    id: str
    author_id: str
    author_name: str
    content: str
    timestamp: datetime
    attachments: List[DiscordAttachment]


@dataclass
class DiscordThread:
    id: str
    guild_id: Optional[str]
    channel_id: str
    name: str
    owner_id: str
    created_at: datetime
    applied_tag_ids: List[str]
    first_message: DiscordMessage

    @property
    def jump_url(self) -> str:
        if not self.guild_id:
            return f"https://discord.com/channels/@me/{self.id}/{self.first_message.id}"
        return f"https://discord.com/channels/{self.guild_id}/{self.id}/{self.first_message.id}"


class DiscordClient:
    def __init__(
        self,
        token: str,
        channel_id: str,
        offline_sample: Optional[Path] = None,
        timeout: int = 15,
        max_retries: int = 5,
    ) -> None:
        if not token and offline_sample is None:
            raise ValueError("DISCORD_BOT_TOKEN が設定されていません")
        self._token = token
        self._channel_id = channel_id
        self._timeout = timeout
        self._max_retries = max_retries
        self._available_tags: Dict[str, str] = {}
        self._offline_sample = offline_sample
        self._offline_payload: Optional[Dict[str, Any]] = None
        if offline_sample:
            with offline_sample.open("r", encoding="utf-8") as fp:
                self._offline_payload = json.load(fp)
            self._available_tags = {
                str(tag["id"]): tag.get("name", "")
                for tag in self._offline_payload.get("channel", {}).get("available_tags", [])
            }

    def fetch_threads(
        self,
        since: Optional[datetime] = None,
        limit: Optional[int] = None,
    ) -> List[DiscordThread]:
        if self._offline_payload is not None:
            return self._threads_from_offline(since, limit)

        self._fetch_channel_metadata()
        collected: List[Dict[str, Any]] = []
        for endpoint in ("threads/active", "threads/archived/public"):
            payload = self._get(f"/channels/{self._channel_id}/{endpoint}")
            collected.extend(payload.get("threads", []))
            if limit and len(collected) >= limit:
                break
            if endpoint.endswith("archived/public") and payload.get("has_more"):
                before = payload.get("threads", [])[-1]["id"] if payload.get("threads") else None
                while payload.get("has_more") and before:
                    query = parse.urlencode({"before": before})
                    payload = self._get(f"/channels/{self._channel_id}/{endpoint}?{query}")
                    collected.extend(payload.get("threads", []))
                    if limit and len(collected) >= limit:
                        break
                    before = payload.get("threads", [])[-1]["id"] if payload.get("threads") else None
                if limit and len(collected) >= limit:
                    break

        threads: List[DiscordThread] = []
        for thread_payload in collected:
            created_at = self._extract_created_at(thread_payload)
            if since and created_at <= since:
                continue
            messages = self.fetch_thread_messages(thread_payload["id"])
            if not messages:
                logger.info("スレッド %s にメッセージが無いためスキップ", thread_payload.get("id"))
                continue
            first_message = min(messages, key=lambda msg: msg.timestamp)
            if created_at < first_message.timestamp:
                created_at = first_message.timestamp
            thread = DiscordThread(
                id=str(thread_payload["id"]),
                guild_id=str(thread_payload.get("guild_id")) if thread_payload.get("guild_id") else None,
                channel_id=self._channel_id,
                name=thread_payload.get("name", "(no title)"),
                owner_id=str(thread_payload.get("owner_id", "")),
                created_at=created_at,
                applied_tag_ids=[str(tag_id) for tag_id in thread_payload.get("applied_tags", [])],
                first_message=first_message,
            )
            threads.append(thread)
            if limit and len(threads) >= limit:
                break
        threads.sort(key=lambda t: t.created_at)
        return threads

    def fetch_thread_messages(self, thread_id: str) -> List[DiscordMessage]:
        if self._offline_payload is not None:
            for thread in self._offline_payload.get("threads", []):
                if str(thread.get("id")) == str(thread_id):
                    return [self._message_from_payload(msg) for msg in thread.get("messages", [])]
            return []

        messages_payload = self._get(f"/channels/{thread_id}/messages?limit=50")
        return [self._message_from_payload(item) for item in messages_payload]

    def resolve_tag_name(self, tag_id: str) -> str:
        return self._available_tags.get(tag_id, tag_id)

    def _fetch_channel_metadata(self) -> None:
        if self._available_tags:
            return
        payload = self._get(f"/channels/{self._channel_id}")
        tags = payload.get("available_tags", [])
        self._available_tags = {str(tag["id"]): tag.get("name", "") for tag in tags}

    def _threads_from_offline(
        self,
        since: Optional[datetime],
        limit: Optional[int],
    ) -> List[DiscordThread]:
        threads: List[DiscordThread] = []
        for thread_payload in self._offline_payload.get("threads", []):
            created_at = self._parse_timestamp(thread_payload.get("created_at"))
            if since and created_at <= since:
                continue
            messages = [self._message_from_payload(msg) for msg in thread_payload.get("messages", [])]
            if not messages:
                continue
            first_message = min(messages, key=lambda msg: msg.timestamp)
            threads.append(
                DiscordThread(
                    id=str(thread_payload.get("id")),
                    guild_id=str(thread_payload.get("guild_id")) if thread_payload.get("guild_id") else None,
                    channel_id=str(self._offline_payload.get("channel", {}).get("id", "")),
                    name=thread_payload.get("name", "(no title)"),
                    owner_id=str(thread_payload.get("owner_id", "")),
                    created_at=created_at,
                    applied_tag_ids=[str(tag_id) for tag_id in thread_payload.get("applied_tags", [])],
                    first_message=first_message,
                )
            )
            if limit and len(threads) >= limit:
                break
        threads.sort(key=lambda t: t.created_at)
        return threads

    @staticmethod
    def _message_from_payload(payload: Dict[str, Any]) -> DiscordMessage:
        attachments = [
            DiscordAttachment(
                id=str(attachment.get("id")),
                url=attachment.get("url", ""),
                filename=attachment.get("filename", "attachment"),
            )
            for attachment in payload.get("attachments", [])
        ]
        timestamp = DiscordClient._parse_timestamp(payload.get("timestamp"))
        author = payload.get("author", {})
        return DiscordMessage(
            id=str(payload.get("id")),
            author_id=str(author.get("id", "")),
            author_name=author.get("global_name") or author.get("username", "unknown"),
            content=payload.get("content", "").strip(),
            timestamp=timestamp,
            attachments=attachments,
        )

    @staticmethod
    def _extract_created_at(thread_payload: Dict[str, Any]) -> datetime:
        metadata = thread_payload.get("thread_metadata") or {}
        ts = metadata.get("create_timestamp") or metadata.get("archive_timestamp")
        if ts:
            return DiscordClient._parse_timestamp(ts)
        return DiscordClient._parse_timestamp(thread_payload.get("timestamp"))

    @staticmethod
    def _parse_timestamp(value: Optional[str]) -> datetime:
        if not value:
            return datetime.now(timezone.utc)
        ts = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        return ts.astimezone(timezone.utc)

    def _get(self, path: str) -> Any:
        if not path.startswith("/"):
            raise ValueError("path は / から始めてください")
        url = f"{API_BASE}{path}"
        headers = {
            "Authorization": f"Bot {self._token}",
            "User-Agent": "EpikaDiscordIssueBridge/1.0",
        }
        req = request.Request(url, headers=headers)
        return self._execute(req)

    def _execute(self, req: request.Request) -> Any:
        for attempt in range(1, self._max_retries + 1):
            try:
                with request.urlopen(req, timeout=self._timeout) as resp:
                    charset = resp.headers.get_content_charset() or "utf-8"
                    body = resp.read().decode(charset)
                    if resp.headers.get("Content-Type", "").startswith("application/json"):
                        return json.loads(body)
                    return json.loads(body)
            except error.HTTPError as exc:
                if exc.code == 429:
                    retry_after = float(exc.headers.get("Retry-After", "1"))
                    logger.warning("Discord RateLimit。%s 秒後に再試行", retry_after)
                    time.sleep(retry_after)
                    continue
                if 500 <= exc.code < 600 and attempt < self._max_retries:
                    self._sleep_with_backoff(attempt)
                    continue
                raise
            except error.URLError:
                if attempt >= self._max_retries:
                    raise
                self._sleep_with_backoff(attempt)
        raise RuntimeError("Discord API の呼び出しに失敗しました")

    @staticmethod
    def _sleep_with_backoff(attempt: int) -> None:
        delay = min(2 ** attempt, 30)
        time.sleep(delay)
