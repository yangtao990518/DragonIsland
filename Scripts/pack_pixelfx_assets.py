"""Losslessly compress exported masters; leave intermediate PNGs untouched."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import shutil
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
def main():
    source=ROOT/'Art/PixelFX'; target=ROOT/'Art/PixelFXMasters'; target.mkdir(parents=True,exist_ok=True)
    manifest=json.loads((source/'manifest.json').read_text(encoding='utf-8'))
    def convert(page):
        src=source/page['file']; dest=target/Path(page['file']).with_suffix('.webp')
        if hashlib.sha256(src.read_bytes()).hexdigest()!=page['sha256']: raise ValueError('Changed export')
        dest.parent.mkdir(parents=True,exist_ok=True)
        with Image.open(src) as image: image.save(dest,lossless=True,method=4)
        return {'file':dest.relative_to(target).as_posix(),'sha256':hashlib.sha256(dest.read_bytes()).hexdigest()}
    with ThreadPoolExecutor(max_workers=4) as pool:
        for i,clip in enumerate(manifest['clips']):
            clip['pages']=list(pool.map(convert,clip['pages']))
            if i%20==0: print('PACK',i+1,'/',len(manifest['clips']),flush=True)
    manifest['actor_mask_source_sha256']=json.loads((source/'actor-mask.json').read_text())['source_sha256']
    shutil.copyfile(source/'actor-mask.json',target/'actor-mask.json')
    (target/'manifest.json').write_text(json.dumps(manifest),encoding='utf-8')
    print('Packed all',len(manifest['clips']),'PixelFX effects losslessly',flush=True)
if __name__=='__main__': main()
