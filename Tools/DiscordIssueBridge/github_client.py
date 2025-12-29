from __future__ import annotations

import json
import logging
import time
from typing import List, Optional, Any
from urllib import error, request

logger = logging.getLogger(__name__)
API_BASE = "https://api.github.com"


class GitHubClient:
    def __init__(
        self,
        token: str,
        repo: str,
        dry_run: bool = False,
        timeout: int = 15,
        max_retries: int = 5,
    ) -> None:
        if not token and not dry_run:
            raise ValueError("GITHUB_TOKEN が設定されていません")
        if "/" not in repo:
            raise ValueError("github_repo は owner/repo 形式で指定してください")
        self._token = token
        self._repo = repo
        self._dry_run = dry_run
        self._timeout = timeout
        self._max_retries = max_retries

    def create_issue(
        self,
        title: str,
        body: str,
        labels: Optional[List[str]] = None,
        assignees: Optional[List[str]] = None,
    ) -> Any:
        payload = {
            "title": title,
            "body": body,
        }
        if labels:
            payload["labels"] = labels
        if assignees:
            payload["assignees"] = assignees

        if self._dry_run:
            logger.info("[DRY-RUN] GitHub Issue 作成予定: title=%s labels=%s assignees=%s", title, labels, assignees)
            return {"dry_run": True, "payload": payload}

        url = f"{API_BASE}/repos/{self._repo}/issues"
        data = json.dumps(payload).encode("utf-8")
        headers = {
            "Authorization": f"Bearer {self._token}",
            "User-Agent": "EpikaDiscordIssueBridge/1.0",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
        }
        req = request.Request(url, data=data, headers=headers, method="POST")
        return self._execute(req)

    def _execute(self, req: request.Request) -> Any:
        for attempt in range(1, self._max_retries + 1):
            try:
                with request.urlopen(req, timeout=self._timeout) as resp:
                    charset = resp.headers.get_content_charset() or "utf-8"
                    body = resp.read().decode(charset)
                    return json.loads(body)
            except error.HTTPError as exc:
                if exc.code == 403 and exc.headers.get("X-RateLimit-Remaining") == "0":
                    reset = exc.headers.get("X-RateLimit-Reset")
                    logger.error("GitHub RateLimit 到達。Reset: %s", reset)
                    raise
                if 500 <= exc.code < 600 and attempt < self._max_retries:
                    self._sleep_with_backoff(attempt)
                    continue
                error_body = exc.read().decode("utf-8", errors="ignore")
                logger.error("GitHub API エラー (%s): %s", exc.code, error_body)
                raise
            except error.URLError:
                if attempt >= self._max_retries:
                    raise
                self._sleep_with_backoff(attempt)
        raise RuntimeError("GitHub API の呼び出しに失敗しました")

    @staticmethod
    def _sleep_with_backoff(attempt: int) -> None:
        delay = min(2 ** attempt, 30)
        time.sleep(delay)
