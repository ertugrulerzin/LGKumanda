#!/usr/bin/env python3
"""Verify the exact iPhone/TestFlight package before uploading; no credentials read."""
from pathlib import Path
import hashlib
import json
import plistlib
import subprocess
import sys
import tempfile
import zipfile

ipa = Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='lgkumanda-verify-') as directory:
    with zipfile.ZipFile(ipa) as package:
        package.extractall(directory)
    apps = list((Path(directory) / 'Payload').glob('*.app'))
    assert len(apps) == 1, 'Expected one app'
    app = apps[0]
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    profile = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')]))
    signed = subprocess.run(['codesign', '-d', '--entitlements', '-', '--xml', str(app)], check=True, capture_output=True)
    entitlements = plistlib.loads(signed.stdout)
    assert info['CFBundleIdentifier'] == 'com.ertugrul.LGKumanda'
    assert info['DTPlatformName'] == 'iphoneos'
    assert info['UIDeviceFamily'] == [1], 'Package must target iPhone only'
    assert entitlements['application-identifier'] == 'PBY9P5GVFB.com.ertugrul.LGKumanda'
    assert not entitlements.get('get-task-allow', False)
    assert profile['Entitlements'].get('beta-reports-active') is True
    assert 'ProvisionedDevices' not in profile
    assert (app / 'PrivacyInfo.xcprivacy').exists()
    print(json.dumps({'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'], 'iphoneOnly': True, 'signatureVerified': True, 'ipa': str(ipa), 'sha256': hashlib.sha256(ipa.read_bytes()).hexdigest()}, indent=2))
