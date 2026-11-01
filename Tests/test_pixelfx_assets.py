import hashlib
import json
from pathlib import Path
import unittest
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
class PixelFXAssetsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.master=ROOT/'Art/PixelFXMasters'
        cls.data=json.loads((cls.master/'manifest.json').read_text(encoding='utf-8'))
        cls.app=ROOT/'App/Resources/SurvivorGameV2'
        cls.runtime=json.loads((cls.app/'manifest.json').read_text(encoding='utf-8'))
    def test_full_pinned_catalog(self):
        skills=self.data['skills']
        self.assertEqual(len(skills),244)
        self.assertEqual(len({s['id'] for s in skills}),244)
        self.assertEqual(len({s['category'] for s in skills}),21)
        self.assertEqual(self.data['source']['commit'],'a84159688af3ca37a4be05a0d422b94451b2e24e')
    def test_original_complete_effect_times(self):
        for clip in self.data['clips']:
            end=0
            for i,f in enumerate(clip['frames']):
                self.assertEqual(f['source_index'],i)
                self.assertAlmostEqual(f['start_ms'],end,places=4)
                self.assertAlmostEqual(f['duration_ms'],1000/60,places=4)
                end=f['start_ms']+f['duration_ms']
            self.assertAlmostEqual(end,clip['duration_ms'],places=4)
            self.assertTrue(all(0<=p<=1 for p in clip['pivot']))
    def test_all_master_hashes_and_page_limits(self):
        for clip in self.data['clips']:
            for page in clip['pages']:
                path=self.master/page['file']
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),page['sha256'])
                with Image.open(path) as image:
                    # Fully opaque transition pages may omit a redundant alpha
                    # plane in lossless WebP; runtime PNGs restore alpha=255.
                    self.assertIn(image.mode,('RGBA','RGB'))
                    self.assertLessEqual(max(image.size),1024)
    def test_runtime_contains_every_choice_and_no_retired_effects(self):
        ids={s['id'] for s in self.data['skills']}
        self.assertEqual({c['id'] for c in self.runtime['clips']},ids|{'dafeiyu-run','demon-run','mushroom-run'})
        self.assertFalse((self.app/'water-bubble.png').exists())
        for clip in self.runtime['clips']:
            for page in clip['pages']:
                self.assertEqual(hashlib.sha256((self.app/page['file']).read_bytes()).hexdigest(),page['sha256'])
        self.assertEqual(len(list((self.app/'PixelFX/Thumbnails').glob('*.png'))),244)
    def test_packing_is_pixel_lossless(self):
        categories=set(); runtime={c['id']:c for c in self.runtime['clips']}
        for clip in self.data['clips']:
            category=next(s['category'] for s in self.data['skills'] if s['id']==clip['id'])
            if category in categories: continue
            categories.add(category)
            with Image.open(self.master/clip['pages'][0]['file']) as a, Image.open(self.app/runtime[clip['id']]['pages'][0]['file']) as b:
                self.assertEqual(b.mode,'RGBA')
                self.assertEqual(a.convert('RGBA').tobytes(),b.tobytes())
    def test_approved_character_mask_and_license_not_gallery_font(self):
        self.assertEqual(self.data['actor_mask_source_sha256'],hashlib.sha256((ROOT/'Art/dafeiyu-chibi.png').read_bytes()).hexdigest())
        self.assertTrue((self.app/'PixelFX/LICENSE').exists())
        self.assertTrue((self.app/'PixelFX/NOTICE.md').exists())
        self.assertFalse(list((ROOT/'ThirdParty/PixelFX').rglob('*.woff2')))

if __name__=='__main__': unittest.main()
