"""App-only PixelFX catalog plus approved character footage; no legacy skills."""
import hashlib
import json
from pathlib import Path
import shutil
from PIL import Image
import copy
from prepare_survivor_audio import prepare_audio

ROOT = Path(__file__).resolve().parents[1]

def prepare():
    source = ROOT / 'Art/PixelFXMasters'
    if not (source / 'manifest.json').exists():
        raise RuntimeError('PixelFX masters must be exported and committed first')
    catalog = json.loads((source / 'manifest.json').read_text(encoding='utf-8'))
    target = ROOT / 'App/Resources/SurvivorGameV2'
    target.mkdir(parents=True, exist_ok=True)
    previous = json.loads((target/'manifest.json').read_text()) if (target/'manifest.json').exists() else {'clips':[]}
    cached={page['file']:page for clip in previous['clips'] for page in clip['pages']}
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
            key='PixelFX/'+path.with_suffix('.png').as_posix()
            entry=cached.get(key,{})
            if not (dest.exists() and entry.get('source_sha256')==page['sha256'] and hashlib.sha256(dest.read_bytes()).hexdigest()==entry.get('sha256')):
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
    gameplay = json.loads((source/'gameplay.json').read_text(encoding='utf-8'))
    for skill in catalog['skills']:
        rule = gameplay[skill['id']]
        skill.update(rule)
        skill['description'] = ("按可见落点范围命中，升级可查看具体数值。" if rule['role']=='attack' else "恢复自身生命，不对怪物造成伤害。" if rule['role']=='support' else "拾取物品素材，不占用攻击技能栏。" if rule['role']=='item' else "仅供特效预览，不加入攻击与升级池。")
    # Combat-only, lower-resolution atlas; ALL original frame timestamps retained.
    # Original full-resolution gallery pages above remain unchanged.
    combat=[]
    active={key for key,row in gameplay.items() if row['role'] in ('attack','support')} | {'impacts-hit-spark','spawn-poof','pickups-collect-burst','ui-level-up','holy-heal'}
    for original in actors['clips']+catalog['clips']:
        if original['kind'] != 'actor' and original['id'] not in active: continue
        clip=copy.deepcopy(original); w,h=clip['cell_size']
        limit=192 if clip['id']=='dafeiyu-run' else 96
        scale=min(1,limit/max(w,h)); nw,nh=max(1,round(w*scale)),max(1,round(h*scale))
        cols,rows=max(1,768//nw),max(1,768//nh); capacity=cols*rows
        pages=[]; atlas=None; loaded={}
        for index,frame in enumerate(clip['frames']):
            oldcell=frame['cell']; oldcap=original['grid'][0]*original['grid'][1]
            oldpage=oldcell//oldcap
            if oldpage not in loaded:
                loaded.clear(); loaded[oldpage]=Image.open(target/original['pages'][oldpage]['file']).convert('RGBA')
            offset=oldcell%oldcap; x,y=offset%original['grid'][0]*w,offset//original['grid'][0]*h
            cell=loaded[oldpage].crop((x,y,x+w,y+h)).resize((nw,nh),Image.Resampling.LANCZOS if clip['kind']=='actor' else Image.Resampling.NEAREST)
            if index%capacity==0: atlas=Image.new('RGBA',(cols*nw,rows*nh))
            atlas.paste(cell,((index%capacity)%cols*nw,(index%capacity)//cols*nh))
            frame['cell']=index
            if index%capacity==capacity-1 or index==len(clip['frames'])-1:
                file=f"Combat/{clip['id']}-{len(pages)}.png"; dest=target/file; dest.parent.mkdir(exist_ok=True)
                atlas.save(dest,compress_level=4); pages.append(dict(file=file,sha256=hashlib.sha256(dest.read_bytes()).hexdigest()))
        clip.update(cell_size=[nw,nh],grid=[cols,rows],pages=pages); combat.append(clip)
    (target/'combat.json').write_text(json.dumps({'clips':combat}),encoding='utf-8')
    prepare_audio(target/'Audio')
    (target/'PixelFXCatalog.json').write_text(json.dumps({'source':catalog['source'],'skills':catalog['skills']}),encoding='utf-8')
    for name in ['LICENSE','NOTICE.md','UPSTREAM.json']:
        shutil.copyfile(ROOT/'ThirdParty/PixelFX'/name,target/'PixelFX'/name)
    print('PixelFX App catalog:',len(catalog['skills']),'choices; legacy bubble/thunder not bundled in game V2')

if __name__ == '__main__': prepare()
