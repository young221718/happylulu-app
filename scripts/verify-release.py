"""Verify Mac release metadata, localized resources, signatures and archive bytes."""
import hashlib
import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile
root = Path(__file__).resolve().parent.parent
release = Path(sys.argv[1]).resolve()
info = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
app = release / 'HappyLulu.app'
assert (app / 'Contents/Info.plist').read_bytes() == (root / 'Resources/Info.plist').read_bytes()
assert (release / 'RELEASE-NOTES.md').read_bytes() == (root / 'RELEASE-NOTES.md').read_bytes()
for language in ('ko', 'en'):
    assert (app / f'Contents/Resources/{language}.lproj/InfoPlist.strings').read_bytes() == (root / f'Resources/{language}.lproj/InfoPlist.strings').read_bytes()
assert set(subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS/HappyLulu')], text=True).split()) == {'arm64', 'x86_64'}
for line in (release / 'SHA256SUMS.txt').read_text().splitlines():
    digest, name = line.split(None, 1)
    assert hashlib.sha256((release / name.strip()).read_bytes()).hexdigest() == digest

def manifest(bundle):
    result = {}
    for entry in bundle.rglob('*'):
        key = str(entry.relative_to(bundle))
        if entry.is_symlink():
            result[key] = ('link', str(entry.readlink()))
        elif entry.is_file():
            result[key] = ('file', hashlib.sha256(entry.read_bytes()).hexdigest())
    return result
expected = manifest(app)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
with tempfile.TemporaryDirectory(prefix='verify-release-', dir=root / 'dist') as temporary:
    temporary = Path(temporary)
    extracted = temporary / 'zip'
    subprocess.run(['ditto', '-x', '-k', str(release / f'HappyLulu-{version}-universal.zip'), str(extracted)], check=True)
    zipped = extracted / 'HappyLulu.app'
    assert manifest(zipped) == expected, 'ZIP differs'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(zipped)], check=True)
    mount = temporary / 'dmg'
    mount.mkdir()
    subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(release / f'HappyLulu-{version}-universal.dmg')], check=True, stdout=subprocess.DEVNULL)
    try:
        mounted = mount / 'HappyLulu.app'
        assert manifest(mounted) == expected, 'DMG differs'
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(mounted)], check=True)
    finally:
        subprocess.run(['hdiutil', 'detach', str(mount)], check=True, stdout=subprocess.DEVNULL)
print(f'Mac {version} build {info["CFBundleVersion"]}: metadata, languages, Universal architectures, hashes, ZIP/DMG files and symlinks, signatures verified.')
