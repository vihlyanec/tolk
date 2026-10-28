#!/usr/bin/env python3
"""Apply the pinned application identity; Sparkle's update key is independent."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def designated_requirement(stdout, stderr):
    lines = (stdout + '\n' + stderr).splitlines()
    requirement = next((line.split('designated =>', 1)[1].strip() for line in lines if 'designated =>' in line), '')
    if 'cdhash' in requirement or 'identifier ' not in requirement or not ('certificate ' in requirement or 'anchor ' in requirement):
        raise ValueError('Подпись не обеспечивает постоянную идентичность приложения')
    return requirement

def identity_for(release=False, configuration=None):
    path = Path(configuration or ROOT / 'Release/app-signing.json')
    configured = None
    if release and not path.is_file():
        raise ValueError('Для выпуска нужен постоянный сертификат: Release/app-signing.json отсутствует')
    if release and path.exists():
        config = json.loads(path.read_text())
        configured = config['identity_sha1']
        if not re.fullmatch(r'[0-9A-F]{40}', configured):
            raise ValueError('Некорректный отпечаток сертификата подписи приложения')
        if not re.fullmatch(r'[0-9a-f]{64}', config['certificate_sha256']):
            raise ValueError('Некорректный SHA-256 сертификата подписи приложения')
    requested = os.environ.get('TOLK_CODE_SIGN_IDENTITY')
    if configured and requested and requested != configured:
        raise ValueError('Нельзя незаметно сменить постоянную подпись приложения')
    identity = configured or requested or '-'
    if identity != '-' and not re.fullmatch(r'[0-9A-F]{40}', identity):
        raise ValueError('Укажите точный SHA-1 отпечаток сертификата, а не его имя')
    return identity

def sign(bundle, release=False):
    bundle = Path(bundle)
    identity = identity_for(release)
    if identity != '-':
        config_path = ROOT / 'Release/app-signing.json'
        if config_path.exists():
            config = json.loads(config_path.read_text())
            if config['identity_sha1'] == identity:
                # Only public certificate data is read from Keychain. Pin its SHA-256
                # as well as codesign's conventional SHA-1 identity selector.
                result = subprocess.run(['security', 'find-certificate', '-a', '-p', '-c', config['name']], check=True, capture_output=True, text=True)
                import base64, hashlib
                certificates = re.findall(r'-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----', result.stdout, re.S)
                if not any(hashlib.sha256(base64.b64decode(c)).hexdigest() == config['certificate_sha256'] for c in certificates):
                    raise ValueError('Постоянный сертификат отсутствует или изменён; выпуск остановлен')
    subprocess.run(['codesign', '--force', '--sign', identity, '--timestamp=none', str(bundle)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)
    if identity != '-':
        display = subprocess.run(['codesign', '-d', '-r-', str(bundle)], check=True, capture_output=True, text=True)
        designated_requirement(display.stdout, display.stderr)
    return identity

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('bundle'); parser.add_argument('--release', action='store_true')
    args = parser.parse_args()
    try: sign(args.bundle, args.release)
    except (ValueError, KeyError, subprocess.CalledProcessError) as error: raise SystemExit(str(error))
