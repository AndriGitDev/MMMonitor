#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
OUTPUT_DIR="$PROJECT_DIR/dist"
APP_DIR="$OUTPUT_DIR/MMMonitor.app"
mkdir -p "$OUTPUT_DIR"
STAGING_DIR="$(mktemp -d "$OUTPUT_DIR/.MMMonitor-build.XXXXXX")"
STAGED_APP="$STAGING_DIR/MMMonitor.app"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cd "$PROJECT_DIR"
swift build -c release --arch arm64 -Xswiftc -warnings-as-errors

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$PROJECT_DIR/.build/arm64-apple-macosx/release/MMMonitor" "$STAGED_APP/Contents/MacOS/MMMonitor"
cp "$PROJECT_DIR/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - "$STAGED_APP"
fi

rm -rf "$APP_DIR"
mv "$STAGED_APP" "$APP_DIR"

echo "$APP_DIR"
