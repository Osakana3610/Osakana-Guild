# Discord Issue Bridge

Epika の β テスター向け Discord Forum への投稿を自動で GitHub Issue に起票するための Python 製 CLI です。Bot トークンと GitHub Personal Access Token (PAT) を利用し、Forum スレッドを巡回して未処理のものだけを Issue 化します。

## 前提条件
- macOS + Python 3.11 以上（Xcode 同梱版で可）
- Discord 開発者ポータルで作成した Bot が対象サーバーへ参加済みで、Forum チャンネルの `View Channel` / `Read Message History` / `Send Messages` / `Send Messages in Threads` / `Manage Messages` / `Read Forum Posts` 権限を持つこと
- GitHub PAT（`repo:issues` スコープ以上）
- 環境変数 `DISCORD_BOT_TOKEN`, `GITHUB_TOKEN` を安全に設定していること（例: direnv, launchd 設定ファイル）

## セットアップ手順
1. Bot Token を取得（Discord Developer Portal → Bot → Reset Token）。コード内では自動で `Bot ` プレフィックスを付与するため、プレーン token を `DISCORD_BOT_TOKEN` として設定してください。
2. GitHub PAT を作成し、`GITHUB_TOKEN` に設定。必要最小権限は `repo:issues`。
3. `Tools/DiscordIssueBridge/config.example.json` をコピーし、各種 ID/ラベル/テンプレートを編集。
4. `tmp/discord_issue_bridge_state.json` など書き込み可能な場所を用意し、config から参照させます。

```bash
cp Tools/DiscordIssueBridge/config.example.json ~/epika-discord-config.json
cp /dev/null tmp/discord_issue_bridge_state.json
```

## 設定ファイルの主な項目
- `discord_channel_id`: Discord Forum チャンネルの ID。Discord クライアントで開発者モードを有効化し、右クリック→「IDをコピー」で取得。
- `github_repo`: `owner/repo` 形式で Issue を作成するリポジトリ。
- `issue_title_prefix`: Issue タイトルの接頭辞（例: `[Discord] `）。
- `issue_body_template`: Markdown 形式のテンプレート。`{{title}}`, `{{author}}`, `{{message_url}}`, `{{content}}`, `{{attachments}}`, `{{created_at}}`, `{{thread_id}}` を埋め込みます。
- `default_labels`: 常に付与するラベル一覧。
- `tag_label_map`: Discord Forum のタグ ID（数値の文字列）を GitHub ラベル配列に変換するマップ。未設定タグは `fallback_label_prefix`＋タグ名で補完します。
- `assignees`: Issue 作成時に自動で割り当てる GitHub ユーザーの配列。
- `state_file`: 既処理スレッド ID を保持する JSON ファイルパス。
- `state_backup_enabled`: State 更新前に `.bak` を自動作成するかどうか。
- `max_threads_per_run`: 1 回の実行で処理する最大スレッド数。RateLimit 回避に利用。

## 実行方法
Dry Run + サンプルデータでテンプレート確認:

```bash
python3 Tools/DiscordIssueBridge/discord_issue_bridge.py \
  --config ~/epika-discord-config.json \
  --state tmp/discord_issue_bridge_state.json \
  --dry-run \
  --offline-sample Tools/DiscordIssueBridge/sample_threads.json
```

本番実行（Forum から直接取得）:

```bash
python3 Tools/DiscordIssueBridge/discord_issue_bridge.py \
  --config ~/epika-discord-config.json \
  --state tmp/discord_issue_bridge_state.json
```

## オプション
- `--since 2025-12-20T00:00:00Z` のように ISO8601 を指定すると、その日時より新しいスレッドのみ対象。
- `--max-threads 10` で設定ファイルより優先的に件数を制限。
- `--dry-run` で GitHub API を呼ばずに出力のみ。
- `--offline-sample path` で HTTP を行わずローカル JSON を読み込み（テスト用途）。

## 定期実行
launchd 例 (`~/Library/LaunchAgents/me.fishnchips.discord-issue-bridge.plist`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>me.fishnchips.discord-issue-bridge</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/python3</string>
    <string>/Users/licht/Development/Epika/Tools/DiscordIssueBridge/discord_issue_bridge.py</string>
    <string>--config</string><string>/Users/licht/epika-discord-config.json</string>
    <string>--state</string><string>/Users/licht/Development/Epika/tmp/discord_issue_bridge_state.json</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>DISCORD_BOT_TOKEN</key><string>xxxx</string>
    <key>GITHUB_TOKEN</key><string>yyyy</string>
  </dict>
  <key>StartInterval</key><integer>900</integer>
  <key>StandardOutPath</key><string>/Users/licht/Library/Logs/discord-issue-bridge.log</string>
  <key>StandardErrorPath</key><string>/Users/licht/Library/Logs/discord-issue-bridge.err</string>
</dict>
</plist>
```

## トラブルシューティング
- Rate Limit に達した場合: ログに `Retry-After` 秒が表示されます。`max_threads_per_run` を減らし再実行してください。
- State ファイル破損時: `.bak` を `.json` に戻して再実行。
- 429/5xx が連続する場合: `--since` で期間を絞って原因スレッドを特定します。

## テスト
テンプレート生成などの単体テスト:

```bash
python3 -m unittest discover Tools/DiscordIssueBridge/tests
```

## セキュリティ
- トークンは必ず環境変数経由で注入し、config やソースコードにハードコードしない。
- GitHub PAT が漏洩しないよう、`launchd` や CI の設定ファイルは `.gitignore` 配下に置いてください。
