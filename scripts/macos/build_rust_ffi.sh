#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_TRIPLE="${1:-$(rustc -vV | awk '/host:/ {print $2}')}"
PROFILE="${2:-release}"

if [[ "${PROFILE}" != "release" && "${PROFILE}" != "debug" ]]; then
  echo "PROFILE must be release or debug"
  exit 1
fi

echo "Building meeting_core_ffi (${PROFILE}) for ${TARGET_TRIPLE}..."
cargo build -p meeting_core_ffi --target "${TARGET_TRIPLE}" $([[ "${PROFILE}" == "release" ]] && echo --release)

ARTIFACT_DIR="${ROOT_DIR}/target/${TARGET_TRIPLE}/${PROFILE}"
VENDOR_DIR="${ROOT_DIR}/apps/macos/MeetingAssistantMac/Vendor/meeting_core_ffi"
mkdir -p "${VENDOR_DIR}/lib" "${VENDOR_DIR}/include"

cp "${ROOT_DIR}/crates/meeting_core_ffi/include/meeting_core_ffi.h" "${VENDOR_DIR}/include/meeting_core_ffi.h"

if [[ -f "${ARTIFACT_DIR}/libmeeting_core_ffi.a" ]]; then
  cp "${ARTIFACT_DIR}/libmeeting_core_ffi.a" "${VENDOR_DIR}/lib/libmeeting_core_ffi.a"
  echo "Copied static lib: ${VENDOR_DIR}/lib/libmeeting_core_ffi.a"
fi

if [[ -f "${ARTIFACT_DIR}/libmeeting_core_ffi.dylib" ]]; then
  cp "${ARTIFACT_DIR}/libmeeting_core_ffi.dylib" "${VENDOR_DIR}/lib/libmeeting_core_ffi.dylib"
  echo "Copied dylib: ${VENDOR_DIR}/lib/libmeeting_core_ffi.dylib"
fi

echo "Done."
echo "Next, build SwiftUI app with:"
echo "MEETING_USE_RUST_FFI=1 MEETING_RUST_FFI_LIB_DIR=${VENDOR_DIR}/lib swift build --package-path ${ROOT_DIR}/apps/macos/MeetingAssistantMac"

