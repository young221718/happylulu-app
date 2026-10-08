#!/bin/bash
# Local signing only. Does not create tags, releases, or upload assets.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
test -z "$(git status --porcelain)" || { printf 'Commit the reviewed source before preparing a release.\n' >&2; exit 1; }
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
release_dir="$project_dir/dist/releases/$version-build$build"
# This explicit operator command may ask for local keychain approval.
bash scripts/check-code-signing.sh
bash scripts/package-release.sh
bash scripts/generate-update-feed.sh "$release_dir/HappyLulu-$version-universal.zip"
python3 scripts/release_delivery.py stage "$release_dir"
printf 'Prepared locally; no release was published.\n'
