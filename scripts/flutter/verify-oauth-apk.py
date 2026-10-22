"""Verify the shipped APK actually embeds the configured public Google client ID."""
import json
import re
import sys
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[2]
client = json.loads((root / 'universal/config/google-oauth.json').read_text())['GOOGLE_WEB_CLIENT_ID']
if not re.fullmatch(r'[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com', client):
    raise SystemExit('Missing or malformed public Google Web client ID')
with zipfile.ZipFile(sys.argv[1]) as apk:
    libraries = [n for n in apk.namelist() if re.fullmatch(r'lib/[^/]+/libapp\.so', n)]
    if not libraries:
        raise SystemExit('No Flutter application libraries in release APK')
    for library in libraries:
        if client.encode() not in apk.read(library):
            raise SystemExit(f'Configured public OAuth client ID missing from {library}')
        print(f'Configured public OAuth client ID embedded: {library}')
print('Build configuration verified. Live Google authorization and uploads still require account testing.')
