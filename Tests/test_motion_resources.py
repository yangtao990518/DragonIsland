import importlib.util
import json
import math
from PIL import Image, ImageChops
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
                self.assertEqual(len(frames),30*60)
                self.assertNotIn('walk' if not mask&1 else 'impossible',slots)
                self.assertNotIn('roll' if not mask&2 else 'impossible',slots)
                self.assertEqual(slots.count('walk')%2,0)
                self.assertEqual(frames[0]['x'],frames[-1]['x'])
                for frame in frames:
                    self.assertLessEqual(abs(frame['x']),motion.WALK_EXTENT)
                    self.assertTrue(frame['asset'].startswith('Motion_'))

    def test_new_neutral_and_required_poses_exist(self):
        self.assertTrue((ROOT/'Art/xiaobai-chibi-v2.png').exists())
        for action,info in motion.MANIFEST['actions'].items():
            for path in info['frames']:self.assertTrue((motion.ART/path).exists(),path)
        self.assertIn('roll',motion.MANIFEST['actions'])
        self.assertIn('turn_left',motion.MANIFEST['actions'])

    def test_island_frame_replaces_old_silhouette_instead_of_ghosting(self):
        # Two different sparse silhouettes at opposite ends recreate the V1.4
        # failure: transparent newer frames leak the previous pose underneath.
        a=Image.new('RGBA',(512,640));a.paste((255,255,255,255),(50,60,150,600))
        b=Image.new('RGBA',(512,640));b.paste((160,100,200,255),(350,60,450,600))
        art={'a':a,'b':b}
        first=motion.render_frame(art,{'asset':'a','x':-16})
        second=motion.render_frame(art,{'asset':'b','x':16})
        self.assertEqual(second.getchannel('A').getextrema(),(255,255))
        self.assertIsNone(ImageChops.difference(Image.alpha_composite(first,second),second).getbbox())
        leaky=motion.render_frame(art,{'asset':'b','x':16},opaque=False)
        self.assertIsNotNone(ImageChops.difference(Image.alpha_composite(first,leaky).convert('RGB'),second.convert('RGB')).getbbox())

    def test_30fps_phase_order_has_one_unambiguous_top_frame(self):
        self.assertEqual(motion.FPS,30)
        self.assertEqual(motion.PHASES,60)
        # Sample between EVERY 30fps boundary over a full minute, including
        # second/minute rollovers; model the actual cumulative native masks.
        for tick in range(1800):
            t=(tick+0.5)/30
            visible=[0]+[i for i in range(1,30) if math.floor(t-i/30)%2==0]
            if math.floor(t+1)%2==0:
                visible += [i for i in range(30,60) if math.floor(t-i/30)%2==0]
            phase=visible[-1]
            second=math.floor(t-1-phase/30)%60
            actual=(((second+1)%60)*30+phase)%1800
            self.assertEqual(actual,tick)

    def test_brisk_walk_keeps_feet_active_during_translation(self):
        for mask in (1,3):
            for seed in range(2):
                _,frames=motion.schedule(mask,seed)
                for previous,current in zip(frames,frames[1:]):
                    if previous['x']!=current['x']:
                        self.assertIn('Motion_walk_',current['asset'])

    def test_preloaded_glyph_survives_a_late_native_text_commit(self):
        # System video exposed an old pose for one frame when a text commit
        # lagged its mask. Replay a 20ms glyph delay at every phase boundary.
        # Preparing text one phase ahead fixes that delay while still hidden.
        old_pose_count=0
        for tick in range(1800):
            t=(tick+0.25)/30
            visible=[0]+[i for i in range(1,30) if math.floor(t-i/30)%2==0]
            if math.floor(t+1)%2==0:
                visible += [i for i in range(30,60) if math.floor(t-i/30)%2==0]
            phase=visible[-1]
            delayed=t-1-phase/30-0.020
            old=(((math.floor(delayed)+1)%60)*30+phase)%1800
            actual=(((math.floor(delayed+1/30)+1)%60)*30+phase)%1800
            old_pose_count += old!=tick
            self.assertEqual(actual,tick)
        self.assertGreater(old_pose_count,0)

    def test_dense_new_sequences_and_roll_share_clean_neutral_endpoints(self):
        for action in ('walk_left','walk_right','roll'):
            info=motion.MANIFEST['actions'][action]
            self.assertEqual(len(info['frames']),16)
            for relative in info['frames']:
                with Image.open(motion.ART/relative) as frame:
                    self.assertEqual(frame.size,(512,640))
                    self.assertEqual(frame.mode,'RGBA')
                    self.assertEqual(frame.getchannel('A').getextrema(),(0,255))
        roll=motion.MANIFEST['actions']['roll']['frames']
        self.assertEqual((motion.ART/roll[0]).read_bytes(),(motion.ART/roll[-1]).read_bytes())

    def test_full_width_walk_reaches_both_edges_and_immediately_returns(self):
        self.assertEqual(motion.WALK_MOVE_MS,4500)
        self.assertEqual(sum(motion.DURATIONS['walk_left']),1125)
        self.assertEqual(sum(motion.DURATIONS['roll']),1000)
        self.assertEqual(motion.ROLL_END,1000)
        for mask in (1,3):
            for seed in range(2):
                slots,frames=motion.schedule(mask,seed)
                i=0
                while i<12:
                    if slots[i]!='walk':i+=1;continue
                    self.assertLess(i,11)
                    self.assertEqual(slots[i+1],'walk')
                    outward=frames[i*150:(i+1)*150]
                    back=frames[(i+1)*150:(i+2)*150]
                    self.assertEqual((outward[0]['x'],outward[-1]['x']),(-50,50))
                    self.assertEqual((back[0]['x'],back[-1]['x']),(50,-50))
                    i+=2
        # Every source pose fits at either endpoint, including wings and tail.
        for info in motion.MANIFEST['actions'].values():
            for name in info['frames']:
                image=Image.open(motion.ART/name).convert('RGBA').resize((72,90))
                x0,y0,x1,y1=image.getbbox()
                for x in (-50,50):
                    self.assertGreaterEqual(54+x+x0,0)
                    self.assertLessEqual(54+x+x1,180)
                self.assertLessEqual(3+y1,96)

    def test_each_scene_replaces_old_pose_with_the_same_opaque_landscape(self):
        a=Image.new('RGBA',(512,640),(250,240,255,255))
        art={'person':a}
        backgrounds=[]
        for scene in motion.SCENES:
            bg=motion.scene_image(scene);backgrounds.append(bg.tobytes())
            self.assertEqual(bg.size,(180,96))
            self.assertEqual(bg.getchannel('A').getextrema(),(255,255))
            first=motion.render_frame(art,{'asset':'person','x':-50},scene=scene)
            last=motion.render_frame(art,{'asset':'person','x':50},scene=scene)
            self.assertIsNone(ImageChops.difference(Image.alpha_composite(first,last),last).getbbox())
            self.assertEqual(last.getpixel((12,45)),bg.getpixel((12,45)))
        self.assertEqual(len(set(backgrounds)),3)

    def test_hidden_bank_clock_does_not_cross_bank_during_two_hour_session(self):
        for bank in range(8):
            for elapsed in (0,1,59,60,3599,3600,7199,7200):
                for phase in (0,29,30,59):
                    counter=bank*3*3600+60+elapsed-1-phase/30
                    self.assertEqual(int(counter//3600)//3,bank)


if __name__=='__main__':unittest.main()
