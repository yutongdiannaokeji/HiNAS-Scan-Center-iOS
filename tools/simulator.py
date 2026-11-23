import json
import argparse
import subprocess
import sys

cli = argparse.ArgumentParser()
cli.add_argument('--family', default='iPhone', choices=('iPhone', 'iPad'))
cli.add_argument('--model-prefix', help='Prefer a simulator whose name starts with this prefix')
cli.add_argument('--major', type=int)
args = cli.parse_args()
state = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))
matching = []
for runtime, devices in state['devices'].items():
    if 'iOS' not in runtime or (args.major and f'iOS-{args.major}-' not in runtime):
        continue
    for device in devices:
        if device['name'].startswith(args.family):
            matching.append(device)
if not matching:
    raise SystemExit(f'No available {args.family} simulator matching iOS {args.major or "any"}')
device = matching[0]
if args.model_prefix:
    device = next((candidate for candidate in matching if candidate['name'].startswith(args.model_prefix)), device)
print(f"Selected {device['name']} ({device['udid']})", file=sys.stderr, flush=True)
if device['state'] != 'Booted':
    subprocess.run(['xcrun', 'simctl', 'boot', device['udid']], check=True)
subprocess.run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b'], check=True, stdout=sys.stderr)
print(device['udid'])

