"""Check restored artwork, exported frames, leash joins and decoded frame counts."""
import hashlib
import json
import subprocess
import numpy as np
from PIL import Image
import animation_runtime as runtime

ROOT=runtime.REPOSITORY
OUT=ROOT/'output/pet-walk-batch2/walk-rig-v4-review'

def main():
    manifest=json.loads((ROOT/'AnimationDrafts/2026-10-27/manifest.json').read_text(encoding='utf-8'))
    png=[item for item in manifest['files'] if item['path'].endswith('.png')]
    changed=[item['path'] for item in png if hashlib.sha256((ROOT/item['path']).read_bytes()).hexdigest()!=item['sha256']]
    assert not changed,changed
    report=dict(restored_pngs_unchanged=len(png),roles={},videos=[])
    for role in ['xiaobai','dafeiyu']:
        files=sorted((OUT/role/'frames-60fps').glob('*.png'))
        assert len(files)==96,(role,len(files))
        hashes=set()
        failures=[]
        for path in files:
            image=Image.open(path).convert('RGBA')
            assert image.size==(896,640)
            hashes.add(hashlib.sha256(image.tobytes()).hexdigest())
            for scale in [1.,556/896]:
                view=image if scale==1 else image.convert('RGBa').resize((556,397),Image.Resampling.LANCZOS).convert('RGBA')
                alpha=np.asarray(view.getchannel('A'))
                start,end=round(420*scale),round(535*scale)
                previous=None
                for x in range(round(437*scale),round(444*scale)+1):
                    ys=np.flatnonzero(alpha[start:end,x]>12)
                    if len(ys)==0 or (previous is not None and np.min(np.abs(ys[:,None]-previous[None,:]))>2):
                        failures.append((path.name,scale,x))
                    previous=ys
        assert len(hashes)==96,(role,'unexpected repeated poses',len(hashes))
        assert not failures,(role,'leash join gaps',failures)
        report['roles'][role]=dict(frames=len(files),unique_frames=len(hashes),leash_join_gaps=0,
                                   leash_scales=[1.,556/896])
    for filename in ['pet-walk-full-v4.mp4','pet-walk-feet-v4.mp4']:
        result=subprocess.run([runtime.ffmpeg(),'-hide_banner','-v','error','-nostats','-progress','pipe:1',
            '-i',str(OUT/filename),'-f','null','-'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,
            text=True,encoding='utf-8',check=True)
        values={}
        for line in result.stdout.splitlines():
            if '=' in line:
                key,value=line.split('=',1)
                values[key]=value.strip()
        assert int(values['frame'])==384,(filename,values)
        assert values['progress']=='end'
        assert not result.stderr.strip(),result.stderr
        report['videos'].append(dict(path=filename,decoded_frames=int(values['frame']),
            sha256=hashlib.sha256((OUT/filename).read_bytes()).hexdigest()))
    report['visual_acceptance']='pending user review'
    (OUT/'final-check.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2))

if __name__=='__main__':
    main()
