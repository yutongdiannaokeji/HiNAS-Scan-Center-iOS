import json
import argparse
import subprocess
import sys

cli = argparse.ArgumentParser()
cli.add_argument('--family', default='iPhone', choices=('iPhone', 'iPad'))
cli.add_argument('--major', type=int)
args = cli.parse_args()
state = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))
for runtime, devices in state['devices'].items():
    if 'iOS' not in runtime or (args.major and f'iOS-{args.major}-' not in runtime):
        continue
    for device in devices:
        if device['name'].startswith(args.family):
            if device['state'] != 'Booted':
                subprocess.run(['xcrun', 'simctl', 'boot', device['udid']], check=True)
            subprocess.run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b'], check=True, stdout=sys.stderr)
            print(device['udid'])
            raise SystemExit(0)
raise SystemExit(f'No available {args.family} simulator matching iOS {args.major or "any"}')

