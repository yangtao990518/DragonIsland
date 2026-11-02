"""Build approved HD2D pixels/timelines; never regenerate or retime bodies."""
from pathlib import Path
import json,zipfile,io,hashlib
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
def prepare(target):
 # The checked-in split sources are verified by the normal restoration entry point.
 import subprocess,sys
 subprocess.run([sys.executable,str(ROOT/'Tools/HD2DMaterialReview/restore_sources.py')],check=True)
 source=ROOT/'Tools/HD2DMaterialReview/assets';clips=[];rules=[]
 def pack(id,images,durations,pivot,loop=False):
  w,h=images[0].size;cols=min(len(images),max(1,1024//w));rows=min(max(1,1024//h),(len(images)+cols-1)//cols);cap=cols*rows;pages=[];frames=[];t=0
  for i,(im,dt) in enumerate(zip(images,durations)):
   if i%cap==0:page=Image.new('RGBA',(cols*w,rows*h))
   page.paste(im,((i%cap)%cols*w,(i%cap)//cols*h));frames.append(dict(cell=i,start_ms=t,duration_ms=dt));t+=dt
   if i%cap==cap-1 or i==len(images)-1:
    path=target/f'HD2D/{id}-{len(pages):03}.png';path.parent.mkdir(parents=True,exist_ok=True);page.save(path,compress_level=4);pages.append(dict(file=path.relative_to(target).as_posix(),sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
  c=dict(id=id,cell_size=[w,h],grid=[cols,rows],pivot=[pivot[0]/w,1-pivot[1]/h],duration_ms=t,pages=pages,frames=frames,loop=loop,display_scale=1);clips.append(c);return c
 def sheet(path,cell,indices,cols):
  im=Image.open(path).convert('RGBA');w,h=cell;return [im.crop((i%cols*w,i//cols*h,i%cols*w+w,i//cols*h+h)) for i in indices]
 z=zipfile.ZipFile(ROOT/'Art/HD2DReview/2026-11-02/SourceBundles/HD2D-characters-idle-eye-only-v4.zip')
 for hero in ['dafeiyu','xiaobai']:
  base=f'characters-v4/{hero}/';m=json.loads(z.read(base+'manifest.json'));images=[];pages={}
  for f in m['frames']:
   n=f['atlas']
   if n not in pages:
    raw=z.read(base+m['atlases'][n]['file']);assert hashlib.sha256(raw).hexdigest()==m['atlases'][n]['sha256'];pages[n]=Image.open(io.BytesIO(raw)).convert('RGBA')
   x,y,w,h=f['rect'];im=pages[n].crop((x,y,x+w,y+h));assert hashlib.sha256(im.tobytes()).hexdigest()==f['rgbaSHA256'];images.append(im)
  # Static union only; no per-frame fit or resampling, all 240 frame pixels retained.
  boxes=[im.getbbox() for im in images];box=(min(b[0] for b in boxes),min(b[1] for b in boxes),max(b[2] for b in boxes),max(b[3] for b in boxes))
  c=pack('hd-'+hero+'-idle',[im.crop(box) for im in images],[f['originalDurationMs'] for f in m['frames']],[m['pivotPixels'][0]-box[0],m['pivotPixels'][1]-box[1]],True)
  c['source_crop']=list(box);c['source_sha256']=m['sourceSHA256'];c['source_frame_hashes']=[f['rgbaSHA256'] for f in m['frames']]
  images[0].crop(box).save(target/f'hd-{hero}-portrait.png')
 cat=json.loads((source/'monsters/catalog.json').read_text());assets={a['id']:a for a in cat['combatAssets']}
 for c in cat['characters']:
  walk='hd-'+c['sourceID'];pack(walk,sheet(source/'monsters'/f"{c['group']}.png",[96,96],range(c['row']*4,c['row']*4+4),4),[150]*4,c['anchor'],True)
  a=assets[c['combat']['asset']];spec=c['combat'];starts=spec['starts']+[spec['duration']];pack(walk+'-attack',sheet(source/'monsters'/a['file'],a['cell'],spec['frames'],a['columns']),[(starts[i+1]-starts[i])*1000 for i in range(len(spec['frames']))],a['anchor'])
  rules.append(dict(id=c['sourceID'],duration=spec['duration'],release=spec['release'],kind=spec['kind'],effect=spec['effect']))
 for a in cat['combatAssets']:
  if a['id'] not in ['curse-bolt','frost-bolt','bone-arrow','healing-pulse','bone-death']:continue
  duration=.54 if a['id']=='bone-death' else .54 if a['id']=='healing-pulse' else .4
  pack('hd-'+a['id'],sheet(source/'monsters'/a['file'],a['cell'],range(a['frameCount']),a['columns']),[duration*1000/a['frameCount']]*a['frameCount'],a['anchor'],a['id'] not in ['bone-death','healing-pulse'])
 fx={'flight':('fireball-flight',.5333333333,True),'impact':('fireball-impact',.9,False),'lightning-strike':('lightning-lv1',1.817,False),'lightning-star':('lightning-explosion',1.817,False),'orbit-blade':('hd-orbit-blade',.5333333333,True),'orbit-crescent':('hd-orbit-crescent',.5,False),'seeking-flight':('seeking-flight',.5333333333,True),'seeking-merged':('seeking-merged',.5333333333,True)}
 for name,(id,duration,loop) in fx.items():
  m=json.loads((source/(name+'-manifest.json')).read_text());anchor=m.get('anchorPixels',m.get('anchor'));frames=sheet(source/(name+'.png'),[96,96],range(16),4)
  starts=([0,.12,.25,.4,.5,.54,.58,.64,.74,.86,1,1.13,1.3,1.47,1.65,1.8] if name=='lightning-strike' else [0,.09,.18,.27,.36,.42,.47,.53,.61,.72,.86,1.02,1.2,1.4,1.58,1.74] if name=='lightning-star' else [i*duration/16 for i in range(16)])+[duration]
  pack(id,frames,[(starts[i+1]-starts[i])*1000 for i in range(16)],anchor,loop)
 for id,name in {'fireball':'fireball','lightning':'lightning-strike','orbit-swords':'orbit-blade','seeking-swords':'seeking-flight'}.items():
  dest=target/'HD2D/Icons';dest.mkdir(exist_ok=True);Image.open(source/(name+'-icon.png')).convert('RGBA').resize((128,128),Image.Resampling.NEAREST).save(dest/(id+'.png'))
 data=dict(clips=clips,monsters=rules,style='approved-hd2d-v4');(target/'hd2d.json').write_text(json.dumps(data,ensure_ascii=False),encoding='utf-8');print('HD2D:',len(clips),'clips,',len(rules),'monsters')
if __name__=='__main__':prepare(ROOT/'App/Resources/SurvivorGameV3')
