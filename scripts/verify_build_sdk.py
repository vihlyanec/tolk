#!/usr/bin/env python3
"""Check the linked SDK, independently of the minimum supported macOS version."""
import argparse
import re
import subprocess


def version(value):
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value):
        raise ValueError("Некорректная версия macOS/SDK: " + value)
    return tuple((list(map(int, value.split('.'))) + [0, 0])[:3])


def parse_build_version(text):
    blocks = re.split(r"(?m)^\s*Load command \d+\s*$", text)
    builds = [block for block in blocks if re.search(r"(?m)^\s*cmd LC_BUILD_VERSION\s*$", block)]
    if len(builds) != 1:
        raise ValueError("Не найдена единственная LC_BUILD_VERSION для архитектуры")
    def field(name):
        match = re.search(r"(?m)^\s*" + name + r"\s+(\S+)\s*$", builds[0])
        if not match:
            raise ValueError("Нет поля " + name + " в LC_BUILD_VERSION")
        return match.group(1)
    return dict(platform=field('platform'), minimum_os=field('minos'), sdk=field('sdk'))


def validate_versions(builds, expected_sdk, minimum_os='14.0', universal=False):
    if not builds or set(builds) - {'arm64', 'x86_64'}:
        raise ValueError("Неподдерживаемый набор архитектур")
    if universal and set(builds) != {'arm64', 'x86_64'}:
        raise ValueError("Универсальная сборка должна содержать Intel и Apple Silicon")
    for arch, build in builds.items():
        if build['platform'] != 'MACOS':
            raise ValueError(arch + ': неверная платформа')
        if version(build['minimum_os']) != version(minimum_os):
            raise ValueError(arch + ': изменена минимальная macOS: ' + build['minimum_os'])
        if version(build['sdk']) != version(expected_sdk):
            raise ValueError(arch + ': неверная метка SDK ' + build['sdk'] + '; ожидалась ' + expected_sdk)
    return builds


def verify_binary(binary, expected_sdk, minimum_os='14.0', universal=False):
    archs = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
    builds = {arch: parse_build_version(subprocess.check_output(
        ['vtool', '-arch', arch, '-show-build', str(binary)], text=True)) for arch in archs}
    return validate_versions(builds, expected_sdk, minimum_os, universal)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('binary')
    parser.add_argument('--expected-sdk', required=True)
    parser.add_argument('--minimum-os', default='14.0')
    parser.add_argument('--universal', action='store_true')
    args = parser.parse_args()
    try:
        builds = verify_binary(args.binary, args.expected_sdk, args.minimum_os, args.universal)
        for arch, build in builds.items():
            print(f"{arch}: macOS {build['minimum_os']}+, SDK {build['sdk']}")
    except (ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit('Проверка SDK не пройдена: ' + str(error))
