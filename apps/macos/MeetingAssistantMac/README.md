# MeetingAssistantMac (SwiftUI App)

This folder is the macOS SwiftUI front-end skeleton for the dual-frontend architecture:

- macOS: SwiftUI + `meeting_core_ffi` C ABI bridge
- Windows: existing React + Tauri frontend

## Current status

- `CoreBridge` wraps:
  - `ma_runtime_new`
  - `ma_runtime_free`
  - `ma_invoke_json`
  - `ma_set_event_callback`
  - `ma_free_c_string`
- Main window and floating overlay window are connected.
- Main window now includes native settings form sections for:
  - language/theme persistence
  - LLM provider/model/base URL/API format
  - keychain API key save for hint LLM
- Overlay supports:
  - opacity adjustment
  - drag to move
  - reset-to-default position
  - size/position persistence
  - bounds correction back into visible screen area
- Package supports two bridge modes:
  - default: local C stub (`Sources/CMeetingCoreFFI/meeting_core_ffi_stub.c`)
  - Rust mode: set `MEETING_USE_RUST_FFI=1` and link real `meeting_core_ffi`.

## Build prerequisites

Full Xcode is required (`xcodebuild` with full SDK/toolchain), not only Command Line Tools.

## Build Rust FFI artifacts (recommended)

From repo root:

```bash
./scripts/macos/build_rust_ffi.sh
```

This copies headers/libs to:

- `apps/macos/MeetingAssistantMac/Vendor/meeting_core_ffi/include`
- `apps/macos/MeetingAssistantMac/Vendor/meeting_core_ffi/lib`

## Xcode 编译运行（推荐方式）

1. 打开 Swift Package（不是 `.xcodeproj`）  
   - `open apps/macos/MeetingAssistantMac/Package.swift`
2. 在 Xcode 选择 scheme: `MeetingAssistantMac`，destination 选 `My Mac`。  
3. 若要启用真实 Rust FFI，在 Scheme -> Edit Scheme -> Run -> Environment Variables 增加：
   - `MEETING_USE_RUST_FFI=1`
   - `MEETING_RUST_FFI_LIB_DIR=/Users/liuchang/Library/CloudStorage/OneDrive-个人/研究生/其他/meeting_assistant/meeting-assistant/apps/macos/MeetingAssistantMac/Vendor/meeting_core_ffi/lib`
   - （可选）`MEETING_RUST_FFI_STATIC_LIB=/Users/liuchang/Library/CloudStorage/OneDrive-个人/研究生/其他/meeting_assistant/meeting-assistant/apps/macos/MeetingAssistantMac/Vendor/meeting_core_ffi/lib/libmeeting_core_ffi.a`
4. 点击 Run (`Cmd+R`)。

## 命令行编译运行

Stub 模式（默认）：

```bash
swift build --package-path apps/macos/MeetingAssistantMac
swift run --package-path apps/macos/MeetingAssistantMac
```

Rust FFI 模式：

```bash
MEETING_USE_RUST_FFI=1 \
MEETING_RUST_FFI_LIB_DIR=/Users/liuchang/Library/CloudStorage/OneDrive-个人/研究生/其他/meeting_assistant/meeting-assistant/apps/macos/MeetingAssistantMac/Vendor/meeting_core_ffi/lib \
swift build --package-path apps/macos/MeetingAssistantMac
```

## xcodebuild（已实测）

Stub 模式：

```bash
./scripts/macos/xcode_build.sh
```

Rust FFI 模式：

```bash
./scripts/macos/build_rust_ffi.sh
MEETING_USE_RUST_FFI=1 ./scripts/macos/xcode_build.sh
```
