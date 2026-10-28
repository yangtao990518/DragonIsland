"""Full original frame/timing, native lossless recovery and timer scheduling."""
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import unittest
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('motion',ROOT/'Scripts/prepare_motion.py')
motion=importlib.util.module_from_spec(spec);spec.loader.exec_module(motion)


class FullVideoActionTests(unittest.TestCase):
    def test_two_minute_timer_phase_matches_the_original_preload_clock(self):
        for tick in range(3600):
            t=(tick+.25)/30
            visible=[0]+[i for i in range(1,30) if math.floor(t-i/30)%2==0]
            if math.floor(t+1)%2==0:visible += [i for i in range(30,60) if math.floor(t-i/30)%2==0]
            phase=visible[-1]
            timer=math.floor(t+60-1-phase/30+1/30-.020)
            minute=(timer//60)%2;second=timer%60
            actual=(((minute*60+second+1-60)%120)*30+phase)%3600
            self.assertEqual(actual,tick)
    def clips(self):
        directory=ROOT/'Art/VideoActions'
        return [(directory/e['manifest'],json.loads((directory/e['manifest']).read_text(encoding='utf-8')))
                for e in json.loads((directory/'manifest.json').read_text(encoding='utf-8'))['clips']]

    def test_every_original_frame_and_presentation_duration_is_preserved(self):
        clips=self.clips();self.assertEqual({c['action'] for _,c in clips},{'dance1','dance2'})
        for path,c in clips:
            self.assertTrue(c['fullOriginalRange']);self.assertFalse(c['upscaled']);self.assertFalse(c['generatedPoses'])
            self.assertEqual(c['frameCount'],720)
            self.assertEqual([f['index'] for f in c['frames']],list(range(720)))
            self.assertEqual(c['sourceSize'],[1280,720])
            self.assertLessEqual(c['durationMs'],20_000)
            self.assertAlmostEqual(sum(f['duration_ms'] for f in c['frames']),c['durationMs'],places=5)
            self.assertAlmostEqual(c['durationMs'],12096.009,places=4)
            self.assertEqual(hashlib.sha256((path.parent/c['sourceVideo']).read_bytes()).hexdigest(),c['sourceSHA256'])
            for a,b in zip(c['frames'],c['frames'][1:]):
                self.assertGreater(b['pts'],a['pts'])
                expected=(b['pts']-a['pts'])*c['timeBase'][0]/c['timeBase'][1]*1000
                self.assertAlmostEqual(a['duration_ms'],expected,places=6)

    def test_native_alpha_can_be_reconstructed_after_lossless_atlas_storage(self):
        for path,c in self.clips():
            width,height=c['sourceSize'];crop=c['uniformCrop']
            for j,atlas in enumerate(c['atlases']):
                file=path.parent/atlas['path']
                self.assertEqual(hashlib.sha256(file.read_bytes()).hexdigest(),atlas['sha256'])
                records=[f for f in c['frames'] if f['atlas']==j]
                with Image.open(file) as sheet:
                    for f in [records[0],records[-1]]:
                        x,y,w,h=f['rect'];native=Image.new('RGBA',(width,height))
                        native.paste(sheet.crop((x,y,x+w,y+h)),crop[:2])
                        self.assertEqual(hashlib.sha256(native.tobytes()).hexdigest(),f['rgba_sha256'])

    def test_app_atlases_include_all_original_timing_and_stay_within_cache_budget(self):
        path=ROOT/'App/Resources/VideoActions.json'
        if not path.exists():self.skipTest('Run prepare_assets.py to build app atlas copies')
        runtime=json.loads(path.read_text(encoding='utf-8'));self.assertEqual(len(runtime),2)
        native={c['id']:c for _,c in self.clips()}
        for clip in runtime:
            source=native[clip['id']]
            self.assertEqual(clip['frameCount'],source['frameCount'])
            self.assertEqual(clip['frameStartMs'],[f['start_seconds']*1000 for f in source['frames']])
            self.assertEqual(clip['frameDurationsMs'],[f['duration_ms'] for f in source['frames']])
            self.assertAlmostEqual(sum(clip['frameDurationsMs']),clip['durationMs'],places=5)
            w,h=clip['cellSize'];columns,rows=clip['grid']
            self.assertLessEqual(3*w*h*columns*rows*4,64*1024*1024)
            for name in clip['atlases']:
                with Image.open(ROOT/'App/Resources/VideoActionAtlases'/f'{name}.png') as image:
                    self.assertEqual(image.size,(w*columns,h*rows))
                    self.assertEqual(image.mode,'RGBA')

    def test_all_enabled_dances_finish_in_every_independent_timer_bank(self):
        clips=motion.load_daily_art('dafeiyu')
        for mask in range(64):
            for seed in range(2):
                _,frames,legs=motion.daily_schedule(mask,seed,motion.DURATIONS,clips)
                self.assertEqual(len(frames),3600 if mask&48 else 1800)
                self.assertEqual(frames[0]['x'],frames[-1]['x'])
                for action,bit in [('dance1',16),('dance2',32)]:
                    selected=[f for f in frames if f['action']==action]
                    if not mask&bit:self.assertFalse(selected)
                    else:
                        self.assertEqual(selected[0]['sourceFrame'],0)
                        self.assertEqual(selected[-1]['sourceFrame'],719)
                        self.assertGreaterEqual(len(selected)/30,sum(clips[action]['durations'])/1000)
                for action,bit in [('walk',1),('roll',2),('ride',4),('pet_walk',8)]:
                    self.assertEqual(any(f['action']==action for f in frames),bool(mask&bit))
                for f in frames:
                    w=f.get('width',72)
                    self.assertGreaterEqual((180-w)//2+f['x'],0)
                    self.assertLessEqual((180-w)//2+f['x']+w,180)

    def test_photos_have_original_bytes_and_do_not_replace_identity_art(self):
        characters=json.loads((ROOT/'Shared/Resources/Characters.json').read_text(encoding='utf-8'))
        for c in characters:
            self.assertEqual(len(c['artworks']),4 if c['id']=='dafeiyu' else 1)
            self.assertEqual(len({a['id'] for a in c['artworks']}),len(c['artworks']))
            for a in c['artworks']:
                self.assertEqual(hashlib.sha256((ROOT/a['source']).read_bytes()).hexdigest(),a['sha256'])
                self.assertTrue(a['asset'].startswith('WorldPhoto'))
                self.assertNotIn(a['asset'],[c['portraitAsset'],c['chibiAsset'],c['heroAsset']])


if __name__=='__main__':unittest.main()
