"""Use the locally configured Git credential helper. Never print credentials."""
import argparse
import json
from pathlib import Path
import subprocess
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
import os

cli = argparse.ArgumentParser()
cli.add_argument('method', choices=('GET', 'POST', 'PATCH'))
cli.add_argument('path')
cli.add_argument('--json')
cli.add_argument('--output', type=Path)
args = cli.parse_args()
env = dict(os.environ, GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='never')
credential = subprocess.run(['git', 'credential', 'fill'], input='protocol=https\nhost=github.com\n\n',
                            capture_output=True, text=True, timeout=30, env=env)
fields = dict(line.split('=', 1) for line in credential.stdout.splitlines() if '=' in line)
token = fields.get('password')
if not token:
    raise SystemExit('A GitHub credential is required in the system credential manager.')
if not args.path.startswith('/') or args.path.startswith('//'):
    raise SystemExit('Expected a GitHub API path.')
body = Path(args.json).read_bytes() if args.json else None
request = Request('https://api.github.com'+args.path, data=body, method=args.method, headers={
    'Authorization': 'Bearer '+token, 'Accept': 'application/vnd.github+json',
    'Content-Type': 'application/json', 'User-Agent': 'HiNAS-ScanCenter-build'})
class ArtifactRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if redirected and urlsplit(newurl).hostname != 'api.github.com':
            redirected.remove_header('Authorization')
        return redirected

try:
    with build_opener(ArtifactRedirect()).open(request, timeout=45) as response:
        data = response.read()
except HTTPError as error:
    print('GitHub HTTP', error.code)
    print(error.read(1500).decode())
    raise SystemExit(1)
if args.output:
    args.output.parent.mkdir(exist_ok=True, parents=True)
    args.output.write_bytes(data)
    print('Saved', args.output)
else:
    print(data.decode())
