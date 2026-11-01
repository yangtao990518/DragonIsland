"""Import the confirmed Nov-2 library without touching originals or their timing.

Run explicitly on the material workstation. Ordinary builds need only the
portable lossless pages in Art/SurvivorV3, not these local source directories.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
from PIL import Image
import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def pack(spec):
    ident, path, metadata, timing, kind, pivot = spec
    data = json.loads(Path(metadata).read_text(encoding='utf-8'))
    frames = data['frames']
    if isinstance(frames, dict):
        frames = list(frames.values())
    with Image.open(path) as source:
        source = source.convert('RGBA')
        boxes = [(f['frame']['x'], f['frame']['y'], f['frame']['x']+f['frame']['w'], f['frame']['y']+f['frame']['h']) for f in frames]
        union = None
        for box in boxes:
            b = source.crop(box).getchannel('A').getbbox()
            if b:
                union = b if union is None else (min(union[0],b[0]),min(union[1],b[1]),max(union[2],b[2]),max(union[3],b[3]))
        union = union or (0,0,frames[0]['frame']['w'],frames[0]['frame']['h'])
        # Static union trim for the ENTIRE clip. Never recenter individual frames.
        left,top,right,bottom=union; w,h=right-left,bottom-top
        if pivot is None and kind=='monster-projectile':
            pivot=[(left+right)/2,(top+bottom)/2]
        if pivot is None:
            original = source.crop(boxes[0]); alpha=np.array(original.getchannel('A'))
            yy,xx=np.where(alpha>96)
            floor=int(np.quantile(yy,.995))
            feet=np.where((alpha>96)&(np.indices(alpha.shape)[0]>=floor-7))[1]
            pivot=[float((np.quantile(feet,.03)+np.quantile(feet,.97))/2),float(floor)]
        px,py=pivot
        cols=max(1,1024//w); rows=max(1,1024//h); cap=cols*rows
        folder=ROOT/'Art/SurvivorV3'/ident; folder.mkdir(parents=True,exist_ok=True)
        pages=[]; timeline=[]; end=0
        for i,box in enumerate(boxes):
            if i%cap==0:
                # Last page omits completely unused bottom rows.
                occupied=min(cap,len(boxes)-i)
                page=Image.new('RGBA',(cols*w,((occupied+cols-1)//cols)*h))
            image=source.crop(box).crop(union)
            cell=i%cap; page.paste(image,((cell%cols)*w,(cell//cols)*h))
            duration=timing[i] if timing else frames[i]['duration']
            timeline.append(dict(source_index=i,cell=i,start_ms=end,duration_ms=duration));end+=duration
            if i%cap==cap-1 or i==len(boxes)-1:
                name=f'{ident}/atlas-{len(pages):03}.webp';dest=ROOT/'Art/SurvivorV3'/name
                page.save(dest,lossless=True,method=3)
                pages.append(dict(file=name,sha256=digest(dest),size=list(page.size)))
        # Runtime uses grid rows for UVs, so pad last page to the same grid height.
        for record in pages:
            dest=ROOT/'Art/SurvivorV3'/record['file']
            with Image.open(dest) as image:
                if image.height!=rows*h:
                    padded=Image.new('RGBA',(cols*w,rows*h));padded.paste(image,(0,0));padded.save(dest,lossless=True,method=3)
            record.update(sha256=digest(dest),size=[cols*w,rows*h])
        info=data.get('meta',{}); fx=info.get('pixelfx',{});anim=info.get('animation',{})
        result=dict(id=ident,kind=kind,cell_size=[w,h],grid=[cols,rows],pivot=[(px-left)/w,1-(py-top)/h],
                    duration_ms=end,frame_count=len(frames),unique_count=len(frames),pages=pages,frames=timeline,
                    source_atlas_sha256=digest(path),source_metadata_sha256=digest(metadata),source_crop=list(union),source_pivot=pivot,
                    loop=fx.get('loop',anim.get('loop',False)),seam='untrimmed source; not claimed seamless' if kind=='skeleton' else 'source timing')
        # Aseprite origin may legitimately sit outside occupied pixels; preserve it.
        result['pivot_unclamped']=result['pivot']
        print('Imported',ident,len(frames),'frames',round(end,3),'ms',flush=True)
        return result


def main():
    parser=argparse.ArgumentParser();parser.add_argument('catalog',type=Path);parser.add_argument('--smoke',action='store_true');args=parser.parse_args()
    data=json.loads(args.catalog.read_text(encoding='utf-8'));specs=[];characters=[];skills=[]
    for c in data['characters'][:1] if args.smoke else data['characters']:
        meta=json.loads(Path(c['animationMetadata']).read_text(encoding='utf-8'))
        ident='skeleton-'+c['id'].replace('/','-')
        specs.append((ident,c['atlas'],c['atlasMetadata'],[d*1000 for d in meta['frameDurationsSeconds']],'skeleton',None))
        characters.append(dict(id=ident,name=c['name'],role=c['role'],bodyAction=c['clip'],nativeSize=c['cellSize'],sourceLoop=False))
    for s in data['playerSkills'][:1] if args.smoke else data['playerSkills']:
        levels=[]
        for level in s['levels'][:1] if args.smoke else s['levels']:
            ident=f"{s['id']}-lv{level['level']}"
            meta=json.loads(Path(level['metadata']).read_text(encoding='utf-8'))['meta']['pixelfx']
            specs.append((ident,level['atlas'],level['metadata'],None,'local-skill',meta['pivot']))
            levels.append(dict(level=level['level'],clipID=ident,duration=level['durationMs']/1000,loop=level['loop']))
        skills.append(dict(id=s['id'],name=s['name'],behavior=s['behavior'],levels=levels))
    # Approved modular flame art drives real projectile movement/collision.
    fire=Path(data['playerSkills'][0]['root'])/'assets'
    for module in ['flight','impact']:
        meta=json.loads((fire/f'Fireball-{module}.json').read_text())
        fx=meta['meta']['pixelfx']
        specs.append((f'fireball-{module}',fire/f'Fireball-{module}.png',fire/f'Fireball-{module}.json',
                      [1000/fx['fps']]*len(meta['frames']),'local-module',fx['pivot']))
    if not args.smoke:
        lightning=Path(data['playerSkills'][1]['root'])/'assets'
        meta=json.loads((lightning/'Lightning-explosion.json').read_text())
        specs.append(('lightning-explosion',lightning/'Lightning-explosion.png',lightning/'Lightning-explosion.json',None,'local-module',meta['meta']['pixelfx']['pivot']))
        c=data['separateMonsterProjectile'];a=json.loads(Path(c['animationMetadata']).read_text())
        specs.append(('archer-arrow',c['atlas'],c['atlasMetadata'],[d*1000 for d in a['frameDurationsSeconds']],'monster-projectile',None))
    if not args.smoke:
        for name in ['seeking-flight','seeking-merged']:
            folder=ROOT/'Art/SurvivorV3/Modules';path=folder/(name+'.json')
            if path.exists():
                meta=json.loads(path.read_text());fx=meta['meta']['pixelfx']
                specs.append((name,folder/(name+'.png'),path,[1000/fx['fps']]*len(meta['frames']),'local-module',fx['pivot']))
    target=ROOT/'Art/SurvivorV3';target.mkdir(parents=True,exist_ok=True)
    with ThreadPoolExecutor(max_workers=3) as pool: clips=list(pool.map(pack,specs))
    icons=[]
    for icon in data['icons']:
        source=Path(icon['png']);dest=target/'Icons'/source.name;dest.parent.mkdir(exist_ok=True);shutil.copyfile(source,dest)
        icons.append(dict(id=icon['id'],name=icon['name'],group=icon['group'],file='Icons/'+source.name,sha256=digest(source)))
    record=dict(schema_version=3,source_catalog_sha256=digest(args.catalog),source_date=data['date'],clips=clips,skills=skills,characters=characters,icons=icons,smoke_only=args.smoke)
    (target/('smoke-manifest.json' if args.smoke else 'manifest.json')).write_text(json.dumps(record,ensure_ascii=False),encoding='utf-8')
    for name in ['LICENSE','NOTICE.md']:
        shutil.copyfile(ROOT/'ThirdParty/PixelFX'/name,target/name)
    print('Ready:',len(clips),'clips',len(icons),'icons; original files retained.')


if __name__=='__main__':main()
