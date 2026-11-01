"""App-only PixelFX catalog plus approved character footage; no legacy skills."""
import hashlib
import json
from pathlib import Path
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]

def prepare():
    source = ROOT / 'Art/PixelFXMasters'
    if not (source / 'manifest.json').exists():
        raise RuntimeError('PixelFX masters must be exported and committed first')
    catalog = json.loads((source / 'manifest.json').read_text(encoding='utf-8'))
    target = ROOT / 'App/Resources/SurvivorGameV2'
    target.mkdir(parents=True, exist_ok=True)
    legacy = ROOT / 'App/Resources/SurvivorGame'
    actors = json.loads((legacy / 'manifest.json').read_text(encoding='utf-8'))
    actors['clips'] = [c for c in actors['clips'] if c['kind'] == 'actor']
    for clip in actors['clips']:
        for page in clip['pages']:
            dest = target / page['file']; dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(legacy / page['file'], dest)
    for name in ['dafeiyu-idle.png','dafeiyu-idle.json']:
        shutil.copyfile(legacy / name, target / name)
    for clip in catalog['clips']:
        for page in clip['pages']:
            path = Path(page['file'])
            if path.is_absolute() or '..' in path.parts: raise ValueError('Invalid PixelFX page')
            raw = (source / path).read_bytes()
            if hashlib.sha256(raw).hexdigest() != page['sha256']: raise ValueError('Changed PixelFX master')
            dest = target / 'PixelFX' / path.with_suffix('.png'); dest.parent.mkdir(parents=True, exist_ok=True)
            with Image.open(source/path) as image: image.convert('RGBA').save(dest,compress_level=6)
            page['file'] = 'PixelFX/' + path.with_suffix('.png').as_posix()
            page['source_sha256'] = page['sha256']
            page['sha256'] = hashlib.sha256(dest.read_bytes()).hexdigest()
        # A small independent thumbnail, not a view retaining a full atlas page.
        picks = [round(i*(len(clip['frames'])-1)/6) for i in range(1,6)]
        best, score = None, -1
        w,h = clip['cell_size']; columns,rows = clip['grid']
        for index in picks:
            frame = clip['frames'][index]; cell = frame['cell']; page = clip['pages'][cell//(columns*rows)]
            with Image.open(target/page['file']) as atlas:
                offset = cell%(columns*rows); x,y = (offset%columns)*w,(offset//columns)*h
                image = atlas.crop((x,y,x+w,y+h)).convert('RGBA')
                alpha = image.getchannel('A'); value = sum(alpha.histogram()[16:])
                if value > score: best,score = image,value
        box = best.getchannel('A').getbbox()
        if box: best = best.crop(box)
        best.thumbnail((144,144), Image.Resampling.NEAREST)
        thumbs = target/'PixelFX/Thumbnails'; thumbs.mkdir(exist_ok=True)
        best.save(thumbs/(clip['id']+'.png'))
    (target/'manifest.json').write_text(json.dumps({'clips':actors['clips']+catalog['clips']}),encoding='utf-8')
    (target/'PixelFXCatalog.json').write_text(json.dumps({'source':catalog['source'],'skills':catalog['skills']}),encoding='utf-8')
    for name in ['LICENSE','NOTICE.md','UPSTREAM.json']:
        shutil.copyfile(ROOT/'ThirdParty/PixelFX'/name,target/'PixelFX'/name)
    print('PixelFX App catalog:',len(catalog['skills']),'choices; legacy bubble/thunder not bundled in game V2')

if __name__ == '__main__': prepare()
