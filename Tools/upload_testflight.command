#!/bin/bash
# ==============================================================================
# TestFlightアップロード自動化スクリプト
#
# 使用方法:
#   ダブルクリックで実行、または ./upload_testflight.command
#
# 処理内容:
#   1. 前回タグからのコミット一覧を取得（リリースノート用）
#   2. バージョン/ビルドの変更をコミット（未コミットの場合）
#   3. アーカイブ & エクスポート
#   4. App Store Connectにアップロード
#   5. リリースノートを設定
#   6. ベータグループ（ギルド酒場）に追加
#   7. 新しいタグを作成
#
# 使い方:
#   1. Xcodeでバージョン/ビルド番号を更新
#   2. このスクリプトを実行
# ==============================================================================

set -e

# スクリプトのディレクトリに移動
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
cd "$PROJECT_DIR"

# 設定
SCHEME="Epika"
PROJECT="Epika.xcodeproj"
BUNDLE_ID="me.fishnchips.Epika"
ARCHIVE_PATH="$HOME/Library/Developer/Xcode/Archives/Epika.xcarchive"
EXPORT_PATH="/tmp/EpikaExport"
CONFIG_DIR="$HOME/.config/appstoreconnect"

echo "======================================"
echo "TestFlight アップロード自動化"
echo "======================================"
echo ""

# App Store Connect API設定確認
if [[ ! -f "$CONFIG_DIR/key.p8" ]] || [[ ! -f "$CONFIG_DIR/key_id" ]] || [[ ! -f "$CONFIG_DIR/issuer_id" ]]; then
    echo "警告: App Store Connect API設定がありません"
    echo "リリースノートの自動設定はスキップされます"
    API_AVAILABLE=false
else
    API_AVAILABLE=true
    KEY_ID=$(cat "$CONFIG_DIR/key_id")
    ISSUER_ID=$(cat "$CONFIG_DIR/issuer_id")
fi

# ==============================================================================
# Step 1: 前回タグからのコミット一覧を取得
# ==============================================================================
echo "[1/7] リリースノートを準備中..."

# 最新のタグを取得
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

if [[ -z "$LAST_TAG" ]]; then
    echo "  警告: 前回のタグが見つかりません。全コミットを対象にします。"
    COMMITS=$(git log --oneline -20)
else
    echo "  前回のタグ: $LAST_TAG"
    COMMITS=$(git log "$LAST_TAG..HEAD" --oneline)
fi

if [[ -z "$COMMITS" ]]; then
    echo "  新しいコミットがありません"
    RELEASE_NOTES="バグ修正と改善"
else
    echo "  含まれるコミット:"
    echo "$COMMITS" | sed 's/^/    /'

    # リリースノート生成（fix: や feat: などのプレフィックスを整形）
    RELEASE_NOTES=$(echo "$COMMITS" | sed 's/^[a-f0-9]* //' | sed 's/^fix: /・修正: /' | sed 's/^feat: /・新機能: /' | sed 's/^chore: //' | sed 's/^docs: //' | sed 's/^perf: /・改善: /' | sed 's/^refactor: //' | grep -v "^Update known issues" | grep -v "^$" | head -10)

    if [[ -z "$RELEASE_NOTES" ]]; then
        RELEASE_NOTES="バグ修正と改善"
    fi
fi

echo ""
echo "  リリースノート:"
echo "$RELEASE_NOTES" | sed 's/^/    /'
echo ""

# ==============================================================================
# Step 2: バージョン/ビルド変更をコミット
# ==============================================================================
echo "[2/7] バージョン/ビルドを確認中..."

# 現在のバージョンとビルド番号を取得
CURRENT_VERSION=$(grep "MARKETING_VERSION" "$PROJECT/project.pbxproj" | head -1 | grep -o '[0-9]*\.[0-9]*\.[0-9]*')
CURRENT_BUILD=$(grep "CURRENT_PROJECT_VERSION" "$PROJECT/project.pbxproj" | head -1 | grep -o '[0-9]*')

echo "  バージョン: $CURRENT_VERSION"
echo "  ビルド: $CURRENT_BUILD"

# project.pbxprojに未コミットの変更があるかチェック
if git diff --quiet "$PROJECT/project.pbxproj" 2>/dev/null; then
    echo "  変更なし（既にコミット済み）"
else
    echo "  未コミットの変更を検出 → コミットします"
    git add "$PROJECT/project.pbxproj"
    git commit -m "chore: バージョンを${CURRENT_VERSION}(${CURRENT_BUILD})に更新"
fi

echo ""

# ==============================================================================
# Step 3: アーカイブ
# ==============================================================================
echo "[3/7] アーカイブ中..."

# 古いアーカイブを削除
rm -rf "$ARCHIVE_PATH"
rm -rf "$EXPORT_PATH"

xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=iOS" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    2>&1 | grep -E "^(Archive|error:|warning:|\*\*)" || true

if [[ ! -d "$ARCHIVE_PATH" ]]; then
    echo "エラー: アーカイブに失敗しました"
    exit 1
fi

echo "  アーカイブ完了"
echo ""

# ==============================================================================
# Step 4: エクスポート
# ==============================================================================
echo "[4/7] エクスポート中..."

# ExportOptions.plistを作成
cat > /tmp/ExportOptions.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist /tmp/ExportOptions.plist \
    -allowProvisioningUpdates \
    2>&1 | grep -E "^(Export|error:|warning:|\*\*)" || true

echo "  エクスポート・アップロード完了"
echo ""

# ==============================================================================
# Step 5: リリースノートを設定（API経由）
# ==============================================================================
echo "[5/7] リリースノートを設定中..."

if [[ "$API_AVAILABLE" == "true" ]]; then
    # JWT生成
    generate_jwt() {
        local header='{"alg":"ES256","kid":"'"$KEY_ID"'","typ":"JWT"}'
        local now=$(date +%s)
        local exp=$((now + 1200))
        local payload='{"iss":"'"$ISSUER_ID"'","iat":'"$now"',"exp":'"$exp"',"aud":"appstoreconnect-v1"}'
        local header_b64=$(echo -n "$header" | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')
        local payload_b64=$(echo -n "$payload" | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')
        local signing_input="$header_b64.$payload_b64"
        local der_sig=$(echo -n "$signing_input" | openssl dgst -sha256 -sign "$CONFIG_DIR/key.p8" | xxd -p | tr -d '\n')
        local signature=$(python3 -c "
der = bytes.fromhex('$der_sig')
pos = 2; r_len = der[pos + 1]; r = der[pos + 2 : pos + 2 + r_len]
pos = pos + 2 + r_len; s_len = der[pos + 1]; s = der[pos + 2 : pos + 2 + s_len]
r = r[-32:].rjust(32, b'\\x00'); s = s[-32:].rjust(32, b'\\x00')
import base64; print(base64.urlsafe_b64encode(r + s).rstrip(b'=').decode())
")
        echo "$signing_input.$signature"
    }

    echo "  処理完了を待機中（最大5分）..."

    # ビルドが処理されるまで待機
    JWT=$(generate_jwt)
    for i in {1..30}; do
        sleep 10

        BUILD_RESPONSE=$(curl -s -g -H "Authorization: Bearer $JWT" \
            "https://api.appstoreconnect.apple.com/v1/builds?filter[app]=6756705558&filter[version]=$CURRENT_BUILD&limit=1")

        BUILD_ID=$(echo "$BUILD_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'] if d.get('data') else '')" 2>/dev/null || echo "")

        if [[ -n "$BUILD_ID" ]]; then
            PROCESSING_STATE=$(echo "$BUILD_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['attributes']['processingState'])" 2>/dev/null || echo "")

            if [[ "$PROCESSING_STATE" == "VALID" ]]; then
                echo "  ビルド処理完了: $BUILD_ID"
                break
            fi
            echo "  処理中... ($PROCESSING_STATE)"
        else
            echo "  ビルドを待機中... ($i/30)"
        fi

        # JWTを更新（期限切れ対策）
        if [[ $((i % 6)) -eq 0 ]]; then
            JWT=$(generate_jwt)
        fi
    done

    if [[ -n "$BUILD_ID" ]]; then
        # リリースノートを設定
        ESCAPED_NOTES=$(echo "$RELEASE_NOTES" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")

        # 既存のlocalizationを確認
        LOC_RESPONSE=$(curl -s -g -H "Authorization: Bearer $JWT" \
            "https://api.appstoreconnect.apple.com/v1/builds/$BUILD_ID/betaBuildLocalizations")

        LOC_ID=$(echo "$LOC_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); locs=[l for l in d.get('data',[]) if l['attributes']['locale']=='ja']; print(locs[0]['id'] if locs else '')" 2>/dev/null || echo "")

        if [[ -n "$LOC_ID" ]]; then
            # 既存のlocalizationを更新
            curl -s -X PATCH \
                -H "Authorization: Bearer $JWT" \
                -H "Content-Type: application/json" \
                -d '{"data":{"type":"betaBuildLocalizations","id":"'"$LOC_ID"'","attributes":{"whatsNew":'"$ESCAPED_NOTES"'}}}' \
                "https://api.appstoreconnect.apple.com/v1/betaBuildLocalizations/$LOC_ID" > /dev/null
            echo "  リリースノート更新完了"
        else
            # 新規作成
            curl -s -X POST \
                -H "Authorization: Bearer $JWT" \
                -H "Content-Type: application/json" \
                -d '{"data":{"type":"betaBuildLocalizations","attributes":{"locale":"ja","whatsNew":'"$ESCAPED_NOTES"'},"relationships":{"build":{"data":{"type":"builds","id":"'"$BUILD_ID"'"}}}}}' \
                "https://api.appstoreconnect.apple.com/v1/betaBuildLocalizations" > /dev/null
            echo "  リリースノート作成完了"
        fi
        # ベータグループに追加
        echo ""
        echo "[6/7] ベータグループに追加中..."

        BETA_GROUP_ID="8cf4ea58-5037-4d34-a576-00aeb7e5b7cf"  # ギルド酒場

        curl -s -X POST \
            -H "Authorization: Bearer $JWT" \
            -H "Content-Type: application/json" \
            -d '{"data":[{"type":"builds","id":"'"$BUILD_ID"'"}]}' \
            "https://api.appstoreconnect.apple.com/v1/betaGroups/$BETA_GROUP_ID/relationships/builds" > /dev/null

        echo "  ギルド酒場に追加完了（テスターに通知されます）"
    else
        echo "  警告: ビルドが見つかりません。手動でリリースノートを設定してください。"
    fi
else
    echo "  スキップ（API設定なし）"
fi

echo ""

# ==============================================================================
# Step 7: タグを作成
# ==============================================================================
echo "[7/7] タグを作成中..."

NEW_TAG="v${CURRENT_VERSION}-${CURRENT_BUILD}"
git tag "$NEW_TAG"
echo "  タグ作成: $NEW_TAG"

# リモートにプッシュ
git push origin main --tags

echo ""
echo "======================================"
echo "完了しました!"
echo "======================================"
echo ""
echo "バージョン: $CURRENT_VERSION ($CURRENT_BUILD)"
echo "タグ: $NEW_TAG"
echo ""
echo "TestFlightで確認してください"
echo ""
