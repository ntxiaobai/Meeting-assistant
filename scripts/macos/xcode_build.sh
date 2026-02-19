#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/apps/macos/MeetingAssistantMac"
SCHEME="MeetingAssistantMac"
DESTINATION="${MEETING_XCODE_DESTINATION:-platform=macOS}"
USE_RUST="${MEETING_USE_RUST_FFI:-0}"

if [[ ! -f "$PACKAGE_DIR/Package.swift" ]]; then
  echo "Package.swift not found: $PACKAGE_DIR/Package.swift" >&2
  exit 1
fi

if [[ "$USE_RUST" == "1" ]]; then
  LIB_DIR="${MEETING_RUST_FFI_LIB_DIR:-$PACKAGE_DIR/Vendor/meeting_core_ffi/lib}"
  if [[ ! -d "$LIB_DIR" ]]; then
    echo "Rust FFI library directory does not exist: $LIB_DIR" >&2
    echo "Run ./scripts/macos/build_rust_ffi.sh first." >&2
    exit 1
  fi
  echo "Building with Rust FFI: $LIB_DIR"
  (
    cd "$PACKAGE_DIR"
    MEETING_USE_RUST_FFI=1 \
    MEETING_RUST_FFI_LIB_DIR="$LIB_DIR" \
    xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" build
  )
else
  echo "Building in stub mode"
  (
    cd "$PACKAGE_DIR"
    xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" build
  )
fi
