# MeetingAssistantMac (SwiftUI)

macOS native app for Meeting Assistant.

## What this package contains
- `MeetingAssistantMac`: SwiftUI executable target
- `CoreBridge`: Swift wrapper for C ABI functions
- `CMeetingCoreFFI`: C target with two modes:
  - Stub mode (default): local C stub implementation
  - Rust FFI mode: link real `meeting_core_ffi` artifacts

## Prerequisites
- macOS 14+
- Full Xcode installation
- Rust toolchain (only required for Rust FFI mode)

## Build Rust FFI artifacts
From repository root:

```bash
./scripts/macos/build_rust_ffi.sh
```

Artifacts are copied to:
- `apps/macos/MeetingAssistantMac/Vendor/meeting_core_ffi/include`
- `apps/macos/MeetingAssistantMac/Vendor/meeting_core_ffi/lib`

## Build and run

### Stub mode (default)
```bash
swift build --package-path apps/macos/MeetingAssistantMac
swift run --package-path apps/macos/MeetingAssistantMac
```

### Rust FFI mode
```bash
MEETING_USE_RUST_FFI=1 \
MEETING_RUST_FFI_LIB_DIR="$(pwd)/apps/macos/MeetingAssistantMac/Vendor/meeting_core_ffi/lib" \
swift build --package-path apps/macos/MeetingAssistantMac
```

## Xcode usage
1. Open package:
   ```bash
   open apps/macos/MeetingAssistantMac/Package.swift
   ```
2. Select scheme `MeetingAssistantMac`, destination `My Mac`.
3. Optional (Rust FFI mode): add env vars in Run scheme:
   - `MEETING_USE_RUST_FFI=1`
   - `MEETING_RUST_FFI_LIB_DIR=$(pwd)/apps/macos/MeetingAssistantMac/Vendor/meeting_core_ffi/lib`

## xcodebuild scripts
- Stub mode:
  ```bash
  ./scripts/macos/xcode_build.sh
  ```
- Rust FFI mode:
  ```bash
  ./scripts/macos/build_rust_ffi.sh
  MEETING_USE_RUST_FFI=1 ./scripts/macos/xcode_build.sh
  ```

## Build DMG (drag-and-drop install)
From repository root:

```bash
./scripts/macos/build_dmg.sh v0.1.1
```

Output files:
- `dist/MeetingAssistantMac-v0.1.1-macos.dmg`
- `dist/MeetingAssistantMac-v0.1.1-macos.dmg.sha256`
