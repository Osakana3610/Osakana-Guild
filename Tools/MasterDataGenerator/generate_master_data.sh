#!/bin/bash
set -e

# MasterDataGenerator ビルドスクリプト
# Xcode Build Phase から呼び出される

GENERATOR="${SRCROOT}/Tools/MasterDataGenerator/.build/release/MasterDataGenerator"
INPUT_DIR="${SRCROOT}/MasterData"
OUTPUT_FILE="${SRCROOT}/Tools/MasterDataGenerator/output/master_data.db"

echo "[MasterDataGenerator] Starting..."
echo "[MasterDataGenerator] SRCROOT: ${SRCROOT}"
echo "[MasterDataGenerator] DERIVED_FILE_DIR: ${DERIVED_FILE_DIR}"

# 毎回ビルド（差分ビルドなので変更がなければ高速）
# Xcodeの環境変数をリセットしてmacOS用にビルド
echo "[MasterDataGenerator] Building generator..."
env -i PATH="$PATH" HOME="$HOME" swift build -c release --package-path "${SRCROOT}/Tools/MasterDataGenerator"

# SQLite生成
echo "[MasterDataGenerator] Generating master_data.db..."
"$GENERATOR" --input "$INPUT_DIR" --output "$OUTPUT_FILE"

echo "[MasterDataGenerator] Output: $OUTPUT_FILE"

# バンドルリソースにコピー（Xcodeビルド時のみ）
if [ -n "$BUILT_PRODUCTS_DIR" ] && [ -n "$UNLOCALIZED_RESOURCES_FOLDER_PATH" ]; then
    BUNDLE_DEST="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/master_data.db"
    echo "[MasterDataGenerator] Copying to bundle: $BUNDLE_DEST"
    mkdir -p "$(dirname "$BUNDLE_DEST")"
    cp "$OUTPUT_FILE" "$BUNDLE_DEST"
fi

echo "[MasterDataGenerator] Completed."
