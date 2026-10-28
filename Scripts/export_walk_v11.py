"""Export review videos, contact sheets and evidence for the latest draft."""
import hashlib,json,math,subprocess
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
import animation_runtime as runtime
import painted_walk_v11 as rig

OUT=rig.OUT
VERSION='v11'
TITLE=ImageFont.truetype(str(runtime.FONT),27)
TEXT=ImageFont.truetype(str(runtime.FONT),18)

def source_hashes():
    manifest=json.loads((runtime.REPOSITORY/'AnimationDrafts/2026-10-27/manifest.json').read_text(encoding='utf-8'))
    files={f['path']:f['sha256'] for f in manifest['files'] if f['path'].endswith('.png')}
    for path,sha in files.items():
        if hashlib.sha256((runtime.REPOSITORY/path).read_bytes()).hexdigest()!=sha:raise ValueError(('source changed',path))
    return len(files)

def stage(tick,cache):
    image=Image.new('RGB',(1440,1120),'#101525');draw=ImageDraw.Draw(image)
    for row,role in enumerate(rig.CFG):
        y=row*555
        draw.rounded_rectangle((12,y+12,1428,y+547),22,fill='#192033')
        draw.text((32,y+24),rig.CFG[role]['name']+f' · 遛宠物 · {VERSION} 待确认',font=TITLE,fill='#f4efff')
        art=cache[role][tick%96].resize((832,499),Image.Resampling.LANCZOS)
        root=tick/96*2*rig.CFG[role]['a']/rig.DUTY
        x=45+root*1.3;integer=math.floor(x);fraction=x-integer
        art=art.transform(art.size,Image.Transform.AFFINE,(1,0,-fraction,0,1,0),Image.Resampling.BILINEAR,fillcolor='#192033')
        image.paste(art,(integer,y+44))
        draw.text((1120,y+195),'60fps 连续合成',font=TEXT,fill='#c5d4ee')
        draw.text((1120,y+230),'保留 Q 版体型',font=TEXT,fill='#c5d4ee')
        draw.text((1120,y+265),'尚未接入 App',font=TEXT,fill='#c5d4ee')
    return image

def detail(tick,cache,pet=False):
    image=Image.new('RGB',(1200,620),'#192033');draw=ImageDraw.Draw(image)
    for col,role in enumerate(rig.CFG):
        x=col*600+35;art=cache[role][tick%96]
        label=('小白龙' if role=='xiaobai' else '小狗') if pet else rig.CFG[role]['name']
        draw.text((x,24),label,font=TITLE,fill='white')
        draw.text((x,66),'60fps 四肢近景 · 待确认' if pet else '60fps 腿与鞋袜近景 · 待确认',font=TEXT,fill='#c5d4ee')
        if pet:
            crop=art.crop((355,200,545,368));crop=crop.resize((494,437),Image.Resampling.LANCZOS);y=125
        else:
            top=235 if role=='xiaobai' else 265;left=180 if role=='xiaobai' else 145;right=310 if role=='xiaobai' else 280
            crop=art.crop((left,top,right,368));crop=crop.resize((round((right-left)*3.5),round((368-top)*3.5)),Image.Resampling.LANCZOS)
            y=round(530-(350-top)*3.5)
        image.paste(crop,(x,y))
    return image

def encode(name,size,maker):
    path=OUT/name
    command=[runtime.ffmpeg(),'-hide_banner','-y','-f','rawvideo','-pixel_format','rgb24','-video_size',f'{size[0]}x{size[1]}',
        '-framerate','60','-i','pipe:0','-an','-c:v',runtime.ENCODER,'-crf','18','-preset','medium','-pix_fmt','yuv420p','-movflags','+faststart',str(path)]
    with (OUT/(name+'.encode.log')).open('wb') as log:
        process=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=log,stderr=log)
        try:
            for tick in range(384):process.stdin.write(maker(tick).tobytes())
        finally:process.stdin.close()
        if process.wait():raise RuntimeError(('video encode failed',name))
    check=subprocess.run([runtime.ffmpeg(),'-hide_banner','-v','error','-nostats','-progress','pipe:1','-i',str(path),'-f','null','-'],capture_output=True,text=True,encoding='utf-8',check=True)
    values=dict(line.split('=',1) for line in check.stdout.splitlines() if '=' in line)
    assert int(values['frame'])==384 and not check.stderr.strip()
    print('Encoded and fully decoded',name,flush=True)
    return dict(path=name,frames=384,fps=60,seconds=6.4,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),fully_decoded=True)

def reference_board(cache):
    board=Image.new('RGB',(1200,1060),'#192033');draw=ImageDraw.Draw(board)
    for row,role in enumerate(rig.CFG):
        if role=='xiaobai':
            normal=Image.open(runtime.REPOSITORY/'Art/xiaobai-standing.png').convert('RGBA')
            q=Image.open(runtime.REPOSITORY/'Art/xiaobai-chibi-v2.png').convert('RGBA')
        else:
            top=Image.open(runtime.REPOSITORY/'Art/dafeiyu-standing-top.png').convert('RGBA');bottom=Image.open(runtime.REPOSITORY/'Art/dafeiyu-standing-bottom.png').convert('RGBA')
            normal=Image.new('RGBA',(max(top.width,bottom.width),top.height+bottom.height));normal.alpha_composite(top);normal.alpha_composite(bottom,(0,top.height))
            q=Image.open(runtime.REPOSITORY/'Art/dafeiyu-chibi.png').convert('RGBA')
        new=Image.open(OUT/role/'frames-60fps/000.png').convert('RGBA').crop((20,0,335,368))
        for col,(label,art) in enumerate([('正常立绘',normal),('原 Q 图',q),(VERSION+' 步态试稿',new)]):
            art=art.crop(art.getbbox())
            scale=440/art.height
            art=art.convert('RGBa').resize((round(art.width*scale),440),Image.Resampling.LANCZOS).convert('RGBA')
            x=col*400+(400-art.width)//2;y=row*530+55
            board.paste(art,(x,y),art)
            draw.text((col*400+20,row*530+16),rig.CFG[role]['name']+' / '+label,font=TEXT,fill='white')
    board.save(OUT/'reference-comparison.png')

def all_frame_boards(role,frames):
    for pet in [False,True]:
        count=48 if pet else 96
        for page in range(math.ceil(count/16)):
            board=Image.new('RGB',(1600,1440),'#192033');draw=ImageDraw.Draw(board)
            for i,tick in enumerate(range(page*16,min((page+1)*16,count))):
                image=frames[tick]
                if pet:box=(355,220,545,368)
                else:box=(180,235,310,368) if role=='xiaobai' else (145,265,280,368)
                crop=image.crop(box);crop.thumbnail((390,320),Image.Resampling.LANCZOS)
                # Scale up in this inspection board only; no asset is changed.
                factor=min(390/crop.width,320/crop.height);crop=crop.resize((round(crop.width*factor),round(crop.height*factor)),Image.Resampling.LANCZOS)
                x=(i%4)*400;y=(i//4)*360;board.paste(crop,(x+(400-crop.width)//2,y+32));draw.text((x+8,y+5),f'{tick}/96',font=TEXT,fill='white')
            board.save(OUT/f'{role}-{ "pet" if pet else "human" }-all-{page}.png')

def main():
    OUT.mkdir(exist_ok=True);environment=runtime.check();unchanged=source_hashes();cache={};stats={}
    for role in rig.CFG:
        folder=OUT/role/'frames-60fps';folder.mkdir(parents=True,exist_ok=True)
        frames=[];joints=[];contacts={};pet_contacts={};human_hashes=set();pet_hashes=set();bobs=[];pet_bobs=[];margin=1000.
        for tick in range(96):
            image,limbs,root,bob=rig.character(role,tick);image.save(folder/f'{tick:03}.png');bobs.append(bob)
            if image.mode=='RGBA':
                preview=Image.new('RGB',image.size,'#192033');preview.paste(image,(0,0),image)
            else:preview=image
            frames.append(preview)
            records=[]
            for limb,pose in limbs:
                margin=min(margin,pose['extension_margin'])
                if pose['stance']:
                    assert abs(pose['sole']-350)<1e-6
                    contacts.setdefault(pose['side'],[]).append((tick,root+float(pose['ankle'][0])))
                records.append({k:v.tolist() if isinstance(v,np.ndarray) else v for k,v in pose.items()})
            human_hashes.add(hashlib.sha256(image.crop((130,230,330,368)).tobytes()).hexdigest())
            pet_hashes.add(hashlib.sha256(image.crop((355,200,545,368)).tobytes()).hexdigest())
            pet_records=[]
            if hasattr(rig,'pet_poses'):
                pet_limbs,pet_bob=rig.pet_poses(role,tick);pet_bobs.append(pet_bob)
                for limb,pose in pet_limbs:
                    margin=min(margin,pose['extension_margin'])
                    if pose['stance']:
                        assert abs(pose['sole']-pose['ground'])<1e-6
                        pet_contacts.setdefault(pose['side'],[]).append((tick,root+float(pose['ankle'][0])))
                    pet_records.append({k:v.tolist() if isinstance(v,np.ndarray) else v for k,v in pose.items()})
            joints.append(dict(tick=tick,root_x=root,body_y=bob,limbs=records,pet_limbs=pet_records))
            if tick%24==0:print('Rendered',role,tick,'/96',flush=True)
        slide=0.
        for values in contacts.values():
            group=[];last=-10
            for tick,x in values:
                if tick!=last+1 and group:slide=max(slide,max(group)-min(group));group=[]
                group.append(x);last=tick
            if group:slide=max(slide,max(group)-min(group))
        assert slide<1e-6
        pet_slide=0.
        for values in pet_contacts.values():
            group=[];last=-10
            for tick,x in values:
                if tick!=last+1 and group:pet_slide=max(pet_slide,max(group)-min(group));group=[]
                group.append(x);last=tick
            if group:pet_slide=max(pet_slide,max(group)-min(group))
        if pet_contacts:assert pet_slide<1e-6
        stats[role]=dict(human_unique_frames=len(human_hashes),pet_unique_frames=len(pet_hashes),human_stance_ankle_slide_px=slide,
            minimum_extension_margin_px=margin,body_vertical_range_px=max(bobs)-min(bobs),pet_cycle_frames=48,
            pet_stance_ankle_slide_px=pet_slide if pet_contacts else None,pet_body_vertical_range_px=(max(pet_bobs)-min(pet_bobs)) if pet_bobs else None,
            human_source_limb_lengths_px={side:[float(limb.l1),float(limb.l2)] for side,limb in (rig.human.LIMBS if hasattr(rig,'pet_poses') else rig.LIMBS)[role].items()},
            pet_source_limb_lengths_px=({side:[float(limb.l1),float(limb.l2)] for side,limb in rig.LIMBS[role].items()} if hasattr(rig,'pet_poses') else None))
        (folder.parent/'joints.json').write_text(json.dumps(joints,indent=2),encoding='utf-8')
        cache[role]=frames;all_frame_boards(role,frames)
    reference_board(cache)
    stage(0,cache).save(OUT/'full-poster.png');detail(0,cache).save(OUT/'human-feet-poster.png');detail(0,cache,True).save(OUT/'pet-feet-poster.png')
    videos=[encode(f'pet-walk-full-{VERSION}.mp4',(1440,1120),lambda t:stage(t,cache)),
        encode(f'human-feet-{VERSION}.mp4',(1200,620),lambda t:detail(t,cache)),
        encode(f'pet-feet-{VERSION}.mp4',(1200,620),lambda t:detail(t,cache,True))]
    assert source_hashes()==unchanged
    (OUT/'verification.json').write_text(json.dumps(dict(status='draft_pending_visual_acceptance',environment=environment,
        original_pngs_verified_unchanged=unchanged,statistics=stats,videos=videos,normal_speed_playback_review=False,
        browser_review_blocked='Prior browser origin permission denied; no retry or alternate browser attempted.',
        integrated=False,ipa_generated=False,transparent_frame_output=(VERSION in ['v12','v13']),frames_are_rgb_review_only=(VERSION not in ['v12','v13'])),ensure_ascii=False,indent=2),encoding='utf-8')

if __name__=='__main__':main()
