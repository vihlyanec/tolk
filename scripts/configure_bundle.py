#!/usr/bin/env python3
"""Configure only the staged app. No private keys are stored in the bundle."""
import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parent.parent

def read_configuration(path=None):
    path = Path(path or os.environ.get('TOLK_RELEASE_CONFIG', ROOT / 'Release/updates.json'))
    if not path.is_file():
        raise ValueError('Сначала настройте репозиторий: python3 scripts/release.py setup ВЛАДЕЛЕЦ/РЕПОЗИТОРИЙ')
    config = json.loads(path.read_text())
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+', config.get('repository', '')):
        raise ValueError('Некорректный адрес репозитория: требуется ВЛАДЕЛЕЦ/РЕПОЗИТОРИЙ')
    try:
        if len(base64.b64decode(config['public_key'], validate=True)) != 32: raise ValueError()
    except (KeyError, ValueError):
        raise ValueError('В конфигурации нет корректного открытого ключа Sparkle') from None
    account = config.get('keychain_account', 'tolk-updates')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', account): raise ValueError('Некорректное имя ключа')
    config['keychain_account'] = account
    return config

def configure(bundle, release=False):
    path = Path(bundle) / 'Contents/Info.plist'
    data = plistlib.loads(path.read_bytes())
    if os.environ.get('TOLK_VERSION'):
        version = os.environ['TOLK_VERSION']
        if not re.fullmatch(r'\d+\.\d+\.\d+', version): raise ValueError('Версия должна выглядеть как 1.0.0')
        data['CFBundleShortVersionString'] = version
    if os.environ.get('TOLK_BUILD'):
        build = os.environ['TOLK_BUILD']
        if not re.fullmatch(r'[1-9][0-9]{0,3}', build): raise ValueError('Номер сборки: целое число 1…9999')
        data['CFBundleVersion'] = build
    if release:
        config = read_configuration()
        data.update(SUFeedURL=f"https://github.com/{config['repository']}/releases/latest/download/appcast.xml",
                    SUPublicEDKey=config['public_key'], SUVerifyUpdateBeforeExtraction=True,
                    SURequireSignedFeed=True, SUAllowsAutomaticUpdates=False,
                    SUSendProfileInfo=False, SUScheduledCheckInterval=86400)
    path.write_bytes(plistlib.dumps(data, sort_keys=False))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('bundle'); parser.add_argument('--release', action='store_true')
    args = parser.parse_args()
    try: configure(args.bundle, args.release)
    except (ValueError, OSError, json.JSONDecodeError) as error: parser.exit(1, str(error) + '\n')
