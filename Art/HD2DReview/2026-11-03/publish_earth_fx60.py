from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
import sys,json,hashlib,base64,shutil
OUT=Path(__file__).resolve().parent;SITE=OUT.parents[1]/'sites/fireball-hd2d-levels-20261102';STAGE=OUT/'earth-fx60-git-staging';ART=STAGE/'Art/HD2DReview/2026-11-03';TOOLS=STAGE/'Tools/HD2DMaterialReview'
sys.path.insert(0,str(OUT.parents[1]/'DragonIsland-IslandReview/output'))
from github_review_api import request,credential,REPO
from publish_hd2d_handoff import build_tree_incrementally,gitsha
BASE='dcf64313c998cac8c7da2fdc82f9e2923815f81f';BRANCH='codex/earth-hd2d-20261103';CACHE=OUT/'earth-fx60-github-upload-cache.json'
def stage():
 ART.mkdir(parents=True,exist_ok=True);TOOLS.mkdir(parents=True,exist_ok=True);bundles=[]
 for file in ['fx60-source-assets-20261103.zip','earth-source-assets-20261103.zip']:
  p=SITE/'dist/assets'/file
  if not p.exists():p=OUT/'skill-fx-60hz-2026-11-03'/file
  directory=ART/'SourceBundles';directory.mkdir(exist_ok=True);parts=directory/(file+'.parts');parts.mkdir(exist_ok=True);data=p.read_bytes();records=[]
  for i,start in enumerate(range(0,len(data),1048576)):
   chunk=data[start:start+1048576];target=parts/f'{i:04d}.part';target.write_bytes(chunk);records.append({'path':str(target.relative_to(ART)).replace('\\','/'),'bytes':len(chunk),'sha256':hashlib.sha256(chunk).hexdigest()})
  bundles.append({'file':'SourceBundles/'+file,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'parts':records})
 (ART/'source-parts.json').write_text(json.dumps({'version':1,'files':bundles},indent=2),encoding='utf-8')
 for p in (SITE/'dist').rglob('*'):
  if not p.is_file() or p.suffix=='.zip':continue
  dest=TOOLS/p.relative_to(SITE/'dist');dest.parent.mkdir(parents=True,exist_ok=True)
  if p.suffix=='.html':
   s=p.read_text(encoding='utf-8')
   for name in ['all-skills-source-assets.zip','fireball-source-assets.zip','lightning-swords-source-assets.zip']:s=s.replace('assets/'+name,'../../Art/HD2DReview/2026-11-02/SourceBundles/'+name)
   for name in ['fx60-source-assets-20261103.zip','earth-source-assets-20261103.zip']:s=s.replace('assets/'+name,'../../Art/HD2DReview/2026-11-03/SourceBundles/'+name)
   dest.write_text(s,encoding='utf-8')
  else:shutil.copy2(p,dest)
 # Asset integrity list reflects only the actual snapshot, including nested paths.
 idx={str(p.relative_to(TOOLS/'assets')).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in (TOOLS/'assets').rglob('*') if p.is_file() and p.name!='asset-index.json'}
 (TOOLS/'assets/asset-index.json').write_text(json.dumps(idx,indent=2),encoding='utf-8')
 docs=STAGE/'docs';docs.mkdir(exist_ok=True)
 for name in ['HANDOFF_2026-11-03_EARTH_FX60.md','SKILL_FX_60HZ_STANDARD.md']:shutil.copy2(OUT.parent/'docs'/name,docs/name)
 for name in ['prepare_skill_fx_60hz.py','package_fx60_sources.py','publish_earth_fx60.py','split_fx60_site_download.py']:shutil.copy2(OUT/name,ART/name)
 for name in ['qa-earth.mjs','qa-fx60.mjs']:shutil.copy2(SITE/name,ART/name)
 qa=ART/'qa';qa.mkdir(exist_ok=True)
 for name in ['earth-results.json','fx60-results.json','rune-swords-50.png','rune-swords-xiaobai.png','earth-earth-spikes.png','earth-stone-fist.png','earth-boulder.png','earth-quicksand.png']:shutil.copy2(SITE/'qa'/name,qa/name)
 (ART/'restore_sources.py').write_text('''from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parent
for entry in json.loads((root/'source-parts.json').read_text(encoding='utf-8'))['files']:
 target=root/entry['file'];target.parent.mkdir(parents=True,exist_ok=True);pieces=[]
 for part in entry['parts']:
  data=(root/part['path']).read_bytes();assert len(data)==part['bytes'] and hashlib.sha256(data).hexdigest()==part['sha256'],part['path'];pieces.append(data)
 data=b''.join(pieces);assert len(data)==entry['bytes'] and hashlib.sha256(data).hexdigest()==entry['sha256'];target.write_bytes(data);print('Verified',entry['file'],len(data))
''',encoding='utf-8')
def upload(item):
 p,rel,sha=item
 if cache.get(rel)==sha:return rel,sha,'cached'
 r=request('POST',f'/repos/{REPO}/git/blobs',{'content':base64.b64encode(p.read_bytes()).decode(),'encoding':'base64'});assert r['sha']==sha;return rel,sha,'uploaded'
if __name__=='__main__':
 stage();credential();commit=request('GET',f'/repos/{REPO}/git/commits/{BASE}');tree=commit['tree']['sha'];old=request('GET',f'/repos/{REPO}/git/trees/{tree}?recursive=1');assert not old.get('truncated');oldmap={e['path']:e['sha'] for e in old['tree'] if e['type']=='blob'}
 assert request('GET',f'/repos/{REPO}/git/ref/heads/{BRANCH}')['object']['sha']==BASE,'New branch advanced; stop without resetting'
 items=[]
 for p in STAGE.rglob('*'):
  if not p.is_file():continue
  rel=str(p.relative_to(STAGE)).replace('\\','/');assert rel.startswith(('Art/HD2DReview/2026-11-03/','Tools/HD2DMaterialReview/','docs/HANDOFF_2026-11-03_EARTH_FX60.md','docs/SKILL_FX_60HZ_STANDARD.md'));data=p.read_bytes();sha=gitsha(data)
  assert len(data)<2500000,(rel,'Use source parts for large files')
  if oldmap.get(rel)!=sha:items.append((p,rel,sha))
 cache=json.loads(CACHE.read_text()) if CACHE.exists() else {};entries=[]
 with ThreadPoolExecutor(max_workers=3) as pool:
  for i,f in enumerate(as_completed([pool.submit(upload,it) for it in items]),1):
   rel,sha,mode=f.result();cache[rel]=sha;CACHE.write_text(json.dumps(cache),encoding='utf-8');entries.append({'path':rel,'mode':'100644','type':'blob','sha':sha})
   if i%10==0 or i==len(items):print('Verified',i,'/',len(items),'blobs',flush=True)
 result_tree=build_tree_incrementally(tree,entries);assert request('GET',f'/repos/{REPO}/git/ref/heads/{BRANCH}')['object']['sha']==BASE
 result=request('POST',f'/repos/{REPO}/git/commits',{'message':'[skip ci] Add HD-2D earth studies,60Hz original skill FX and small rune sword swarm','tree':result_tree,'parents':[BASE]});request('PATCH',f'/repos/{REPO}/git/refs/heads/{BRANCH}',{'sha':result['sha'],'force':False})
 verify=request('GET',f'/repos/{REPO}/git/trees/{result_tree}?recursive=1');assert not verify.get('truncated');remote={e['path']:e['sha'] for e in verify['tree'] if e['type']=='blob'};assert all(remote[e['path']]==e['sha'] for e in entries)
 changed={e['path'] for e in entries};assert all(remote[k]==v for k,v in oldmap.items() if k not in changed),'Unrelated base files changed'
 report={'repository':REPO,'branch':BRANCH,'base':BASE,'sha':result['sha'],'tree':result_tree,'changedFiles':len(items),'allFilesVerified':True,'nativeBaseUnchanged':True,'handoff':'docs/HANDOFF_2026-11-03_EARTH_FX60.md'};(OUT/'earth-fx60-github-published.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report),flush=True)
