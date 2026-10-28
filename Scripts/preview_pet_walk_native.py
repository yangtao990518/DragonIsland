"""Render and inspect the v5 human + quadruped preview. No App integration."""
import hashlib,json,math,subprocess
import numpy as np
from PIL import Image,ImageDraw,ImageFont
import animation_runtime as runtime
import pet_walk_native as rig

OUT=rig.OUT
TITLE=ImageFont.truetype(str(runtime.FONT),27)
TEXT=ImageFont.truetype(str(runtime.FONT),17)
SMALL=ImageFont.truetype(str(runtime.FONT),14)

def resize(image,size):
    return image.convert('RGBa').resize(size,Image.Resampling.LANCZOS).convert('RGBA')

def paste_fractional(canvas,art,x,y):
    integer=math.floor(x);fraction=x-integer
    art=art.convert('RGBa').transform(art.size,Image.Transform.AFFINE,(1,0,-fraction,0,1,0),Image.Resampling.BILINEAR).convert('RGBA')
    canvas.paste(art,(integer,y),art)

def stage(tick,actors):
    canvas=Image.new('RGB',(1080,980),'#0f1320');draw=ImageDraw.Draw(canvas)
    for row,role in enumerate(rig.CFG):
        offset=row*480
        draw.rounded_rectangle((16,16+offset,1064,474+offset),24,fill='#181d2f')
        draw.text((36,30+offset),rig.CFG[role]['name']+(' · 遛小龙' if role=='xiaobai' else ' · 遛小狗'),font=TITLE,fill='#efedff')
        draw.text((36,74+offset),'人物与宠物连续动作 · v5 待确认',font=TEXT,fill='#bbc8dd')
        floor=round(82+590*397/640)+offset;draw.line((35,floor,1035,floor),fill='#58657e')
        root=tick/rig.CYCLE*2*rig.CFG[role]['a']/rig.DUTY
        paste_fractional(canvas,actors[role][tick%rig.CYCLE],45+root*556/896,82+offset)
        draw.text((36,451+offset),'60fps 合成预览 · 长绳与原角色身份保留',font=SMALL,fill='#bbc8dd')
    return canvas

def closeup(tick,cache,pet=False):
    height=650 if pet else 560
    canvas=Image.new('RGB',(1200,height),'#0f1320');draw=ImageDraw.Draw(canvas)
    for col,role in enumerate(rig.CFG):
        x=col*600
        draw.text((x+25,18),('小白龙' if role=='xiaobai' else '小狗') if pet else rig.CFG[role]['name'],font=TITLE,fill='#efedff')
        draw.text((x+25,53),'四肢与落脚近景 · 连续 60fps' if pet else '腿与鞋袜近景 · 原图比例对照',font=TEXT,fill='#bbc8dd')
        art=cache[role][tick%rig.CYCLE]
        if pet:y=105
        else:
            top=440 if role=='xiaobai' else 495;y=round(478-(590-top)*2.5)
            draw.line((x+25,478,x+575,478),fill='#647088')
        canvas.paste(art,(x+35,y),art)
        draw.text((x+25,height-32),'现有原画贴图连续变形 · 尚未集成',font=SMALL,fill='#bbc8dd')
    return canvas

def encode(filename,size,maker):
    destination=OUT/filename
    command=[runtime.ffmpeg(),'-hide_banner','-y','-f','rawvideo','-pixel_format','rgb24','-video_size',f'{size[0]}x{size[1]}',
        '-framerate','60','-i','pipe:0','-an','-c:v',runtime.ENCODER,'-crf','18','-preset','medium','-pix_fmt','yuv420p','-movflags','+faststart',str(destination)]
    with (OUT/(filename+'.encode.log')).open('wb') as log:
        process=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=log,stderr=log)
        try:
            for tick in range(rig.CYCLE*4):process.stdin.write(maker(tick).tobytes())
            process.stdin.close()
        finally:
            if process.stdin and not process.stdin.closed:process.stdin.close()
            code=process.wait()
        assert code==0,filename
    result=subprocess.run([runtime.ffmpeg(),'-hide_banner','-v','error','-nostats','-progress','pipe:1','-i',str(destination),'-f','null','-'],capture_output=True,text=True,encoding='utf-8',check=True)
    values=dict(line.split('=',1) for line in result.stdout.splitlines() if '=' in line)
    assert int(values['frame'])==384 and values['progress']=='end',values
    assert not result.stderr.strip(),result.stderr
    print('Encoded and decoded',filename,flush=True)
    return dict(path=filename,frames=384,fps=60,seconds=6.4,sha256=hashlib.sha256(destination.read_bytes()).hexdigest(),decode_passed=True)

def reference_board():
    board=Image.new('RGB',(1500,1100),'#181d2f');draw=ImageDraw.Draw(board)
    for row,role in enumerate(rig.CFG):
        if role=='xiaobai':
            normal=Image.open(runtime.REPOSITORY/'Art/xiaobai-standing.png').convert('RGBA')
            q=Image.open(runtime.REPOSITORY/'Art/xiaobai-chibi-v2.png').convert('RGBA')
        else:
            top=Image.open(runtime.REPOSITORY/'Art/dafeiyu-standing-top.png').convert('RGBA');bottom=Image.open(runtime.REPOSITORY/'Art/dafeiyu-standing-bottom.png').convert('RGBA')
            normal=Image.new('RGBA',(max(top.width,bottom.width),top.height+bottom.height));normal.alpha_composite(top);normal.alpha_composite(bottom,(0,top.height))
            q=Image.open(runtime.REPOSITORY/'Art/dafeiyu-chibi.png').convert('RGBA')
        new=Image.open(OUT/role/'frames-60fps/012.png').convert('RGBA').crop((45,120,445,610))
        for col,(label,image) in enumerate([('正常立绘：身份与服饰',normal),('原 Q 版：人物比例',q),('v5：动作人物',new)]):
            image=image.crop(image.getbbox());image.thumbnail((460,470))
            x=col*500+(500-image.width)//2;y=row*550+60
            board.paste(image,(x,y),image);draw.text((col*500+25,row*550+18),rig.CFG[role]['name']+' / '+label,font=TEXT,fill='white')
    board.save(OUT/'reference-comparison.png')

def main():
    OUT.mkdir(exist_ok=True);environment=runtime.check()
    manifest=json.loads((runtime.REPOSITORY/'AnimationDrafts/2026-10-27/manifest.json').read_text(encoding='utf-8'))
    source_pngs={f['path']:f['sha256'] for f in manifest['files'] if f['path'].endswith('.png')}
    for path,sha in source_pngs.items():assert hashlib.sha256((runtime.REPOSITORY/path).read_bytes()).hexdigest()==sha,path
    actors={};feet={};pets={};statistics={}
    for role in rig.CFG:
        actors[role]=[];feet[role]=[];pets[role]=[];joints=[];contacts={};human_hashes=set();pet_hashes=set();previous_pet=None;held=0
        folder=OUT/role/'frames-60fps';folder.mkdir(parents=True,exist_ok=True)
        min_margin=1000.
        for tick in range(rig.CYCLE):
            image,human,pet,root=rig.character(role,tick);image.save(folder/f'{tick:03d}.png')
            actors[role].append(resize(image,(556,397)))
            top=440 if role=='xiaobai' else 495
            human_crop=image.crop((220,top,425,610));feet[role].append(resize(human_crop,(513,round((610-top)*2.5))))
            pet_crop=image.crop((550,395,800,610));pets[role].append(resize(pet_crop,(550,473)))
            human_hashes.add(hashlib.sha256(human_crop.tobytes()).hexdigest())
            digest=hashlib.sha256(pet_crop.tobytes()).hexdigest();pet_hashes.add(digest);held+=int(digest==previous_pet);previous_pet=digest
            records=[]
            for kind,limbs in [('human',human),('pet',pet)]:
                for limb,pose in limbs:
                    min_margin=min(min_margin,pose['extension_margin'])
                    if pose['stance']:
                        assert abs(pose['sole']-pose['ground'])<1e-6
                        key=(kind,pose['side'])
                        contacts.setdefault(key,[]).append((tick,root+float(pose['ankle'][0])))
                    records.append(dict(kind=kind,name=limb.name,**{key:(value.tolist() if isinstance(value,np.ndarray) else value) for key,value in pose.items()}))
            joints.append(dict(tick=tick,seconds=tick/60,root_x=root,limbs=records))
            if tick%24==0:print('Rendered',role,tick,'/',rig.CYCLE,flush=True)
        max_slide=0.
        for values in contacts.values():
            group=[];last=-10
            for tick,x in values:
                if tick!=last+1 and group:max_slide=max(max_slide,max(group)-min(group));group=[]
                group.append(x);last=tick
            if group:max_slide=max(max_slide,max(group)-min(group))
        assert held==0,(role,'held pet frames',held)
        assert max_slide<1e-6,(role,max_slide)
        statistics[role]=dict(human_unique_images=len(human_hashes),pet_unique_images_in_96_samples=len(pet_hashes),
            consecutive_held_pet_frames=held,max_stance_world_slide_px=max_slide,minimum_extension_margin_px=min_margin,
            human_bare_leg_opaque_widths_px=[36,24] if role=='xiaobai' else [29,25],
            human_original_shoe_sizes={side:list(limb.shoe.size) for side,limb in rig.HUMAN[role].items()},
            pet_cycle_frames=48,pet_cycle_seconds=.8)
        (folder.parent/'joints.json').write_text(json.dumps(joints,indent=2),encoding='utf-8')
    reference_board()
    stage(12,actors).save(OUT/'full-poster.png');closeup(12,feet).save(OUT/'human-feet-poster.png');closeup(12,pets,True).save(OUT/'pet-feet-poster.png')
    videos=[encode('pet-walk-full-v5.mp4',(1080,980),lambda t:stage(t,actors)),
            encode('human-feet-v5.mp4',(1200,560),lambda t:closeup(t,feet)),
            encode('pet-feet-v5.mp4',(1200,650),lambda t:closeup(t,pets,True))]
    for path,sha in source_pngs.items():assert hashlib.sha256((runtime.REPOSITORY/path).read_bytes()).hexdigest()==sha,path
    report=dict(status='pending visual playback review',environment=environment,source_pngs_unchanged=len(source_pngs),
        statistics=statistics,videos=videos,ios_integrated=False,ipa_generated=False,
        limitation='Continuous animation of existing artwork, not 60 independent painted originals per second.')
    (OUT/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('All v5 previews exported:',OUT,flush=True)

if __name__=='__main__':main()
