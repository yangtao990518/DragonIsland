"""Validate original AI-generated stickers and package bounded App-only copies.

Original PNGs are immutable. This is build-time proportional downsampling, not
regeneration, matting, pose editing or a replacement for the source artwork.
"""
import hashlib
import io
import json
from pathlib import Path
import uuid

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Art/Stickers/manifest.json'
DESTINATION = ROOT / 'App/Resources/BuiltinStickers'
CATALOG = ROOT / 'App/Resources/BuiltinStickers.json'


def source_entries():
    manifest = json.loads(SOURCE.read_text(encoding='utf-8'))
    entries = manifest['stickers']
    if manifest['version'] != 1 or len(entries) != 40:
        raise ValueError('Expected the reviewed first pack of 40 stickers')
    if len({uuid.UUID(item['id']) for item in entries}) != 40:
        raise ValueError('Sticker IDs must be unique UUIDs')
    for character in ('xiaobai', 'dafeiyu'):
        if sum(item['characterID'] == character for item in entries) != 20:
            raise ValueError(f'Expected 20 stickers for {character}')
    base = (ROOT / 'Art/Stickers').resolve()
    for item in entries:
        path = (ROOT / item['source']).resolve()
        if not path.is_relative_to(base) or path.suffix.lower() != '.png':
            raise ValueError('Sticker source must stay inside Art/Stickers')
        if not 0 < len(item['name']) <= 40 or len(item['meaning']) > 300:
            raise ValueError('Invalid sticker name or meaning')
        if hashlib.sha256(path.read_bytes()).hexdigest() != item['sourceSHA256']:
            raise ValueError(f'Source digest mismatch: {path.name}')
        with Image.open(path) as source:
            if source.format != 'PNG' or source.mode != 'RGBA' or source.width > 4096 or source.height > 4096:
                raise ValueError('Expected RGBA PNG within supported bounds')
            if source.getchannel('A').getextrema() != (0, 255):
                raise ValueError('Sticker needs both transparent background and opaque artwork')
    return entries


def prepare():
    DESTINATION.mkdir(parents=True, exist_ok=True)
    entries = []
    expected = set()
    for item in source_entries():
        with Image.open(ROOT / item['source']) as source:
            image = source.copy()
        # A 150pt chat sticker at @3x needs about 450px, not the 1280px original.
        image.thumbnail((448, 448), Image.Resampling.LANCZOS)
        output = io.BytesIO()
        image.save(output, format='PNG', optimize=True)
        data = output.getvalue()
        digest = hashlib.sha256(data).hexdigest()
        filename = digest + '.png'
        expected.add(filename)
        (DESTINATION / filename).write_bytes(data)
        entries.append({key: item[key] for key in ('id', 'characterID', 'name', 'meaning')} | {
            'asset': {'sha256': digest, 'fileExtension': 'png', 'width': image.width, 'height': image.height,
                      'frameCount': 1, 'duration': 0, 'byteCount': len(data)}})
    # Only remove stale generated copies in this dedicated build-output folder.
    for path in DESTINATION.glob('*.png'):
        if path.name not in expected:
            path.unlink()
    CATALOG.write_text(json.dumps({'version': 1, 'stickers': entries}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Built-in stickers ready: 20 Xiaobai + 20 Dafeiyu, App only, originals unchanged.')


if __name__ == '__main__':
    prepare()
