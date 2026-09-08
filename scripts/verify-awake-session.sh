#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/MMMonitor-awake-tests.XXXXXX")"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

swiftc \
    -parse-as-library \
    "$PROJECT_DIR/Sources/MMMonitor/AwakeSessionController.swift" \
    "$PROJECT_DIR/Tests/AwakeSessionVerification/main.swift" \
    -framework AppKit \
    -framework IOKit \
    -o "$TEST_DIR/awake-session-verification"

"$TEST_DIR/awake-session-verification"
