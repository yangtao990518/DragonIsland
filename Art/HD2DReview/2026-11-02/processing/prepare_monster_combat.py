"""Process generated combat assets, with one shared neutral-pose scale per enemy."""
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor
import json,sys,hashlib,shutil,zipfile
import numpy as np
from PIL import Image
from prepare_hd2d_monsters import clean
ROOT=Path(__file__).resolve().parent/'hd2d-monsters-combat-2026-11-02'
OLD=ROOT.parent/'hd2d-monsters-2026-11-02'
SITE=ROOT.parents[2]/'sites/fireball-hd2d-levels-20261102/dist/assets/monsters'
BODY=['warriors-attack','mages-cast','healers-cast','archers-shoot','elite-guard-attack','elite-mage-cast','elite-archer-shoot','boss-attack']
GROUPS=['warriors','mages','healers','archers']
def process(job):
 name=job['id'];folder=ROOT/name;raw=folder/('raw-final-v2.png' if (folder/'raw-final-v2.png').exists() else 'raw-sheet.png')
 # Cached cleanup is keyed by raw bytes, never by an old filename alone.
 digest=hashlib.sha256(raw.read_bytes()).hexdigest();cache=folder/'clean-sha.txt'
 if cache.exists() and cache.read_text()==digest:im=Image.open(folder/'source-clean.png').convert('RGBA')
 else:im=clean(Image.open(raw));im.save(folder/'source-clean.png');cache.write_text(digest)
 w,h=im.size;rows,cols=job['rows'],job['cols'];slots=[];source_rects=[];source_edges=[]
 # Calibrate horizontal boundaries only in fully transparent gutters. Some
 # generated crowns rise over the nominal equal-height row. Every frame of a
 # given actor still uses exactly one shared row rectangle and neutral scale.
 opaque=np.asarray(im)[:,:,3].max(axis=1)>0;blank=np.flatnonzero(~opaque);runs=np.split(blank,np.where(np.diff(blank)>1)[0]+1);yb=[0]
 for r in range(1,rows):
  nominal=r*h/rows;candidates=[v for v in runs if len(v)>=4 and abs((v[0]+v[-1])/2-nominal)<h/rows*.30]
  yb.append(round((max(candidates,key=len)[0]+max(candidates,key=len)[-1])/2) if candidates else round(nominal))
 yb.append(h)
 for r in range(rows):
  for c in range(cols):
   rect=(round(c*w/cols),yb[r],round((c+1)*w/cols),yb[r+1]);s=im.crop(rect);a=np.asarray(s)[:,:,3];edge=bool(a[0].any() or a[-1].any() or a[:,0].any() or a[:,-1].any())
   if edge:source_edges.append([r,c])
   slots.append(s);source_rects.append(rect)
 assert not source_edges,(name,'source-grid-crossing',source_edges)
 body=name in BODY;C=(192,128) if body else (96,96);frames=[];meta=[];origins=[]
 count=len(slots);nactors=4 if name in BODY[:4] else 1;per=count//nactors
 for actor in range(nactors):
  neutral=slots[actor*per+per-1];box=neutral.getbbox();assert box,(name,'empty neutral')
  if body:
   target_group=GROUPS[BODY.index(name)] if nactors==4 else 'elites-boss';target_row=actor if nactors==4 else BODY.index(name)-4
   master=Image.open(OLD/target_group/'frames'/f'{target_row}-0.png');b=master.getbbox();target_height=b[3]-b[1]
   scale=target_height/(box[3]-box[1])
   aa=np.asarray(neutral)[:,:,3];yy=box[3]-1;xx=np.flatnonzero(aa[max(0,yy-2):yy+1].max(axis=0)>64);px=(float(xx[0])+float(xx[-1]))/2 if len(xx) else neutral.width/2;py=box[3];origin=[96,108]
  else:scale=96/max(w/cols,h/rows);px=neutral.width/2;py=neutral.height/2;origin=[48,48]
  for local in range(per):
   i=actor*per+local;s=slots[i];scaled=s.resize((round(s.width*scale),round(s.height*scale)),Image.Resampling.NEAREST);f=Image.new('RGBA',C)
   # The lowest solid point in these inspected body poses is the planted foot
   # (all carried weapons remain above it). Align this floor contact by integer
   # translation only; retain one shared scale and horizontal origin per actor.
   ground_y=s.getbbox()[3] if body else py
   offset=(round(origin[0]-px*scale),round(origin[1]-ground_y*scale));f.paste(scaled,offset)
   assert s.getbbox(),(name,i,'empty')
   if body:
    sb=s.getbbox();transformed=[sb[0]*scale+offset[0],sb[1]*scale+offset[1],sb[2]*scale+offset[0],sb[3]*scale+offset[1]]
    assert min(transformed[:2])>=1 and transformed[2]<C[0]-1 and transformed[3]<C[1]-1,(name,i,'transformed-edge',transformed)
   a=np.asarray(f)[:,:,3];assert not a[0].any() and not a[-1].any() and not a[:,0].any() and not a[:,-1].any(),(name,i,'edge')
   frames.append(f);meta.append({'index':i,'sourceRect':source_rects[i],'sharedActorScale':scale,'translation':offset,'groundFootY':ground_y if body else None,'bbox':f.getbbox(),'edgeTouch':False});origins.append(origin)
 outcols=4 if body else cols;outrows=(len(frames)+outcols-1)//outcols;sheet=Image.new('RGBA',(outcols*C[0],outrows*C[1]));(folder/'frames').mkdir(exist_ok=True)
 for i,f in enumerate(frames):sheet.paste(f,(i%outcols*C[0],i//outcols*C[1]));f.save(folder/'frames'/f'{i:02d}.png')
 sheet.save(folder/'sheet-transparent.png');shutil.copy2(folder/'sheet-transparent.png',SITE/(name+'.png'))
 m={'id':name,'rawFile':raw.name,'rawSHA256':digest,'cell':C,'columns':outcols,'frameCount':count,'posesPerActor':per,'actors':nactors,'anchor':origins[0],'sourceEdgeTouch':source_edges,'frames':meta,'body':body,'scalePolicy':'shared neutral-reference scale and horizontal origin per actor; integer vertical ground-foot registration only; no per-frame scale or bbox centering'}
 (folder/'manifest.json').write_text(json.dumps(m,indent=2),encoding='utf-8');shutil.copy2(folder/'manifest.json',SITE/(name+'-manifest.json'));return m
def timing(durations):
 t=0;starts=[]
 for d in durations:starts.append(round(t,6));t+=d
 return starts,round(t,6)
if __name__=='__main__':
 jobs=json.loads((ROOT/'jobs.json').read_text(encoding='utf-8'));selection=sys.argv[1:];todo=[j for j in jobs if not selection or j['id'] in selection]
 with ProcessPoolExecutor(max_workers=3) as pool:
  for m in pool.map(process,todo):print('PREPARED',m['id'],m['frameCount'],flush=True)
 if selection:sys.exit(0)
 catalog=json.loads((SITE/'catalog.json').read_text(encoding='utf-8'));assets={j['id']:json.loads((ROOT/j['id']/'manifest.json').read_text()) for j in jobs};catalog['combatAssets']=[{'id':n,'file':n+'.png','cell':m['cell'],'columns':m['columns'],'frameCount':m['frameCount'],'anchor':m['anchor']} for n,m in assets.items()]
 for i,c in enumerate(catalog['characters']):
  n=BODY[i//4] if i<16 else BODY[4+i-16];m=assets[n];row=i%4 if i<16 else 0;kind='cast' if 'cast' in n else 'shoot' if 'shoot' in n else 'attack'
  durations=[.15,.09,.12,.24] if kind=='attack' else [.18,.22,.12,.24] if kind=='cast' else [.16,.22,.10,.24]
  if i in [16,17,18]:durations=[.15,.16,.18,.10,.14,.25]
  if i==19:durations=[.15,.17,.20,.20,.09,.13,.17,.27]
  starts,duration=timing(durations);release=starts[4] if i==19 else starts[3] if i>=16 else starts[2] if kind!='attack' else starts[1]
  effect='healing-pulse' if c['group']=='healers' else 'frost-bolt' if i==5 else 'fireball' if i==6 else 'curse-bolt' if kind=='cast' else 'bone-arrow' if kind=='shoot' else None
  c['combat']={'asset':n,'frames':list(range(row*m['posesPerActor'],(row+1)*m['posesPerActor'])),'kind':kind,'label':'施法' if kind=='cast' else '射击' if kind=='shoot' else '攻击','starts':starts,'duration':duration,'release':round(release,6),'repeatAfter':round(duration+.75,6),'effect':effect,'eliteProjectiles':3 if i==18 else 2 if i==17 else 1}
 catalog['version']=2;catalog['actions']=['walk','combat','death'];catalog['pendingActions']=[];catalog['death']={'duration':.68,'flashEnd':.09,'bodyGone':.27,'debrisStart':.10,'debrisEnd':.64,'asset':'bone-death'}
 (SITE/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf-8');shutil.copy2(SITE/'catalog.json',ROOT/'catalog.json')
 with zipfile.ZipFile(SITE/'monster-combat-source-assets.zip','w',zipfile.ZIP_DEFLATED) as z:
  for j in jobs:
   f=ROOT/j['id'];m=assets[j['id']]
   for name in [m['rawFile'],'sheet-transparent.png','manifest.json','prompt-final-v2.txt' if (f/'prompt-final-v2.txt').exists() else 'prompt-used.txt']:z.write(f/name,j['id']+'/'+name)
   for p in sorted((f/'frames').glob('*.png')):z.write(p,j['id']+'/frames/'+p.name)
  z.write(ROOT/'catalog.json','catalog.json');z.write(ROOT/'jobs.json','jobs.json');z.write(Path(__file__).resolve(),'reproduction/prepare_monster_combat.py');z.write(ROOT.parent/'prepare_hd2d_monsters.py','reproduction/prepare_hd2d_monsters.py')
 print('COMPLETE',json.dumps({'enemies':20,'combatBodyPoses':90,'fxPoses':22,'archiveBytes':(SITE/'monster-combat-source-assets.zip').stat().st_size}),flush=True)
