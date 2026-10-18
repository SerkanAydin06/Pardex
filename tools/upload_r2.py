#!/usr/bin/env python3
"""Upload a prepared release to R2 using AWS CLI v2; publish the catalog last."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path
from urllib.parse import urlsplit


def upload(root, base, account, bucket='pardex-releases', run=subprocess.run):
    root = Path(root).resolve()
    url = urlsplit(base)
    if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment or url.path not in ('', '/'):
        raise ValueError('Use the HTTPS Worker origin without a path')
    if not re.fullmatch(r'[a-f0-9]{32}', account) or not re.fullmatch(r'[a-z0-9][a-z0-9-]{1,61}[a-z0-9]', bucket):
        raise ValueError('Invalid Cloudflare account ID or bucket name')
    catalog = root / 'channel.json'
    raw = catalog.read_bytes()
    if len(raw) > 1048576:
        raise ValueError('Catalog exceeds 1 MiB')
    manifest = json.loads(raw)
    if manifest.get('schema') != 1 or not isinstance(manifest.get('games'), list):
        raise ValueError('Invalid catalog')
    entries = manifest['games'] + ([manifest['launcher']] if manifest.get('launcher') else [])
    packages = {}
    # Validate every artifact before the first remote write.
    assets = [entry['package'] for entry in entries]
    assets += [entry[key] for entry in manifest['games'] for key in ('cover', 'banner') if entry.get(key)]
    for package in assets:
        prefix = base.rstrip('/') + '/packages/'
        name = package['url'].removeprefix(prefix)
        if not package['url'].startswith(prefix) or not re.fullmatch(r'[a-f0-9]{64}\.(zip|exe|png|jpg|webp)', name):
            raise ValueError('Package URL does not belong to this Worker')
        source = root / 'packages' / name
        if source.is_symlink() or not source.is_file() or source.stat().st_size != package['size'] or not 0 < package['size'] <= 2147483648:
            raise ValueError('Missing or invalid package')
        with source.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        if digest != package['sha256'] or name.split('.')[0] != digest:
            raise ValueError('Package checksum mismatch')
        packages[name] = source
    # Full path: on Windows AWS CLI may be aws.cmd, which subprocess cannot find by name.
    aws = shutil.which('aws')
    if not aws:
        raise FileNotFoundError('AWS CLI (aws) bulunamadi; AWS CLI v2 kurulu ve PATH icinde olmali.')
    common = [aws, '--endpoint-url', f'https://{account}.r2.cloudflarestorage.com', '--region', 'auto', 's3', 'cp']
    for name, source in packages.items():
        kind = {'png': 'image/png', 'jpg': 'image/jpeg', 'webp': 'image/webp'}.get(name.rsplit('.', 1)[1], 'application/octet-stream')
        run(common + [str(source), f's3://{bucket}/packages/{name}', '--no-progress', '--content-type', kind, '--cache-control', 'public,max-age=31536000,immutable'], check=True)
    # No sync/delete: retain old versions and leave the live PC address untouched.
    run(common + [str(catalog), f's3://{bucket}/channel.json', '--no-progress', '--content-type', 'application/json', '--cache-control', 'no-store'], check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path('distribution/public'))
    parser.add_argument('--url', required=True)
    parser.add_argument('--account-id', required=True)
    parser.add_argument('--bucket', default='pardex-releases')
    args = parser.parse_args()
    upload(args.directory, args.url, args.account_id, args.bucket)
    print('R2 packages and catalog published.')
