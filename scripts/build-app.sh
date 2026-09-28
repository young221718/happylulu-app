#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
swift build --build-system native -c release --product HappyLulu
binary_dir="$(swift build --build-system native -c release --show-bin-path)"
app_dir="$project_dir/dist/HappyLulu.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/HappyLulu" "$app_dir/Contents/MacOS/HappyLulu"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
swift scripts/make-icon.swift "$project_dir/Resources/HappyLuluIcon.png" "$project_dir/.build/HappyLulu.iconset"
iconutil -c icns "$project_dir/.build/HappyLulu.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier local.chanyoung.AfterSix "$app_dir"
codesign --verify --deep --strict "$app_dir"
printf 'Built: %s\n' "$app_dir"
