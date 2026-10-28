"""Painted anatomy + neural intermediate frames for review, RGB previews only.

The keyframe alpha originals are retained. The v8 frames are rendered over a
constant review background; they are not transparent runtime-ready materials.
"""
import hashlib,json,subprocess
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
import painted_pet_walk as helpers
from animation_runtime import REPOSITORY,FONT

SOURCE=helpers.OUT
OUT=SOURCE.parent/'walk-painted-v8'
RIFE=REPOSITORY.parent/'tools/rife/rife-ncnn-vulkan-20221029-windows'
BG=np.array([25,32,51],np.float32)/255.
FILES={'xiaobai':'exec-9f540cfe-e77a-446e-b243-0006f8e70038.png',
       'dafeiyu':'exec-1fbb2d32-2b58-4f76-bfc4-54f29560ad32.png'}

def material_keys(role):
    result=[helpers.clean_key(SOURCE/role/'keys/00.png'),helpers.clean_key(SOURCE/role/'keys/02.png')]
    sheet=Image.open(SOURCE/'generated'/FILES[role]).convert('RGBA')
    folder=OUT/role/'inputs';folder.mkdir(parents=True,exist_ok=True)
    for col in [0,1]:
        key=sheet.crop((col*sheet.width//2,0,(col+1)*sheet.width//2,sheet.height))
        key=key.convert('RGBa').resize((512,384),Image.Resampling.LANCZOS).convert('RGBA')
        key.save(folder/f'guide-render-{col}.png')
        result.append(helpers.clean_key(folder/f'guide-render-{col}.png'))
    return result

def prepare(role):
    keys=material_keys(role);reference=keys[0]
    h,w=reference.shape[:2];yy,xx=np.mgrid[:h,:w].astype('float32')
    result=[];reports=[]
    folder=OUT/role/'keys';folder.mkdir(exist_ok=True)
    for i,key in enumerate(keys):
        if i==0:
            human=pet=np.array([[1.,0.,0.],[0.,1.,0.]])
            report={'reference':True}
        else:
            human,hm=helpers.align_matrix(key,reference,(40,5,300,235))
            pet,pm=helpers.align_matrix(key,reference,(365,205,507,299))
            report=dict(human=hm,pet=pm)
        ih=helpers.cv2.invertAffineTransform(human);ip=helpers.cv2.invertAffineTransform(pet)
        p=helpers.ease((xx-275)/100)
        mx=(ih[0,0]*xx+ih[0,1]*yy+ih[0,2])*(1-p)+(ip[0,0]*xx+ip[0,1]*yy+ip[0,2])*p
        my=(ih[1,0]*xx+ih[1,1]*yy+ih[1,2])*(1-p)+(ip[1,0]*xx+ip[1,1]*yy+ip[1,2])*p
        aligned=helpers.remap(key,mx,my)
        mx=xx.copy();my=yy.copy();offsets=[]
        for left,right,top in [(120,285,265 if role=='xiaobai' else 280),(345,508,300)]:
            src=np.where(aligned[top:,left:right,3]>.5)[0]+top
            ref=np.where(reference[top:,left:right,3]>.5)[0]+top
            offset=float(ref.max()-src.max());offsets.append(offset)
            weight=helpers.ease((yy-(top-20))/(float(ref.max())-(top-20)))
            my-=((xx>=left)&(xx<right))*weight*offset
        aligned=helpers.remap(aligned,mx,my)
        boundary=np.where(xx<325,235.,290.)
        weight=helpers.ease((yy-boundary)/22)[:,:,None]
        weight[(xx>278)&(xx<352)]=0
        aligned=reference*(1-weight)+aligned*weight
        helpers.unpremult(aligned).save(OUT/role/f'painted-key-{i}.png')
        rgb=aligned[:,:,:3]+BG[None,None,:]*(1-aligned[:,:,3:4])
        image=Image.fromarray(np.round(np.clip(rgb,0,1)*255).astype('uint8'))
        image.save(folder/f'{i:03}.png')
        result.append(image)
        reports.append(dict(key=i,source_registration=report,sole_corrections=offsets))
    result[0].save(folder/'004.png')
    (OUT/role/'registration.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
    return result

def main():
    OUT.mkdir(exist_ok=True)
    for role in helpers.CFG:
        keys=prepare(role)
        folder=OUT/role/'frames-60fps';folder.mkdir(exist_ok=True)
        command=[str(RIFE/'rife-ncnn-vulkan.exe'),'-i',str(OUT/role/'keys'),'-o',str(folder),'-n','97',
            '-m',str(RIFE/'rife-v4.6'),'-g','0','-j','1:1:1','-f','%03d.png']
        print('Neural interpolation',role,flush=True)
        with (OUT/role/'rife.log').open('wb') as log:
            process=subprocess.run(command,cwd=RIFE,stdout=log,stderr=log)
        if process.returncode:raise RuntimeError(('RIFE failed',role,process.returncode))
        files=sorted(folder.glob('*.png'))
        if len(files)!=97:raise ValueError(('bad RIFE frame count',len(files)))
        board=Image.new('RGB',(1600,1440),'#192033');draw=ImageDraw.Draw(board)
        font=ImageFont.truetype(str(FONT),18)
        for col,tick in enumerate(range(0,96,6)):
            image=Image.open(files[tick]).convert('RGB')
            crop=image.crop((120,245,280,365)).resize((400,300),Image.Resampling.LANCZOS)
            x=(col%4)*400;y=(col//4)*360
            board.paste(crop,(x,y+30));draw.text((x+8,y+4),f'{tick}/96',fill='white',font=font)
        board.save(OUT/f'{role}-leg-audit.png')
        print(role,'97 rendered frames, last duplicates first for loop closure',flush=True)

if __name__=='__main__':main()
