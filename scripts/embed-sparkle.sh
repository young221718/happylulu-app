#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="${1:?Pass the app bundle path}"
scratch_dir="${2:-$project_dir/.build}"
framework="$scratch_dir/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$framework" ]]; then
  printf 'Sparkle framework missing; resolve package dependencies first.\n' >&2
  exit 1
fi
mkdir -p "$app_dir/Contents/Frameworks"
ditto "$framework" "$app_dir/Contents/Frameworks/Sparkle.framework"
# Preserve Sparkle's existing nested signatures and versioned symlinks.
codesign --verify --deep --strict "$app_dir/Contents/Frameworks/Sparkle.framework"
