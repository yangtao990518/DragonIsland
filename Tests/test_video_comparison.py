"""Ensure the app-only comparison movie is shipped with the accepted timing."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class VideoComparisonTests(unittest.TestCase):
    def test_video_bytes_match_manifest_and_accepted_source(self):
        path = ROOT / 'App/Resources/DafeiyuDogWalkTest.mp4'
        data = path.read_bytes()
        report = json.loads(path.with_suffix('.json').read_text(encoding='utf-8'))
        self.assertEqual(hashlib.sha256(data).hexdigest(), report['sha256'])
        self.assertEqual(len(data), report['bytes'])
        self.assertEqual(hashlib.sha256(json.dumps(json.loads((ROOT / 'Art/DailyMotions/manifest.json').read_text(encoding='utf-8')), sort_keys=True, separators=(',', ':')).encode()).hexdigest(), report['sourceSHA256'])
        self.assertEqual((report['fps'], report['durationSeconds'], report['frames']), (60, 20, 1200))
        self.assertEqual(report['size'], [900, 480])
        self.assertTrue(report['appOnly'])
        self.assertFalse(report['audio'])
        for box in (b'ftyp', b'moov', b'mdat', b'avc1'):
            self.assertIn(box, data)
        self.assertLess(len(data), 5_000_000)
