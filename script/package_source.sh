#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="0.5.3"
PACKAGE_NAME="Wexi-LoL-source-$VERSION"
OUTPUT="$ROOT_DIR/dist/$PACKAGE_NAME.zip"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/wexilol-source.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$ROOT_DIR/dist" "$STAGING/$PACKAGE_NAME/script"
for ITEM in App Assets Tests docs Package.swift README.md LICENSE .gitignore; do
    ditto "$ROOT_DIR/$ITEM" "$STAGING/$PACKAGE_NAME/$ITEM"
done
for SCRIPT in build_and_run.sh package_dmg.sh package_source.sh; do
    ditto "$ROOT_DIR/script/$SCRIPT" "$STAGING/$PACKAGE_NAME/script/$SCRIPT"
done

rm -f "$OUTPUT"
(
    cd "$STAGING"
    COPYFILE_DISABLE=1 /usr/bin/zip -q -r -X "$OUTPUT" "$PACKAGE_NAME"
)

echo "Created: $OUTPUT"
