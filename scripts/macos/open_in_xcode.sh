#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
open "${ROOT_DIR}/apps/macos/MeetingAssistantMac/Package.swift"

