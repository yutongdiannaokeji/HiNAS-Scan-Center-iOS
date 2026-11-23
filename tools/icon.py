"""Generate the app icon with the macOS AppKit system framework through Swift."""
from pathlib import Path
import json
import subprocess

root = Path(__file__).resolve().parents[1]
folder = root/'App/Assets.xcassets/AppIcon.appiconset'
folder.mkdir(parents=True, exist_ok=True)
(folder.parent/'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}))
subprocess.run(['swift', str(root/'tools/icon.swift'), str(folder/'Icon.png')], check=True)
(folder/'Contents.json').write_text(json.dumps({'images': [{'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024', 'filename': 'Icon.png'}], 'info': {'author': 'xcode', 'version': 1}}))

