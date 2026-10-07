#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
probe_dir="$(mktemp -d "${TMPDIR:-/tmp/}happylulu-login-probe.XXXXXX")"
trap 'rm -rf "$probe_dir"' EXIT
app="$probe_dir/LoginProbe.app"
mkdir -p "$app/Contents/MacOS"
swiftc -swift-version 6 Sources/MacLaunchSupport/LoginLaunch.swift Tests/LoginLaunchProbe/main.swift -o "$app/Contents/MacOS/LoginProbe"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LoginProbe</string>
<key>CFBundleIdentifier</key><string>local.happylulu.disposable-login-probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
for kind in manual login service; do
    result="$probe_dir/$kind.txt"
    "$app/Contents/MacOS/LoginProbe" --launch "$app" "$result" "$kind"
    for attempt in {1..50}; do
        [ -f "$result" ] && break
        sleep 0.1
    done
    expected=false
    [ "$kind" = login ] && expected=true
    [ -f "$result" ] && [ "$(cat "$result")" = "$expected" ] || { echo "FAIL launch lifecycle: $kind"; exit 1; }
    echo "PASS AppKit will/didFinishLaunching: $kind -> $expected"
done
