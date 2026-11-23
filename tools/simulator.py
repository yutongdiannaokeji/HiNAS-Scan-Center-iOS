import json
import subprocess
import sys

state = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))
for runtime, devices in state['devices'].items():
    if 'iOS' not in runtime:
        continue
    for device in devices:
        if device['name'].startswith('iPhone'):
            if device['state'] != 'Booted':
                subprocess.run(['xcrun', 'simctl', 'boot', device['udid']], check=True)
            subprocess.run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b'], check=True, stdout=sys.stderr)
            print(device['udid'])
            raise SystemExit(0)
raise SystemExit('No available iPhone simulator')

