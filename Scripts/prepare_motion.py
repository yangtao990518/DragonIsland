#!/usr/bin/env python3
"""Compile transparent artwork into system-timer color fonts and app previews.

No network, service, background Timer, or per-frame Activity.update.
Timer/font layering technique inspired by Bryce Bostwick's MIT WidgetAnimation;
the font compiler, artwork, schedule and integration here are project-specific.
"""
import hashlib
import math
from io import BytesIO
import json
from pathlib import Path
import random
from PIL import Image, ImageDraw
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.ttLib import newTable
from fontTools.ttLib.tables.sbixGlyph import Glyph
from fontTools.ttLib.tables.sbixStrike import Strike

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'Art/MotionV4'
OUTPUT=ROOT/'Shared/Resources/MotionFonts'
MANIFEST=json.loads((ART/'manifest.json').read_text())
FPS=30
PHASES=FPS*2
SEEDS=2
PERIOD=60
SLOT_MS=5000
WALK_END=10000
WALK_MOVE_START=200
WALK_MOVE_MS=9600
WALK_EXTENT=50  # Native 3x pixels, inside the 180px-wide visible stage.
GLYPH_PIXELS=96  # Exactly 32pt at 3x; avoid oversized bitmaps in 60 timer layers.
STAGE_WIDTH=180
ADVANCE=1875  # 60pt wide at a 32pt font size.
ROLL_END=5000
ROLL_MOVE_START=600
ROLL_MOVE_MS=3550
SCENES={'black':'mAIverse','meadow':'mAIverseMeadow','night':'mAIverseNight'}
DURATIONS={a:info['frameDurationsMs'] for a,info in MANIFEST['actions'].items()}


def scene_image(name,size=(STAGE_WIDTH,GLYPH_PIXELS)):
    """Small code-drawn scenery, kept dark enough to distinguish white artwork."""
    width,height=size
    sx,sy=width/180,height/96
    def box(values):return tuple(v*(sx if i%2==0 else sy) for i,v in enumerate(values))
    image=Image.new('RGBA',size,(0,0,0,255))
    if name=='black':return image
    draw=ImageDraw.Draw(image)
    top,bottom=((6,20,20),(24,51,30)) if name=='meadow' else ((9,12,31),(22,22,47))
    for y in range(height):
        t=y/(height-1)
        draw.line((0,y,width,y),fill=tuple(round(a+(b-a)*t) for a,b in zip(top,bottom))+(255,))
    if name=='meadow':
        draw.ellipse(box((-40,55,130,145)),fill=(20,52,29,255))
        draw.ellipse(box((75,60,235,140)),fill=(26,64,33,255))
        draw.rectangle(box((0,88,180,96)),fill=(24,60,30,255))
        for x in range(3,180,9):
            y=91+(x%3)
            draw.line([((x-2)*sx,(y-5)*sy),(x*sx,y*sy),((x+3)*sx,(y-4)*sy)],fill=(39,83,43,255),width=max(1,round(sy)))
        for x in (17,61,108,156):draw.ellipse(box((x,87,x+1,88)),fill=(97,80,39,255))
    else:
        cx,cy=149*sx,19*sy
        draw.ellipse((cx-9*sy,cy-9*sy,cx+9*sy,cy+9*sy),fill=(86,81,99,255))
        draw.ellipse((cx-3*sy,cy-12*sy,cx+13*sy,cy+5*sy),fill=(11,15,35,255))
        for x,y in ((12,15),(39,31),(65,10),(98,25),(123,8),(172,42),(86,47)):
            draw.line((x*sx-sy,y*sy,x*sx+sy,y*sy),fill=(88,86,98,255),width=max(1,round(sy)))
            draw.line((x*sx,y*sy-sy,x*sx,y*sy+sy),fill=(88,86,98,255),width=max(1,round(sy)))
        draw.ellipse(box((-30,77,120,135)),fill=(20,24,45,255))
        draw.ellipse(box((75,81,220,128)),fill=(28,28,51,255))
    return image


def walk_clip(direction, durations=None):
    durations = durations or DURATIONS
    # Six complete, unhurried two-step cycles. Travel lasts longer instead of
    # speeding up the feet to cover the wider stage. Neutral poses never slide.
    stand='roll_left' if direction=='walk_left' else 'roll_right'
    gait=[(d,direction,i) for i,d in enumerate(durations[direction])]*6
    return [(WALK_MOVE_START,stand,11)]+gait+[(200,stand,11)]


def key(action,index):
    return f'Motion_{action}_{index:03}'


def timeline(entries):
    result=[]
    for e in entries:
        result.append((e['durationMs'],e['action'],e['frame']))
    return result


def sample(entries,ms):
    for duration,action,index in entries:
        if ms < duration:return action,index
        ms-=duration
    return entries[-1][1:]


def movement_leg(action, direction, durations=None):
    durations = durations or DURATIONS
    """One grounded leg, shared by native fonts, previews and regression tests."""
    left=direction=='left'
    start=WALK_EXTENT if left else -WALK_EXTENT
    end=-start
    name=f'{action}_{direction}'
    if action=='walk':
        clip=walk_clip(name, durations)
        duration,move_start,move_ms=WALK_END,WALK_MOVE_START,WALK_MOVE_MS
    else:
        clip=[(d,name,i) for i,d in enumerate(durations[name])]
        duration,move_start,move_ms=ROLL_END,ROLL_MOVE_START,ROLL_MOVE_MS
    frames=[]
    for j in range(round(duration*FPS/1000)):
        ms=j*1000/FPS
        # Keep the last moving pose at the exact end of travel, then settle.
        pose_time=ms-0.001 if abs(ms-(move_start+move_ms))<0.000001 else ms
        a,i=sample(clip,pose_time)
        p=start+(end-start)*min(1,max(0,(ms-move_start)/move_ms))
        frames.append({'asset':key(a,i),'x':round(p),'action':action})
    return frames


def idle_frames(duration, position, durations=None):
    durations = durations or DURATIONS
    clip=[(d,'idle',i) for i,d in enumerate(durations['idle'])]
    period=sum(durations['idle'])
    return [{'asset':key(*sample(clip,j*1000/FPS%period)), 'x':position,'action':'idle'}
            for j in range(round(duration*FPS/1000))]


def plan_blocks(mask,seed):
    rng=random.Random(5707+seed)
    # Give the system time to present the island before either complete action.
    blocks=['idle','idle']
    if mask==3:
        # Both variants exercise walking AND rolling, in opposite orders.
        blocks += ['walk','roll'] if seed==0 else ['roll','walk']
    used=sum(4 if a=='walk' else 2 if a=='roll' else 1 for a in blocks)
    while used<12:
        choices=['idle']+(['walk'] if mask&1 and used<=8 else [])+(['roll'] if mask&2 and used<=10 else [])
        options=[a for a in choices if a!=blocks[-1]]
        action=rng.choice(options or choices)
        blocks.append(action)
        used+=4 if action=='walk' else 2 if action=='roll' else 1
    return blocks


def plan_legs(mask,seed):
    legs=[];start=0
    for action in plan_blocks(mask,seed):
        if action=='idle':start+=5;continue
        duration=10 if action=='walk' else 5
        for direction in ('right','left'):
            legs.append({'action':action,'direction':direction,'start':start,'duration':duration})
            start+=duration
    return legs


def schedule(mask,seed,durations=None):
    blocks=plan_blocks(mask,seed)
    position=-WALK_EXTENT if any(a!='idle' for a in blocks) else 0
    slots=[];frames=[]
    for action in blocks:
        if action=='idle':
            slots.append(action);frames+=idle_frames(SLOT_MS,position,durations)
        else:
            slots += [action]*(4 if action=='walk' else 2)
            frames+=movement_leg(action,'right',durations)+movement_leg(action,'left',durations)
    return slots,frames


def preview_frames(durations=None):
    return {'idle':idle_frames(sum((durations or DURATIONS)['idle']),0,durations),
            'walk_right':movement_leg('walk','right',durations)+movement_leg('walk','left',durations),
            'walk_left':movement_leg('walk','left',durations)+movement_leg('walk','right',durations),
            'roll':movement_leg('roll','right',durations)+movement_leg('roll','left',durations)}


def render_frame(artwork,frame,*,opaque=True,scene='black'):
    # Timer masks reveal cumulative stacks. Transparent PNGs let old silhouettes
    # show THROUGH the new pose. A fully opaque island-black tile replaces all
    # older pixels, including where a previous leg/tail used to be. This matte
    # is only for island fonts; app imagesets retain their original alpha.
    canvas=scene_image(scene) if opaque else Image.new('RGBA',(STAGE_WIDTH,GLYPH_PIXELS))
    width,height=frame.get('width',72),frame.get('height',90)
    image=artwork[frame['asset']].resize((width,height),Image.Resampling.LANCZOS)
    canvas.alpha_composite(image,((STAGE_WIDTH-width)//2+frame['x'],GLYPH_PIXELS-height-3))
    return canvas


def load_daily_art(character_id):
    """Read compact, accepted source atlases. No draft files are needed to build."""
    from PIL import ImageOps
    manifest_path=ROOT/'Art/DailyMotions/manifest.json'
    if not manifest_path.exists():return {}
    clips=json.loads(manifest_path.read_text(encoding='utf-8'))['clips']
    result={}
    for clip in clips.values():
        if clip['characterID']!=character_id:continue
        cells=[];w,h=clip['cellSize']
        for relative in clip['atlases']:
            with Image.open(manifest_path.parent/relative) as sheet:
                cells += [sheet.crop((x,0,x+w,h)).convert('RGBA') for x in range(0,sheet.width,w)]
        assert len(cells)==clip['uniqueFrames']
        images=[cells[i] for i in clip['order']]
        result[clip['action']]={'right':images,'left':[ImageOps.mirror(im) for im in images],
                                'durations':clip['durationsMs']}
    video_catalog=ROOT/'Art/VideoActions/manifest.json'
    if video_catalog.exists():
        for entry in json.loads(video_catalog.read_text(encoding='utf-8'))['clips']:
            path=video_catalog.parent/entry['manifest'];info=json.loads(path.read_text(encoding='utf-8'))
            if info['characterID']!=character_id:continue
            w,h=info['cellSize'];display=(round(w*86/h),86);images=[]
            for atlas in info['atlases']:
                with Image.open(path.parent/atlas['path']) as sheet:
                    page=len(images)//(info['grid'][0]*info['grid'][1])
                    for frame in (f for f in info['frames'] if f['atlas']==page):
                        x,y,cw,ch=frame['rect'];image=sheet.crop((x,y,x+cw,y+ch)).convert('RGBA')
                        images.append(image.convert('RGBa').resize(display,Image.Resampling.LANCZOS).convert('RGBA'))
            assert len(images)==info['frameCount']
            result[info['action']]={'right':images,'left':images,
                'durations':[f['duration_ms'] for f in info['frames']], 'display_size':display,
                'full_source_once':True,'source_id':info['id']}
    return result


def clip_size(action,clip):
    return clip.get('display_size',(112,78) if action=='pet_walk' else (86,86))


def source_once_frames(action,clip,*,fps=FPS,position=0):
    width,height=clip_size(action,clip)
    entries=[(d,action+'_right',i) for i,d in enumerate(clip['durations'])]
    result=[]
    for tick in range(math.ceil(sum(clip['durations'])*fps/1000)):
        _,index=sample(entries,tick*1000/fps+1e-7)
        result.append({'asset':key(action+'_right',index),'x':position,'action':action,
                       'width':width,'height':height,'videoAction':action,'sourceFrame':index})
    return result


def full_video_schedule(mask,seed,durations,clips):
    """A two-minute schedule reserves enough time for every COMPLETE dance.

    Source clocks never accelerate. Dance plays once then holds its last pose
    for the fractional slot remainder; neither endpoint is trimmed or blended.
    Fixed slots also share timer bitmaps across independent setting banks.
    """
    extent=min([WALK_EXTENT]+[(STAGE_WIDTH-clip_size(a,c)[0])//2-2 for a,c in clips.items()])
    position=-extent if mask&15 else 0
    d1=math.ceil(sum(clips.get('dance1',{}).get('durations',[]))/1000)
    d2=math.ceil(sum(clips.get('dance2',{}).get('durations',[]))/1000)
    assert d1<=20 and d2<=20
    parts=[('idle',5),('walk',20),('roll',10),('ride',20),('pet_walk',20),('dance1',d1),('dance2',d2),('idle',120-75-d1-d2)]
    bits={'walk':1,'roll':2,'ride':4,'pet_walk':8,'dance1':16,'dance2':32}
    if seed%2:parts[5],parts[6]=parts[6],parts[5]
    frames=[];legs=[];start=0
    for action,seconds in parts:
        if action=='idle' or not mask&bits[action] or (action not in ('walk','roll') and action not in clips):
            frames+=idle_frames(seconds*1000,position,durations)
        elif action.startswith('dance'):
            source=source_once_frames(action,clips[action],position=position)
            assert len(source)<=seconds*FPS,'Slot must contain the complete source'
            frames+=source+[dict(source[-1]) for _ in range(seconds*FPS-len(source))]
            legs.append({'action':action,'direction':'stationary','start':start,'duration':seconds,
                         'sourceDurationMs':sum(clips[action]['durations'])})
        else:
            for direction in ('right','left'):
                duration=seconds//2
                part=(daily_leg(action,direction,clips[action],duration=duration) if action in clips
                      else movement_leg(action,direction,durations))
                own_extent=max(abs(f['x']) for f in part)
                for f in part:f['x']=round(f['x']*extent/own_extent)
                frames+=part
                legs.append({'action':action,'direction':direction,'start':start+(0 if direction=='right' else duration),'duration':duration})
        start+=seconds
    assert len(frames)==120*FPS
    return [frames[i*5*FPS]['action'] for i in range(24)],frames,legs


def daily_leg(action,direction,clip,*,fps=FPS,duration=10):
    """Travel while preserving clip timing and aspect ratio; fit at both edges."""
    width,height=clip_size(action,clip)
    extent=(STAGE_WIDTH-width)//2-2
    sign=1 if direction=='right' else -1
    durations=clip['durations'];period=sum(durations)
    entries=[(d,action+'_'+direction,i) for i,d in enumerate(durations)]
    result=[]
    for tick in range(duration*fps):
        ms=tick*1000/fps
        # A repeating 1000/60 duration accumulates binary float error. Bias
        # exact boundaries by a microsecond, avoiding duplicate/skipped poses.
        _,index=sample(entries,(ms%period+0.000001)%period)
        x=round((-extent+2*extent*tick/(duration*fps-1))*sign)
        result.append({'asset':key(action+'_'+direction,index),'x':x,'action':action,
                       'width':width,'height':height})
    return result


def daily_schedule(mask,seed,durations,clips):
    if mask&48 and any(c.get('full_source_once') for c in clips.values()):
        return full_video_schedule(mask,seed,durations,clips)
    # Each checkbox owns one bit. Never substitute a disabled activity for walk.
    travelling=(['walk'] if mask&1 else [])+[a for a,b in (('ride',4),('pet_walk',8)) if mask&b and a in clips]
    if len(travelling)==3:
        # Fit EVERY enabled action into the repeating minute. Keep the source
        # pose clock unchanged; only travel duration changes for wide scenes.
        # Otherwise one selected activity could be absent for an entire session.
        extent=min((STAGE_WIDTH-(112 if a=='pet_walk' else 86))//2-2 for a in clips)
        frames=[];legs=[];start=0
        ordered=travelling[seed:]+travelling[:seed]
        for action in ordered+(['roll'] if mask&2 else []):
            duration=5 if action=='roll' else 7 if action in clips and mask&2 else 10
            for direction in ('right','left'):
                part=(daily_leg(action,direction,clips[action],duration=duration) if action in clips
                      else movement_leg(action,direction,durations))
                own_extent=max(abs(f['x']) for f in part)
                for frame in part:frame['x']=round(frame['x']*extent/own_extent)
                frames+=part
                legs.append({'action':action,'direction':direction,'start':start,'duration':duration})
                start+=duration
        if start<60:frames+=idle_frames((60-start)*1000,-extent,durations)
        return [frames[i*5*FPS]['action'] for i in range(12)],frames,legs
    blocks=['idle','idle']
    if travelling:blocks.append(travelling[seed%len(travelling)])
    if mask&2:blocks.append('roll')
    used=sum(1 if a=='idle' else 2 if a=='roll' else 4 for a in blocks)
    next_travel=seed+1
    while used<12:
        if travelling and used<=8:
            action=travelling[next_travel%len(travelling)];next_travel+=1
        elif mask&2 and used<=10 and blocks[-1]!='roll':action='roll'
        else:action='idle'
        blocks.append(action);used+=1 if action=='idle' else 2 if action=='roll' else 4
    slots=[];frames=[];legs=[];start=0
    extent=min([WALK_EXTENT]+[(STAGE_WIDTH-(112 if a=='pet_walk' else 86))//2-2 for a in clips])
    position=-extent if travelling or mask&2 else 0
    for action in blocks:
        if action=='idle':
            slots.append('idle');frames+=idle_frames(5000,position,durations);start+=5
            continue
        duration=5 if action=='roll' else 10
        slots += [action]*(duration*2//5)
        for direction in ('right','left'):
            replacement=(daily_leg(action,direction,clips[action]) if action in clips
                         else movement_leg(action,direction,durations))
            own_extent=max(abs(f['x']) for f in replacement)
            for frame in replacement:frame['x']=round(frame['x']*extent/own_extent)
            frames+=replacement
            legs.append({'action':action,'direction':direction,'start':start,'duration':duration})
            start+=duration
    return slots,frames,legs


def base_font(name,glyph_order):
    builder=FontBuilder(1000,isTTF=True)
    builder.setupGlyphOrder(glyph_order)
    builder.setupCharacterMap({ord(str(i)):f'd{i}' for i in range(10)}|{32:'space',58:'colon',160:'space'})
    builder.setupGlyf({n:TTGlyphPen(None).glyph() for n in glyph_order})
    builder.setupHorizontalMetrics({n:(ADVANCE,0) for n in glyph_order})
    builder.setupHorizontalHeader(ascent=1000,descent=0)
    builder.setupOS2(sTypoAscender=1000,sTypoDescender=0,usWinAscent=1000,usWinDescent=0)
    builder.setupNameTable({'familyName':name,'styleName':'Regular','uniqueFontIdentifier':name,
                           'fullName':name,'psName':name,'version':'Version 1.0'})
    builder.setupPost();builder.setupMaxp()
    return builder.font


def features(names):
    return 'languagesystem DFLT dflt; feature liga {'+' '.join(
        f'sub d{s//10} d{s%10} by {names[s]};' for s in range(60))+'} liga;'


def bank_glyph(bank,second,minute=0):
    if minute==0:return f'f{second:02}' if bank==0 else f'b{bank}s{second:02}'
    return f'm{minute}s{second:02}' if bank==0 else f'b{bank}m{minute}s{second:02}'


def bank_features(banks=32,minutes=1,aliases=None):
    # Encode the selected bank in synthetic elapsed HOURS (3 hours per bank).
    # Prefix matching requires H:MM:SS, so M:SS cannot be mistaken for an hour.
    rules=['languagesystem DFLT dflt;','@digits=['+' '.join(f'd{i}' for i in range(10))+'];']
    aliases=aliases or {}
    def target(b,s,m=0):
        name=bank_glyph(b,s,m)
        return aliases.get(name,name)
    for b in range(banks):rules.append(f'@bank{b}=['+' '.join(target(b,s) for s in range(60))+'];')
    if minutes==2:
        rules.append('@oddMinutes=['+' '.join([f'd{s}' for s in range(1,10,2)]+[f'f{s:02}' for s in range(1,60,2)])+'];')
        for b in range(banks):rules.append(f'@bank{b}minute1=['+' '.join(target(b,s,1) for s in range(60))+'];')
    rules.append('lookup markHours {')
    # Two-digit hour contexts must win before their one-digit suffix (13 vs 3).
    for h in reversed(range(0 if minutes==2 else 3,banks*3)):
        prefix=' '.join(f'd{x}' for x in str(h)[:-1])
        rules.append(f'sub {prefix} d{h%10}\' colon @digits @digits colon by H{h//3};')
    rules.append('} markHours; lookup pairs {')
    rules += [f'sub d{s//10} d{s%10} by f{s:02};' for s in range(60)]
    rules.append('} pairs;')
    if minutes==2:
        rules += ['lookup selectMinute {',"sub @oddMinutes colon @bank0' by @bank0minute1;",'} selectMinute;']
    rules.append('lookup selectBank useExtension {')
    rules += [f'sub H{b} colon @bank0 colon @bank0\' by @bank{b};' for b in range(1,banks)]
    if minutes==2:rules += [f'sub H{b} colon @bank0 colon @bank0minute1\' by @bank{b}minute1;' for b in range(1,banks)]
    rules.append('} selectBank; feature liga {lookup markHours; lookup pairs; '+('lookup selectMinute; ' if minutes==2 else '')+'lookup selectBank;} liga;')
    return '\n'.join(rules)


def mask_font():
    names=['.notdef','space','colon']+[f'd{i}' for i in range(10)]+['full','empty']
    font=base_font('mAIverseGate',names)
    pen=TTGlyphPen(None);pen.moveTo((0,0));pen.lineTo((ADVANCE,0));pen.lineTo((ADVANCE,1000));pen.lineTo((0,1000));pen.closePath()
    font['glyf']['full']=pen.glyph()
    addOpenTypeFeaturesFromString(font,features(['full' if s%2==0 else 'empty' for s in range(60)]))
    font.save(OUTPUT/'mAIverseGate.ttf')


def compile_character(profile):
    from prepare_assets import imageset,SHARED
    OUTPUT.mkdir(parents=True,exist_ok=True)
    art=(ROOT/profile['manifest']).parent
    manifest=json.loads((ROOT/profile['manifest']).read_text(encoding='utf-8'))
    durations={a:info['frameDurationsMs'] for a,info in manifest['actions'].items()}
    scenes={scene:profile['fontPrefix']+prefix.removeprefix('mAIverse') for scene,prefix in SCENES.items()}
    artwork={}
    for action,info in manifest['actions'].items():
        for i,path in enumerate(info['frames']):
            image=Image.open((art/path).resolve()).convert('RGBA')
            artwork[key(action,i)]=image
            imageset(SHARED,key(action,i).replace('Motion_',profile['assetPrefix']+'_',1),image,(64,80))
    daily=load_daily_art(profile['characterID'])
    for action,clip in daily.items():
        for direction in (('right',) if clip.get('full_source_once') else ('right','left')):
            for i,image in enumerate(clip[direction]):
                name=key(action+'_'+direction,i)
                artwork[name]=image
                if not clip.get('full_source_once'):
                    imageset(SHARED,name.replace('Motion_',profile['assetPrefix']+'_',1),image,clip_size(action,clip))
    # A fixed palette per scene keeps its grass/sky identical across frames;
    # per-frame adaptive palettes would make the background shimmer.
    palettes={}
    for scene in SCENES:
        imageset(SHARED,f'IslandScene_{scene}',scene_image(scene),(60,32))
        imageset(SHARED,f'IslandSceneWide_{scene}',scene_image(scene,(900,300)),(300,100))
        master=Image.new('RGB',(STAGE_WIDTH*8,GLYPH_PIXELS*((len(artwork)+7)//8)))
        for j,asset in enumerate(artwork):
            master.paste(render_frame(artwork,{'asset':asset,'x':0},scene=scene).convert('RGB'),((j%8)*STAGE_WIDTH,(j//8)*GLYPH_PIXELS))
        palettes[scene]=master.quantize(colors=256,method=Image.Quantize.MEDIANCUT)
    rendered={}
    def png(frame,scene):
        k=(scene,frame['asset'],frame['x'])
        if k not in rendered:
            canvas=render_frame(artwork,frame,scene=scene).convert('RGB').quantize(palette=palettes[scene],dither=Image.Dither.NONE)
            buf=BytesIO();canvas.save(buf,format='PNG');rendered[k]=buf.getvalue()
        return rendered[k]
    # One ordinary, WidgetKit-compatible font per phase, all banks in each file.
    # Avoid runtime CTFont bridging and unsupported named variable instances.
    plans=[]
    has_video=any(c.get('full_source_once') for c in daily.values())
    banks=128 if has_video else 32 if 'pet_walk' in daily else 16
    minutes=2 if has_video else 1;period=minutes*60
    order=['.notdef','space','colon']+[f'd{i}' for i in range(10)]+[f'H{i}' for i in range(0 if minutes==2 else 1,banks)]
    order += [bank_glyph(b,s,m) for b in range(banks) for m in range(minutes) for s in range(60)]
    for mask in range(banks//SEEDS):
        for seed in range(SEEDS):
            bank=mask*SEEDS+seed
            chosen,frames,legs=daily_schedule(mask,seed,durations,daily)
            if minutes==2 and len(frames)==60*FPS:frames=frames*2;chosen=chosen*2
            assert len(frames)==period*FPS
            plans.append({'id':bank,'mask':mask,'slots':chosen,'frames':frames,'legs':legs})
    unique=set();checks=[]
    for scene,prefix in scenes.items():
      for phase in range(PHASES):
        name=f'{prefix}F{phase}'
        phase_order=(order[:13+banks]+[bank_glyph(0,s,m) for m in range(minutes) for s in range(60)]) if has_video else list(order)
        encoded={};payloads={};aliases={}
        for plan in plans:
            bank=plan['id'];frames=plan['frames']
            for minute in range(minutes):
              for second in range(60):
                frame=frames[(((minute*60+second+1-60)%period)*FPS+phase)%len(frames)]
                glyph=bank_glyph(bank,second,minute)
                data=png(frame,scene);digest=hashlib.sha256(data).digest()
                unique.add(digest)
                if has_video and bank>0:
                    if digest not in encoded:
                        canonical=f'v{len(payloads)}';phase_order.append(canonical);encoded[digest]=canonical
                        payloads[canonical]=Glyph(glyphName=canonical,originOffsetX=0,originOffsetY=0,graphicType='png ',imageData=data)
                    aliases[glyph]=encoded[digest]
                elif digest in encoded:
                    aliases[glyph]=glyph
                    payloads[glyph]=Glyph(glyphName=glyph,graphicType='dupe',referenceGlyphName=encoded[digest])
                else:
                    aliases[glyph]=glyph;encoded[digest]=glyph
                    payloads[glyph]=Glyph(glyphName=glyph,originOffsetX=0,originOffsetY=0,graphicType='png ',imageData=data)
        font=base_font(name,phase_order)
        strike=Strike(ppem=GLYPH_PIXELS,resolution=72)
        for n in phase_order:strike.glyphs[n]=payloads.get(n,Glyph(glyphName=n))
        sbix=newTable('sbix');sbix.strikes={GLYPH_PIXELS:strike};font['sbix']=sbix
        addOpenTypeFeaturesFromString(font,bank_features(banks,minutes,aliases))
        font.save(OUTPUT/f'{name}.ttf')
        if phase in (0,1,15,29,30,58,59):
            checks += [{'fontPrefix':prefix,'scene':scene,'bank':b,'phase':phase,'minute':m,'second':s,
                        'glyph':font.getGlyphID(aliases[bank_glyph(b,s,m%minutes)])}
                       for b in range(banks) for m in ((0,1,2,59) if has_video else (1,)) for s in (15,55)]

    previews=preview_frames(durations)
    app_previews={}
    for action,clip in daily.items():
        if clip.get('full_source_once'):
            previews[action]=source_once_frames(action,clip)
            app_previews[action]=source_once_frames(action,clip,fps=60)
        else:
            previews[action]=daily_leg(action,'right',clip)+daily_leg(action,'left',clip)
            app_previews[action]=daily_leg(action,'right',clip,fps=60)+daily_leg(action,'left',clip,fps=60)
    auto_extent=min([WALK_EXTENT]+[(STAGE_WIDTH-(112 if a=='pet_walk' else 86))//2-2 for a in daily])
    data={'fps':FPS,'previewFPS':60,'period':period,'plans':plans,'previews':previews,'appPreviews':app_previews,'durations':durations,'scenes':list(SCENES),'stagePixels':[STAGE_WIDTH,GLYPH_PIXELS],'travelPixels':WALK_EXTENT*2,'automaticTravelPixels':auto_extent*2}
    # Runtime timelines and asset names are isolated per character. Movement
    # geometry/timer banks stay identical; expressions may have their own holds.
    for frames in [p['frames'] for p in data['plans']]+list(data['previews'].values())+list(app_previews.values()):
        for frame in frames:
            frame['asset']=frame['asset'].replace('Motion_',profile['assetPrefix']+'_',1)
    if has_video:
        # A shared frame table avoids decoding hundreds of thousands of copies
        # in the App. Widget playback still consists solely of native fonts.
        table=[];indices={}
        for plan in plans:
            sequence=[]
            for frame in plan['frames']:
                identity=tuple(sorted(frame.items()))
                if identity not in indices:indices[identity]=len(table);table.append(frame)
                sequence.append(indices[identity])
            plan['frameIndices']=sequence;plan['frames']=[]
        data['frameTable']=table
    (ROOT/'Shared/Resources'/f"{profile['timelineResource']}.json").write_text(json.dumps(data,separators=(',',':'))+'\n',encoding='utf-8')
    print(f"{profile['fontPrefix']}: {len(artwork)} poses, {len(plans)} plans")
    return checks,len(unique)


def main():
    characters=json.loads((ROOT/'Shared/Resources/Characters.json').read_text(encoding='utf-8'))
    profiles=[]
    for character in characters:
        profile=character.get('motion')
        if profile is None and character['id']=='xiaobai':
            profile={'manifest':'Art/MotionV4/manifest.json','fontPrefix':'mAIverse','assetPrefix':'Motion','timelineResource':'MotionTimeline'}
        if profile:profiles.append(dict(profile,characterID=character['id']))
    for field in ('fontPrefix','assetPrefix','timelineResource'):
        if len({p[field] for p in profiles})!=len(profiles):raise ValueError('Duplicate motion namespace')
    OUTPUT.mkdir(parents=True,exist_ok=True)
    for old in OUTPUT.glob('*.ttf'):
        assert old.resolve().parent==OUTPUT.resolve()
        old.unlink()
    mask_font()
    checks=[];unique=0
    for profile in profiles:
        result,count=compile_character(profile);checks+=result;unique+=count
    (OUTPUT/'checks.json').write_text(json.dumps(checks),encoding='utf-8')
    paths=[p.name for p in sorted(OUTPUT.glob('*.ttf'))]
    (OUTPUT/'font-summary.json').write_text(json.dumps({'fontFiles':len(paths),'fontBytesPerBundle':sum((OUTPUT/p).stat().st_size for p in paths),'uniqueBitmaps':unique,'targetFPS':FPS,'phases':PHASES,'maxPlans':128,'characters':len(profiles)}),encoding='utf-8')
    (ROOT/'motion-fonts.yml').write_text('targets:\n  DragonIsland:\n    info:\n      properties:\n        UIAppFonts: &motionFonts\n'+''.join(f'          - {n}\n' for n in paths)+'  DragonIslandWidget:\n    info:\n      properties:\n        UIAppFonts: *motionFonts\n',encoding='utf-8')
    print(f'Motion resources: {len(profiles)} characters, {len(paths)} fonts; native timer rendering.')


if __name__=='__main__':main()
