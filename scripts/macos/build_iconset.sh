#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ICON_DIR="$ROOT_DIR/apps/macos/MeetingAssistantMac/Sources/MeetingAssistantMac/Resources/Icons"
BASE_PNG="$ICON_DIR/app_icon_1024.png"
ICONSET_DIR="$ICON_DIR/MeetingAssistant.iconset"
ICNS_PATH="$ICON_DIR/MeetingAssistant.icns"

python3 "$ROOT_DIR/scripts/macos/generate_app_icon.py" --out "$BASE_PNG" --size 1024

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

sips -z 16 16 "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$BASE_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

if iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"; then
  echo "Generated iconset and icns:"
  echo "  $ICONSET_DIR"
  echo "  $ICNS_PATH"
else
  echo "iconutil failed to pack icns, but icon PNG/iconset have been generated:"
  echo "  $ICON_DIR/app_icon_1024.png"
  echo "  $ICONSET_DIR"
fi
