import hashlib
import json
from pathlib import Path
import unittest
import wave
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]


class ConfirmedSurvivorAssetsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source=ROOT/'Art/SurvivorV3'
        cls.runtime=ROOT/'App/Resources/SurvivorGameV3'
        cls.master=json.loads((cls.source/'manifest.json').read_text(encoding='utf-8'))
        cls.mobile=json.loads((cls.runtime/'manifest.json').read_text(encoding='utf-8'))

    def test_exact_approved_catalog_and_icons(self):
        self.assertEqual(len(self.master['skills']),8)
        self.assertEqual(sum(len(s['levels']) for s in self.master['skills']),40)
        self.assertEqual(len(self.master['characters']),20)
        self.assertEqual(len(self.master['icons']),13)
        self.assertEqual(sum(i['group']=='support' for i in self.master['icons']),5)
        for icon in self.master['icons']:
            self.assertEqual(hashlib.sha256((self.source/icon['file']).read_bytes()).hexdigest(),icon['sha256'])
            with Image.open(self.runtime/'Icons'/(icon['id']+'.png')) as image:self.assertEqual(image.size,(128,128))

    def test_complete_frames_and_original_variable_timing(self):
        source={c['id']:c for c in self.master['clips']}
        for clip in self.mobile['clips']:
            if clip['id']=='dafeiyu-run':continue
            original=source[clip['id']]
            self.assertEqual([(f['source_index'],f['start_ms'],f['duration_ms']) for f in clip['frames']],[(f['source_index'],f['start_ms'],f['duration_ms']) for f in original['frames']])
            self.assertAlmostEqual(sum(f['duration_ms'] for f in clip['frames']),clip['duration_ms'],places=5)
            if clip['kind']=='skeleton':
                self.assertEqual(len(clip['frames']),240)
                self.assertAlmostEqual(clip['duration_ms'],4016.667,places=3)
                self.assertGreater(max(f['duration_ms'] for f in clip['frames']),30)
                self.assertFalse(clip['loop'])

    def test_transparent_bounded_pages_and_hashes(self):
        for clip in self.mobile['clips']:
            for page in clip['pages']:
                path=self.runtime/page['file']
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),page['sha256'])
                with Image.open(path) as image:
                    self.assertEqual(image.mode,'RGBA')
                    self.assertLessEqual(max(image.size),1024)
                    self.assertEqual(image.getchannel('A').getextrema()[0],0)

    def test_mobile_frames_preserve_master_resolution_and_pixels(self):
        masters={c['id']:c for c in self.master['clips']}
        for clip in self.mobile['clips']:
            if clip['id']=='dafeiyu-run':continue
            original=masters[clip['id']]
            self.assertEqual(clip['cell_size'],original['cell_size'])
            self.assertEqual(clip['display_scale'],1)
            width,height=clip['cell_size']
            for index in {0,len(clip['frames'])//2,len(clip['frames'])-1}:
                samples=[]
                for catalog,folder in [(original,self.source),(clip,self.runtime)]:
                    cell=catalog['frames'][index]['cell']
                    capacity=catalog['grid'][0]*catalog['grid'][1]
                    slot=cell%capacity
                    x=slot%catalog['grid'][0]*width;y=slot//catalog['grid'][0]*height
                    with Image.open(folder/catalog['pages'][cell//capacity]['file']) as page:
                        samples.append(page.convert('RGBA').crop((x,y,x+width,y+height)).tobytes())
                self.assertEqual(samples[0],samples[1],(clip['id'],index))

    def test_no_retired_monsters_or_unconfirmed_effects(self):
        ids={c['id'] for c in self.mobile['clips']}
        self.assertFalse(ids.intersection({'demon-run','mushroom-run','thunder-1','water-bubble'}))
        self.assertFalse(any('fusion-review' in s.lower() for s in ids))
        self.assertTrue({'fireball-flight','fireball-impact','seeking-flight','seeking-merged','archer-arrow'}.issubset(ids))

    def test_native_smoke_feet_anchor_and_module_origin(self):
        clips={c['id']:c for c in self.master['clips']}
        c=clips['skeleton-group01-skeleton-roles-R1C1']
        self.assertTrue(0<c['pivot'][0]<1)
        self.assertTrue(0<c['pivot'][1]<0.15)
        self.assertEqual(c['frame_count'],240)
        flight=clips['fireball-flight']
        self.assertEqual(flight['source_pivot'],[110,40])
        self.assertAlmostEqual(flight['duration_ms'],1200,places=5)
        self.assertTrue(flight['loop'])

    def test_distinct_skill_audio_and_finite_map_texture(self):
        hashes=set()
        for skill in self.master['skills']:
            path=self.runtime/'Audio'/(skill['id']+'.wav')
            with wave.open(str(path)) as audio:self.assertGreater(audio.getnframes(),100)
            hashes.add(hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertEqual(len(hashes),8)
        self.assertTrue((self.runtime/'Terrain/grass.png').is_file())


if __name__=='__main__':unittest.main()
