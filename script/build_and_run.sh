#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
case "$MODE" in run|--verify|--build-only|--debug|--logs|--telemetry) ;; *) echo "Usage: $0 [--verify|--build-only|--debug|--logs|--telemetry]"; exit 2 ;; esac
if [[ "$MODE" != "--build-only" ]]; then
    pkill -x RiftOverlay >/dev/null 2>&1 || true
    pkill -x WexiLoL >/dev/null 2>&1 || true
fi
mkdir -p .build/module-cache .build/clang-cache
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-cache"
swift build --disable-sandbox -Xswiftc -module-cache-path -Xswiftc "$ROOT_DIR/.build/module-cache"
BIN_DIR="$(swift build --disable-sandbox --show-bin-path)"
BUNDLE="$ROOT_DIR/dist/Wexi LoL.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_DIR/WexiLoL" "$BUNDLE/Contents/MacOS/WexiLoL"
for RESOURCE in "$BIN_DIR"/*.bundle; do
    [[ -d "$RESOURCE" ]] || continue
    ditto "$RESOURCE" "$BUNDLE/Contents/Resources/$(basename "$RESOURCE")"
done
ICON_SOURCE="$ROOT_DIR/Assets/Wexi-AppIcon.png"
if [[ -f "$ICON_SOURCE" ]]; then
    ICONSET="$ROOT_DIR/.build/WexiLoL.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    for SPEC in "16 icon_16x16.png" "32 icon_16x16@2x.png" \
                "32 icon_32x32.png" "64 icon_32x32@2x.png" \
                "128 icon_128x128.png" "256 icon_128x128@2x.png" \
                "256 icon_256x256.png" "512 icon_256x256@2x.png" \
                "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
        read -r SIZE NAME <<< "$SPEC"
        sips -z "$SIZE" "$SIZE" "$ICON_SOURCE" --out "$ICONSET/$NAME" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/WexiLoL.icns"
fi
cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>WexiLoL</string>
<key>CFBundleIdentifier</key><string>dev.local.wexilol</string>
<key>CFBundleName</key><string>Wexi LoL</string>
<key>CFBundleDisplayName</key><string>Wexi LoL</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>WexiLoL</string>
<key>CFBundleShortVersionString</key><string>0.5.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSUIElement</key><false/>
<key>NSHighResolutionCapable</key><true/>
<key>NSScreenCaptureUsageDescription</key><string>Wexi LoL 只读取英雄联盟游戏窗口，用于识别海克斯选择和技能加点；不会保存或上传画面。</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
# Keep the designated requirement stable across local rebuilds. Without this,
# ad-hoc signing defaults to a changing cdhash and macOS treats every build as
# a different Screen Recording client.
codesign --force --deep --sign - --requirements '=designated => identifier "dev.local.wexilol"' "$BUNDLE"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then "$LSREGISTER" -f "$BUNDLE"; fi
case "$MODE" in
    --build-only) echo "Built: $BUNDLE" ;;
    --debug) lldb -- "$BUNDLE/Contents/MacOS/WexiLoL" ;;
    --logs|--telemetry)
        open -n "$BUNDLE"
        /usr/bin/log stream --info --style compact --predicate 'process == "WexiLoL"' ;;
    --verify)
        open -n "$BUNDLE"
        sleep 2
        pgrep -x WexiLoL >/dev/null
        echo "WexiLoL is running." ;;
    run) open -n "$BUNDLE" ;;
esac
