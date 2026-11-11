#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
CARGO_TARGET_DIR="$HOME/.cache/qs-helper-target" cargo build --release
mkdir -p ../bin
cp "$HOME/.cache/qs-helper-target/release/qs-helper" ../bin/
