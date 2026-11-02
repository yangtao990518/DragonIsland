from pathlib import Path
from concurrent.futures import ProcessPoolExecutor
import importlib.util,json,hashlib,zipfile,shutil
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parent/'hd2d-lightning-swords-2026-11-02'
SITE=Path(r'E:/ai_workspace/ios_ldd/sites/fireball-hd2d-levels-20261102/dist/assets')
IDS=['lightning-strike','lightning-star','orbit-blade','orbit-crescent','seeking-flight','seeking-merged']
def process(name):
 spec=importlib.util.spec_from_file_location('sprite_processor',r'C:/Users/yangtao/.codex/skills/generate2dsprite/scripts/generate2dsprite.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 folder=ROOT/name;raw=Image.open(folder/'raw-sheet.png').convert('RGBA');clean=m.remove_bg_magenta(raw.copy(),100,150)
 a=np.asarray(clean).astype(np.float64)/255;excess=np.minimum(a[:,:,0],a[:,:,2])-a[:,:,1];edge=(excess>.075)&(a[:,:,3]>0);fraction=np.clip(1-excess,.005,1)
 fg=(a[:,:,:3]-(1-fraction[:,:,None])*np.array([1,0,1]))/fraction[:,:,None];a[:,:,:3][edge]=np.clip(fg[edge],0,1);a[:,:,3][edge]*=fraction[edge];a[a[:,:,3]==0]=0
 clean=Image.fromarray(np.rint(a*255).astype('uint8'));clean.save(folder/'source-descreened.png');w,h=clean.size
 frames=[];entries=[];(folder/'frames').mkdir(exist_ok=True)
 for i in range(16):
  rect=[round(i%4*w/4),round(i//4*h/4),round((i%4+1)*w/4),round((i//4+1)*h/4)];im=clean.crop(rect).resize((96,96),Image.Resampling.NEAREST)
  offset=(0,10) if name=='lightning-star' and i>=8 else (0,[5,0,7,10][i//4]) if name=='lightning-strike' else (0,0)
  frame=Image.new('RGBA',(96,96));frame.paste(im,offset);alpha=np.asarray(frame)[:,:,3];assert not alpha[0].any() and not alpha[-1].any() and not alpha[:,0].any() and not alpha[:,-1].any(),(name,i,'edge')
  rgb=np.asarray(frame).astype(np.int16);bad=(rgb[:,:,0]>180)&(rgb[:,:,2]>150)&(rgb[:,:,1]<90)&(rgb[:,:,3]>32);assert not bad.any(),(name,i,'magenta')
  frame.save(folder/'frames'/f'{i:02d}.png');frames.append(frame);entries.append({'index':i,'sourceRect':rect,'integerTranslation':offset})
 sheet=Image.new('RGBA',(384,384))
 for i,im in enumerate(frames):sheet.paste(im,(i%4*96,i//4*96))
 sheet.save(folder/'sheet-transparent.png');shutil.copy2(folder/'sheet-transparent.png',SITE/(name+'.png'))
 anchor={'lightning-strike':[48,82],'lightning-star':[48,72],'orbit-blade':[48,44],'orbit-crescent':[48,48],'seeking-flight':[74,50],'seeking-merged':[77,51]}[name]
 meta={'id':name,'frameCount':16,'cell':[96,96],'anchor':anchor,'rawSHA256':hashlib.sha256((folder/'raw-sheet.png').read_bytes()).hexdigest(),'builtInImageGeneration':True,'frameExtraction':'fixed grid and shared scale, no per-frame bbox fit','frames':entries}
 (folder/'manifest.json').write_text(json.dumps(meta,indent=2),encoding='utf-8');shutil.copy2(folder/'manifest.json',SITE/(name+'-manifest.json'))
 icon=frames[6 if name=='lightning-strike' else 0];icon.save(SITE/(name+'-icon.png'))
 return name
if __name__=='__main__':
 with ProcessPoolExecutor(max_workers=3) as pool:
  for name in pool.map(process,IDS):print('PREPARED',name,flush=True)
 bundle=ROOT/'lightning-swords-HD2D-sources-v1.zip'
 with zipfile.ZipFile(bundle,'w',zipfile.ZIP_DEFLATED) as z:
  for name in IDS:
   for file in ['raw-sheet.png','sheet-transparent.png','manifest.json','prompt-final-v2.txt' if name in ['seeking-merged','lightning-strike'] else 'prompt-used.txt']:
    p=ROOT/name/file;z.write(p,str(p.relative_to(ROOT)))
   for p in sorted((ROOT/name/'frames').glob('*.png')):z.write(p,str(p.relative_to(ROOT)))
  z.write(Path(__file__).resolve(),'reproduction/prepare_lightning_swords.py')
 shutil.copy2(bundle,SITE/'lightning-swords-source-assets.zip')
 print('BUNDLE',bundle.stat().st_size,flush=True)
