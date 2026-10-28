"""Video and native-size contact sheets for visual review, without integration."""
import hashlib,json,math,subprocess
import numpy as np
from PIL import Image,ImageDraw,ImageFont
import animation_runtime as runtime
import painted_pet_walk as rig
OUT=rig.OUT
TITLE=ImageFont.truetype(str(runtime.FONT),26)
TEXT=ImageFont.truetype(str(runtime.FONT),17)

def resized(image,size):
    return image.convert('RGBa').resize(size,Image.Resampling.LANCZOS).convert('RGBA')

def stage(tick,cache):
    canvas=Image.new('RGB',(1120,1000),'#101525');draw=ImageDraw.Draw(canvas)
    for row,role in enumerate(rig.CFG):
        y=row*495
        draw.rounded_rectangle((12,y+12,1108,y+486),22,fill='#192033')
        draw.text((32,y+26),rig.CFG[role]['name']+' · 遛宠物 · 60fps 试稿',font=TITLE,fill='#f4eeff')
        image=cache[role][tick%rig.CYCLE]
        root=(tick/rig.CYCLE)*2*rig.CFG[role]['a']/rig.CFG[role]['duty']
        art=resized(image,(614,461))
        x=50+root*1.1
        integer=math.floor(x);fraction=x-integer
        art=art.convert('RGBa').transform(art.size,Image.Transform.AFFINE,(1,0,-fraction,0,1,0),Image.Resampling.BILINEAR).convert('RGBA')
        canvas.paste(art,(integer,y+42),art)
        draw.text((740,y+200),'完整人物与宠物',font=TEXT,fill='#ced7ef')
        draw.text((740,y+230),'补画关键姿势 + 连续过渡',font=TEXT,fill='#ced7ef')
        draw.text((740,y+260),'待确认，尚未集成',font=TEXT,fill='#ced7ef')
    return canvas

def detail(tick,cache,pet=False):
    canvas=Image.new('RGB',(1200,600),'#101525');draw=ImageDraw.Draw(canvas)
    for col,role in enumerate(rig.CFG):
        art=cache[role][tick%rig.CYCLE]
        box=(345,215,510,362) if pet else (115,235 if role=='xiaobai' else 260,285,365)
        crop=art.crop(box)
        scale=2.8
        crop=resized(crop,(round(crop.width*scale),round(crop.height*scale)))
        x=col*600+35
        draw.text((x,25),('小白龙' if role=='xiaobai' else '小狗') if pet else rig.CFG[role]['name'],font=TITLE,fill='#f4eeff')
        draw.text((x,65),'宠物四肢近景' if pet else '人物腿部与鞋袜近景',font=TEXT,fill='#ced7ef')
        canvas.paste(crop,(x,115),crop)
    return canvas

def encode(name,size,maker):
    path=OUT/name
    command=[runtime.ffmpeg(),'-hide_banner','-y','-f','rawvideo','-pixel_format','rgb24','-video_size',f'{size[0]}x{size[1]}',
        '-framerate','60','-i','pipe:0','-an','-c:v',runtime.ENCODER,'-crf','18','-preset','medium','-pix_fmt','yuv420p','-movflags','+faststart',str(path)]
    with (OUT/(name+'.encode.log')).open('wb') as log:
        process=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=log,stderr=log)
        try:
            for tick in range(rig.CYCLE*4):process.stdin.write(maker(tick).tobytes())
        finally:process.stdin.close()
        if process.wait():raise RuntimeError('encoding failed: '+name)
    check=subprocess.run([runtime.ffmpeg(),'-hide_banner','-v','error','-nostats','-progress','pipe:1','-i',str(path),'-f','null','-'],capture_output=True,text=True,encoding='utf-8',check=True)
    progress=dict(line.split('=',1) for line in check.stdout.splitlines() if '=' in line)
    assert int(progress['frame'])==384 and not check.stderr.strip()
    return dict(path=name,frames=384,fps=60,seconds=6.4,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),fully_decoded=True)

def main():
    environment=runtime.check();cache={}
    for role in rig.CFG:
        cache[role]=[Image.open(OUT/role/'frames-60fps'/f'{i:03}.png').convert('RGBA') for i in range(rig.CYCLE)]
        board=Image.new('RGB',(1600,1440),'#192033');draw=ImageDraw.Draw(board)
        for col,tick in enumerate(range(0,96,6)):
            x=(col%4)*400;y=(col//4)*360
            crop=cache[role][tick].crop((120,245,280,365));crop=resized(crop,(400,300))
            board.paste(crop,(x,y+30),crop);draw.text((x+8,y+5),f'{tick}/96',font=TEXT,fill='white')
        board.save(OUT/f'{role}-interpolated-leg-audit.png')
    stage(0,cache).save(OUT/'full-poster.png');detail(0,cache).save(OUT/'human-feet-poster.png');detail(0,cache,True).save(OUT/'pet-feet-poster.png')
    videos=[encode('pet-walk-full-v7.mp4',(1120,1000),lambda t:stage(t,cache)),
        encode('human-feet-v7.mp4',(1200,600),lambda t:detail(t,cache)),
        encode('pet-feet-v7.mp4',(1200,600),lambda t:detail(t,cache,True))]
    (OUT/'video-checks.json').write_text(json.dumps(dict(status='awaiting visual review',environment=environment,videos=videos,integrated=False),indent=2),encoding='utf-8')
    print('Videos encoded and fully decoded',flush=True)

if __name__=='__main__':main()
