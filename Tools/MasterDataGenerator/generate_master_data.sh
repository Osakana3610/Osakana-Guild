#!/bin/bash
set -e

# MasterDataGenerator ビルドスクリプト
# Xcode Build Phase から呼び出される

GENERATOR="${SRCROOT}/Tools/MasterDataGenerator/.build/release/MasterDataGenerator"
INPUT_DIR="${SRCROOT}/MasterData"
OUTPUT_FILE="${SRCROOT}/Epika/Generated/master_data.db"

echo "[MasterDataGenerator] Starting..."
echo "[MasterDataGenerator] SRCROOT: ${SRCROOT}"
echo "[MasterDataGenerator] DERIVED_FILE_DIR: ${DERIVED_FILE_DIR}"

# ジェネレータが未ビルドならビルド
if [ ! -f "$GENERATOR" ]; then
    echo "[MasterDataGenerator] Building generator..."
    swift build -c release --package-path "${SRCROOT}/Tools/MasterDataGenerator"
fi

# SQLite生成
echo "[MasterDataGenerator] Generating master_data.db..."
"$GENERATOR" --input "$INPUT_DIR" --output "$OUTPUT_FILE"

echo "[MasterDataGenerator] Output: $OUTPUT_FILE"
echo "[MasterDataGenerator] Completed."
