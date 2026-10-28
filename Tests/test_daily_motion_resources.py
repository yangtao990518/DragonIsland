"""Regression checks for accepted scenes, source timing and safe island travel."""
import importlib.util
import json
from pathlib import Path
import unittest
from PIL import ImageChops, ImageOps

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('prepare_motion',ROOT/'Scripts/prepare_motion.py')
motion=importlib.util.module_from_spec(spec);spec.loader.exec_module(motion)


class DailyMotionTests(unittest.TestCase):
    def test_only_accepted_clips_and_original_blink_timing_are_packaged(self):
        data=json.loads((ROOT/'Art/DailyMotions/manifest.json').read_text(encoding='utf-8'))
        self.assertEqual(set(data['clips']),{'xiaobai-sword','dafeiyu-whale','dafeiyu-dog'})
        self.assertAlmostEqual(sum(data['clips']['dafeiyu-dog']['durationsMs']),1600)
        for name in ('xiaobai-sword','dafeiyu-whale'):
            d=data['clips'][name]['durationsMs']
            pause=4 if name=='xiaobai-sword' else 6
            self.assertAlmostEqual(sum(d[pause+1:pause+8]),450)

    def test_mirror_timing_and_no_clipping_or_jumps_in_every_bank(self):
        for character in ('xiaobai','dafeiyu'):
            # This regression retains all pre-existing travelling schedules;
            # full-video additions have their own complete-range bank tests.
            clips={a:c for a,c in motion.load_daily_art(character).items() if not c.get('full_source_once')}
            self.assertEqual(set(clips),{'ride'} if character=='xiaobai' else {'ride','pet_walk'})
            for clip in clips.values():
                for right,left in zip(clip['right'],clip['left']):
                    self.assertIsNone(ImageChops.difference(ImageOps.mirror(right),left).getbbox())
            selected=set()
            for mask in range(16):
                for seed in range(2):
                    _,frames,legs=motion.daily_schedule(mask,seed,motion.DURATIONS,clips)
                    self.assertEqual(len(frames),1800)
                    self.assertEqual(frames[0]['x'],frames[-1]['x'])
                    self.assertTrue(all(abs(b['x']-a['x'])<=1 for a,b in zip(frames,frames[1:])))
                    for f in frames:
                        w=f.get('width',72)
                        self.assertGreaterEqual((180-w)//2+f['x'],0)
                        self.assertLessEqual((180-w)//2+f['x']+w,180)
                        if f['action'] in clips:
                            self.assertTrue(mask & {"ride":4,"pet_walk":8}[f["action"]])
                            selected.add(f['action'])
                    for action,bit in (('walk',1),('roll',2),('ride',4),('pet_walk',8)):
                        if not mask&bit:self.assertTrue(all(f['action']!=action for f in frames))
                        elif action in ('walk','roll') or action in clips:
                            self.assertTrue(any(f['action']==action for f in frames), (character,mask,seed,action))
            self.assertEqual(selected,set(clips))

    def test_sixty_fps_dog_preview_visits_every_source_pose_in_order(self):
        clip=motion.load_daily_art('dafeiyu')['pet_walk']
        frames=motion.daily_leg('pet_walk','right',clip,fps=60)
        self.assertEqual([f['asset'] for f in frames[:192]],
                         [motion.key('pet_walk_right',i) for _ in range(2) for i in range(96)])


if __name__=='__main__':unittest.main()
