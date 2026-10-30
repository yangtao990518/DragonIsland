"""Validate shipped original art plus the actual build-time sticker catalog."""
import hashlib
import json
from pathlib import Path
import sys
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'Scripts'))
import prepare_builtin_stickers as stickers


class BuiltinStickerTests(unittest.TestCase):
    def test_sources_are_complete_transparent_and_separate_per_character(self):
        entries = stickers.source_entries()
        self.assertEqual(len(entries), 40)
        for character in ('xiaobai', 'dafeiyu'):
            own = [item for item in entries if item['characterID'] == character]
            self.assertEqual(len(own), 20)
            self.assertEqual(len({item['source'] for item in own}), 20)
            self.assertTrue(all(item['meaning'] for item in own))

    def test_packaged_bytes_match_catalog_and_fit_chat_preview(self):
        stickers.prepare()
        catalog = json.loads(stickers.CATALOG.read_text(encoding='utf-8'))
        self.assertEqual(len(catalog['stickers']), 40)
        self.assertEqual(len(list(stickers.DESTINATION.glob('*.png'))), 40)
        for item in catalog['stickers']:
            asset = item['asset']
            path = stickers.DESTINATION / (asset['sha256'] + '.png')
            data = path.read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), asset['sha256'])
            self.assertEqual(len(data), asset['byteCount'])
            with Image.open(path) as image:
                self.assertEqual(image.size, (asset['width'], asset['height']))
                self.assertLessEqual(max(image.size), 450)
                self.assertEqual(image.mode, 'RGBA')
                self.assertEqual(image.getchannel('A').getextrema(), (0, 255))
        self.assertLess(sum(item['asset']['byteCount'] for item in catalog['stickers']), 15 * 1024 * 1024)


if __name__ == '__main__':
    unittest.main()
