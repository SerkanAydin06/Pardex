#!/usr/bin/env python3
"""Build an immutable release directory for any HTTPS host, without GitHub."""
import argparse, hashlib, json, os, re, shutil, tempfile, zipfile
from pathlib import Path
from urllib.parse import urlsplit


def version(value):
    if not re.fullmatch(r'[0-9]{1,6}(\.[0-9]{1,6}){0,3}', value):
        raise ValueError('Version must be numeric: 1.2.3')
    return value


def safe_path(value):
    forbidden = set('<>:"\\|?*')
    reserved = {'CON','PRN','AUX','NUL'} | {f'{p}{i}' for p in ('COM','LPT') for i in range(1,10)}
    return bool(value) and all(p and p not in ('.','..') and not p.endswith(('.', ' ')) and not any(c in forbidden or ord(c)<32 for c in p) and p.split('.')[0].upper() not in reserved for p in value.split('/'))


def publish(spec, base, output):
    url = urlsplit(base)
    if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment:
        raise ValueError('A permanent HTTPS distribution URL is required')
    output = Path(output).resolve()
    packages = output / 'packages'
    packages.mkdir(parents=True, exist_ok=True)
    manifest = {'schema':1, 'launcher':{}, 'games':[]}

    def package(source, suffix):
        size = source.stat().st_size
        if not 0 < size <= 2147483648:
            raise ValueError('Package must be 1 byte to 2 GiB')
        with source.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        name = digest + suffix
        target = packages / name
        temp = packages / (name + '.tmp')
        shutil.copyfile(source, temp)
        os.replace(temp, target)
        return {'url':base.rstrip('/')+'/packages/'+name, 'sha256':digest, 'size':size}

    if spec.get('launcher'):
        app = spec['launcher']
        manifest['launcher'] = {'version':version(app['version']), 'package':package(Path(app['setup']).resolve(), '.exe')}
    ids = set()
    for game in spec.get('games', []):
        ident = game['id']
        if not re.fullmatch(r'[a-z][a-z0-9_-]{0,47}', ident) or ident in ids:
            raise ValueError('Invalid or duplicate game ID')
        ids.add(ident)
        executable = game['executable']
        if not safe_path(executable) or not executable.lower().endswith('.exe'):
            raise ValueError('Unsafe game executable path')
        root = Path(game['directory']).resolve()
        if not (root / executable).is_file():
            raise ValueError('Game executable is missing')
        if root == output or root in output.parents:
            raise ValueError('Output must be outside the game directory')
        if not str(game['title']).strip():
            raise ValueError('Game title is required')
        files = sorted(p for p in root.rglob('*') if p.is_file())
        if any(p.is_symlink() for p in root.rglob('*')) or len(files) > 4096:
            raise ValueError('Symlinks or too many files in game package')
        names = [p.relative_to(root).as_posix() for p in files]
        if not all(safe_path(n) for n in names) or len({n.lower() for n in names}) != len(names):
            raise ValueError('Unsafe or duplicate paths in package')
        if sum(p.stat().st_size for p in files) > 8589934592:
            raise ValueError('Unpacked game exceeds 8 GiB')
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / 'game.zip'
            with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as bundle:
                for source, name in zip(files, names):
                    bundle.write(source, name)
            entry = {k:game[k] for k in ('id','title','executable')}
            entry.update(version=version(game['version']), package=package(archive, '.zip'))
            for key in ('description','players'):
                entry[key] = str(game.get(key,''))
            # A test build: playable, but the store marks it "Test".
            if game.get('test') is True:
                entry['test'] = True
            genres = game.get('genres', [])
            if not isinstance(genres, list) or len(genres) > 4 or not all(isinstance(g, str) and 0 < len(g.strip()) <= 24 for g in genres):
                raise ValueError('Genres must be up to 4 short names')
            if genres:
                entry['genres'] = [g.strip() for g in genres]
            # Store artwork: cover (portrait card) and banner (wide hero), optional.
            for key in ('cover', 'banner'):
                if game.get(key):
                    image = Path(game[key]).resolve()
                    suffix = {'.png': '.png', '.jpg': '.jpg', '.jpeg': '.jpg', '.webp': '.webp'}.get(image.suffix.lower())
                    if not suffix or not image.is_file() or image.stat().st_size > 8388608:
                        raise ValueError(f'{key} must be a PNG/JPG/WebP image up to 8 MiB')
                    entry[key] = package(image, suffix)
            for key in ('long_description', 'requirements', 'release_notes', 'connection_modes'):
                value = game.get(key, '')
                if not isinstance(value, str) or len(value) > 16000:
                    raise ValueError(f'{key} must be text up to 16000 characters')
                if value:
                    entry[key] = value
            screenshots = game.get('screenshots', [])
            if not isinstance(screenshots, list) or len(screenshots) > 8:
                raise ValueError('At most 8 screenshots are allowed')
            if screenshots:
                entry['screenshots'] = []
            for source in screenshots:
                image = Path(source).resolve()
                suffix = {'.png': '.png', '.jpg': '.jpg', '.jpeg': '.jpg', '.webp': '.webp'}.get(image.suffix.lower())
                if not suffix or not image.is_file() or image.stat().st_size > 8388608:
                    raise ValueError('Screenshot must be PNG/JPG/WebP up to 8 MiB')
                entry['screenshots'].append(package(image, suffix))
            manifest['games'].append(entry)
    if len(ids) > 100:
        raise ValueError('Too many games')
    # Publish last: clients never see a manifest whose packages are still being copied.
    temp = output / 'channel.json.tmp'
    temp.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    os.replace(temp, output / 'channel.json')
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--spec', required=True, type=Path)
    parser.add_argument('--url', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    publish(json.loads(args.spec.read_text(encoding='utf-8-sig')), args.url, args.output)
    print('Release directory ready; publish packages first and channel.json last.')
