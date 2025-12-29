from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from Tools.DiscordIssueBridge.bridge_config import BridgeConfig
from Tools.DiscordIssueBridge.discord_client import DiscordClient
from Tools.DiscordIssueBridge.issue_syncer import IssueSyncer
from Tools.DiscordIssueBridge.state_store import StateStore
from Tools.DiscordIssueBridge.template_engine import render


class DummyGitHubClient:
    def __init__(self) -> None:
        self.created_payloads = []

    def create_issue(self, title, body, labels=None, assignees=None):  # pragma: no cover - simple stub
        self.created_payloads.append(
            {
                "title": title,
                "body": body,
                "labels": labels,
                "assignees": assignees,
            }
        )
        return {"number": len(self.created_payloads)}


class IssueSyncerRenderingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.sample_path = (
            Path(__file__).resolve().parents[1] / "sample_threads.json"
        )
        self.config = BridgeConfig(
            discord_channel_id="123456789012345678",
            github_repo="fishnchips/Epika",
            issue_title_prefix="[Discord] ",
            issue_body_template=(
                "## Discord Forum 報告\n"
                "- 投稿者: {{author}}\n"
                "- 投稿日時 (UTC): {{created_at}}\n"
                "- スレッド ID: {{thread_id}}\n"
                "- URL: {{message_url}}\n\n"
                "### 内容\n{{content}}\n\n"
                "### 添付ファイル\n{{attachments}}\n"
            ),
            default_labels=["discord", "triage"],
            tag_label_map={"987654321098765432": ["bug"]},
            fallback_label_prefix="discord/tag/",
            assignees=["licht"],
            state_file=Path("/tmp/dummy"),
            state_backup_enabled=False,
            max_threads_per_run=10,
        )
        tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(tmpdir.cleanup)
        self.state_path = Path(tmpdir.name) / "state.json"
        self.state_store = StateStore(self.state_path, backup_enabled=False)
        self.state_store.load()

    def test_render_template_success(self) -> None:
        template = "Hello {{name}}"
        rendered = render(template, {"name": "Epika"})
        self.assertEqual(rendered, "Hello Epika")

    def test_syncer_creates_bodies_from_offline_sample(self) -> None:
        discord_client = DiscordClient(
            token="",
            channel_id=self.config.discord_channel_id,
            offline_sample=self.sample_path,
        )
        github_stub = DummyGitHubClient()
        syncer = IssueSyncer(
            self.config,
            discord_client,
            github_stub,
            self.state_store,
        )
        created = syncer.run(since=None, max_threads=5)
        self.assertEqual(created, 2)
        self.assertEqual(len(github_stub.created_payloads), 2)
        first_payload = github_stub.created_payloads[0]
        self.assertIn("クラッシュ", first_payload["title"])
        self.assertIn("添付ファイル", first_payload["body"])
        self.assertIn("crash-log.txt", first_payload["body"])
        self.assertIn("bug", first_payload["labels"])
        self.assertIn("discord", first_payload["labels"])

    def test_render_missing_placeholder_raises(self) -> None:
        with self.assertRaises(KeyError):
            render("Hello {{name}}", {})


if __name__ == "__main__":
    unittest.main()
