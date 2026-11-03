"""Extract newly generated original drawings. Never interpolate/duplicate creative art.
Fixed grid and shared canvas/scale; original raw sheets/prompts retained per page.
"""
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor
import json, hashlib, shutil, sys, math, zipfile, os, importlib.util
import numpy as np
from PIL import Image
ROOT=Path(os.environ.get('MAIVERSE_FX_ROOT',str(Path(__file__).resolve().parent/'skill-fx-60hz-2026-11-03')))
SITE=Path(os.environ.get('MAIVERSE_FX_EXPORT',str(ROOT.parents[2]/'sites/fireball-hd2d-levels-20261102/dist/assets/fx60')))
def clean(raw):
 processor=Path(__file__).with_name('sprite_processor.py')
 if not processor.exists():processor=Path.home()/'.codex/skills/generate2dsprite/scripts/generate2dsprite.py'
 spec=importlib.util.spec_from_file_location('sprite_processor',processor);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 return module.remove_bg_magenta(raw.convert('RGBA'),90,130)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def process(job):
 key=f"{job['id']}-{job['page']}"; generated=json.loads((ROOT/'generated-all.json').read_text(encoding='utf-8'))
 if key not in generated:return None
 generated_path=Path(generated[key]);generated_path=generated_path if generated_path.is_absolute() else ROOT/generated_path
 folder=ROOT/job['id'];folder.mkdir(exist_ok=True);raw=folder/f"raw-{job['page']:02d}.png"
 dirty=not raw.exists() or (generated_path.exists() and sha(raw)!=sha(generated_path))
 if dirty:
  if raw.exists():raw.rename(folder/f"rejected-{job['page']:02d}-{sha(raw)[:8]}.png")
  shutil.copy2(generated_path,raw)
 (folder/f"prompt-{job['page']:02d}.txt").write_text(job['prompt'],encoding='utf-8')
 cached=folder/f"clean-{job['page']:02d}.png"
 stamp=folder/f"clean-{job['page']:02d}.version";version='matte-v3-earth-rgb-only-interior'
 if cached.exists() and not dirty and stamp.exists() and stamp.read_text()==version:im=Image.open(cached).convert('RGBA')
 else:
  im=clean(Image.open(raw));a=np.asarray(im).astype(np.float64)/255;bg=a[:,:,3]==0;band=bg.copy()
  for _ in range(4):band=band|np.roll(band,1,0)|np.roll(band,-1,0)|np.roll(band,1,1)|np.roll(band,-1,1)
  excess=np.minimum(a[:,:,0],a[:,:,2])-a[:,:,1];edge=band&(a[:,:,3]>0)&(excess>.10)
  fraction=np.clip(1-excess,.005,1);fg=(a[:,:,:3]-(1-fraction[:,:,None])*np.array([1,0,1]))/fraction[:,:,None]
  a[:,:,:3][edge]=np.clip(fg[edge],0,1);a[:,:,3][edge]*=fraction[edge]
  # Earth brief contains no purple material: remove magenta RGB contamination
  # in rock/dust interiors too, without reducing their alpha or moving outlines.
  if job['id'] in ['earth-pillar','earth-shatter','earth-shockwave','stone-fist','boulder-roll','quicksand-vortex','quicksand-burst']:
   interior=(~band)&(a[:,:,3]>0)&(excess>.075);a[:,:,:3][interior]=np.clip(fg[interior],0,1)
  a[a[:,:,3]==0]=0
  im=Image.fromarray(np.rint(a*255).astype('uint8'));im.save(cached);stamp.write_text(version)
 frames=[];checks=[];w,h=im.size;cols=job['cols'];rows=job['rows'];(folder/'frames').mkdir(exist_ok=True)
 for i in range(job['count']):
  # One fixed page-origin correction, shared by every frame on that page.
  # Does not fit/recenter/scale individual poses or remove any visible pixels.
  oy=job.get('gridOffsetY',0)
  rect=[round(i%cols*w/cols),round(i//cols*h/rows)+oy,round((i%cols+1)*w/cols),round((i//cols+1)*h/rows)+oy]
  slot=im.crop(rect);a=np.asarray(slot)[:,:,3]
  edge=bool(a[0].any() or a[-1].any() or a[:,0].any() or a[:,-1].any())
  f=slot.resize((96,96),Image.Resampling.NEAREST);f.save(folder/'frames'/f"{i+job['start']:04d}.png")
  checks.append({'index':i+job['start'],'sourceRect':rect,'bbox':f.getbbox(),'edgeTouch':edge,'sourcePage':job['page'],'rawSHA256':sha(raw)})
 (folder/f"checks-{job['page']:02d}.json").write_text(json.dumps(checks,indent=2),encoding='utf-8')
 return {'key':key,'frames':len(checks),'edgeTouch':[c['index'] for c in checks if c['edgeTouch']],'empty':[c['index'] for c in checks if not c['bbox']]}
def assemble(plan):
 SITE.mkdir(parents=True,exist_ok=True);assets={};pending=[];issues=[]
 for name in dict.fromkeys(j['id'] for j in plan['jobs']):
  jobs=sorted([j for j in plan['jobs'] if j['id']==name],key=lambda j:j['start']);folder=ROOT/name
  if any(not (folder/f"checks-{j['page']:02d}.json").exists() for j in jobs):pending.append(name);continue
  checks=[x for j in jobs for x in json.loads((folder/f"checks-{j['page']:02d}.json").read_text())];n=len(checks)
  # Explicit finite decay to transparent is allowed in the final 0.1 second.
  # These transparent samples are reported separately, never claimed as new poses.
  bad_empty=[c['index'] for c in checks if not c['bbox'] and (jobs[0].get('loop',False) or c['index']<n-6)]
  if any(c['edgeTouch'] for c in checks) or bad_empty:issues.append(name);continue
  assert [c['index'] for c in checks]==list(range(n)),name
  frames=[Image.open(folder/'frames'/f'{i:04d}.png').convert('RGBA') for i in range(n)];sheet=Image.new('RGBA',(768,math.ceil(n/8)*96))
  for i,f in enumerate(frames):sheet.paste(f,(i%8*96,i//8*96))
  sheet.save(SITE/(name+'.png'));hashes=[hashlib.sha256(f.tobytes()).hexdigest() for f in frames];dups=[i for i in range(1,n) if hashes[i]==hashes[i-1]]
  bounds=[c['bbox'] for c in checks if c['bbox']];union=[min(b[0] for b in bounds),min(b[1] for b in bounds),max(b[2] for b in bounds),max(b[3] for b in bounds)]
  duration=jobs[0]['duration'];assert n==math.ceil(duration*60-1e-8),(name,n,duration)
  assets[name]={'id':name,'file':name+'.png','columns':8,'cell':[96,96],'count':n,'duration':duration,'loop':jobs[0].get('loop',False),'fps':60,'anchor':jobs[0]['anchor'],'unionBounds':union,'extent':{'w':union[2]-union[0],'h':union[3]-union[1]},'frameStarts':[i/60 for i in range(n)],'frameDurations':[min(1/60,duration-i/60) for i in range(n)],'frames':checks,'frameHashes':hashes,'consecutiveExactDuplicates':dups,'source':'built-in-imagegen-original-drawings','interpolated':False,'perFrameBboxFit':False,'sheetSHA256':sha(SITE/(name+'.png'))}
  assets[name].update(nonEmptyDrawings=sum(bool(c['bbox']) for c in checks),transparentTailSamples=[c['index'] for c in checks if not c['bbox']],distinctSamples=len(set(hashes)),pageTransforms=[{'page':j['page'],'gridOffsetY':j.get('gridOffsetY',0),'sharedAcrossEveryCell':True} for j in jobs],matting='v3: boundary unmix, earth RGB-only interior despill, no silhouette erosion')
  (SITE/(name+'-manifest.json')).write_text(json.dumps(assets[name],indent=2),encoding='utf-8')
 manifest={'version':1,'fps':60,'nativeBase':plan['nativeBase'],'deferred':plan.get('deferred',[]),'assets':assets,'pending':pending,'issues':issues}
 (SITE/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
 print(json.dumps({'assets':len(assets),'frames':sum(a['count'] for a in assets.values()),'pending':pending,'issues':issues,'duplicates':{k:v['consecutiveExactDuplicates'] for k,v in assets.items() if v['consecutiveExactDuplicates']}}),flush=True)
 return manifest
if __name__=='__main__':
 plan=json.loads((ROOT/'plan-60hz.json').read_text(encoding='utf-8'));keys=set(sys.argv[1:]);jobs=[j for j in plan['jobs'] if not keys or f"{j['id']}-{j['page']}" in keys]
 with ProcessPoolExecutor(max_workers=3) as pool:
  for result in pool.map(process,jobs):
   if result:print(json.dumps(result),flush=True)
 assemble(plan)
