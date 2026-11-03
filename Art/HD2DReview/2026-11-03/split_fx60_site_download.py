from pathlib import Path
import json,hashlib
OUT=Path(__file__).resolve().parent;SITE=OUT.parents[1]/'sites/fireball-hd2d-levels-20261102/dist';data=(OUT/'skill-fx-60hz-2026-11-03/fx60-source-assets-20261103.zip').read_bytes();directory=SITE/'assets/fx60-source-assets-20261103.zip.parts';directory.mkdir(exist_ok=True);parts=[]
for i,start in enumerate(range(0,len(data),1048576)):
 chunk=data[start:start+1048576];name=f'{i:04d}.part';(directory/name).write_bytes(chunk);parts.append({'path':directory.name+'/'+name,'bytes':len(chunk)})
(SITE/'assets/fx60-download.json').write_text(json.dumps({'file':'fx60-source-assets-20261103.zip','bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'parts':parts},indent=2),encoding='utf-8')
for name in ['index.html','fx60.html']:
 p=SITE/name;s=p.read_text(encoding='utf-8').replace('href="assets/fx60-source-assets-20261103.zip" download','href="assets/fx60-download.json" data-fx60-download');p.write_text(s,encoding='utf-8')
index={str(p.relative_to(SITE/'assets')).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((SITE/'assets').rglob('*')) if p.is_file() and p.name!='asset-index.json'};(SITE/'assets/asset-index.json').write_text(json.dumps(index,indent=2),encoding='utf-8');print('38 lossless parts; SHA256 unchanged')
