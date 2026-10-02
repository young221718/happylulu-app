#!/bin/bash
# Produces a signed, data-free update feed locally. Does not publish it.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
archive="${1:?Pass a packaged Universal HappyLulu ZIP}"
updates_dir="${2:-$project_dir/dist/updates}"
tools_dir="$project_dir/.build/artifacts/sparkle/Sparkle/bin"
if [[ ! -x "$tools_dir/generate_appcast" ]]; then
  printf 'Sparkle tools missing; run swift package resolve first.\n' >&2
  exit 1
fi
feed_url="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' Resources/Info.plist)"
case "$feed_url" in https://*/appcast.xml) ;; *) printf 'Expected an HTTPS appcast URL.\n' >&2; exit 1;; esac
mkdir -p "$updates_dir"
filename="$(basename "$archive")"
case "$filename" in HappyLulu-*-universal.zip) ;; *) printf 'Expected a Universal release archive.\n' >&2; exit 1;; esac
if [[ -e "$updates_dir/$filename" ]]; then
  cmp "$archive" "$updates_dir/$filename"
else
  cp "$archive" "$updates_dir/$filename"
fi
cp RELEASE-NOTES.md "$updates_dir/${filename%.zip}.md"
"$tools_dir/generate_appcast" --account happylulu-updates \
  --download-url-prefix "${feed_url%appcast.xml}" \
  --release-notes-url-prefix "${feed_url%appcast.xml}" \
  --maximum-deltas 0 "$updates_dir"
printf 'Signed update files: %s\n' "$updates_dir"
