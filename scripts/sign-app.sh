#!/bin/bash
# Local signing only; this does not notarize or publish an application.
set -euo pipefail
app="${1:?Pass an app bundle}"
identity="$(python3 - <<'PY'
from pathlib import Path
import hashlib,json,os,re,sys
record=Path.home()/'Library/Application Support/HappyLulu/Signing/identity.json'
if 'HAPPY_LULU_SIGNING_IDENTITY' in os.environ:
    identity=os.environ['HAPPY_LULU_SIGNING_IDENTITY']
elif record.exists():
    data=json.loads(record.read_text())
    identity=data['sha1']
    certificate=Path(data['certificate'])
    if hashlib.sha1(certificate.read_bytes()).hexdigest().upper()!=identity.upper():
        sys.exit('Configured signing certificate fingerprint differs; refusing fallback')
else:
    identity='-'
if identity!='-' and re.fullmatch(r'[A-Fa-f0-9]{40}',identity) is None:
    sys.exit('Set HAPPY_LULU_SIGNING_IDENTITY to a certificate SHA-1 or explicit - for ad-hoc')
print(identity)
PY
)"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
codesign --force --sign "$identity" --timestamp=none --identifier "$bundle_id" "$app"
codesign --verify --deep --strict "$app"
if [[ "$identity" == "-" ]]; then
    printf 'Signing: ad-hoc; update-to-update app identity is not stable.\n'
else
    printf 'Signing: fixed certificate %s; Apple notarization not performed.\n' "$identity"
fi
