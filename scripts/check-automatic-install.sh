#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
probe_dir="$(mktemp -d "${TMPDIR:-/tmp/}happylulu-auto-probe.XXXXXX")"
trap 'rm -rf "$probe_dir"' EXIT
app="$probe_dir/AutoProbe.app"
frameworks="$(pwd)/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
mkdir -p "$app/Contents/MacOS"
swiftc -swift-version 6 -F "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" Sources/AfterSix/AppUpdater.swift Tests/AutomaticInstallProbe/main.swift -o "$app/Contents/MacOS/AutoProbe"
python3 - "$app/Contents/Info.plist" <<'PY'
import plistlib,sys,uuid
info=plistlib.load(open('Resources/Info.plist','rb'))
info.update(CFBundleIdentifier='local.happylulu.auto-probe.'+uuid.uuid4().hex,CFBundleExecutable='AutoProbe')
plistlib.dump(info,open(sys.argv[1],'wb'))
PY
"$app/Contents/MacOS/AutoProbe"
