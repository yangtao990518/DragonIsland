#!/usr/bin/env python3
"""Compile transparent artwork into system-timer color fonts and app previews.

No network, service, background Timer, or per-frame Activity.update.
Timer/font layering technique inspired by Bryce Bostwick's MIT WidgetAnimation;
the font compiler, artwork, schedule and integration here are project-specific.
"""
import hashlib
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


def walk_clip(direction):
    # Six complete, unhurried two-step cycles. Travel lasts longer instead of
    # speeding up the feet to cover the wider stage. Neutral poses never slide.
    stand='roll_left' if direction=='walk_left' else 'roll_right'
    gait=[(d,direction,i) for i,d in enumerate(DURATIONS[direction])]*6
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


def movement_leg(action, direction):
    """One grounded leg, shared by native fonts, previews and regression tests."""
    left=direction=='left'
    start=WALK_EXTENT if left else -WALK_EXTENT
    end=-start
    name=f'{action}_{direction}'
    if action=='walk':
        clip=walk_clip(name)
        duration,move_start,move_ms=WALK_END,WALK_MOVE_START,WALK_MOVE_MS
    else:
        clip=[(d,name,i) for i,d in enumerate(DURATIONS[name])]
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


def idle_frames(duration, position):
    clip=[(d,'idle',i) for i,d in enumerate(DURATIONS['idle'])]
    period=sum(DURATIONS['idle'])
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


def schedule(mask,seed):
    blocks=plan_blocks(mask,seed)
    position=-WALK_EXTENT if any(a!='idle' for a in blocks) else 0
    slots=[];frames=[]
    for action in blocks:
        if action=='idle':
            slots.append(action);frames+=idle_frames(SLOT_MS,position)
        else:
            slots += [action]*(4 if action=='walk' else 2)
            frames+=movement_leg(action,'right')+movement_leg(action,'left')
    return slots,frames


def preview_frames():
    return {'idle':idle_frames(2000,0),
            'walk_right':movement_leg('walk','right')+movement_leg('walk','left'),
            'walk_left':movement_leg('walk','left')+movement_leg('walk','right'),
            'roll':movement_leg('roll','right')+movement_leg('roll','left')}


def render_frame(artwork,frame,*,opaque=True,scene='black'):
    # Timer masks reveal cumulative stacks. Transparent PNGs let old silhouettes
    # show THROUGH the new pose. A fully opaque island-black tile replaces all
    # older pixels, including where a previous leg/tail used to be. This matte
    # is only for island fonts; app imagesets retain their original alpha.
    canvas=scene_image(scene) if opaque else Image.new('RGBA',(STAGE_WIDTH,GLYPH_PIXELS))
    image=artwork[frame['asset']].resize((72,90),Image.Resampling.LANCZOS)
    canvas.alpha_composite(image,((STAGE_WIDTH-72)//2+frame['x'],3))
    return canvas


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


def bank_features():
    # Encode the selected bank in synthetic elapsed HOURS (3 hours per bank).
    # Prefix matching requires H:MM:SS, so M:SS cannot be mistaken for an hour.
    rules=['languagesystem DFLT dflt;','@digits=['+' '.join(f'd{i}' for i in range(10))+'];']
    for b in range(8):rules.append(f'@bank{b}=['+' '.join(f'f{s:02}' if b==0 else f'b{b}s{s:02}' for s in range(60))+'];')
    rules.append('lookup markHours {')
    # Two-digit hour contexts must win before their one-digit suffix (13 vs 3).
    for h in reversed(range(3,24)):
        prefix=' '.join(f'd{x}' for x in str(h)[:-1])
        rules.append(f'sub {prefix} d{h%10}\' colon @digits @digits colon by H{h//3};')
    rules.append('} markHours; lookup pairs {')
    rules += [f'sub d{s//10} d{s%10} by f{s:02};' for s in range(60)]
    rules.append('} pairs; lookup selectBank {')
    rules += [f'sub H{b} colon @bank0 colon @bank0\' by @bank{b};' for b in range(1,8)]
    rules.append('} selectBank; feature liga {lookup markHours; lookup pairs; lookup selectBank;} liga;')
    return '\n'.join(rules)


def mask_font():
    names=['.notdef','space','colon']+[f'd{i}' for i in range(10)]+['full','empty']
    font=base_font('mAIverseGate',names)
    pen=TTGlyphPen(None);pen.moveTo((0,0));pen.lineTo((ADVANCE,0));pen.lineTo((ADVANCE,1000));pen.lineTo((0,1000));pen.closePath()
    font['glyf']['full']=pen.glyph()
    addOpenTypeFeaturesFromString(font,features(['full' if s%2==0 else 'empty' for s in range(60)]))
    font.save(OUTPUT/'mAIverseGate.ttf')


def main():
    from prepare_assets import imageset,SHARED
    OUTPUT.mkdir(parents=True,exist_ok=True)
    artwork={}
    for action,info in MANIFEST['actions'].items():
        for i,path in enumerate(info['frames']):
            image=Image.open((ART/path).resolve()).convert('RGBA')
            artwork[key(action,i)]=image
            imageset(SHARED,key(action,i),image,(64,80))
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
    for old in OUTPUT.glob('*.ttf'):
        assert old.resolve().parent==OUTPUT.resolve()
        old.unlink()
    mask_font()
    plans=[]
    order=['.notdef','space','colon']+[f'd{i}' for i in range(10)]+[f'H{i}' for i in range(1,8)]
    def glyph_name(bank,second):return f'f{second:02}' if bank==0 else f'b{bank}s{second:02}'
    order += [glyph_name(b,s) for b in range(8) for s in range(60)]
    for mask in range(4):
        for seed in range(SEEDS):
            bank=mask*SEEDS+seed
            chosen,frames=schedule(mask,seed)
            plans.append({'id':bank,'mask':mask,'slots':chosen,'frames':frames,'legs':plan_legs(mask,seed)})
    unique=set()
    for scene,prefix in SCENES.items():
      for phase in range(PHASES):
        name=f'{prefix}F{phase}'
        font=base_font(name,order)
        strike=Strike(ppem=GLYPH_PIXELS,resolution=72)
        for n in order:strike.glyphs[n]=Glyph(glyphName=n)
        encoded={}
        for plan in plans:
            bank=plan['id'];frames=plan['frames']
            for second in range(60):
                frame=frames[(((second+1)%60)*FPS+phase)%len(frames)]
                glyph=glyph_name(bank,second)
                data=png(frame,scene);digest=hashlib.sha256(data).digest()
                unique.add(digest)
                if digest in encoded:
                    strike.glyphs[glyph]=Glyph(glyphName=glyph,graphicType='dupe',referenceGlyphName=encoded[digest])
                else:
                    encoded[digest]=glyph
                    strike.glyphs[glyph]=Glyph(glyphName=glyph,originOffsetX=0,originOffsetY=0,graphicType='png ',imageData=data)
        sbix=newTable('sbix');sbix.strikes={GLYPH_PIXELS:strike};font['sbix']=sbix
        addOpenTypeFeaturesFromString(font,bank_features())
        font.save(OUTPUT/f'{name}.ttf')
    checks=[{'scene':scene,'bank':b,'phase':p,'second':s,'glyph':font.getGlyphID(glyph_name(b,s))}
            for scene in SCENES for b in range(8) for p in (0,1,15,29,30,58,59) for s in (15,55)]
    (OUTPUT/'checks.json').write_text(json.dumps(checks),encoding='utf-8')
    (ROOT/'Shared/Resources/MotionTimeline.json').write_text(json.dumps({'fps':FPS,'period':PERIOD,'plans':plans,'previews':preview_frames(),'durations':DURATIONS,'scenes':list(SCENES),'stagePixels':[STAGE_WIDTH,GLYPH_PIXELS],'travelPixels':WALK_EXTENT*2},separators=(',',':'))+'\n',encoding='utf-8')
    # XcodeGen includes this generated settings fragment in both Info.plists.
    paths=[p.name for p in sorted(OUTPUT.glob('*.ttf'))]
    (OUTPUT/'font-summary.json').write_text(json.dumps({'fontFiles':len(paths),'fontBytesPerBundle':sum((OUTPUT/p).stat().st_size for p in paths),'uniqueBitmaps':len(unique),'targetFPS':FPS,'phases':PHASES,'plans':len(plans)}),encoding='utf-8')
    (ROOT/'motion-fonts.yml').write_text('targets:\n  DragonIsland:\n    info:\n      properties:\n        UIAppFonts: &motionFonts\n'+''.join(f'          - {n}\n' for n in paths)+'  DragonIslandWidget:\n    info:\n      properties:\n        UIAppFonts: *motionFonts\n',encoding='utf-8')
    print(f'Motion resources: {len(artwork)} PNG poses, {len(plans)} plans, {len(paths)} fonts; native timer rendering.')


if __name__=='__main__':main()

