import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
from zipfile import ZIP_DEFLATED, ZipFile

app, destination = map(Path, sys.argv[1:])
destination.mkdir(exist_ok=True, parents=True)
info = plistlib.loads((app/'Info.plist').read_bytes())
binary = app/info['CFBundleExecutable']
architecture = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).strip()
platform = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(binary)], text=True)
assert architecture == 'arm64' and 'platform IOS\n' in platform, platform
assert not (app/'embedded.mobileprovision').exists()
ipa = destination/'ScanCenter-1.0.0-unsigned.ipa'
with ZipFile(ipa, 'w', ZIP_DEFLATED) as archive:
    for file in sorted(app.rglob('*')):
        if file.is_file():
            archive.write(file, Path('Payload')/app.name/file.relative_to(app))
receipt = {'bundle_id': info['CFBundleIdentifier'], 'architecture': architecture,
           'platform': 'iphoneos', 'signed': False, 'sha256': hashlib.sha256(ipa.read_bytes()).hexdigest()}
(destination/'build.json').write_text(json.dumps(receipt, indent=2)+'\n')
(destination/(ipa.name+'.sha256')).write_text(receipt['sha256']+'  '+ipa.name+'\n')
print(json.dumps(receipt))

