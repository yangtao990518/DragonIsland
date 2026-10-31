"""Delivery invariants: all original frames, timing, alpha and App-only assets."""
import hashlib
import json
from pathlib import Path
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


class SurvivorAssetsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = ROOT / 'Art/Survivor'
        cls.manifest = json.loads((cls.source / 'manifest.json').read_text(encoding='utf-8'))

    def test_original_sources_archived_unchanged(self):
        for source in self.manifest['sources'].values():
            self.assertEqual(hashlib.sha256((self.source / source['path']).read_bytes()).hexdigest(), source['sha256'])
            self.assertTrue(source['full_original_range'])
            self.assertEqual(source['frame_count'], 240)
            self.assertLessEqual(source['duration_ms'], 20000)

    def test_full_frame_order_and_original_holds(self):
        self.assertEqual(self.manifest['dropped_frames'], 0)
        self.assertEqual(self.manifest['synthesized_frames'], 0)
        for clip in self.manifest['clips']:
            origin = self.manifest['sources'][clip['source']]
            self.assertEqual(len(clip['frames']), origin['frame_count'])
            end = 0
            for index, frame in enumerate(clip['frames']):
                self.assertEqual(frame['source_index'], index)
                self.assertAlmostEqual(frame['start_ms'], end, places=5)
                self.assertGreater(frame['duration_ms'], 0)
                self.assertLess(frame['cell'], clip['unique_count'])
                end = frame['start_ms'] + frame['duration_ms']
            self.assertAlmostEqual(end, origin['duration_ms'], places=5)
            self.assertGreater(max(f['duration_ms'] for f in clip['frames']), 30)

    def test_atlas_alpha_and_bytes(self):
        for clip in self.manifest['clips']:
            self.assertTrue(all(0 <= p <= 1 for p in clip['pivot']))
            for page in clip['pages']:
                path = self.source / page['file']
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), page['sha256'])
                with Image.open(path) as image:
                    self.assertEqual(image.mode, 'RGBA')
                    self.assertEqual(image.size, tuple(a*b for a,b in zip(clip['cell_size'], clip['grid'])))
                    self.assertEqual(image.getchannel('A').getextrema()[0], 0)

    def test_build_resource_conversion_keeps_lossless_pixels(self):
        runtime = ROOT / 'App/Resources/SurvivorGame'
        built = json.loads((runtime / 'manifest.json').read_text(encoding='utf-8'))
        self.assertEqual(len(built['clips']), 8)
        for source, dest in zip(self.manifest['clips'], built['clips']):
            self.assertEqual(source['frames'], dest['frames'])
            for master, page in zip(source['pages'], dest['pages']):
                self.assertEqual(page['source_sha256'], master['sha256'])
                self.assertEqual(hashlib.sha256((runtime / page['file']).read_bytes()).hexdigest(), page['sha256'])
                with Image.open(self.source / master['file']) as a, Image.open(runtime / page['file']) as b:
                    self.assertEqual(a.tobytes(), b.tobytes())

    def test_basic_attack_reuses_the_earlier_water_bubble(self):
        directory = self.source / 'Static'
        bubble = json.loads((directory / 'manifest.json').read_text(encoding='utf-8'))
        self.assertEqual(hashlib.sha256((directory / bubble['source']).read_bytes()).hexdigest(), bubble['source_sha256'])
        raw = (directory / bubble['file']).read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), bubble['sha256'])
        self.assertEqual(raw, (ROOT / 'App/Resources/SurvivorGame/water-bubble.png').read_bytes())
        self.assertTrue(all(0 <= p <= 1 for p in bubble['pivot']))


if __name__ == '__main__':
    unittest.main()
