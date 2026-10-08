#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --build-system native --target CalendarSyncServices >/dev/null
build_dir="$(swift build --build-system native --show-bin-path)"
probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/HappyLulu-runtime-check.XXXXXX")"
trap 'rm -rf "$probe_dir"' EXIT
swiftc -parse-as-library -swift-version 6 -I "$build_dir/Modules" \
  Sources/AfterSix/CalendarSyncRuntimeChecks.swift Tests/CalendarRuntimeProbe/main.swift \
  "$build_dir"/CalendarSyncCore.build/*.swift.o \
  "$build_dir"/CalendarSyncServices.build/*.swift.o \
  -framework AppKit -framework EventKit -framework Security -lsqlite3 -o "$probe_dir/check"
"$probe_dir/check"
