#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Resources/Info.plist")"
ARCHIVE="$PROJECT_DIR/dist/MMMonitor-$VERSION-arm64.zip"
ARCHIVE_NAME="${ARCHIVE:t}"

"$PROJECT_DIR/scripts/verify-history.sh"
"$PROJECT_DIR/scripts/build-app.sh"
"$PROJECT_DIR/scripts/verify-app.sh"

rm -f "$ARCHIVE" "$ARCHIVE.sha256"
ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl \
    "$PROJECT_DIR/dist/MMMonitor.app" "$ARCHIVE"
unzip -tqq "$ARCHIVE"

(
    cd "$PROJECT_DIR/dist"
    shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
    shasum -a 256 -c "$ARCHIVE_NAME.sha256"
)

echo "$ARCHIVE"
echo "$ARCHIVE.sha256"
