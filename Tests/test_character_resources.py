"""Cross-character regression checks against the actual art and compiled timelines."""
import importlib.util
import json
from pathlib import Path
import unittest
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('prepare_motion',ROOT/'Scripts/prepare_motion.py')
motion=importlib.util.module_from_spec(spec);spec.loader.exec_module(motion)

class CharacterResourcesTests(unittest.TestCase):
    def test_every_character_has_normal_art_avatar_crop_and_separate_motion(self):
        characters=json.loads((ROOT/'Shared/Resources/Characters.json').read_text(encoding='utf-8'))
        self.assertEqual([c['id'] for c in characters],['xiaobai','dafeiyu'])
        for character in characters:
            self.assertNotEqual(character['portraitAsset'],character['chibiAsset'])
            for field in ('chibiSource','standingSource'):
                with Image.open(ROOT/character[field]) as image:
                    self.assertEqual(image.mode,'RGBA')
                    self.assertEqual(image.getchannel('A').getextrema(),(0,255))
            x,y,w,h=character['avatarCrop']
            self.assertTrue(0<=x<x+w<=1 and 0<=y<y+h<=1)
        self.assertNotEqual(characters[1]['motion']['fontPrefix'],'mAIverse')
        profile=characters[1]['motion']
        self.assertEqual(len(profile['greetingFrames']),4)
        self.assertTrue(all(name.startswith(profile['assetPrefix']+'_') for name in profile['greetingFrames']))

    def test_fish_poses_have_safe_alpha_scale_and_expressive_actions(self):
        folder=ROOT/'Art/DafeiyuMotion'
        manifest=json.loads((folder/'manifest.json').read_text(encoding='utf-8'))
        heights={}
        for action,info in manifest['actions'].items():
            self.assertEqual(len(info['frames']),len(info['frameDurationsMs']))
            self.assertGreaterEqual(len(set(info['expressions'])),3)
            heights[action]=[]
            for path in info['frames']:
                with Image.open(folder/path) as image:
                    self.assertEqual(image.size,(512,640))
                    self.assertEqual(image.convert('RGBA').getchannel('A').getextrema(),(0,255))
                    x0,y0,x1,y1=image.getbbox()
                    self.assertTrue(x0>0 and y0>0 and x1<512 and y1<640)
                    self.assertEqual(y1,600)
                    heights[action].append(y1-y0)
        for direction in ('left','right'):
            walking=heights['walk_'+direction]
            self.assertLess(max(walking)/min(walking),1.1)
            self.assertLess(abs(heights['roll_'+direction][-1]/max(walking)-1),.1)

    def test_both_characters_use_full_travel_and_their_own_assets(self):
        for name,prefix in [('MotionTimeline','Motion_'),('MotionTimelineDafeiyu','MotionDafeiyu_')]:
            path=ROOT/'Shared/Resources'/f'{name}.json'
            if not path.exists():self.skipTest('Run prepare_motion.py to compile timelines')
            timeline=json.loads(path.read_text(encoding='utf-8'))
            self.assertEqual(timeline['fps'],30)
            self.assertEqual(len(timeline['plans']),8)
            for plan in timeline['plans']:
                self.assertEqual(len(plan['frames']),1800)
                self.assertTrue(all(f['asset'].startswith(prefix) for f in plan['frames']))
                for leg in plan['legs']:
                    frames=plan['frames'][leg['start']*30:(leg['start']+leg['duration'])*30]
                    self.assertEqual(max(f['x'] for f in frames)-min(f['x'] for f in frames),100)
            for action in ('walk_right','walk_left','roll'):
                frames=timeline['previews'][action]
                self.assertEqual(frames[0]['x'],frames[-1]['x'])

    def test_fish_has_no_borrowed_voice_and_gentle_walking_timing(self):
        voices=json.loads((ROOT/'App/Resources/Voices.json').read_text(encoding='utf-8'))
        self.assertTrue(all(v['characterID']!='dafeiyu' for v in voices))
        manifest=json.loads((ROOT/'Art/DafeiyuMotion/manifest.json').read_text(encoding='utf-8'))
        durations={a:info['frameDurationsMs'] for a,info in manifest['actions'].items()}
        self.assertEqual(durations['walk_right'],[400]*4)
        for action in ('walk','roll'):
            for direction in ('left','right'):
                frames=motion.movement_leg(action,direction,durations)
                self.assertEqual(len(frames),300 if action=='walk' else 150)
                self.assertEqual({frames[0]['x'],frames[-1]['x']},{-50,50})

if __name__=='__main__':unittest.main()
