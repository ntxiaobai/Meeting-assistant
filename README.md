# Meeting Assistant (macOS)

> A macOS-only meeting assistant built with SwiftUI + Rust FFI.

## 中文说明

### 1. 项目简介
Meeting Assistant 是一个 macOS 单平台桌面应用，采用：
- SwiftUI（原生 UI）
- Rust `meeting_core` + `meeting_core_ffi`（核心能力与 FFI）

当前仓库已经移除旧的 Tauri/React 实现，主分支仅保留 macOS 版本。

### 2. 目录结构
```text
apps/macos/MeetingAssistantMac     # SwiftUI 应用
crates/meeting_core                # Rust 核心逻辑
crates/meeting_core_ffi            # Rust FFI 导出层
scripts/macos                      # 构建与辅助脚本
```

### 3. 环境要求
- macOS 14+
- Xcode（完整安装，含 `xcodebuild`）
- Rust stable（`rustup` + `cargo`）

### 4. 快速开始
#### 4.1 Stub 模式（默认）
```bash
swift build --package-path apps/macos/MeetingAssistantMac
swift run --package-path apps/macos/MeetingAssistantMac
```

#### 4.2 Rust FFI 模式（推荐）
```bash
./scripts/macos/build_rust_ffi.sh
MEETING_USE_RUST_FFI=1 \
MEETING_RUST_FFI_LIB_DIR="$(pwd)/apps/macos/MeetingAssistantMac/Vendor/meeting_core_ffi/lib" \
swift build --package-path apps/macos/MeetingAssistantMac
```

### 5. 常用脚本
- `./scripts/macos/build_rust_ffi.sh`：构建并复制 Rust FFI 产物到 Vendor
- `./scripts/macos/xcode_build.sh`：使用 `xcodebuild` 构建 Swift 包
- `./scripts/macos/open_in_xcode.sh`：直接打开 `Package.swift`
- `./scripts/macos/build_iconset.sh`：从源图生成 iconset/icns

### 6. 环境变量
- `MEETING_USE_RUST_FFI=1`：启用 Rust FFI 链接
- `MEETING_RUST_FFI_LIB_DIR`：Rust FFI 库目录
- `MEETING_RUST_FFI_STATIC_LIB`：可选，指定静态库完整路径
- `MEETING_XCODE_DESTINATION`：可选，覆盖 `xcodebuild` destination

### 7. 常见问题
- `xcodebuild: command not found`：请安装完整 Xcode，而非仅 Command Line Tools。
- Rust FFI 模式链接失败：先执行 `./scripts/macos/build_rust_ffi.sh`，并检查 `MEETING_RUST_FFI_LIB_DIR` 是否正确。

---

## English Guide

### 1. Overview
Meeting Assistant is now a **macOS-only** desktop app built with:
- SwiftUI for native UI
- Rust `meeting_core` + `meeting_core_ffi` for core logic and FFI bridge

Legacy Tauri/React implementation has been removed from `main`.

### 2. Project Layout
```text
apps/macos/MeetingAssistantMac     # SwiftUI app
crates/meeting_core                # Rust core
crates/meeting_core_ffi            # Rust FFI layer
scripts/macos                      # Build/helper scripts
```

### 3. Prerequisites
- macOS 14+
- Full Xcode installation (`xcodebuild` available)
- Rust stable toolchain (`rustup`, `cargo`)

### 4. Quick Start
#### 4.1 Stub mode (default)
```bash
swift build --package-path apps/macos/MeetingAssistantMac
swift run --package-path apps/macos/MeetingAssistantMac
```

#### 4.2 Rust FFI mode (recommended)
```bash
./scripts/macos/build_rust_ffi.sh
MEETING_USE_RUST_FFI=1 \
MEETING_RUST_FFI_LIB_DIR="$(pwd)/apps/macos/MeetingAssistantMac/Vendor/meeting_core_ffi/lib" \
swift build --package-path apps/macos/MeetingAssistantMac
```

### 5. Useful Scripts
- `./scripts/macos/build_rust_ffi.sh`: build and copy Rust FFI artifacts
- `./scripts/macos/xcode_build.sh`: build via `xcodebuild`
- `./scripts/macos/open_in_xcode.sh`: open `Package.swift` in Xcode
- `./scripts/macos/build_iconset.sh`: generate iconset/icns from source image

### 6. Environment Variables
- `MEETING_USE_RUST_FFI=1`: enable Rust FFI link mode
- `MEETING_RUST_FFI_LIB_DIR`: directory containing Rust FFI libraries
- `MEETING_RUST_FFI_STATIC_LIB`: optional full path to static library
- `MEETING_XCODE_DESTINATION`: optional `xcodebuild` destination override

### 7. Troubleshooting
- `xcodebuild: command not found`: install full Xcode, not only CLI tools.
- Rust FFI linking issues: run `./scripts/macos/build_rust_ffi.sh` first and verify `MEETING_RUST_FFI_LIB_DIR`.
