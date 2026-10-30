"""The accepted full-scene crop stays portable and is packaged only in the App."""
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'Art/HomeScenes/dafeiyu-touch'
spec = importlib.util.spec_from_file_location('home_scene', ROOT / 'Scripts/prepare_home_scene.py')
scene = importlib.util.module_from_spec(spec); spec.loader.exec_module(scene)


class HomeSceneResourcesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.info = json.loads((ART / 'manifest.json').read_text(encoding='utf-8'))
        scene.prepare()

    def test_complete_source_and_user_approved_crop(self):
        c = self.info
        self.assertEqual(c['characterID'], 'dafeiyu')
        self.assertEqual(c['uniformCrop'], [1176, 0, 1854, 2160])
        self.assertEqual(c['sourceSize'], [3840, 2160])
        self.assertEqual(c['frameCount'], 240)
        self.assertTrue(c['fullOriginalRange'])
        self.assertEqual(c['droppedFrames'], 0)
        self.assertEqual(c['synthesizedFrames'], 0)
        self.assertEqual(c['playbackSpeed'], 1)
        original = scene.source_data(c)
        self.assertEqual(hashlib.sha256(original).hexdigest(), c['sourceSHA256'])
        self.assertEqual(len(original), c['sourceBytes'])
        self.assertAlmostEqual(float(scene.movie_duration(original)) * 1000, c['durationMs'])
        self.assertAlmostEqual(c['durationMs'], 4064)

    def test_every_source_pts_and_final_hold_is_used(self):
        c = self.info; frames = c['frames']
        self.assertEqual([f['index'] for f in frames], list(range(240)))
        self.assertEqual(frames[0]['startMs'], 0)
        self.assertEqual(len({f['file'] for f in frames}), 240)
        tb = c['timeBase'][0] / c['timeBase'][1]
        for a, b in zip(frames, frames[1:]):
            self.assertGreater(b['pts'], a['pts'])
            self.assertAlmostEqual(a['durationMs'], (b['pts'] - a['pts']) * tb * 1000)
            self.assertAlmostEqual(b['startMs'], a['startMs'] + a['durationMs'])
        self.assertAlmostEqual(sum(f['durationMs'] for f in frames), c['durationMs'])
        # This source has a longer original interval; flattening to 60 FPS loses it.
        self.assertGreater(max(f['durationMs'] for f in frames[:-1]), 30)
        self.assertGreater(frames[-1]['durationMs'], 30)

    def test_all_240_app_frames_and_manifest_match_portable_sources(self):
        c = self.info
        runtime = json.loads((scene.DEST / 'HomeScenes.json').read_text(encoding='utf-8'))[0]
        self.assertEqual(runtime['frameCount'], 240)
        self.assertEqual(runtime['frameStartMs'], [f['startMs'] for f in c['frames']])
        self.assertEqual(runtime['frameDurationsMs'], [f['durationMs'] for f in c['frames']])
        for f in c['frames']:
            original = ART / f['file']; built = scene.DEST / original.name
            self.assertEqual(hashlib.sha256(original.read_bytes()).hexdigest(), f['sha256'])
            self.assertEqual(original.read_bytes(), built.read_bytes())
            with Image.open(original) as image:
                self.assertEqual(list(image.size), c['runtimeFrameSize'])
                self.assertEqual(image.format, 'JPEG')
                self.assertEqual(image.mode, 'RGB')
        native = c['nativeFrameSize']; runtime_size = c['runtimeFrameSize']
        self.assertEqual(native[0] * runtime_size[1], native[1] * runtime_size[0])
        self.assertLess(sum((ART / f['file']).stat().st_size for f in c['frames']), 100 * 1024 * 1024)


if __name__ == '__main__': unittest.main()
