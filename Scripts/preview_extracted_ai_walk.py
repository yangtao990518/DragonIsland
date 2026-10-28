"""Package extracted RGBA poses and preview them without synthesizing motion."""
import argparse
import hashlib
import json
import math
import subprocess
import zipfile
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from animation_runtime import ffmpeg
from extract_ai_walk_video import font


def encode(path,frames,size):
    cmd=[ffmpeg(),'-hide_banner','-y','-f','rawvideo','-pixel_format','rgb24','-video_size',f'{size[0]}x{size[1]}',
         '-framerate','60','-i','pipe:0','-an','-c:v','libx264','-crf','18','-preset','fast','-pix_fmt','yuv420p','-movflags','+faststart',str(path)]
    count=0
    with path.with_suffix('.encode.log').open('wb') as log:
        proc=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=log,stderr=log)
        try:
            for image in frames:
                proc.stdin.write(image.convert('RGB').tobytes());count+=1
        finally:proc.stdin.close()
        if proc.wait():raise RuntimeError(('encode failed',path))
    result=subprocess.run([ffmpeg(),'-hide_banner','-v','error','-nostats','-progress','pipe:1','-i',str(path),'-f','null','-'],capture_output=True,text=True,check=True)
    values=dict(line.split('=',1) for line in result.stdout.splitlines() if '=' in line)
    if int(values['frame'])!=count or result.stderr.strip():raise RuntimeError(('decode failed',path,result.stderr))
    print('Encoded and decoded',path.name,count,'frames',flush=True)
    return dict(file=path.name,frames=count,fps=60,seconds=count/60,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),decoded=True)


def review(art,label,checker=False):
    size=(1280,800)
    output=Image.new('RGB',size,'#192033')
    draw=ImageDraw.Draw(output)
    if checker:
        for y in range(48,768,24):
            for x in range(0,1280,24):
                draw.rectangle((x,y,x+23,y+23),fill='#bec4cb' if ((x//24+(y-48)//24)%2) else '#e5e8ec')
    output.paste(art,(0,48),art)
    draw.text((20,10),label,font=font(22),fill='white')
    draw.text((20,773),'仅提取原视频动作 / 去绿底 / 固定画布；未接入 App',font=font(16),fill='#bdc8dc')
    return output


def package(out,start,end):
    report=json.loads((out/'extraction-analysis.json').read_text(encoding='utf-8'))
    frames=out/'frames-source-rgba'
    loopdir=out/'frames-loop-rgba';loopdir.mkdir(exist_ok=True)
    crop=report['uniform_crop_xyxy'];x0,y0,x1,y1=crop
    # One union crop for ALL frames; never center using each moving bbox.
    size=(x1-x0,y1-y0)
    images=[];records=[]
    for index,tick in enumerate(range(start,end)):
        original=Image.open(frames/f'{tick:04}.png').convert('RGBA')
        art=original.crop(crop)
        file=loopdir/f'{index:03}.png';art.save(file,compress_level=6)
        images.append(art)
        records.append(dict(index=index,source_frame=tick,source_pts=report['presentation_timestamps_seconds'][tick],
                            duration_seconds=1/60,sha256=hashlib.sha256(file.read_bytes()).hexdigest()))
    durations=[round((i+1)*1000/60)-round(i*1000/60) for i in range(len(images))]
    webp=out/'dafeiyu-dog-loop-transparent.webp'
    images[0].save(webp,save_all=True,append_images=images[1:],duration=durations,loop=0,lossless=True,exact=True,method=4)
    decoded=Image.open(webp)
    assert decoded.n_frames==len(images) and decoded.mode=='RGBA'
    # The source has one 1/30s interval. Hold that existing decoded pose for
    # an extra display tick rather than speeding up the full clip or inventing
    # an intermediate pose. The selected loop is uniformly 60fps already.
    times=np.array(report['presentation_timestamps_seconds'])
    count=round((times[-1]+1/60)*60)
    mapping=np.maximum(0,np.searchsorted(times,np.arange(count)/60+1e-7,side='right')-1)
    def full_review():
        for index in mapping:
            art=Image.open(frames/f'{index:04}.png').convert('RGBA')
            yield review(art,'AI 视频去背景：完整动作 / 棋盘格检查透明边缘',True)
    full=encode(out/'full-keyed-review.mp4',full_review(),(1280,800))
    def looping():
        for tick in range(len(images)*4):
            canvas=Image.new('RGBA',(report['width'],report['height']))
            canvas.alpha_composite(images[tick%len(images)],(x0,y0))
            yield review(canvas,f'循环候选：源帧 {start}–{end-1} / {len(images)} 帧 / {len(images)/60:.2f} 秒')
    repeated=encode(out/'loop-keyed-review.mp4',looping(),(1280,800))
    first=Image.new('RGBA',(report['width'],report['height']));first.alpha_composite(images[0],(x0,y0))
    review(first,'去绿底预览 / 动作来自用户提供的视频').save(out/'keyed-poster.png')
    seam=Image.new('RGB',(1280,880),'#192033');draw=ImageDraw.Draw(seam)
    for i,t in enumerate([end-2,end-1,start,start+1]):
        art=Image.open(frames/f'{t:04}.png').convert('RGBA')
        canvas=Image.new('RGB',art.size,'#192033');canvas.paste(art,(0,0),art);canvas.thumbnail((640,400))
        xx=(i%2)*640;yy=(i//2)*440
        seam.paste(canvas,(xx,yy+35));draw.text((xx+10,yy+5),f'源帧 {t}'+(' / 接缝前' if i<2 else ' / 接缝后'),font=font(20),fill='white')
    seam.save(out/'loop-seam-review.png')
    manifest=dict(source=report['source'],source_sha256=report['source_sha256'],source_decoded_frames=report['decoded_frames'],
                  source_frame_size=[report['width'],report['height']],uniform_crop_xyxy=crop,canvas_size=list(size),
                  selected_source_range=[start,end],source_end_exclusive=True,frame_count=len(images),fps=60,seconds=len(images)/60,
                  records=records,transparent_webp=webp.name,webp_duration_ms=sum(durations),video_previews=[full,repeated],
                  complete_preview_display_frames=count,source_gap_handling='one original pose held for its original extra 1/60s; no synthesized frame',
                  generated_new_poses=False,optical_flow_used=False,per_frame_bbox_recentering=False,
                  status='trial_extraction_loop_not_accepted_as_seamless',
                  limitations=['AI source clothing/hair/hand motion is not exactly periodic; direct loop cut can show a small seam.',
                               'The supplied video itself has soft overlapping shoe contours during passing poses; extraction preserves them.',
                               'Green-screen compression edges have been cleaned, but still need normal-size and contrast-background review.'],
                  app_integrated=False,ipa_generated=False)
    if report.get('status') in ('edge_refinement_v2','contour_refinement_v3'):
        manifest.update(status=report['status']+'_pending_user_review',user_motion_accepted=True,
                        edge_refinement_report='edge-verification.json',
                        previous_output=report['previous_output'],
                        preserved_previous_loop=True,edge_cleanup_only=True)
    (out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    with zipfile.ZipFile(out/'dafeiyu-dog-loop-pngs.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6) as bundle:
        bundle.write(out/'manifest.json','manifest.json')
        for i in range(len(images)):bundle.write(loopdir/f'{i:03}.png',f'frames/{i:03}.png')
    with zipfile.ZipFile(out/'dafeiyu-dog-loop-pngs.zip') as bundle:assert bundle.testzip() is None
    assert hashlib.sha256(Path(report['source']).read_bytes()).hexdigest()==report['source_sha256']
    print(json.dumps(dict(loop_frames=len(images),size=size,seconds=len(images)/60,original_unchanged=True)),flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('out',type=Path);parser.add_argument('--start',type=int,default=49);parser.add_argument('--end',type=int,default=145)
    args=parser.parse_args();package(args.out,args.start,args.end)
