"""Export the unapproved fourth walking revision, outside all iOS resource paths."""
import argparse
import hashlib
import json
import math
import subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import animation_runtime as runtime
import pet_walk_rig as rig

OUT = rig.BASE / 'walk-rig-v4-review'
TITLE = ImageFont.truetype(str(runtime.FONT), 28)
TEXT = ImageFont.truetype(str(runtime.FONT), 17)
SMALL = ImageFont.truetype(str(runtime.FONT), 14)

def preserved_hashes():
    paths = list((runtime.REPOSITORY / 'output/ride-batch1/revision3').rglob('*.png'))
    paths += list((runtime.REPOSITORY / 'output/ride-batch1/revision2/xiaobai-sword').glob('*.png'))
    for role in rig.CFG:
        paths += list((rig.BASE / (role+'-wait') / 'blink').glob('*.png'))
    return {p.relative_to(runtime.REPOSITORY).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}

def pm_resize(image, size):
    return image.convert('RGBa').resize(size, Image.Resampling.LANCZOS).convert('RGBA')

def motion_checks():
    report = {}
    for role, c in rig.CFG.items():
        contacts = {}
        knees = []
        flex = []
        reach_margin = []
        for tick in range(rig.CYCLE):
            poses, root, body_y = rig.gait(role, tick)
            knees.append([p['knee'] for p in poses])
            for p in poses:
                flex.append(p['knee_flex_degrees'])
                reach_margin.append(c['l1']+c['l2']-float(np.linalg.norm(p['ankle']-p['hip'])))
                if p['stance']:
                    assert abs(p['sole_lowest']-rig.GROUND) < 1e-6
                    group = (p['side'], math.floor(tick/rig.CYCLE + (.5 if p['side']=='far' else 0)))
                    contacts.setdefault(group, []).append(root+p['ankle'][0])
        knee = np.asarray(knees)
        acceleration = np.roll(knee,1,axis=0)-2*knee+np.roll(knee,-1,axis=0)
        first = rig.gait(role, 0)
        last = rig.gait(role, rig.CYCLE)
        assert all(np.allclose(a['knee'],b['knee']) for a,b in zip(first[0],last[0]))
        report[role] = dict(stride_pixels=2*c['a']/rig.DUTY, ankle_excursion_pixels=2*c['a'],
            old_ankle_excursion_pixels=44 if role=='xiaobai' else 30,
            max_stance_ankle_slide_pixels=max(max(v)-min(v) for v in contacts.values()),
            minimum_IK_extension_margin_pixels=min(reach_margin), knee_flex_degrees=[min(flex),max(flex)],
            max_knee_second_difference_pixels=float(np.linalg.norm(acceleration,axis=2).max()),
            body_vertical_range_pixels=2*c['bob'], loop_pose_equal=True)
    return report

def contact_sheet():
    sheet = Image.new('RGB', (1600, 500), '#181d2f')
    draw = ImageDraw.Draw(sheet)
    for row, role in enumerate(rig.CFG):
        for col, tick in enumerate([0,12,24,36,48,60,72,84]):
            image, _, _ = rig.character(role,tick)
            top = 430 if role=='xiaobai' else 480
            crop = image.crop((220,top,430,610))
            crop = pm_resize(crop,(190,round(crop.height*190/crop.width)))
            x = col*200+5
            y = row*250
            draw.text((x,y+15),rig.CFG[role]['name']+' '+str(tick),font=TEXT,fill='white')
            sheet.paste(crop,(x,y+55),crop)
    sheet.save(OUT/'contacts.png')

def fractional_paste(target, art, x, y):
    integer = math.floor(x)
    fraction = x-integer
    art = art.convert('RGBa').transform(art.size,Image.Transform.AFFINE,
        (1,0,-fraction,0,1,0),Image.Resampling.BILINEAR).convert('RGBA')
    target.paste(art,(integer,y),art)

def stage_frame(tick, cache):
    image = Image.new('RGB',(1080,980),'#0f1320')
    draw = ImageDraw.Draw(image)
    for row, role in enumerate(rig.CFG):
        offset = row*480
        draw.rounded_rectangle((16,16+offset,1064,474+offset),24,fill='#181d2f')
        draw.text((36,30+offset),rig.CFG[role]['name']+(' · 遛小龙' if role=='xiaobai' else ' · 遛小狗'),font=TITLE,fill='#efedff')
        draw.text((36,74+offset),'步态修订 v4 · 待确认',font=TEXT,fill='#bbc8dd')
        floor = round(82+rig.GROUND*397/640)+offset
        draw.line((35,floor,1035,floor),fill='#58657e')
        distance = tick/rig.CYCLE * 2*rig.CFG[role]['a']/rig.DUTY
        art = cache[role][tick%rig.CYCLE]
        x = 38+distance*556/896
        assert x+art.getbbox()[2]<1064
        fractional_paste(image,art,x,82+offset)
        draw.text((36,451+offset),'舒展迈步 · 低抬脚 · 轻微重心起伏',font=SMALL,fill='#bbc8dd')
    return image

def feet_frame(tick, cache):
    image=Image.new('RGB',(1200,560),'#0f1320')
    draw=ImageDraw.Draw(image)
    for col,role in enumerate(rig.CFG):
        x=col*600
        draw.text((x+25,22),rig.CFG[role]['name'],font=TITLE,fill='#efedff')
        draw.text((x+25,54),'脚部近景 · v4 待确认',font=TEXT,fill='#bbc8dd')
        top=430 if role=='xiaobai' else 480
        art=cache[role][tick%rig.CYCLE]
        y=round(478-(rig.GROUND-top)*2.5)
        draw.line((x+25,478,x+575,478),fill='#647088')
        image.paste(art,(x+45,y),art)
        draw.text((x+25,520),'60fps 合成预览 · 不代表 60 张独立原画',font=SMALL,fill='#bbc8dd')
    return image

def encode(filename,size,maker,frames):
    destination=OUT/filename
    command=[runtime.ffmpeg(),'-hide_banner','-y','-f','rawvideo','-pixel_format','rgb24',
        '-video_size',f'{size[0]}x{size[1]}','-framerate',str(rig.FPS),'-i','pipe:0','-an',
        '-c:v',runtime.ENCODER,'-crf','18','-preset','medium','-pix_fmt','yuv420p','-movflags','+faststart',str(destination)]
    with (OUT/(filename+'.encode.log')).open('wb') as log:
        process=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=log,stderr=log)
        try:
            for tick in range(frames):
                process.stdin.write(maker(tick).tobytes())
            process.stdin.close()
        finally:
            if process.poll() is None and process.stdin and not process.stdin.closed:
                process.stdin.close()
            code=process.wait()
        assert code==0, 'Inspect '+str(log.name)
    with (OUT/(filename+'.decode.log')).open('wb') as log:
        subprocess.run([runtime.ffmpeg(),'-hide_banner','-v','error','-i',str(destination),'-f','null','-'],
            stdout=log,stderr=log,check=True)
    return dict(path=str(destination),frames=frames,fps=rig.FPS,seconds=frames/rig.FPS,
                sha256=hashlib.sha256(destination.read_bytes()).hexdigest(),full_decode_passed=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--contacts-only',action='store_true')
    args=parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    environment=runtime.check()
    preserved=preserved_hashes()
    report=dict(status='unapproved review draft',base_commit='bafc996fb3a70cace014d182163af863e90c1713',
                environment=environment,motion=motion_checks(),garment_removed_pixels=rig.GARMENT_REMOVED_PIXELS,
                ios_integrated=False,ipa_generated=False,source_png_sha256=preserved)
    contact_sheet()
    if args.contacts_only:
        print(OUT/'contacts.png')
        return
    actors={}
    feet={}
    for role in rig.CFG:
        actors[role]=[]
        feet[role]=[]
        joints=[]
        frames=OUT/role/'frames-60fps'
        frames.mkdir(parents=True,exist_ok=True)
        for tick in range(rig.CYCLE):
            high,poses,root,body_y=rig.leg_layer(role,tick,high_resolution=True)
            image,_,_=rig.character(role,tick,high)
            image.save(frames/f'{tick:03d}.png')
            actors[role].append(pm_resize(image,(556,397)))
            # Sample the high resolution leg mesh directly for the near camera.
            top=430 if role=='xiaobai' else 480
            box=(220,top,430,610)
            size=(525,round((610-top)*2.5))
            crop=Image.new('RGBA',size)
            origin=(rig.REGION[0],rig.REGION[1])
            roi=tuple((v-origin[i%2])*rig.SS for i,v in enumerate(box))
            crop.alpha_composite(pm_resize(high.crop(roi),size))
            front=rig.shift_body(rig.TORSO[role]['front'],body_y).crop(box)
            crop.alpha_composite(pm_resize(front,size))
            feet[role].append(crop)
            joints.append(dict(tick=tick,body_y=body_y,root_x=root,legs=[{k:(v.tolist() if isinstance(v,np.ndarray) else v) for k,v in p.items()} for p in poses]))
            if tick%24==0:
                print('Rendered',role,tick,'/',rig.CYCLE,flush=True)
        (frames.parent/'joints.json').write_text(json.dumps(joints,indent=2),encoding='utf-8')
    stage_frame(12,actors).save(OUT/'full-poster.png')
    feet_frame(12,feet).save(OUT/'feet-poster.png')
    total=rig.CYCLE*4
    report['videos']=[encode('pet-walk-full-v4.mp4',(1080,980),lambda tick:stage_frame(tick,actors),total),
                      encode('pet-walk-feet-v4.mp4',(1200,560),lambda tick:feet_frame(tick,feet),total)]
    assert preserved_hashes()==preserved,'Previously confirmed PNGs changed'
    report['confirmed_pngs_unchanged']=True
    report['review_note']='Motion constraints and successful decoding do not establish visual acceptance. Review normal-speed loops and phase contacts.'
    (OUT/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Preview export and decode complete:',OUT,flush=True)

if __name__=='__main__':
    main()
