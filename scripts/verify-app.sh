#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_DIR="${1:-$PROJECT_DIR/dist/MMMonitor.app}"
EXECUTABLE="$APP_DIR/Contents/MacOS/MMMonitor"
ICON_FILE="$APP_DIR/Contents/Resources/AppIcon.icns"

test -d "$APP_DIR"
test -x "$EXECUTABLE"
test -f "$ICON_FILE"
plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP_DIR/Contents/Info.plist")"
test "$ICON_NAME" = "AppIcon.icns"

FILE_DESCRIPTION="$(file "$EXECUTABLE")"
case "$FILE_DESCRIPTION" in
    *arm64*) ;;
    *)
        echo "Expected an arm64 executable, received: $FILE_DESCRIPTION" >&2
        exit 1
        ;;
esac

echo "Verified $APP_DIR"
