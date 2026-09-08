#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/MMMonitor-history-tests.XXXXXX")"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

swiftc \
    "$PROJECT_DIR/Sources/MMMonitor/SystemSnapshot.swift" \
    "$PROJECT_DIR/Sources/MMMonitor/PersistedHistory.swift" \
    "$PROJECT_DIR/Tests/HistoryVerification/main.swift" \
    -o "$TEST_DIR/history-verification"

"$TEST_DIR/history-verification"
