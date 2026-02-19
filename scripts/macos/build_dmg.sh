#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/apps/macos/MeetingAssistantMac"
SCHEME="MeetingAssistantMac"
CONFIGURATION="${MEETING_XCODE_CONFIGURATION:-Release}"
DESTINATION="${MEETING_XCODE_DESTINATION:-platform=macOS}"
VOLUME_NAME="${MEETING_DMG_VOLUME_NAME:-Meeting Assistant}"

VERSION="${1:-$(git -C "$ROOT_DIR" describe --tags --always 2>/dev/null || echo dev)}"
TARGET_TRIPLE="${2:-$(rustc -vV | awk '/host:/ {print $2}')}"

BUILD_ROOT="$ROOT_DIR/build/dmg"
DERIVED_DATA="$BUILD_ROOT/derivedData"
STAGING_DIR="$BUILD_ROOT/staging"
OUTPUT_DIR="$ROOT_DIR/dist"
DMG_NAME="MeetingAssistantMac-${VERSION}-macos.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

RUST_LIB_DIR="${MEETING_RUST_FFI_LIB_DIR:-$PACKAGE_DIR/Vendor/meeting_core_ffi/lib}"

echo "==> Building Rust FFI artifacts ($TARGET_TRIPLE, release)"
"$ROOT_DIR/scripts/macos/build_rust_ffi.sh" "$TARGET_TRIPLE" release

if [[ ! -d "$RUST_LIB_DIR" ]]; then
  echo "Rust FFI library directory not found: $RUST_LIB_DIR" >&2
  exit 1
fi

echo "==> Building macOS app ($CONFIGURATION)"
(
  cd "$PACKAGE_DIR"
  xcodebuild -list >/dev/null
  MEETING_USE_RUST_FFI=1 \
  MEETING_RUST_FFI_LIB_DIR="$RUST_LIB_DIR" \
  xcodebuild \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    build
)

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$SCHEME.app"
if [[ ! -d "$APP_PATH" ]]; then
  APP_PATH="$(find "$DERIVED_DATA/Build/Products" -maxdepth 3 -type d -name "$SCHEME.app" | head -n 1 || true)"
fi

if [[ -z "${APP_PATH:-}" || ! -d "$APP_PATH" ]]; then
  echo "Built app not found under: $DERIVED_DATA/Build/Products" >&2
  exit 1
fi

echo "==> Preparing DMG staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$OUTPUT_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating DMG: $DMG_PATH"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"

echo "==> Done"
echo "DMG: $DMG_PATH"
echo "SHA256: $DMG_PATH.sha256"
