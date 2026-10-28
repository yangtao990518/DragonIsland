"""Split the imagegen key sheets and make honest native-pixel review boards."""
import json
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from animation_runtime import REPOSITORY,FONT

OUT=REPOSITORY/'output/pet-walk-batch2/walk-painted-v7'
FILES={'xiaobai':'exec-f986ba59-fe95-4e36-ba3b-0ecef8917a01.png',
       'dafeiyu':'exec-2909df58-9892-44c9-b28f-676a697f8520.png'}

def split():
    stats={}
    for role,name in FILES.items():
        sheet=Image.open(OUT/'generated'/name).convert('RGBA')
        width,height=sheet.width//2,sheet.height//4
        folder=OUT/role/'keys';folder.mkdir(parents=True,exist_ok=True)
        board=Image.new('RGB',(1600,1050),'#192033');draw=ImageDraw.Draw(board)
        stats[role]=[]
        for i in range(8):
            art=sheet.crop(((i%2)*width,(i//2)*height,(i%2+1)*width,(i//2+1)*height))
            # Fully transparent pixels may carry a coloured matte from the
            # generator. Premultiplied resampling prevents that matte bleeding.
            rgba=np.array(art);rgba[rgba[:,:,3]<5]=0;art=Image.fromarray(rgba)
            art.save(folder/f'{i:02}.png')
            human=art.crop((0,0,round(width*.66),height));pet=art.crop((round(width*.66),0,width,height))
            bbox=human.getbbox();petbox=pet.getbbox()
            stats[role].append(dict(frame=i,human_bbox=bbox,pet_bbox=petbox))
            foot=human.crop((int(width*.25),int(height*.64),int(width*.6),height))
            foot=foot.convert('RGBa').resize((390,round(foot.height*390/foot.width)),Image.Resampling.LANCZOS).convert('RGBA')
            petcrop=pet.crop(petbox);petcrop.thumbnail((380,220))
            x=(i%4)*400;y=(i//4)*525
            board.paste(foot,(x,y),foot);board.paste(petcrop,(x+10,y+295),petcrop)
            draw.text((x+8,y+5),str(i),fill='white',font=ImageFont.truetype(str(FONT),20))
        board.save(OUT/f'{role}-painted-key-review.png')
        print(role,stats[role],flush=True)
    (OUT/'sheet-split.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')

if __name__=='__main__':split()
