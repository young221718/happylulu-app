#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/happylulu-signing-check.XXXXXX")"
trap 'rm -rf "$probe_dir"' EXIT
for build in 1 2; do
    app="$probe_dir/Build$build.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp /usr/bin/true "$app/Contents/MacOS/Probe"
    python3 - "$app" "$build" <<'PY'
from pathlib import Path
import plistlib,sys
app=Path(sys.argv[1])
plistlib.dump({'CFBundleIdentifier':'local.happylulu.signing-check',
    'CFBundleExecutable':'Probe','CFBundlePackageType':'APPL','CFBundleVersion':sys.argv[2]},
    (app/'Contents/Info.plist').open('wb'))
(app/'Contents/Resources/version.txt').write_text(sys.argv[2])
PY
    if [[ -f scripts/sign-app.sh ]]; then
        bash scripts/sign-app.sh "$app"
    else
        codesign --force --sign - --identifier local.happylulu.signing-check "$app"
    fi
    codesign --verify --deep --strict "$app"
    codesign -d -r- "$app" >"$probe_dir/requirement$build.txt" 2>&1
    sed -E -n 's/^(# )?designated => //p' "$probe_dir/requirement$build.txt" > "$probe_dir/dr$build.txt"
done
if ! cmp -s "$probe_dir/dr1.txt" "$probe_dir/dr2.txt"; then
    printf 'FAIL: different app builds must retain the same certificate identity.\n' >&2
    exit 1
fi
if ! rg -q 'certificate|anchor' "$probe_dir/dr1.txt"; then
    printf 'FAIL: signing must bind a certificate, not only a build hash.\n' >&2
    exit 1
fi
codesign --verify --strict -R "=$(cat "$probe_dir/dr1.txt")" "$probe_dir/Build2.app"
printf 'changed' > "$probe_dir/Build2.app/Contents/Resources/version.txt"
if codesign --verify --deep --strict "$probe_dir/Build2.app" 2>/dev/null; then
    printf 'FAIL: changed sealed resources must be rejected.\n' >&2
    exit 1
fi
before="$(shasum -a 256 "$probe_dir/Build1.app/Contents/MacOS/Probe")"
if HAPPY_LULU_SIGNING_IDENTITY=0000000000000000000000000000000000000000 \
    bash scripts/sign-app.sh "$probe_dir/Build1.app" >/dev/null 2>&1; then
    printf 'FAIL: missing requested identity must not fall back to ad-hoc.\n' >&2
    exit 1
fi
[[ "$before" == "$(shasum -a 256 "$probe_dir/Build1.app/Contents/MacOS/Probe")" ]]
printf 'PASS stable certificate identity across builds, cross-requirement verification, tamper rejection, and missing-identity refusal\n'
