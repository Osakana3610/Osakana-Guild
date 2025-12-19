#!/bin/bash
# ==============================================================================
# 既知の問題ページを生成してGitHubにプッシュするスクリプト
#
# 使用方法:
#   ダブルクリックで実行、または ./publish_known_issues.command
# ==============================================================================

set -e

# スクリプトのディレクトリに移動
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "======================================"
echo "既知の問題ページを更新します"
echo "======================================"
echo ""

# Python3が利用可能か確認
if ! command -v python3 &> /dev/null; then
    echo "エラー: Python3 がインストールされていません"
    read -p "Enterキーで終了..."
    exit 1
fi

# HTMLを生成
echo "[1/4] HTMLを生成中..."

python3 << 'PYTHON_SCRIPT'
import subprocess
import sys
from datetime import datetime
from pathlib import Path

# PyYAMLがない場合は自動インストール
try:
    import yaml
except ImportError:
    print("PyYAML をインストールしています...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyyaml", "-q"])
    import yaml

DOCS_DIR = Path(__file__).parent if "__file__" in dir() else Path.cwd()
YAML_FILE = DOCS_DIR / "known_issues.yaml"
HTML_FILE = DOCS_DIR / "known-issues.html"

STATUS_LABELS = {
    "investigating": ("調査中", "#f39c12"),
    "confirmed": ("確認済み", "#3498db"),
    "fixing": ("修正中", "#9b59b6"),
    "wontfix": ("対応しない", "#95a5a6"),
    "fixed": ("修正済み", "#27ae60"),
}

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>既知の問題 - おさかなギルド</title>
    <style>
        * {{ box-sizing: border-box; }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            line-height: 1.8;
            max-width: 900px;
            margin: 0 auto;
            padding: 40px 20px;
            color: #333;
            background-color: #fafafa;
        }}
        h1 {{ color: #1a1a1a; border-bottom: 2px solid #4a90d9; padding-bottom: 10px; }}
        h2 {{ color: #2c3e50; margin-top: 40px; padding-bottom: 8px; border-bottom: 1px solid #ddd; }}
        .issue-count {{ font-size: 0.9em; color: #666; font-weight: normal; }}
        .issue {{
            background: #fff;
            border: 1px solid #e1e4e8;
            border-radius: 8px;
            margin: 16px 0;
            overflow: hidden;
        }}
        .issue-header {{
            padding: 16px 20px;
            cursor: pointer;
            display: flex;
            align-items: flex-start;
            gap: 12px;
        }}
        .issue-header:hover {{ background: #f6f8fa; }}
        .issue-id {{
            font-family: monospace;
            font-size: 0.85em;
            color: #666;
            background: #f1f3f4;
            padding: 2px 8px;
            border-radius: 4px;
            flex-shrink: 0;
        }}
        .issue-title {{ flex: 1; font-weight: 600; color: #24292e; }}
        .issue-meta {{ display: flex; gap: 8px; align-items: center; flex-shrink: 0; }}
        .status {{
            font-size: 0.75em;
            padding: 4px 10px;
            border-radius: 12px;
            color: #fff;
            font-weight: 500;
        }}
        .category {{
            font-size: 0.75em;
            padding: 4px 10px;
            border-radius: 12px;
            background: #e1e4e8;
            color: #586069;
        }}
        .toggle-icon {{ color: #666; transition: transform 0.2s; flex-shrink: 0; }}
        .issue.open .toggle-icon {{ transform: rotate(90deg); }}
        .issue-body {{
            display: none;
            padding: 0 20px 20px 20px;
            border-top: 1px solid #e1e4e8;
        }}
        .issue.open .issue-body {{ display: block; }}
        .issue-section {{ margin-top: 16px; }}
        .issue-section-title {{ font-size: 0.85em; font-weight: 600; color: #586069; margin-bottom: 4px; }}
        .issue-section-content {{
            white-space: pre-wrap;
            font-size: 0.95em;
            color: #24292e;
            background: #f6f8fa;
            padding: 12px;
            border-radius: 6px;
        }}
        .date {{ font-size: 0.85em; color: #666; }}
        .resolved-section .issue {{ opacity: 0.8; }}
        .resolved-section .issue-title {{ text-decoration: line-through; color: #586069; }}
        .no-issues {{ color: #666; font-style: italic; padding: 20px; text-align: center; }}
        .updated {{
            color: #666;
            font-size: 0.9em;
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #ddd;
        }}
        @media (max-width: 600px) {{
            .issue-header {{ flex-wrap: wrap; }}
            .issue-meta {{ width: 100%; margin-top: 8px; }}
        }}
    </style>
</head>
<body>
    <h1>既知の問題</h1>
    <p>おさかなギルドで現在確認されている問題と、その対応状況をお知らせします。</p>
    <h2>対応中の問題 <span class="issue-count">({open_count}件)</span></h2>
    {open_issues_html}
    <h2 class="resolved-section">解決済みの問題 <span class="issue-count">({resolved_count}件)</span></h2>
    <div class="resolved-section">
    {resolved_issues_html}
    </div>
    <p class="updated">最終更新日: {last_updated}</p>
    <script>
        document.querySelectorAll('.issue-header').forEach(header => {{
            header.addEventListener('click', () => {{
                header.parentElement.classList.toggle('open');
            }});
        }});
    </script>
</body>
</html>
"""

ISSUE_TEMPLATE = """
    <div class="issue">
        <div class="issue-header">
            <span class="toggle-icon">&#9654;</span>
            <span class="issue-id">{id}</span>
            <span class="issue-title">{title}</span>
            <div class="issue-meta">
                <span class="category">{category}</span>
                <span class="status" style="background-color: {status_color}">{status_label}</span>
            </div>
        </div>
        <div class="issue-body">
            <div class="date">報告日: {reported_date}{resolved_date_html}</div>
            <div class="issue-section">
                <div class="issue-section-title">概要</div>
                <div class="issue-section-content">{description}</div>
            </div>
            {details_html}
            {workaround_html}
            {fix_plan_html}
            {resolution_html}
        </div>
    </div>
"""

def escape_html(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")

def render_issue(issue, is_resolved=False):
    status = issue.get("status", "investigating")
    status_label, status_color = STATUS_LABELS.get(status, ("不明", "#666"))
    resolved_date_html = ""
    if is_resolved and issue.get("resolved_date"):
        resolved_date_html = f" / 解決日: {issue['resolved_date']}"
    details_html = ""
    if issue.get("details", "").strip():
        details_html = f'<div class="issue-section"><div class="issue-section-title">詳細</div><div class="issue-section-content">{escape_html(issue["details"].strip())}</div></div>'
    workaround_html = ""
    if issue.get("workaround", "").strip():
        workaround_html = f'<div class="issue-section"><div class="issue-section-title">回避策</div><div class="issue-section-content">{escape_html(issue["workaround"].strip())}</div></div>'
    fix_plan_html = ""
    if issue.get("fix_plan", "").strip():
        fix_plan_html = f'<div class="issue-section"><div class="issue-section-title">修正予定</div><div class="issue-section-content">{escape_html(issue["fix_plan"].strip())}</div></div>'
    resolution_html = ""
    if is_resolved and issue.get("resolution", "").strip():
        resolution_html = f'<div class="issue-section"><div class="issue-section-title">解決方法</div><div class="issue-section-content">{escape_html(issue["resolution"].strip())}</div></div>'
    return ISSUE_TEMPLATE.format(
        id=escape_html(issue.get("id", "N/A")),
        title=escape_html(issue.get("title", "タイトルなし")),
        category=escape_html(issue.get("category", "その他")),
        status_label=status_label,
        status_color=status_color,
        reported_date=issue.get("reported_date", "不明"),
        resolved_date_html=resolved_date_html,
        description=escape_html(issue.get("description", "").strip()),
        details_html=details_html,
        workaround_html=workaround_html,
        fix_plan_html=fix_plan_html,
        resolution_html=resolution_html,
    )

# Main
if not YAML_FILE.exists():
    print(f"エラー: {YAML_FILE} が見つかりません")
    sys.exit(1)

with open(YAML_FILE, "r", encoding="utf-8") as f:
    data = yaml.safe_load(f)

open_issues = data.get("issues", []) or []
resolved_issues = data.get("resolved", []) or []

if open_issues:
    open_issues_html = "\n".join(render_issue(issue) for issue in open_issues)
else:
    open_issues_html = '<div class="no-issues">現在、対応中の問題はありません</div>'

if resolved_issues:
    resolved_issues_html = "\n".join(render_issue(issue, is_resolved=True) for issue in resolved_issues)
else:
    resolved_issues_html = '<div class="no-issues">解決済みの問題はありません</div>'

last_updated = datetime.now().strftime("%Y年%m月%d日")

html = HTML_TEMPLATE.format(
    open_count=len(open_issues),
    resolved_count=len(resolved_issues),
    open_issues_html=open_issues_html,
    resolved_issues_html=resolved_issues_html,
    last_updated=last_updated,
)

with open(HTML_FILE, "w", encoding="utf-8") as f:
    f.write(html)

print(f"生成完了: {HTML_FILE}")
print(f"  - 対応中: {len(open_issues)}件")
print(f"  - 解決済み: {len(resolved_issues)}件")
PYTHON_SCRIPT

echo ""

# Gitの状態を確認
echo "[2/4] 変更を確認中..."
cd "$SCRIPT_DIR/.."

if git diff --quiet docs/known_issues.yaml docs/known-issues.html 2>/dev/null && \
   ! git status --porcelain docs/ | grep -q .; then
    echo "変更はありません"
    read -p "Enterキーで終了..."
    exit 0
fi

echo "変更されたファイル:"
git status --porcelain docs/
echo ""

# 変更をステージング
echo "[3/4] 変更をコミット中..."
git add docs/known_issues.yaml docs/known-issues.html docs/publish_known_issues.command

COMMIT_MSG="Update known issues page"
git commit --no-verify -m "$COMMIT_MSG" || {
    echo "コミットに失敗しました"
    read -p "Enterキーで終了..."
    exit 1
}
echo ""

# プッシュ
echo "[4/4] GitHubにプッシュ中..."
git push

echo ""
echo "======================================"
echo "完了しました!"
echo "======================================"
echo ""
echo "GitHub Pages URL:"
echo "  https://osakana3610.github.io/Osakana-Guild/known-issues.html"
echo ""
echo "3秒後にウィンドウを閉じます..."
sleep 3

# このターミナルウィンドウを閉じる
TTY_NAME=$(tty | sed 's|/dev/||')
osascript -e "tell application \"Terminal\" to close (first window whose tty contains \"$TTY_NAME\")" &>/dev/null &
exit 0
