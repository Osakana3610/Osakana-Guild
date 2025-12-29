from __future__ import annotations

import argparse
import logging
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

if __package__ is None or __package__ == "":
    sys.path.append(str(Path(__file__).resolve().parent))
    from bridge_config import BridgeConfig  # type: ignore
    from discord_client import DiscordClient  # type: ignore
    from github_client import GitHubClient  # type: ignore
    from issue_syncer import IssueSyncer  # type: ignore
    from state_store import StateStore  # type: ignore
else:
    from .bridge_config import BridgeConfig
    from .discord_client import DiscordClient
    from .github_client import GitHubClient
    from .issue_syncer import IssueSyncer
    from .state_store import StateStore


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Discord Forum から GitHub Issue を自動起票するツール")
    parser.add_argument("--config", required=True, help="設定ファイル (JSON) のパス")
    parser.add_argument("--state", help="State ファイルのパス。未指定時は設定ファイルの値を使用")
    parser.add_argument("--since", help="ISO8601 形式のUTC日時。これ以降のスレッドのみ処理")
    parser.add_argument("--max-threads", type=int, help="1回の実行で処理する最大スレッド数")
    parser.add_argument("--dry-run", action="store_true", help="GitHub Issue を作成せず内容のみ表示")
    parser.add_argument("--offline-sample", help="Discord API の代わりにローカル JSON を利用")
    parser.add_argument("--verbose", action="store_true", help="詳細ログを表示")
    return parser.parse_args()


def parse_iso8601(value: str) -> datetime:
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def main() -> None:
    args = parse_args()
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s - %(message)s",
    )

    config_path = Path(args.config).expanduser().resolve()
    config = BridgeConfig.load(config_path)

    state_path = Path(args.state).expanduser().resolve() if args.state else config.state_file
    state_store = StateStore(state_path, config.state_backup_enabled)
    state_store.load()

    discord_token = os.environ.get("DISCORD_BOT_TOKEN")
    github_token = os.environ.get("GITHUB_TOKEN")

    offline_sample = Path(args.offline_sample).expanduser().resolve() if args.offline_sample else None

    discord_client = DiscordClient(
        token=discord_token or "",
        channel_id=config.discord_channel_id,
        offline_sample=offline_sample,
    )
    github_client = GitHubClient(
        token=github_token or "",
        repo=config.github_repo,
        dry_run=args.dry_run,
    )

    since_dt = parse_iso8601(args.since) if args.since else None
    effective_max = args.max_threads or config.max_threads_per_run

    syncer = IssueSyncer(config, discord_client, github_client, state_store)
    created_count = syncer.run(since=since_dt, max_threads=effective_max)
    logging.info("処理完了。新規 Issue: %d 件", created_count)


if __name__ == "__main__":
    main()
