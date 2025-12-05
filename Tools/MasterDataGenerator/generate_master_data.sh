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

# 毎回ビルド（差分ビルドなので変更がなければ高速）
# Xcodeの環境変数をリセットしてmacOS用にビルド
echo "[MasterDataGenerator] Building generator..."
env -i PATH="$PATH" HOME="$HOME" swift build -c release --package-path "${SRCROOT}/Tools/MasterDataGenerator"

# SQLite生成
echo "[MasterDataGenerator] Generating master_data.db..."
"$GENERATOR" --input "$INPUT_DIR" --output "$OUTPUT_FILE"

echo "[MasterDataGenerator] Output: $OUTPUT_FILE"
echo "[MasterDataGenerator] Completed."
