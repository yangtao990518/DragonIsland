"""Extract a supplied green-screen animation without generating new artwork.

Keep decoded source poses and timing, remove green, use ONE crop for the whole
clip, and rank possible loop cuts. No optical flow, skeleton or pose redrawing.
"""
import argparse
import hashlib
import json
from pathlib import Path
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont


def key_green(rgb):
    c=rgb.astype(np.float32)
    r,g,b=c[:,:,0],c[:,:,1],c[:,:,2]
    other=np.maximum(r,b)
    pure=(g>120)&(other<25)&(g>other*3)
    background=np.median(c[pure],axis=0) if pure.any() else np.array([0.,210.,0.])
    # Core colors are blue/white/tan/ink, not green. Keep substantial connected
    # subjects, rejecting compression flecks that otherwise expand the crop.
    core=(g<=other+6).astype(np.uint8)
    count,labels,stats,_=cv2.connectedComponentsWithStats(core,8)
    accepted=np.flatnonzero(stats[:,cv2.CC_STAT_AREA]>=100)
    accepted=accepted[accepted!=0]
    core=np.isin(labels,accepted).astype(np.uint8)
    # Estimate foreground color from the nearest confident interior, then solve
    # C = a*F + (1-a)*B. This avoids assuming cyan hair has neutral green.
    interior=cv2.erode(core,np.ones((3,3),np.uint8))
    distance,nearest=cv2.distanceTransformWithLabels(1-interior,cv2.DIST_L2,5,labelType=cv2.DIST_LABEL_PIXEL)
    palette=np.zeros((int(nearest.max())+1,3),np.float32)
    palette[1:]=c[interior>0]
    estimate=palette[nearest]
    direction=estimate-background
    alpha=np.clip(np.sum((c-background)*direction,axis=2)/np.maximum(np.sum(direction*direction,axis=2),1),0,1)
    alpha[distance>4]=0
    alpha[core>0]=1
    alpha[alpha<.08]=0
    alpha[alpha>.98]=1
    # Unmix edge pixels from the measured screen color in straight RGBA.
    a=alpha[:,:,None]
    foreground=np.clip((c-(1-a)*background[None,None,:])/np.maximum(a,.01),0,255)
    foreground[alpha==0]=0
    rgba=np.dstack([np.round(foreground).astype(np.uint8),np.round(alpha*255).astype(np.uint8)])
    return rgba,background


def composite(rgba,bg=(25,32,51)):
    a=rgba[:,:,3:4].astype(np.float32)/255
    return np.round(rgba[:,:,:3]*a+np.array(bg)[None,None,:]*(1-a)).astype(np.uint8)


def features(rgba,rect,size):
    x0,y0,x1,y1=rect
    small=cv2.resize(composite(rgba[y0:y1,x0:x1]),size,interpolation=cv2.INTER_AREA)
    return small.astype(np.float32).reshape(-1)/255


def font(size):
    return ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',size)


def analyze(source,out):
    out.mkdir(parents=True,exist_ok=True)
    full=out/'frames-source-rgba';full.mkdir(exist_ok=True)
    capture=cv2.VideoCapture(str(source))
    if not capture.isOpened():raise RuntimeError('Video cannot be decoded')
    fps=capture.get(cv2.CAP_PROP_FPS)
    width=int(capture.get(cv2.CAP_PROP_FRAME_WIDTH));height=int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
    xscale,yscale=width/1280,height/720
    regions=[((0,0,width,height),(64,36),.25),
             ((int(240*xscale),int(515*yscale),int(650*xscale),int(710*yscale)),(64,32),.45),
             ((int(800*xscale),int(515*yscale),int(1200*xscale),int(710*yscale)),(56,32),.30)]
    sequence=[];times=[];bounds=[];screens=[];tiny=[]
    i=0
    while True:
        ok,bgr=capture.read()
        if not ok:break
        times.append(capture.get(cv2.CAP_PROP_POS_MSEC)/1000)
        rgb=cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)
        rgba,bg=key_green(rgb)
        Image.fromarray(rgba).save(full/f'{i:04}.png',compress_level=3)
        mask=rgba[:,:,3]>32;ys,xs=np.nonzero(mask)
        if not len(xs):raise RuntimeError(('empty frame',i))
        bounds.append([int(xs.min()),int(ys.min()),int(xs.max()+1),int(ys.max()+1)])
        screens.append(bg.tolist())
        sequence.append(np.concatenate([features(rgba,rect,size)*np.sqrt(weight/(size[0]*size[1]*3)) for rect,size,weight in regions]))
        tiny.append(cv2.resize(rgb,(128,72),interpolation=cv2.INTER_AREA))
        if i%60==0:print('Extracted',i,flush=True)
        i+=1
    capture.release()
    data=np.array(sequence,np.float32)
    norms=np.sum(data*data,axis=1)
    distances=np.maximum(norms[:,None]+norms[None,:]-2*data@data.T,0)
    candidates=[]
    # Exclude the model's first half-second settling and leave context at end.
    for start in range(30,max(30,i-60)):
        for end in range(start+55,min(start+160,i-4)):
            window=float(np.mean([distances[start+k,end+k] for k in range(-2,3)]))
            velocity=float(np.mean(((data[start+1]-data[start-1])-(data[end+1]-data[end-1]))**2)*data.shape[1])
            candidates.append(dict(start=start,end_exclusive=end,frames=end-start,
                                   seconds=times[end]-times[start],score=window+.15*velocity,
                                   pose_rmse=float(np.sqrt(distances[start,end])),window_mse=window))
    candidates.sort(key=lambda v:v['score'])
    picked=[]
    for item in candidates:
        if all(abs(item['start']-v['start'])>12 or abs(item['frames']-v['frames'])>12 for v in picked):picked.append(item)
        if len(picked)==12:break
    bounds=np.array(bounds)
    union=[max(0,int(bounds[:,0].min())-16),max(0,int(bounds[:,1].min())-16),
           min(width,int(bounds[:,2].max())+16),min(height,int(bounds[:,3].max())+16)]
    differences=np.mean(np.abs(np.diff(np.array(tiny).astype(np.float32),axis=0)),axis=(1,2,3))
    report=dict(source=str(source),source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                decoded_frames=i,width=width,height=height,reported_average_fps=fps,
                presentation_timestamps_seconds=times,median_frame_interval=float(np.median(np.diff(times))),
                median_consecutive_rgb_difference=float(np.median(differences)),near_identical_pairs_under_point1=int(np.count_nonzero(differences<.1)),
                uniform_crop_xyxy=union,loop_candidates=picked,background_sample_rgb=screens,
                status='extracted_loop_candidates_pending_visual_review',generated_new_poses=False,
                optical_flow_used=False,app_integrated=False)
    (out/'extraction-analysis.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    # Boundary/contact diagnostic: last two exported frames and the next two.
    board=Image.new('RGB',(1600,len(picked[:6])*245),'#192033');draw=ImageDraw.Draw(board)
    for row,item in enumerate(picked[:6]):
        for col,t in enumerate([item['start'],item['start']+1,item['end_exclusive']-1,item['end_exclusive']]):
            rgba=np.array(Image.open(full/f'{t:04}.png'))
            im=Image.fromarray(composite(rgba));im.thumbnail((400,218))
            x,y=col*400,row*245;board.paste(im,(x,y+27))
            draw.text((x+7,y+2),f"#{row+1} {item['start']}..{item['end_exclusive']-1} | frame {t}",font=font(15),fill='white')
    board.save(out/'loop-candidates.png')
    print(json.dumps(dict(frames=i,crop=union,best_candidates=picked[:6]),indent=2),flush=True)
    return report


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('source',type=Path);parser.add_argument('out',type=Path)
    args=parser.parse_args();analyze(args.source,args.out)
