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
from PIL import Image
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.ttLib import newTable
from fontTools.ttLib.tables.sbixGlyph import Glyph
from fontTools.ttLib.tables.sbixStrike import Strike
from fontTools.varLib.featureVars import addFeatureVariations

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'Art/MotionV3'
OUTPUT=ROOT/'Shared/Resources/MotionFonts'
MANIFEST=json.loads((ART/'manifest.json').read_text())
FPS=30
PHASES=FPS*2
SEEDS=2
PERIOD=60
WALK_END=1566
WALK_MOVE_START=250
WALK_MOVE_MS=1066
WALK_EXTENT=16
GLYPH_PIXELS=96  # Exactly 32pt at 3x; avoid oversized bitmaps in 60 timer layers.
ROLL_END=1066


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


def schedule(mask,seed):
    rng=random.Random(5707+seed)
    pool=['idle']+(['walk'] if mask&1 else [])+(['roll'] if mask&2 else [])
    chosen=[]
    for slot in range(12):
        options=[a for a in pool if not chosen or a != chosen[-1]]
        chosen.append(rng.choice(options or pool))
    # The 60-second loop must return to the same physical position.
    if chosen.count('walk')%2:
        chosen[max(i for i,a in enumerate(chosen) if a=='walk')]='idle'
    idle=timeline([{'action':'idle','frame':i,'durationMs':d} for i,d in enumerate(MANIFEST['actions']['idle']['frameDurationsMs'])])
    roll=timeline([{'action':'roll','frame':i,'durationMs':d} for i,d in enumerate(MANIFEST['actions']['roll']['frameDurationsMs'])]*2)
    right=timeline(MANIFEST['clips']['walk_burst']['entries'])
    left=timeline(MANIFEST['clips']['walk_left_burst']['entries'])
    frames=[];position=-WALK_EXTENT if 'walk' in chosen else 0
    for slot,action in enumerate(chosen):
        start=position
        direction='walk_right' if start<0 else 'walk_left'
        end=-start if action=='walk' else start
        clip=right if direction=='walk_right' else left
        for j in range(FPS*5):
            ms=j*1000/FPS
            if action=='walk' and ms<WALK_END:
                a,i=sample(clip,ms)
                # Actual root movement is baked into color glyphs, not a background task.
                p=start+(end-start)*min(1,max(0,(ms-WALK_MOVE_START)/WALK_MOVE_MS))
            elif action=='roll' and ms<ROLL_END:a,i=sample(roll,ms);p=start
            else:
                a,i=sample(idle,(ms-(WALK_END if action=='walk' else ROLL_END if action=='roll' else 0))%2000)
                p=end
            frames.append({'asset':key(a,i),'x':round(p),'action':action})
        position=end
    return chosen,frames


def render_frame(artwork,frame,*,opaque=True):
    # Timer masks reveal cumulative stacks. Transparent PNGs let old silhouettes
    # show THROUGH the new pose. A fully opaque island-black tile replaces all
    # older pixels, including where a previous leg/tail used to be. This matte
    # is only for island fonts; app imagesets retain their original alpha.
    canvas=Image.new('RGBA',(GLYPH_PIXELS,GLYPH_PIXELS),(0,0,0,255 if opaque else 0))
    image=artwork[frame['asset']].resize((72,90),Image.Resampling.LANCZOS)
    canvas.alpha_composite(image,(12+round(frame['x']*GLYPH_PIXELS/128),3))
    return canvas


def base_font(name,glyph_order):
    builder=FontBuilder(1000,isTTF=True)
    builder.setupGlyphOrder(glyph_order)
    builder.setupCharacterMap({ord(str(i)):f'd{i}' for i in range(10)}|{32:'space',58:'colon',160:'space'})
    builder.setupGlyf({n:TTGlyphPen(None).glyph() for n in glyph_order})
    builder.setupHorizontalMetrics({n:(1000,0) for n in glyph_order})
    builder.setupHorizontalHeader(ascent=1000,descent=0)
    builder.setupOS2(sTypoAscender=1000,sTypoDescender=0,usWinAscent=1000,usWinDescent=0)
    builder.setupNameTable({'familyName':name,'styleName':'Regular','uniqueFontIdentifier':name,
                           'fullName':name,'psName':name,'version':'Version 1.0'})
    builder.setupPost();builder.setupMaxp()
    return builder.font


def features(names):
    return 'languagesystem DFLT dflt; feature liga {'+' '.join(
        f'sub d{s//10} d{s%10} by {names[s]};' for s in range(60))+'} liga;'


def mask_font():
    names=['.notdef','space','colon']+[f'd{i}' for i in range(10)]+['full','empty']
    font=base_font('mAIverseGate',names)
    pen=TTGlyphPen(None);pen.moveTo((0,0));pen.lineTo((1000,0));pen.lineTo((1000,1000));pen.lineTo((0,1000));pen.closePath()
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
    rendered={}
    def png(frame):
        k=(frame['asset'],frame['x'])
        if k not in rendered:
            canvas=render_frame(artwork,frame)
            buf=BytesIO();canvas.save(buf,format='PNG');rendered[k]=buf.getvalue()
        return rendered[k]
    # Share one variable font across all banks and phases. Independent fonts
    # registered hundreds of times impose too much overhead on Live Activities.
    for old in OUTPUT.glob('mAIverseP*F*.ttf'):
        assert old.resolve().parent==OUTPUT.resolve()
        old.unlink()
    mask_font()
    plans=[]
    order=['.notdef','space','colon']+[f'd{i}' for i in range(10)]+[f'f{s:02}' for s in range(60)]
    def glyph_name(bank,phase,second):
        return f'f{second:02}' if bank==0 and phase==0 else f'b{bank}p{phase}s{second:02}'
    for mask in range(4):
        for seed in range(SEEDS):
            bank=mask*SEEDS+seed
            chosen,frames=schedule(mask,seed)
            plans.append({'id':bank,'mask':mask,'slots':chosen,'frames':frames})
            for phase in range(PHASES):
                if bank or phase:order += [glyph_name(bank,phase,s) for s in range(60)]
    font=base_font('mAIverseMotion',order)
    builder=FontBuilder(font=font)
    builder.setupFvar([('BANK',0,0,7,'Motion bank'),('PHAS',0,0,PHASES-1,'Frame phase')],[])
    builder.setupGvar({})
    strike=Strike(ppem=GLYPH_PIXELS,resolution=72)
    for n in order:strike.glyphs[n]=Glyph(glyphName=n)
    encoded={};variations=[]
    for plan in plans:
        bank=plan['id'];frames=plan['frames']
        for phase in range(PHASES):
            substitutions={}
            for second in range(60):
                frame=frames[(((second+1)%60)*FPS+phase)%len(frames)]
                glyph=glyph_name(bank,phase,second)
                data=png(frame);digest=hashlib.sha256(data).digest()
                if digest in encoded:
                    strike.glyphs[glyph]=Glyph(glyphName=glyph,graphicType='dupe',referenceGlyphName=encoded[digest])
                else:
                    encoded[digest]=glyph
                    strike.glyphs[glyph]=Glyph(glyphName=glyph,originOffsetX=0,originOffsetY=0,graphicType='png ',imageData=data)
                if bank or phase:substitutions[f'f{second:02}']=glyph
            if substitutions:
                box={'BANK':(max(0,(bank-.45)/7),min(1,(bank+.45)/7)),
                     'PHAS':(max(0,(phase-.45)/(PHASES-1)),min(1,(phase+.45)/(PHASES-1)))}
                variations.append(([box],substitutions))
    sbix=newTable('sbix');sbix.strikes={GLYPH_PIXELS:strike};font['sbix']=sbix
    addOpenTypeFeaturesFromString(font,features([f'f{s:02}' for s in range(60)]))
    # The variation lookup follows the default seconds ligature in liga.
    addFeatureVariations(font,variations,featureTag='liga')
    font.save(OUTPUT/'mAIverseMotion.ttf')
    checks=[{'bank':b,'phase':p,'second':s,'glyph':font.getGlyphID(glyph_name(b,p,s))}
            for b in range(8) for p in (0,1,15,29,30,58,59) for s in (15,55)]
    (OUTPUT/'checks.json').write_text(json.dumps(checks),encoding='utf-8')
    durations={a:info['frameDurationsMs'] for a,info in MANIFEST['actions'].items()}
    (ROOT/'Shared/Resources/MotionTimeline.json').write_text(json.dumps({'fps':FPS,'period':PERIOD,'plans':plans,'durations':durations},separators=(',',':'))+'\n',encoding='utf-8')
    # XcodeGen includes this generated settings fragment in both Info.plists.
    paths=[p.name for p in sorted(OUTPUT.glob('*.ttf'))]
    (OUTPUT/'font-summary.json').write_text(json.dumps({'fontFiles':len(paths),'fontBytesPerBundle':sum((OUTPUT/p).stat().st_size for p in paths),'uniqueBitmaps':len(encoded),'targetFPS':FPS,'phases':PHASES,'plans':len(plans)}),encoding='utf-8')
    (ROOT/'motion-fonts.yml').write_text('targets:\n  DragonIsland:\n    info:\n      properties:\n        UIAppFonts: &motionFonts\n'+''.join(f'          - {n}\n' for n in paths)+'  DragonIslandWidget:\n    info:\n      properties:\n        UIAppFonts: *motionFonts\n',encoding='utf-8')
    print(f'Motion resources: {len(artwork)} PNG poses, {len(plans)} plans, {len(paths)} fonts; native timer rendering.')


if __name__=='__main__':main()
