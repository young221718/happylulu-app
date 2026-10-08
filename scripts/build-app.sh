#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
swift build --build-system native -c release --product HappyLulu --disable-local-rpath
binary_dir="$(swift build --build-system native -c release --show-bin-path)"
app_dir="$project_dir/dist/HappyLulu.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/HappyLulu" "$app_dir/Contents/MacOS/HappyLulu"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
for language in ko en; do
    mkdir -p "$app_dir/Contents/Resources/$language.lproj"
    cp "Resources/$language.lproj/InfoPlist.strings" "$app_dir/Contents/Resources/$language.lproj/InfoPlist.strings"
done
bash scripts/embed-sparkle.sh "$app_dir"
swift scripts/make-icon.swift "$project_dir/Resources/HappyLuluIcon.png" "$project_dir/.build/HappyLulu.iconset"
iconutil -c icns "$project_dir/.build/HappyLulu.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
bash scripts/sign-app.sh "$app_dir"
printf 'Built: %s\n' "$app_dir"
