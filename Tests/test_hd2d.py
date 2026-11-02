import unittest,json,zipfile,io,hashlib
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];TARGET=ROOT/'App/Resources/SurvivorGameV3'
class HD2DAssets(unittest.TestCase):
 @classmethod
 def setUpClass(cls):cls.data=json.loads((TARGET/'hd2d.json').read_text());cls.clips={c['id']:c for c in cls.data['clips']}
 def frame(self,c,i):
  w,h=c['cell_size'];cap=c['grid'][0]*c['grid'][1];slot=i%cap
  im=Image.open(TARGET/c['pages'][i//cap]['file']).convert('RGBA');return im.crop((slot%c['grid'][0]*w,slot//c['grid'][0]*h,slot%c['grid'][0]*w+w,slot//c['grid'][0]*h+h))
 def test_both_v4_bodies_preserve_all_240_pixels_and_pts(self):
  with zipfile.ZipFile(ROOT/'Art/HD2DReview/2026-11-02/SourceBundles/HD2D-characters-idle-eye-only-v4.zip') as z:
   for hero in ['dafeiyu','xiaobai']:
    base=f'characters-v4/{hero}/';m=json.loads(z.read(base+'manifest.json'));c=self.clips['hd-'+hero+'-idle'];self.assertEqual(len(c['frames']),240);self.assertAlmostEqual(c['duration_ms'],4097);pages={}
    for i,f in enumerate(m['frames']):
     if f['atlas'] not in pages:pages[f['atlas']]=Image.open(io.BytesIO(z.read(base+m['atlases'][f['atlas']]['file']))).convert('RGBA')
     x,y,w,h=f['rect'];expected=pages[f['atlas']].crop((x,y,x+w,y+h)).crop(tuple(c['source_crop']))
     self.assertEqual(self.frame(c,i).tobytes(),expected.tobytes());self.assertAlmostEqual(c['frames'][i]['start_ms'],f['sourceStartMs']);self.assertAlmostEqual(c['frames'][i]['duration_ms'],f['originalDurationMs'])
 def test_all_monsters_keep_ids_actions_and_release_timing(self):
  cat=json.loads((ROOT/'Tools/HD2DMaterialReview/assets/monsters/catalog.json').read_text());self.assertEqual(len(self.data['monsters']),20)
  for m in cat['characters']:
   c=self.clips['hd-'+m['sourceID']];attack=self.clips[c['id']+'-attack'];rule=next(r for r in self.data['monsters'] if r['id']==m['sourceID'])
   self.assertEqual(len(c['frames']),4);self.assertAlmostEqual(c['duration_ms'],600);self.assertEqual(len(attack['frames']),len(m['combat']['frames']));self.assertAlmostEqual(rule['release'],m['combat']['release']);self.assertAlmostEqual(attack['duration_ms'],m['combat']['duration']*1000)
 def test_fx_source_pixels_and_every_frame_present(self):
  for name,id in [('flight','fireball-flight'),('impact','fireball-impact'),('lightning-strike','lightning-lv1'),('lightning-star','lightning-explosion'),('orbit-blade','hd-orbit-blade'),('orbit-crescent','hd-orbit-crescent'),('seeking-flight','seeking-flight'),('seeking-merged','seeking-merged')]:
   im=Image.open(ROOT/f'Tools/HD2DMaterialReview/assets/{name}.png').convert('RGBA');c=self.clips[id];self.assertEqual(len(c['frames']),16)
   for i in range(16):self.assertEqual(self.frame(c,i).tobytes(),im.crop((i%4*96,i//4*96,i%4*96+96,i//4*96+96)).tobytes())
 def test_pages_bounded_and_hashes_intact(self):
  first_bytes=0
  for c in self.clips.values():
   with Image.open(TARGET/c['pages'][0]['file']) as first:first_bytes+=first.width*first.height*4
   end=0
   for f in c['frames']:self.assertAlmostEqual(f['start_ms'],end);self.assertGreater(f['duration_ms'],0);end+=f['duration_ms']
   self.assertAlmostEqual(end,c['duration_ms'])
   for p in c['pages']:
    path=TARGET/p['file'];self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),p['sha256']);
    with Image.open(path) as image:self.assertLessEqual(max(image.size),1024)
  self.assertLess(first_bytes,32*1024*1024)
if __name__=='__main__':unittest.main()
