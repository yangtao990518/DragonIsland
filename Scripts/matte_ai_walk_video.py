"""Recover video alpha and foreground separately from the original green plate.

The eroded/dilated masks below are confidence seeds for a matting solve, never
the delivered silhouette. No contour contraction, RGB nearest-neighbor edge
replacement, per-frame recentering, or generated animation poses are used.
"""
import argparse
import hashlib
import json
import time
from pathlib import Path
import cv2
import numpy as np
from PIL import Image,ImageDraw,ImageFont


def trimap_for(rgb):
    hsv=cv2.cvtColor(rgb.astype(np.float32)/255,cv2.COLOR_RGB2HSV)
    green=(hsv[:,:,0]>=70)&(hsv[:,:,0]<=175)&(hsv[:,:,1]>.15)&(hsv[:,:,2]>.12)
    seed=(~green).astype(np.uint8)
    count,labels,stats,_=cv2.connectedComponentsWithStats(seed,8)
    good=np.flatnonzero(stats[:,cv2.CC_STAT_AREA]>=64);good=good[good!=0]
    seed=np.isin(labels,good).astype(np.uint8)
    interior=cv2.erode(seed,np.ones((7,7),np.uint8))
    outside=1-cv2.dilate(seed,np.ones((7,7),np.uint8))
    trimap=np.full(seed.shape,.5,np.float64)
    trimap[outside>0]=0;trimap[interior>0]=1
    # Narrow holes between strands may have no background seed after a
    # geometric dilation. A pure screen pixel is known background even there.
    c=rgb.astype(np.float32)/255
    # Thin dark-blue strands can have no interior after confidence erosion.
    # Preserve truly blue, strongly separated pixels as foreground anchors.
    blue=(c[:,:,2]-c[:,:,1]>.18)&(c[:,:,2]-c[:,:,0]>.20)&(hsv[:,:,0]>=195)&(hsv[:,:,0]<=265)
    trimap[blue]=1
    pure=(c[:,:,1]>.40)&(np.maximum(c[:,:,0],c[:,:,2])<.07)
    # The supplied character has blue/cyan, white, skin and tan, but no green.
    # Add hue-confident screen anchors even inside narrow, compressed gaps;
    # a purely geometric trimap has no zero-alpha seed in those small holes.
    screen=(hsv[:,:,0]>=85)&(hsv[:,:,0]<=165)&(hsv[:,:,1]>.28)&(hsv[:,:,2]>.10)
    trimap[pure|screen]=0
    return trimap


def read_frames(source,indices):
    capture=cv2.VideoCapture(str(source));images={}
    if not capture.isOpened():raise RuntimeError(source)
    capture.set(cv2.CAP_PROP_POS_FRAMES,min(indices))
    for tick in range(min(indices),max(indices)+1):
        ok,bgr=capture.read()
        if not ok:raise RuntimeError(('decode',tick))
        if tick in indices:images[tick]=cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)
    capture.release();return images


def composite(rgba,bg=(25,32,51)):
    a=rgba[:,:,3:4].astype(np.float32)/255
    return np.round(rgba[:,:,:3]*a+np.array(bg)[None,None,:]*(1-a)).astype(np.uint8)


def aligned_alpha(rgb,neighbor,neighbor_alpha):
    shape=rgb.shape[:2]
    current=cv2.cvtColor(cv2.resize(rgb,(640,360)),cv2.COLOR_RGB2GRAY)
    other=cv2.cvtColor(cv2.resize(neighbor,(640,360)),cv2.COLOR_RGB2GRAY)
    flow=cv2.calcOpticalFlowFarneback(current,other,None,.5,3,19,3,5,1.2,0)
    flow=cv2.resize(flow,(shape[1],shape[0]),interpolation=cv2.INTER_LINEAR)*2
    yy,xx=np.mgrid[:shape[0],:shape[1]].astype(np.float32)
    mx,my=xx+flow[:,:,0],yy+flow[:,:,1]
    warped=cv2.remap(neighbor_alpha.astype(np.float32),mx,my,cv2.INTER_LINEAR,borderMode=cv2.BORDER_CONSTANT)
    warped_rgb=cv2.remap(neighbor.astype(np.float32),mx,my,cv2.INTER_LINEAR,borderMode=cv2.BORDER_CONSTANT)
    difference=np.mean((rgb.astype(np.float32)-warped_rgb)**2,axis=2)
    weight=.22*np.exp(-difference/(12.**2))
    return warped,weight


def board(images,out):
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',17)
    ticks=list(images)[:8]
    sheet=Image.new('RGB',(960,len(ticks)*320),'#192033');draw=ImageDraw.Draw(sheet)
    for row,tick in enumerate(ticks):
        rgba=images[tick]
        for col,bg in enumerate([(15,15,15),(245,245,245)]):
            im=Image.fromarray(composite(rgba,bg)).crop((360,530,660,710)).resize((480,288),Image.Resampling.LANCZOS)
            x=col*480;y=row*320
            sheet.paste(im,(x,y+30));draw.text((x+8,y+5),f'源帧 {tick} / 连续边缘',font=font,fill='white')
    sheet.save(out/'consecutive-feet.png')


def run(old,out,pilot=False,pilot_start=49):
    from pymatting import estimate_alpha_cf,estimate_foreground_ml
    report=json.loads((old/'extraction-analysis.json').read_text(encoding='utf-8'))
    source=Path(report['source']);out.mkdir(parents=True,exist_ok=True)
    indices=list(range(pilot_start,pilot_start+8)) if pilot else list(range(48,146))
    images=read_frames(source,set(indices));alpha_dir=out/'alpha-solved';alpha_dir.mkdir(exist_ok=True)
    alphas={};timings=[]
    for tick,rgb in images.items():
        path=alpha_dir/f'{tick:04}-trimap-v4.npy'
        if path.exists():a=np.load(path)
        else:
            then=time.perf_counter();tri=trimap_for(rgb)
            a=estimate_alpha_cf(rgb.astype(np.float64)/255,tri,laplacian_kwargs={'epsilon':1e-6},cg_kwargs={'maxiter':2000,'rtol':1e-5})
            a=np.clip(a,0,1).astype(np.float32);np.save(path,a)
            timings.append(time.perf_counter()-then)
            if tick==indices[0]:Image.fromarray(np.round(tri*255).astype(np.uint8)).save(out/'confidence-trimap.png')
        alphas[tick]=a
        print('Solved alpha',tick,'seconds',round(timings[-1],3) if timings else 'cached',flush=True)
    folder=out/'frames-source-rgba';folder.mkdir(exist_ok=True)
    saved={}
    for tick in (list(range(pilot_start+1,pilot_start+7)) if pilot else list(range(49,145))):
        rgb=images[tick];a=alphas[tick]
        sum_a=a.copy();sum_w=np.ones_like(a)
        for neighbor in [tick-1,tick+1]:
            if neighbor not in images:continue
            warped,w=aligned_alpha(rgb,images[neighbor],alphas[neighbor])
            sum_a+=warped*w;sum_w+=w
        stable=np.clip(sum_a/sum_w,0,1).astype(np.float64)
        # Freeze the deep confident interior and exterior; stabilization acts
        # only near uncertain boundaries and uses neighboring frames aligned
        # to the current source frame, never unaligned temporal blur.
        band=cv2.dilate(((a>.001)&(a<.999)).astype(np.uint8),np.ones((3,3),np.uint8))>0
        stable=np.where(band,stable,a).astype(np.float64)
        confidence=trimap_for(rgb)
        stable[confidence==0]=0;stable[confidence==1]=1
        then=time.perf_counter()
        foreground=estimate_foreground_ml(rgb.astype(np.float64)/255,stable,n_small_iterations=10,n_big_iterations=4)
        stable[stable<.002]=0;stable[stable>.998]=1
        foreground[stable==0]=0
        rgba=np.dstack([np.round(np.clip(foreground,0,1)*255).astype(np.uint8),np.round(stable*255).astype(np.uint8)])
        Image.fromarray(rgba).save(folder/f'{tick:04}.png',compress_level=3)
        saved[tick]=rgba
        print('Recovered foreground',tick,'seconds',round(time.perf_counter()-then,3),flush=True)
    board(saved,out)
    first=min(saved);Image.fromarray(saved[first]).save(out/'pilot-rgba.png')
    Image.fromarray(composite(saved[first])).save(out/'pilot-dark.png')
    info=dict(source=str(source),source_sha256=report['source_sha256'],method='closed-form alpha + motion-compensated alpha confidence filter + multilevel foreground recovery',
              source_frames=list(saved),uniform_crop_xyxy=report['uniform_crop_xyxy'],fps=60,
              morphological_final_edge_shrink=False,nearest_color_replacement=False,generated_new_poses=False,
              alpha_median_seconds=float(np.median(timings)) if timings else None,
              status='pilot_pending_visual_review' if pilot else 'v4_candidate_pending_user_review')
    (out/'matting-report.json').write_text(json.dumps(info,ensure_ascii=False,indent=2),encoding='utf-8')
    assert hashlib.sha256(source.read_bytes()).hexdigest()==report['source_sha256']


if __name__=='__main__':
    from PIL import ImageFont
    parser=argparse.ArgumentParser();parser.add_argument('old',type=Path);parser.add_argument('out',type=Path);parser.add_argument('--pilot',action='store_true');parser.add_argument('--pilot-start',type=int,default=49)
    args=parser.parse_args();run(args.old,args.out,args.pilot,args.pilot_start)
