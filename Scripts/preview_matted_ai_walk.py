"""Package a separately solved alpha/foreground sequence for user review."""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path
import cv2
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from preview_extracted_ai_walk import encode
from matte_ai_walk_video import composite

FONT='C:/Windows/Fonts/msyh.ttc'


def stage(rgba,bg,label):
    image=Image.new('RGB',(1280,800),'#192033');draw=ImageDraw.Draw(image)
    image.paste(Image.fromarray(composite(rgba,bg)),(0,48))
    draw.text((20,10),label,font=ImageFont.truetype(FONT,21),fill='white')
    draw.text((20,774),'原视频动作 / 重做透明遮罩与边缘颜色 / 1.6秒循环 / 待审阅',font=ImageFont.truetype(FONT,16),fill='#bac8dd')
    return image


def detail(before,after):
    output=Image.new('RGB',(1280,1000),'#101419');draw=ImageDraw.Draw(output)
    for col,(rgba,title) in enumerate([(before,'上一版 v3'),(after,'新抠像 v4')]):
        x=col*640
        draw.text((x+20,15),title,font=ImageFont.truetype(FONT,25),fill='white')
        canvas=Image.fromarray(composite(rgba,(16,20,25)))
        feet=canvas.crop((350,525,650,710)).resize((600,370),Image.Resampling.LANCZOS)
        leash=canvas.crop((580,400,960,585)).resize((600,292),Image.Resampling.LANCZOS)
        output.paste(feet,(x+20,90));output.paste(leash,(x+20,580))
        draw.text((x+20,55),'鞋袜轮廓 · 连续原速',font=ImageFont.truetype(FONT,18),fill='#bdc9d9')
        draw.text((x+20,540),'牵引绳轮廓 · 连续原速',font=ImageFont.truetype(FONT,18),fill='#bdc9d9')
    draw.text((20,945),'对照用于检查轮廓跳动；两列使用同一批源视频帧，不重画动作。',font=ImageFont.truetype(FONT,19),fill='#bdc9d9')
    return output


def run(out,old):
    report=json.loads((out/'matting-report.json').read_text(encoding='utf-8'))
    indices=report['source_frames'];assert indices==list(range(49,145))
    images=[];previous=[];records=[];checks=[]
    frames=out/'frames-loop-rgba';frames.mkdir(exist_ok=True)
    crop=report['uniform_crop_xyxy'];x0,y0,x1,y1=crop
    for i,tick in enumerate(indices):
        rgba=np.array(Image.open(out/'frames-source-rgba'/f'{tick:04}.png').convert('RGBA'))
        prior=np.array(Image.open(old/'frames-source-rgba'/f'{tick:04}.png').convert('RGBA'))
        assert rgba.shape==prior.shape==(720,1280,4)
        images.append(rgba);previous.append(prior)
        file=frames/f'{i:03}.png';Image.fromarray(rgba).crop(crop).save(file,compress_level=6)
        records.append(dict(frame=i,source_frame=tick,duration_seconds=1/60,sha256=hashlib.sha256(file.read_bytes()).hexdigest()))
        _,labels=cv2.connectedComponents((rgba[:,:,3]>64).astype(np.uint8),8)
        def main(rect):
            xx,yy,xxx,yyy=rect;v=labels[yy:yyy,xx:xxx].reshape(-1);v=v[v>0]
            return int(np.bincount(v).argmax()) if len(v) else -1
        outside=rgba[:,:,3].copy();outside[y0:y1,x0:x1]=0
        checks.append(dict(source_frame=tick,leash_connected=main((350,230,600,540))==main((850,410,1100,600)),
                           maximum_alpha_outside_crop=int(outside.max())))
    assert all(v['maximum_alpha_outside_crop']<4 for v in checks)
    backgrounds=[((15,15,15),'近黑背景'),((245,245,245),'近白背景'),((25,32,51),'深蓝灰背景'),((120,120,120),'中灰背景')]
    def full():
        for tick in range(384):
            color,label=backgrounds[tick//96]
            yield stage(images[tick%96],color,'新抠像 v4 / '+label+' / 同一动作循环')
    full_video=encode(out/'loop-matting-review.mp4',full(),(1280,800))
    def closeups():
        for tick in range(384):yield detail(previous[tick%96],images[tick%96])
    detail_video=encode(out/'edge-motion-comparison.mp4',closeups(),(1280,1000))
    stills=[Image.open(frames/f'{i:03}.png').convert('RGBA') for i in range(96)]
    durations=[round((i+1)*1000/60)-round(i*1000/60) for i in range(96)]
    webp=out/'dafeiyu-dog-loop-transparent.webp'
    stills[0].save(webp,save_all=True,append_images=stills[1:],duration=durations,lossless=True,exact=True,method=4,loop=0)
    decoded=Image.open(webp);assert decoded.n_frames==96 and decoded.mode=='RGBA'
    stage(images[0],(25,32,51),'新抠像 v4 / 原动作保持').save(out/'keyed-poster.png')
    # True 4x magnification, before/after on dark and light backgrounds.
    boxes=[('鞋外沿',(385,605,449,669)),('发丝',(165,340,229,404)),
           ('牵引绳',(716,506,780,570)),('狗耳外沿',(990,386,1054,450))]
    board=Image.new('RGB',(1024,len(boxes)*290),'#192033');draw=ImageDraw.Draw(board)
    for row,(label,rect) in enumerate(boxes):
        for col,(rgba,bg) in enumerate([(previous[0],(15,15,15)),(images[0],(15,15,15)),(previous[0],(245,245,245)),(images[0],(245,245,245))]):
            patch=Image.fromarray(composite(rgba,bg)).crop(rect).resize((256,256),Image.Resampling.NEAREST)
            x,y=col*256,row*290;board.paste(patch,(x,y+34))
            draw.text((x+5,y+5),label+(' / v3' if col%2==0 else ' / v4'),font=ImageFont.truetype(FONT,16),fill='white')
    board.save(out/'edge-4x-comparison.png')
    manifest=dict(status='new_matting_candidate_pending_user_review',source=report['source'],source_sha256=report['source_sha256'],
                  selected_source_frames=[49,145],end_exclusive=True,frame_count=96,fps=60,seconds=1.6,
                  uniform_crop_xyxy=crop,canvas_size=[x1-x0,y1-y0],method=report['method'],
                  morphological_final_edge_shrink=False,nearest_color_replacement=False,
                  optical_flow_scope='alignment of adjacent alpha mattes only; no image synthesis',
                  user_motion_accepted=True,app_integrated=False,ipa_generated=False,checks=checks,
                  records=records,previews=[full_video,detail_video],
                  limitation='This is a new matting trial. Source motion/shape artifacts and the original loop seam remain; user edge review is still required.')
    (out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    with zipfile.ZipFile(out/'dafeiyu-dog-loop-pngs.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        z.write(out/'manifest.json','manifest.json')
        for i in range(96):z.write(frames/f'{i:03}.png',f'frames/{i:03}.png')
    with zipfile.ZipFile(out/'dafeiyu-dog-loop-pngs.zip') as z:assert z.testzip() is None
    assert hashlib.sha256(Path(report['source']).read_bytes()).hexdigest()==report['source_sha256']
    print('Packaged 96 frames; disconnected leash frames:',[v['source_frame'] for v in checks if not v['leash_connected']],flush=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('out',type=Path);p.add_argument('old',type=Path);a=p.parse_args();run(a.out,a.old)
