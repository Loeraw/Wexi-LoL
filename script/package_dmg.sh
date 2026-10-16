#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/script/build_and_run.sh"
BUNDLE="$ROOT_DIR/dist/Wexi LoL.app"

"$BUILD_SCRIPT" --build-only
codesign --verify --deep --strict --verbose=2 "$BUNDLE"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUNDLE/Contents/Info.plist")"
DMG_PATH="$ROOT_DIR/dist/Wexi LoL-$VERSION.dmg"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/wexilol-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

ditto "$BUNDLE" "$STAGING/Wexi LoL.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create -quiet -volname "Wexi LoL $VERSION" \
    -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
hdiutil verify "$DMG_PATH"

echo "Created: $DMG_PATH"
