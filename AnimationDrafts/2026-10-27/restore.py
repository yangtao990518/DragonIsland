"""Verify and restore today's archived local work. Standard Python only."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path,
                        help='Repository root; defaults to the repository containing this script')
    parser.add_argument('--overwrite', action='store_true',
                        help='Replace differing files; without this option existing edits are preserved')
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    archive_root = Path(__file__).resolve().parent
    destination = (args.destination or archive_root.parents[1]).resolve()
    manifest = json.loads((archive_root / 'manifest.json').read_text(encoding='utf-8'))
    files_by_hash = {}
    for item in manifest['files']:
        target = (destination / item['path']).resolve()
        if not target.is_relative_to(destination) or not item['path'].startswith('output/'):
            raise ValueError('Unsafe destination: ' + item['path'])
        files_by_hash.setdefault(item['sha256'], []).append((item, target))
    verified = 0
    restored = 0
    conflicts = []
    for archive in manifest['archives']:
        package = archive_root / archive['path']
        if digest(package.read_bytes()) != archive['sha256']:
            raise ValueError('Archive SHA256 mismatch: ' + str(package))
        with zipfile.ZipFile(package) as z:
            bad = z.testzip()
            if bad:
                raise ValueError('ZIP CRC error: ' + bad)
            for member in z.infolist():
                sha = member.filename.removeprefix('objects/')
                if sha not in files_by_hash or member.filename != 'objects/' + sha:
                    raise ValueError('Unexpected archive member: ' + member.filename)
                data = z.read(member)
                if digest(data) != sha:
                    raise ValueError('Content SHA256 mismatch: ' + member.filename)
                for item, target in files_by_hash[sha]:
                    if len(data) != item['bytes']:
                        raise ValueError('Content length mismatch: ' + item['path'])
                    verified += 1
                    if args.verify_only:
                        continue
                    if target.exists() and digest(target.read_bytes()) != sha and not args.overwrite:
                        conflicts.append(item['path'])
                        continue
                    if not target.exists() or digest(target.read_bytes()) != sha:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_bytes(data)
                    restored += 1
    if verified != len(manifest['files']):
        raise ValueError('Incomplete archive set')
    for preview in manifest['previews']:
        if digest((archive_root / preview['path']).read_bytes()) != preview['sha256']:
            raise ValueError('Preview SHA256 mismatch: ' + preview['path'])
    print(f'Verified {verified} source paths and {len(manifest["previews"])} latest previews.')
    if not args.verify_only:
        print(f'Restored/retained {restored} files in {destination}')
    if conflicts:
        print('Preserved differing local files (review before using --overwrite):')
        print('\n'.join(conflicts))
        raise SystemExit(2)


if __name__ == '__main__':
    main()
