#!/usr/bin/env python3
"""Slice approved ImageGen 4x4 atlases; no optical-flow or blended fake poses."""
from collections import deque
import json
from pathlib import Path
from PIL import Image, ImageDraw
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'Art/MotionV3'


def clean_cell(cell):
    rgba=np.array(cell.convert('RGBA'))
    mask=rgba[:,:,3]>12
    seen=np.zeros_like(mask)
    components=[]
    height,width=mask.shape
    for yy,xx in zip(*np.where(mask)):
        if seen[yy,xx]:continue
        q=deque([(int(xx),int(yy))]);seen[yy,xx]=True;points=[]
        while q:
            x,y=q.popleft();points.append((x,y))
            for nx,ny in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
                if 0<=nx<width and 0<=ny<height and mask[ny,nx] and not seen[ny,nx]:
                    seen[ny,nx]=True;q.append((nx,ny))
        if len(points)>100:components.append(points)
    if not components:raise ValueError('Empty sprite cell')
    # Discard isolated alpha specks outside the illustrated character.
    keep=np.zeros_like(mask)
    for points in [max(components,key=len)]:
        x,y=zip(*points);keep[y,x]=True
    rgba[~keep,3]=0
    image=Image.fromarray(rgba)
    return image.crop(image.getchannel('A').getbbox())


def main():
    manifest=json.loads((ROOT/'Art/MotionV2/manifest.json').read_text())
    manifest['schemaVersion']=2
    manifest['status']='V1.5_walk_replacement_30fps_target'
    for action,info in manifest['actions'].items():
        info['frames']=['../MotionV2/'+p for p in info['frames']]
    previews=ROOT/'build/motion-v3-preview';previews.mkdir(parents=True,exist_ok=True)
    for action,source in [('walk_left','walk-left-16.png'),('walk_right','walk-right-16.png'),('roll','roll-16.png')]:
        atlas=Image.open(ART/'sources'/source).convert('RGBA')
        boundaries=[0]
        counts=(np.asarray(atlas)[:,:,3]>16).sum(axis=1)
        for row in range(1,4):
            center=row*atlas.height/4;radius=atlas.height/4*.22
            boundaries.append(min(range(round(center-radius),round(center+radius)),key=lambda y:(counts[y],abs(y-center))))
        boundaries.append(atlas.height)
        cells=[]
        for i in range(16):
            x,y=i%4,i//4
            cells.append(clean_cell(atlas.crop((round(x*atlas.width/4),boundaries[y],round((x+1)*atlas.width/4),boundaries[y+1]))))
        # One scale for the entire sequence; independent per-frame scaling causes
        # breathing/jitter even if the source animation is otherwise correct.
        scale=min(468/max(c.width for c in cells),566/max(c.height for c in cells))
        frames=[]
        for i,cell in enumerate(cells):
            cell=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.LANCZOS)
            canvas=Image.new('RGBA',(512,640))
            canvas.alpha_composite(cell,((512-cell.width)//2,600-cell.height))
            path=ART/f'frames/{action}/{i:03}.png';path.parent.mkdir(parents=True,exist_ok=True);canvas.save(path)
            frames.append(canvas)
        if action=='roll':
            neutral=Image.open(ROOT/'Art/MotionV2/frames/idle/000.png').convert('RGBA')
            for i in (0,15):
                frames[i]=neutral.copy();frames[i].save(ART/f'frames/{action}/{i:03}.png')
        # Every 30fps tick advances a genuine newly drawn pose. 16/30s cycle.
        durations=[33,34,33]*5+[33]
        manifest['actions'][action]={'frames':[f'frames/{action}/{i:03}.png' for i in range(16)],'frameDurationsMs':durations,'durationMs':sum(durations),'loop':action!='roll','uniqueDrawings':15 if action=='roll' else 16,'mirrorAllowed':False}
        contact=Image.new('RGB',(4*256,4*340),'#14111c');d=ImageDraw.Draw(contact)
        for i,frame in enumerate(frames):
            rgb=Image.new('RGBA',frame.size,'#14111c');rgb.alpha_composite(frame)
            contact.paste(rgb.convert('RGB').resize((256,320)),((i%4)*256,(i//4)*340+20))
            d.text(((i%4)*256+5,(i//4)*340+3),f'{action} {i:02}',fill='white')
        contact.save(previews/f'{action}-contact.jpg')
        rgb=[]
        for frame in frames:
            im=Image.new('RGBA',frame.size,'#08060e');im.alpha_composite(frame);rgb.append(im.convert('RGB'))
        rgb[0].save(previews/f'{action}.gif',save_all=True,append_images=rgb[1:],duration=[30,30,40]*5+[30],loop=0)
    # Left walk: turn first, two full gait cycles during translation, turn back.
    for name,action in [('walk_burst','walk_right'),('walk_left_burst','walk_left')]:
        entries=[]
        if action=='walk_left':
            entries += [{'action':'turn_left','frame':i,'durationMs':62.5} for i in range(4)]
        else:entries += [{'action':'idle','frame':0,'durationMs':250}]
        # Two complete cycles at 30fps; no gait poses skipped to gain speed.
        for _ in range(2):
            entries += [{'action':action,'frame':i,'durationMs':duration} for i,duration in enumerate(durations)]
        if action=='walk_left':
            entries += [{'action':'turn_left','frame':i,'durationMs':62.5} for i in reversed(range(4))]
        else:entries += [{'action':'idle','frame':0,'durationMs':250}]
        manifest['clips'][name]={'entries':entries,'durationMs':1566,'note':'gait active exactly during 250..1316ms root movement; no sliding during turns'}
    (ART/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Imported 16 left + 16 right + 16 roll frames (shared neutral endpoints); V2 preserved.')


if __name__=='__main__':main()
