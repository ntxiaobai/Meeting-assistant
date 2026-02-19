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
APP_BUILD_DIR="$BUILD_ROOT/app"
OUTPUT_DIR="$ROOT_DIR/dist"
DMG_NAME="MeetingAssistantMac-${VERSION}-macos.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
ICON_DIR="$PACKAGE_DIR/Sources/MeetingAssistantMac/Resources/Icons"
ICONSET_DIR="$ICON_DIR/MeetingAssistant.iconset"
ICNS_SOURCE_PATH="$ICON_DIR/MeetingAssistant.icns"
BASE_ICON_PNG="$ICON_DIR/app_icon_1024.png"
ICNS_NAME="MeetingAssistant.icns"
ICNS_WORK_PATH="$BUILD_ROOT/$ICNS_NAME"

RUST_LIB_DIR="${MEETING_RUST_FFI_LIB_DIR:-$PACKAGE_DIR/Vendor/meeting_core_ffi/lib}"

ensure_icns() {
  mkdir -p "$BUILD_ROOT"

  if [[ -f "$ICNS_SOURCE_PATH" ]]; then
    cp "$ICNS_SOURCE_PATH" "$ICNS_WORK_PATH"
    return 0
  fi

  if [[ -d "$ICONSET_DIR" ]] && command -v iconutil >/dev/null 2>&1; then
    echo "==> Generating $ICNS_NAME from iconset"
    if iconutil -c icns "$ICONSET_DIR" -o "$ICNS_WORK_PATH" >/dev/null 2>&1; then
      return 0
    fi
  fi

  if [[ -f "$BASE_ICON_PNG" ]] && command -v python3 >/dev/null 2>&1; then
    echo "==> Fallback: generating $ICNS_NAME from app_icon_1024.png via Pillow"
    if python3 - "$BASE_ICON_PNG" "$ICNS_WORK_PATH" <<'PY'
from PIL import Image
import sys
src = sys.argv[1]
dst = sys.argv[2]
img = Image.open(src)
img.save(dst, format="ICNS", sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
PY
    then
      return 0
    fi
  fi

  return 1
}

echo "==> Building Rust FFI artifacts ($TARGET_TRIPLE, release)"
"$ROOT_DIR/scripts/macos/build_rust_ffi.sh" "$TARGET_TRIPLE" release

if [[ ! -d "$RUST_LIB_DIR" ]]; then
  echo "Rust FFI library directory not found: $RUST_LIB_DIR" >&2
  exit 1
fi

echo "==> Building macOS app ($CONFIGURATION)"
if [[ "${MEETING_SKIP_XCODEBUILD:-0}" != "1" ]]; then
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
else
  echo "Skipping xcodebuild (MEETING_SKIP_XCODEBUILD=1)"
fi

PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$CONFIGURATION"
APP_PATH="$PRODUCTS_DIR/$SCHEME.app"
EXECUTABLE_PATH="$PRODUCTS_DIR/$SCHEME"
RESOURCE_BUNDLE_PATH="$PRODUCTS_DIR/${SCHEME}_${SCHEME}.bundle"
PACKAGE_FRAMEWORKS_DIR="$PRODUCTS_DIR/PackageFrameworks"
HAVE_ICNS=0

if [[ ! -d "$APP_PATH" ]]; then
  APP_PATH="$(find "$DERIVED_DATA/Build/Products" -maxdepth 3 -type d -name "$SCHEME.app" | head -n 1 || true)"
fi

if ensure_icns; then
  HAVE_ICNS=1
fi

# Swift Package executable targets may output only a binary.
# In that case, assemble a minimal .app bundle for DMG distribution.
if [[ -z "${APP_PATH:-}" || ! -d "$APP_PATH" ]]; then
  if [[ ! -f "$EXECUTABLE_PATH" ]]; then
    echo "Built app/executable not found under: $DERIVED_DATA/Build/Products" >&2
    exit 1
  fi

  APP_PATH="$APP_BUILD_DIR/$SCHEME.app"
  APP_CONTENTS="$APP_PATH/Contents"
  APP_MACOS="$APP_CONTENTS/MacOS"
  APP_RESOURCES="$APP_CONTENTS/Resources"
  APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"

  echo "==> Assembling .app bundle from executable output"
  rm -rf "$APP_PATH"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$EXECUTABLE_PATH" "$APP_MACOS/$SCHEME"
  chmod +x "$APP_MACOS/$SCHEME"

  if [[ -d "$RESOURCE_BUNDLE_PATH" ]]; then
    cp -R "$RESOURCE_BUNDLE_PATH" "$APP_RESOURCES/"
  fi

  if [[ -d "$PACKAGE_FRAMEWORKS_DIR" ]]; then
    mkdir -p "$APP_FRAMEWORKS"
    cp -R "$PACKAGE_FRAMEWORKS_DIR/." "$APP_FRAMEWORKS/" || true
  fi

  if [[ "$HAVE_ICNS" == "1" ]]; then
    cp "$ICNS_WORK_PATH" "$APP_RESOURCES/$ICNS_NAME"
  fi

  cat > "$APP_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$SCHEME</string>
  <key>CFBundleIdentifier</key>
  <string>com.meetingassistant.mac</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$SCHEME</string>
  <key>CFBundleIconFile</key>
  <string>$ICNS_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST
fi

# If xcodebuild already produced an .app, still inject icon if missing.
if [[ -d "$APP_PATH" ]] && [[ "$HAVE_ICNS" == "1" ]]; then
  APP_RESOURCES="$APP_PATH/Contents/Resources"
  APP_INFO_PLIST="$APP_PATH/Contents/Info.plist"
  mkdir -p "$APP_RESOURCES"
  cp "$ICNS_WORK_PATH" "$APP_RESOURCES/$ICNS_NAME"
  if [[ -f "$APP_INFO_PLIST" ]] && ! /usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$APP_INFO_PLIST" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string $ICNS_NAME" "$APP_INFO_PLIST" || true
  fi
fi

echo "==> Preparing DMG staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$OUTPUT_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
rm -f "$STAGING_DIR/Applications"
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
