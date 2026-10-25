import importlib.util
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('prepare_motion',ROOT/'Scripts/prepare_motion.py')
motion=importlib.util.module_from_spec(spec)
spec.loader.exec_module(motion)


class MotionResourcesTests(unittest.TestCase):
    def test_selection_and_loop_position_for_every_plan(self):
        for mask in range(4):
            for seed in range(2):
                slots,frames=motion.schedule(mask,seed)
                self.assertEqual(len(slots),12)
                self.assertEqual(len(frames),480)
                self.assertNotIn('walk' if not mask&1 else 'impossible',slots)
                self.assertNotIn('roll' if not mask&2 else 'impossible',slots)
                self.assertEqual(slots.count('walk')%2,0)
                self.assertEqual(frames[0]['x'],frames[-1]['x'])
                for frame in frames:
                    self.assertLessEqual(abs(frame['x']),10)
                    self.assertTrue(frame['asset'].startswith('Motion_'))

    def test_new_neutral_and_required_poses_exist(self):
        self.assertTrue((ROOT/'Art/xiaobai-chibi-v2.png').exists())
        for action,info in motion.MANIFEST['actions'].items():
            for path in info['frames']:self.assertTrue((motion.ART/path).exists(),path)
        self.assertIn('roll',motion.MANIFEST['actions'])
        self.assertIn('turn_left',motion.MANIFEST['actions'])


if __name__=='__main__':unittest.main()
