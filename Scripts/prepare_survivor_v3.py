"""Portable build from confirmed lossless Nov-2 masters. No office paths."""
import hashlib
import json
from pathlib import Path
import shutil
from PIL import Image
from prepare_survivor_audio import prepare_audio

ROOT=Path(__file__).resolve().parents[1]


def prepare():
    source=ROOT/'Art/SurvivorV3'; target=ROOT/'App/Resources/SurvivorGameV3'
    data=json.loads((source/'manifest.json').read_text(encoding='utf-8'))
    if data.get('smoke_only'):raise ValueError('A smoke import is not the full game library')
    target.mkdir(parents=True,exist_ok=True); clips=[]
    for original in data['clips']:
        clip=json.loads(json.dumps(original));w,h=clip['cell_size']
        limit=192 if clip['kind']=='skeleton' else 288
        scale=min(1,limit/max(w,h));nw,nh=max(1,round(w*scale)),max(1,round(h*scale))
        cols,rows=max(1,768//nw),max(1,768//nh);cap=cols*rows;oldcap=original['grid'][0]*original['grid'][1]
        oldimage=None;oldpage=-1;pages=[]
        for i,frame in enumerate(clip['frames']):
            cell=original['frames'][i]['cell'];pageIndex=cell//oldcap
            if pageIndex!=oldpage:
                path=source/original['pages'][pageIndex]['file']
                if hashlib.sha256(path.read_bytes()).hexdigest()!=original['pages'][pageIndex]['sha256']:raise ValueError('Master hash mismatch')
                oldimage=Image.open(path).convert('RGBA');oldpage=pageIndex
            slot=cell%oldcap;x,y=slot%original['grid'][0]*w,slot//original['grid'][0]*h
            image=oldimage.crop((x,y,x+w,y+h))
            if scale<1:image=image.resize((nw,nh),Image.Resampling.NEAREST)
            if i%cap==0:page=Image.new('RGBA',(cols*nw,rows*nh))
            page.paste(image,((i%cap)%cols*nw,(i%cap)//cols*nh));frame['cell']=i
            if i%cap==cap-1 or i==len(clip['frames'])-1:
                name=f"Combat/{clip['id']}-{len(pages):03}.png";dest=target/name;dest.parent.mkdir(exist_ok=True)
                page.save(dest,compress_level=4);pages.append(dict(file=name,sha256=hashlib.sha256(dest.read_bytes()).hexdigest()))
        clip.update(cell_size=[nw,nh],grid=[cols,rows],pages=pages,display_scale=1/scale)
        clips.append(clip)
    # Only approved player animation survives from old bundle; old enemies/FX do not.
    legacy=json.loads((ROOT/'App/Resources/SurvivorGame/manifest.json').read_text())
    for clip in legacy['clips']:
        if clip['id']!='dafeiyu-run':continue
        for page in clip['pages']:
            dest=target/page['file'];dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(ROOT/'App/Resources/SurvivorGame'/page['file'],dest)
        clips.append(clip)
    shutil.copyfile(source/'arrow-pose.png',target/'arrow-pose.png')
    shutil.copyfile(ROOT/'App/Resources/SurvivorGame/dafeiyu-idle.png',target/'dafeiyu-idle.png')
    icons=target/'Icons';icons.mkdir(exist_ok=True)
    for icon in data['icons']:
        path=source/icon['file']
        if hashlib.sha256(path.read_bytes()).hexdigest()!=icon['sha256']:raise ValueError('Icon hash mismatch')
        with Image.open(path) as image:image.convert('RGBA').resize((128,128),Image.Resampling.LANCZOS).save(icons/(icon['id']+'.png'))
    catalog=[]
    categories={'fireball':('fire','火焰'),'lightning':('lightning','雷电'),'earth-spikes':('earth','大地'),'stone-fist':('earth','大地'),'boulder':('earth','大地'),'quicksand':('earth','大地'),'orbit-swords':('sword','剑术'),'seeking-swords':('sword','剑术')}
    for skill in data['skills']:
        category,title=categories[skill['id']]
        catalog.append(dict(id=skill['id'],title=skill['name'],description=skill['behavior'],category=category,category_title=title,profile='projectile' if skill['id'] in ('fireball','seeking-swords') else 'orbit' if skill['id']=='orbit-swords' else 'zone',role='attack',loop=skill['id']=='orbit-swords',duration=skill['levels'][0]['duration'],localLevels=skill['levels']))
    (target/'manifest.json').write_text(json.dumps({'clips':clips},ensure_ascii=False),encoding='utf-8')
    (target/'PixelFXCatalog.json').write_text(json.dumps({'skills':catalog,'characters':data['characters']},ensure_ascii=False),encoding='utf-8')
    (target/'combat.json').write_text(json.dumps({'clips':clips},ensure_ascii=False),encoding='utf-8')
    for name in ['LICENSE','NOTICE.md']:shutil.copyfile(source/name,target/name)
    if (source/'Terrain').exists():shutil.copytree(source/'Terrain',target/'Terrain',dirs_exist_ok=True)
    prepare_audio(target/'Audio')
    print('Confirmed library:',len(catalog),'skills / 40 levels;',len(data['characters']),'latest skeletons; 13 V2 icons.')


if __name__=='__main__':prepare()
