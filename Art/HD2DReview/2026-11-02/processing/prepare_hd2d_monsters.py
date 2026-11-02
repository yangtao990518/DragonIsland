"""Deterministic background removal and fixed-grid extraction of generated art.
No sprite drawing, skeleton deformation, frame synthesis or per-frame bbox fitting.
"""
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor
import importlib.util,json,hashlib,zipfile,shutil
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent/'hd2d-monsters-2026-11-02'
SITE=ROOT.parents[2]/'sites/fireball-hd2d-levels-20261102/dist/assets/monsters'
GROUPS=['warriors','mages','healers','archers','elites-boss']
def clean(raw):
 spec=importlib.util.spec_from_file_location('sprite_processor',r'C:/Users/yangtao/.codex/skills/generate2dsprite/scripts/generate2dsprite.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 im=m.remove_bg_magenta(raw.convert('RGBA'),90,130)
 a=np.asarray(im).astype(np.float64)/255;alpha=a[:,:,3]>0
 # Despill only bright magenta mixed pixels next to true background. Purple
 # costume interiors remain exactly untouched; no erosion of the silhouette.
 bg=~alpha;adj=np.zeros_like(bg)
 for dy,dx in [(1,0),(-1,0),(0,1),(0,-1)]:adj|=np.roll(bg,(dy,dx),(0,1))
 excess=np.minimum(a[:,:,0],a[:,:,2])-a[:,:,1]
 edge=adj&alpha&(a[:,:,0]>.68)&(a[:,:,2]>.66)&(a[:,:,1]<.52)&(excess>.22)
 f=np.clip(1-excess,.005,1);fg=(a[:,:,:3]-(1-f[:,:,None])*np.array([1,0,1]))/f[:,:,None]
 a[:,:,:3][edge]=np.clip(fg[edge],0,1);a[:,:,3][edge]*=f[edge];a[a[:,:,3]==0]=0
 return Image.fromarray(np.rint(a*255).astype('uint8'))
def process(name):
 folder=ROOT/name;raw=Image.open(folder/'raw-sheet.png');im=clean(raw);im.save(folder/'source-clean.png');w,h=im.size
 boss=None
 if name=='elites-boss':
  boss=clean(Image.open(ROOT/'boss-corrected/raw-sheet.png'));boss.save(ROOT/'boss-corrected/source-clean.png')
 frames=[];qc=[];anchors=[]
 (folder/'frames').mkdir(exist_ok=True)
 for row in range(4):
  rowframes=[]
  for col in range(4):
   # The generated grid has visible blank gutters but two sheets have unequal
   # row spacing. Calibrate one full-size source cell per ROW in those gutters;
   # do not crop through neighboring art or move/fit individual frames.
   starts={'healers':[0,310,605,920],'elites-boss':[0,313.5,594,940.5]}.get(name)
   top=starts[row] if starts else row*h/4
   rect=(round(col*w/4),round(top),round((col+1)*w/4),round(top+h/4));source=im
   if boss is not None and row==3:
    bw,bh=boss.size;x=col%2;y=col//2
    # Second source row is 43px higher than nominal; its blank gutter starts
    # after y563 and crown begins628. Use shared row origin584 to keep feet
    # aligned without fitting or transforming any individual pose.
    by=0 if y==0 else 584
    rect=(round(x*bw/2),by,round((x+1)*bw/2),round(by+bh/2));source=boss
   if name=='elites-boss' and row==2:
    # Entire archer occupies y648..887; the rejected king's crown begins905.
    # Cut at the actual blank gutter and PAD the absent bottom, preserving
    # exactly the same pixel scale as all other elite rows.
    rect=(rect[0],rect[1],rect[2],900)
    slot=Image.new('RGBA',(rect[2]-rect[0],round(h/4)));slot.paste(source.crop(rect),(0,0))
   else:slot=source.crop(rect)
   if boss is not None and row==3:
    padded=Image.new('RGBA',(slot.width+96,slot.height+96));padded.paste(slot,(48,48));slot=padded
   frame=slot.resize((96,96),Image.Resampling.NEAREST)
   a=np.asarray(frame)[:,:,3];assert not a[0].any() and not a[-1].any() and not a[:,0].any() and not a[:,-1].any(),(name,row,col,'edge touch')
   bbox=frame.getbbox();assert bbox,(name,row,col,'empty')
   frame.save(folder/'frames'/f'{row}-{col}.png');frames.append(frame);rowframes.append(frame)
   qc.append({'row':row,'frame':col,'bbox':bbox,'sourceRect':rect,'edgeTouch':False})
  # One pivot shared by all four frames of the same enemy, never per-frame fit.
  anchors.append([48,int(round(np.median([x.getbbox()[3] for x in rowframes])))])
  gifs=[]
  for f in rowframes:
   bg=Image.new('RGBA',f.size,'#19282b');bg.alpha_composite(f);gifs.append(bg.convert('RGB').resize((288,288),Image.Resampling.NEAREST))
  gifs[0].save(folder/f'row-{row}-walk.gif',save_all=True,append_images=gifs[1:],duration=150,loop=0)
 sheet=Image.new('RGBA',(384,384))
 for i,f in enumerate(frames):sheet.paste(f,(i%4*96,i//4*96))
 sheet.save(folder/'sheet-transparent.png');SITE.mkdir(parents=True,exist_ok=True);shutil.copy2(folder/'sheet-transparent.png',SITE/(name+'.png'))
 meta={'id':name,'rows':4,'columns':4,'cell':[96,96],'frameCount':16,'action':'walk','frameDurationMs':150,'cycleSeconds':.6,'anchors':anchors,'rawSHA256':hashlib.sha256((folder/'raw-sheet.png').read_bytes()).hexdigest(),'fixedGrid':True,'perFrameFit':False,'frames':qc}
 if boss is not None:meta['bossCorrectionSHA256']=hashlib.sha256((ROOT/'boss-corrected/raw-sheet.png').read_bytes()).hexdigest()
 (folder/'manifest.json').write_text(json.dumps(meta,indent=2),encoding='utf-8');shutil.copy2(folder/'manifest.json',SITE/(name+'-manifest.json'))
 return meta
if __name__=='__main__':
 with ProcessPoolExecutor(max_workers=3) as pool:metas=list(pool.map(process,GROUPS))
 original=json.loads((ROOT/'roster-original.json').read_text(encoding='utf-8'))
 names=['锈刃盾卫','断枪骸兵','巨剑骨卫','重斧骷髅','紫袍咒术师','寒霜法师','赤烬术士','黑冠巫师','白袍骨医','金纹祭司','提灯牧者','圣冠主教','残弓斥候','兜帽猎手','骨弩射手','月骨长弓手','骸盾禁卫','幽焰骨法师','猎魂弓卫','冥冠骨王']
 weapons=['剑盾','长枪盾','巨剑','重斧','咒术杖','冰晶杖','赤金杖','骷髅杖','骨医杖','日轮杖','提灯','主教杖','短弓','猎弓','骨弩','长弓','重盾巨剑','幽焰杖','猎魂弓','双手巨剑']
 chars=[]
 for i,old in enumerate(original):
  group=GROUPS[i//4];row=i%4;rank='common' if i<16 else 'elite' if i<19 else 'boss';size=52 if rank=='common' else 79 if rank=='elite' else 128
  chars.append({'id':old['id'].replace('skeleton-group01-skeleton-roles-','').replace('skeleton-group02-elites-boss-','elite-'),'sourceID':old['id'],'name':names[i],'role':old['role'],'group':group,'row':row,'rank':rank,'weapon':weapons[i],'anchor':metas[i//4]['anchors'][row],'previewSize':size,'relativeScale':.7 if rank=='common' else 1.1 if rank=='elite' else 1.6,'description':('精英' if rank=='elite' else '首领' if rank=='boss' else old['role'])+' · '+weapons[i]+'，保留原怪物的职业与装备辨识度。'})
 catalog={'version':1,'style':'classic-HD-2D-pixel','source':'built-in-imagegen','cycleSeconds':.6,'uniquePosesPerEnemy':4,'groups':[{'id':g,'file':g+'.png'} for g in GROUPS],'characters':chars,'nativeIntegration':False,'actions':['walk'],'pendingActions':['attack','cast','death']}
 (SITE/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf-8');shutil.copy2(SITE/'catalog.json',ROOT/'catalog.json')
 contact=Image.new('RGB',(1000,760),'#19282b');draw=ImageDraw.Draw(contact)
 for i,c in enumerate(chars):
  im=Image.open(ROOT/c['group']/'frames'/f'{c["row"]}-0.png').resize((144,144),Image.Resampling.NEAREST);x=i%5*200;y=i//5*190;contact.paste(im,(x+28,y+15),im);draw.text((x+12,y+166),str(i+1)+' '+c['id'],fill='#e3d6b9')
 contact.save(ROOT/'monster-roster-HD2D.png')
 with zipfile.ZipFile(SITE/'monster-source-assets.zip','w',zipfile.ZIP_DEFLATED) as z:
  for g in GROUPS:
   for file in ['raw-sheet.png','sheet-transparent.png','manifest.json','prompt-used.txt']:z.write(ROOT/g/file,g+'/'+file)
   for p in sorted((ROOT/g/'frames').glob('*.png')):z.write(p,g+'/frames/'+p.name)
  for p in (ROOT/'boss-corrected').glob('*.txt'):z.write(p,'boss-corrected/'+p.name)
  z.write(ROOT/'boss-corrected/raw-sheet.png','boss-corrected/raw-sheet.png');z.write(SITE/'catalog.json','catalog.json');z.write(Path(__file__).resolve(),'reproduction/prepare_hd2d_monsters.py')
 print(json.dumps({'enemies':len(chars),'walkPoses':len(chars)*4,'edgeTouchFrames':0,'archiveBytes':(SITE/'monster-source-assets.zip').stat().st_size,'site':str(SITE)}))
