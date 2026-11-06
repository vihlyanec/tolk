"""Online SQLite backup with a bounded retention window, run inside the container."""
import os
import sqlite3
from datetime import datetime, timezone
from pathlib import Path


def backup(path):
    source = Path(path)
    directory = source.parent / 'backups'
    directory.mkdir(mode=0o700, exist_ok=True)
    destination = directory / (datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '.sqlite')
    incoming, outgoing = sqlite3.connect(source), sqlite3.connect(destination)
    try:
        incoming.backup(outgoing)
        if outgoing.execute('PRAGMA quick_check').fetchone()[0] != 'ok':
            raise RuntimeError('Backup integrity check failed')
    finally:
        incoming.close(); outgoing.close()
    destination.chmod(0o600)
    for old in sorted(directory.glob('*.sqlite'), reverse=True)[14:]:
        old.unlink()
    return destination.name


if __name__ == '__main__': print(backup(os.environ['TOLK_DATABASE']))
