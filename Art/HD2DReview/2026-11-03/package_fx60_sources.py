from pathlib import Path
import json,zipfile,hashlib
OUT=Path(__file__).resolve().parent;ROOT=OUT/'skill-fx-60hz-2026-11-03';SITE=OUT.parents[1]/'sites/fireball-hd2d-levels-20261102/dist'
manifest=json.loads((SITE/'assets/fx60/manifest.json').read_text());plan=json.loads((ROOT/'plan-60hz.json').read_text());assert not manifest['pending'] and not manifest['issues']
dest=SITE/'assets/fx60-source-assets-20261103.zip';source_map={}
with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED) as z:
 for job in plan['jobs']:
  name=job['id'];page=job['page'];folder=ROOT/name;key=f'{name}-{page}';rel=f'{name}/raw-{page:02d}.png';source_map[key]=rel
  z.write(folder/f'raw-{page:02d}.png',rel);z.write(folder/f'prompt-{page:02d}.txt',f'{name}/prompt-{page:02d}.txt')
 for name,m in manifest['assets'].items():
  for p in sorted((ROOT/name/'frames').glob('*.png')):z.write(p,f'{name}/frames/{p.name}')
  z.write(SITE/'assets/fx60'/m['file'],f'exports/{m["file"]}');z.write(SITE/'assets/fx60'/(name+'-manifest.json'),f'exports/{name}-manifest.json')
 z.writestr('generated-all.json',json.dumps(source_map,indent=2));z.write(ROOT/'plan-60hz.json','plan-60hz.json');z.write(SITE/'assets/fx60/manifest.json','exports/manifest.json')
 z.write(OUT/'prepare_skill_fx_60hz.py','reproduction/prepare_skill_fx_60hz.py');z.write(Path.home()/'.codex/skills/generate2dsprite/scripts/generate2dsprite.py','reproduction/sprite_processor.py')
 z.write(ROOT/'rune-single-reference.png','references/rune-single-reference.png');z.write(ROOT/'grid-6x8.png','references/grid-6x8.png')
 z.write(OUT.parent/'docs/HANDOFF_2026-11-03_EARTH_FX60.md','README.md');z.write(OUT.parent/'docs/SKILL_FX_60HZ_STANDARD.md','SKILL_FX_60HZ_STANDARD.md')
with zipfile.ZipFile(dest) as z:assert z.testzip() is None
p=SITE/'index.html';s=p.read_text(encoding='utf-8').replace('土系素材与提示词 ↗','土系16关键帧初稿 ↗');p.write_text(s,encoding='utf-8')
index={str(p.relative_to(SITE/'assets')).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((SITE/'assets').rglob('*')) if p.is_file() and p.name!='asset-index.json'}
(SITE/'assets/asset-index.json').write_text(json.dumps(index,indent=2),encoding='utf-8')
report={'file':dest.name,'bytes':dest.stat().st_size,'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'frames':sum(m['count'] for m in manifest['assets'].values()),'nonEmpty':sum(m['nonEmptyDrawings'] for m in manifest['assets'].values()),'assets':len(manifest['assets'])}
(ROOT/'package.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report),flush=True)
