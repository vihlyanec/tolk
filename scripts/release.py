#!/usr/bin/env python3
"""Local release preparation and explicit draft/publish steps; never stores a GitHub token."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from configure_bundle import ROOT, read_configuration
from sign_bundle import identity_for

RELEASES = Path(os.environ.get('TOLK_RELEASE_DIR', ROOT / 'build/releases'))
SPARKLE_NAMESPACE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
PUBLISH_PATHS = ['Sources','Tests','Resources','scripts','.github','Release','Package.swift','README.md','DISTRIBUTION.md','THIRD_PARTY_NOTICES.md','.gitignore']

def run(args, **kwargs):
    return subprocess.run([str(a) for a in args], cwd=ROOT, check=True, **kwargs)

def output(args):
    return run(args, capture_output=True, text=True).stdout.strip()

def tools():
    root = Path(os.environ.get('TOLK_SCRATCH_PATH', '/private/tmp/takt-native'))
    found = list(root.glob('artifacts/*/Sparkle/bin/generate_appcast'))
    if not found:
        run(['swift', 'package', '--disable-sandbox', '--scratch-path', root, 'resolve'])
        found = list(root.glob('artifacts/*/Sparkle/bin/generate_appcast'))
    if len(found) != 1: raise ValueError('Не найдены инструменты Sparkle. Сначала выполните zsh scripts/build.sh')
    return found[0].parent

def setup(repository):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+', repository):
        raise ValueError('Укажите адрес в формате ВЛАДЕЛЕЦ/РЕПОЗИТОРИЙ')
    path = ROOT / 'Release/updates.json'
    if path.exists():
        existing = read_configuration(path)
        if existing['repository'] != repository:
            raise ValueError('Репозиторий уже настроен. Его адрес должен оставаться доступным всем установленным приложениям.')
        print('Репозиторий и ключ уже настроены.'); return
    binary = tools() / 'generate_keys'; account = 'tolk-updates'
    run([binary, '--account', account])  # Only the public key is printed by Sparkle.
    public = output([binary, '--account', account, '-p'])
    if len(base64.b64decode(public, validate=True)) != 32: raise ValueError('Не удалось получить открытый ключ')
    path.write_text(json.dumps(dict(repository=repository, public_key=public, keychain_account=account), ensure_ascii=False, indent=2) + '\n')
    print('Готово. Закрытый ключ находится в Связке ключей Mac; в updates.json только открытый ключ.')

def release_dir(version):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version): raise ValueError('Версия должна выглядеть как 1.0.0')
    return RELEASES / ('v' + version)

def verify_manifest(folder, config):
    manifest = json.loads((folder / 'manifest.json').read_text())
    if manifest['repository'] != config['repository'] or manifest['public_key'] != config['public_key']:
        raise ValueError('Конфигурация не соответствует собранному выпуску')
    for name, expected in manifest['sha256'].items():
        if Path(name).name != name or hashlib.sha256((folder / name).read_bytes()).hexdigest() != expected:
            raise ValueError('Артефакт изменён после подписи: ' + name)
    return manifest

def source_state():
    commit = subprocess.run(['git','rev-parse','HEAD'], cwd=ROOT, capture_output=True, text=True)
    tracked = output(['git','status','--porcelain','--untracked-files=no'])
    new_sources = output(['git','ls-files','--others','--exclude-standard','--'] + PUBLISH_PATHS)
    return (commit.stdout.strip() if commit.returncode == 0 else None), not bool(tracked or new_sources)

def backup_key(destination):
    config = read_configuration(); destination = Path(destination).expanduser().resolve()
    if destination == ROOT or ROOT in destination.parents: raise ValueError('Сохраните закрытый ключ ВНЕ папки проекта')
    if destination.exists(): raise ValueError('Файл уже существует; ключ не перезаписан')
    run([tools() / 'generate_keys','--account',config['keychain_account'],'-x',destination])
    destination.chmod(0o600)
    print('Копия ключа сохранена. Храните её в защищённом хранилище; в GitHub её загружать не нужно.')

def prepare(args):
    application_identity = identity_for(release=not args.test_build)
    commit, clean = source_state()
    if (not clean or commit is None) and not args.test_build:
        raise ValueError('Перед выпуском сохраните изменения исходников в Git. Для локального теста используйте --test-build --key-file ВРЕМЕННЫЙ_КЛЮЧ')
    if args.test_build and not args.key_file: raise ValueError('Тестовый выпуск требует отдельного временного --key-file')
    config = read_configuration(); folder = release_dir(args.version)
    if args.key_file:
        try: run(['swift','scripts/check_update_key.swift',Path(args.key_file).resolve(),config['public_key']])
        except subprocess.CalledProcessError: raise ValueError('Файл закрытого ключа не соответствует открытому ключу этого приложения') from None
    elif output([tools() / 'generate_keys','--account',config['keychain_account'],'-p']) != config['public_key']:
        raise ValueError('Ключ в Связке ключей не соответствует конфигурации. Нельзя выпускать обновление с другим ключом.')
    if folder.exists(): raise ValueError('Этот выпуск уже подготовлен. Используйте новую версию или отдельно проверьте старую папку.')
    if not 1 <= args.build <= 9999: raise ValueError('Номер сборки должен быть от 1 до 9999 и больше предыдущего')
    notes = Path(args.notes).resolve()
    if not notes.is_file(): raise ValueError('Создайте файл с описанием изменений и укажите его через --notes')
    current_build = int(plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())['CFBundleVersion'])
    previous_builds = [json.loads(p.read_text())['build'] for p in RELEASES.glob('*/manifest.json')]
    if args.build <= max([current_build] + previous_builds): raise ValueError('Номер сборки должен быть больше предыдущих локальных сборок')
    folder.parent.mkdir(parents=True, exist_ok=True)
    # Stage outside the File Provider workspace until the app and feed are complete.
    with tempfile.TemporaryDirectory(prefix='tolk-release-', dir='/private/tmp') as temp:
        stage = Path(temp); apps = stage / 'apps'; feed = stage / 'feed'; feed.mkdir()
        env = dict(os.environ, TOLK_RELEASE='1', TOLK_TEST_BUILD='1' if args.test_build else '0', TOLK_UNIVERSAL='1', TOLK_VERSION=args.version,
                   TOLK_BUILD=str(args.build), TOLK_OUTPUT_DIR=str(apps))
        run(['zsh', 'scripts/build.sh'], env=env)
        app = apps / 'Толк.app'
        archs = output(['lipo', '-archs', app / 'Contents/MacOS/Takt']).split()
        if not {'arm64','x86_64'}.issubset(archs): raise ValueError('Релиз должен поддерживать Apple Silicon и Intel')
        archive = feed / f'Tolk-{args.version}.zip'
        run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive])
        shutil.copyfile(notes, feed / f'Tolk-{args.version}.md')
        prefix = f"https://github.com/{config['repository']}/releases/download/v{args.version}/"
        command = [tools() / 'generate_appcast', '--download-url-prefix', prefix,
                   '--release-notes-url-prefix', prefix, '--maximum-deltas', '0', '--account', config['keychain_account']]
        if args.key_file: command += ['--ed-key-file', str(Path(args.key_file).resolve())]
        run(command + [feed])
        root = ET.parse(feed / 'appcast.xml').getroot()
        enclosure = root.find('./channel/item/enclosure')
        if enclosure is None or not enclosure.get(SPARKLE_NAMESPACE + 'edSignature'): raise ValueError('Обновление не подписано')
        # Require correct destinations and version before making any files publishable.
        if enclosure.get('url') != prefix + archive.name: raise ValueError('Неверный адрес архива в appcast')
        version = root.find('./channel/item/' + SPARKLE_NAMESPACE + 'version')
        if version is None or version.text != str(args.build): raise ValueError('Неверный номер сборки в appcast')
        checksums = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(feed.iterdir()) if p.is_file()}
        (feed / 'checksums.txt').write_text(''.join(f'{digest}  {name}\n' for name,digest in checksums.items()))
        checksums['checksums.txt'] = hashlib.sha256((feed / 'checksums.txt').read_bytes()).hexdigest()
        (feed / 'manifest.json').write_text(json.dumps(dict(version=args.version, build=args.build, repository=config['repository'],
            public_key=config['public_key'], application_signing_identity=application_identity, source_commit=commit, source_clean=clean, test_build=args.test_build, sha256=checksums), ensure_ascii=False, indent=2) + '\n')
        shutil.copytree(feed, folder)
    print(f'Выпуск подготовлен: {folder}')
    if args.test_build: print('Это тестовая сборка. Её загрузка и публикация запрещены.')
    else: print(f'Ничего не опубликовано. Следующий шаг: python3 scripts/release.py upload {args.version}')

def github(args):
    if shutil.which('gh') is None: raise ValueError('Установите GitHub CLI с https://cli.github.com и выполните gh auth login')
    return output(['gh'] + args)

def check_remote_build(config, build):
    # Only a genuine 404 means that a public repository has no releases yet.
    url = f"https://github.com/{config['repository']}/releases/latest/download/appcast.xml"
    try:
        with urllib.request.urlopen(url, timeout=30) as response: xml = response.read(2_000_000)
    except urllib.error.HTTPError as error:
        if error.code == 404: return
        raise ValueError('Не удалось проверить предыдущий выпуск GitHub: ' + str(error.code)) from error
    root = ET.fromstring(xml)
    builds = [int(node.text) for node in root.findall('.//' + SPARKLE_NAMESPACE + 'version')]
    if builds and build <= max(builds): raise ValueError('Номер сборки не больше уже опубликованного')

def upload(version):
    config = read_configuration(); folder = release_dir(version); manifest = verify_manifest(folder, config)
    if manifest.get('test_build') or not manifest.get('source_clean'):
        raise ValueError('Тестовые сборки и несохранённые исходники не публикуются')
    head, clean = source_state()
    if manifest.get('test_build') or not manifest.get('source_clean') or not clean or head != manifest.get('source_commit'):
        raise ValueError('Загрузить можно только выпуск, собранный из текущего сохранённого commit. Тестовые сборки не публикуются.')
    if github(['api', 'repos/' + config['repository'], '--jq', '.private']) != 'false':
        raise ValueError('Для обновлений без авторизации нужен публичный репозиторий выпусков')
    check_remote_build(config, manifest['build'])
    assets = [folder / name for name in manifest['sha256']]
    github(['release','create','v' + version,'--repo',config['repository'],'--draft','--target',head,
            '--title','Толк ' + version,'--notes-file',str(folder / f'Tolk-{version}.md')] + [str(p) for p in assets])
    print('Создан ЧЕРНОВИК. Проверьте его в GitHub, затем опубликуйте вручную или выполните publish.')

def find_release(config, version):
    # Draft tags may not have a Git ref yet: /releases/tags/... then returns 404.
    pages = json.loads(github(['api','repos/' + config['repository'] + '/releases?per_page=100','--paginate','--slurp']))
    matches = [release for page in pages for release in page if release['tag_name'] == 'v' + version]
    if len(matches) != 1: raise ValueError('Не найден единственный выпуск с этой версией')
    return matches[0]

def publish(version):
    config = read_configuration(); manifest = verify_manifest(release_dir(version), config)
    if manifest.get('test_build') or not manifest.get('source_clean'): raise ValueError('Тестовый выпуск не публикуется')
    info = find_release(config, version)
    if not info['draft']: raise ValueError('Этот выпуск уже опубликован')
    for name, expected in manifest['sha256'].items():
        asset = next((a for a in info['assets'] if a['name'] == name), None)
        if asset is None or asset.get('digest') != 'sha256:' + expected:
            raise ValueError('Не совпадает контрольная сумма загруженного файла: ' + name)
    check_remote_build(config, manifest['build'])
    github(['release','edit','v'+version,'--repo',config['repository'],'--draft=false','--latest'])
    print('Выпуск опубликован. Установленные приложения смогут обнаружить обновление.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Подготовка и публикация обновлений Толка')
    commands = parser.add_subparsers(dest='command', required=True)
    p = commands.add_parser('setup'); p.add_argument('repository')
    p = commands.add_parser('backup-key'); p.add_argument('destination')
    p = commands.add_parser('prepare'); p.add_argument('version'); p.add_argument('build', type=int); p.add_argument('--notes', required=True); p.add_argument('--test-build', action='store_true', help='Непубликуемая проверочная сборка'); p.add_argument('--key-file', help='Необязательный файл ключа вместо Связки ключей')
    for name in ['upload','publish']:
        p = commands.add_parser(name); p.add_argument('version')
    args = parser.parse_args()
    try:
        if args.command == 'setup': setup(args.repository)
        elif args.command == 'backup-key': backup_key(args.destination)
        elif args.command == 'prepare': prepare(args)
        elif args.command == 'upload': upload(args.version)
        else: publish(args.version)
    except (ValueError, OSError, subprocess.CalledProcessError, json.JSONDecodeError, ET.ParseError) as error:
        sys.exit('Ошибка: ' + str(error))
