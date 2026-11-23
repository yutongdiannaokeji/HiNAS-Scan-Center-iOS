import json
from pathlib import Path
import re
import shutil
import sys

family = sys.argv[1]
assert family in ('iPhone', 'iPad')
folder = Path('dist/attachments')
names = {'scan': '', 'documents': '-1', 'print': '-2', 'device': '-3', 'dark': '-dark', 'large-type': '-large-type'}
found = set()


def records(value):
    if isinstance(value, dict):
        yield value
        for nested in value.values():
            yield from records(nested)
    elif isinstance(value, list):
        for nested in value:
            yield from records(nested)


for manifest in folder.rglob('*.json'):
    for item in records(json.loads(manifest.read_text())):
        strings = [v for v in item.values() if isinstance(v, str)]
        label = next((re.search(r'scan-center-(scan|documents|print|device|dark|large-type)', v) for v in strings if 'scan-center-' in v), None)
        if not label:
            continue
        filename = item.get('exportedFileName') or item.get('filename')
        if not isinstance(filename, str):
            continue
        source = folder / filename
        if source.suffix.lower() != '.png' or not source.is_file():
            continue
        key = label.group(1)
        shutil.copyfile(source, Path('dist') / (family + names[key] + '.png'))
        found.add(key)
if found != set(names):
    raise SystemExit('Missing verified UI screenshots: ' + ', '.join(sorted(set(names) - found)))
print(f'{family}: verified all six visible-screen screenshots.')
