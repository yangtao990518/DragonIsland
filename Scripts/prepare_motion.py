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

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'Art/MotionV2'
OUTPUT=ROOT/'Shared/Resources/MotionFonts'
MANIFEST=json.loads((ART/'manifest.json').read_text())
PHASES=16
FPS=8
SEEDS=2
PERIOD=60


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
    roll=timeline([{'action':'roll','frame':i,'durationMs':d} for i,d in enumerate(MANIFEST['actions']['roll']['frameDurationsMs'])])
    right=timeline(MANIFEST['clips']['walk_burst']['entries'])
    left=timeline(MANIFEST['clips']['walk_left_burst']['entries'])
    frames=[];position=-10 if 'walk' in chosen else 0
    for slot,action in enumerate(chosen):
        start=position
        direction='walk_right' if start<0 else 'walk_left'
        end=-start if action=='walk' else start
        clip=right if direction=='walk_right' else left
        for j in range(40):
            ms=j*125
            if action=='walk' and ms<2000:
                a,i=sample(clip,ms)
                # Actual root movement is baked into color glyphs, not a background task.
                p=start+(end-start)*min(1,max(0,(ms-180)/1500))
            elif action=='roll' and ms<1600:a,i=sample(roll,ms);p=start
            else:
                a,i=sample(idle,(ms-(2000 if action=='walk' else 1600 if action=='roll' else 0))%2000)
                p=end
            frames.append({'asset':key(a,i),'x':round(p),'action':action})
        position=end
    return chosen,frames


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
            image=Image.open(ART/path).convert('RGBA')
            artwork[key(action,i)]=image
            imageset(SHARED,key(action,i),image,(64,80))
    rendered={}
    def png(frame):
        k=(frame['asset'],frame['x'])
        if k not in rendered:
            canvas=Image.new('RGBA',(128,128))
            image=artwork[k[0]].resize((96,120),Image.Resampling.LANCZOS)
            canvas.alpha_composite(image,(16+k[1],4))
            buf=BytesIO();canvas.save(buf,format='PNG');rendered[k]=buf.getvalue()
        return rendered[k]
    mask_font()
    plans=[]
    for mask in range(4):
        for seed in range(SEEDS):
            bank=mask*SEEDS+seed
            chosen,frames=schedule(mask,seed)
            plans.append({'id':bank,'mask':mask,'slots':chosen,'frames':frames})
            for phase in range(PHASES):
                name=f'mAIverseP{bank}F{phase}'
                order=['.notdef','space','colon']+[f'd{i}' for i in range(10)]+[f'f{s:02}' for s in range(60)]
                font=base_font(name,order)
                strike=Strike(ppem=128,resolution=72)
                for n in order:strike.glyphs[n]=Glyph(glyphName=n)
                for second in range(60):
                    # For the active layer, timer text lags the reference by 1s.
                    frame=frames[(((second+1)%60)*FPS+phase)%len(frames)]
                    glyph=f'f{second:02}'
                    strike.glyphs[glyph]=Glyph(glyphName=glyph,originOffsetX=0,originOffsetY=0,
                                               graphicType='png ',imageData=png(frame))
                sbix=newTable('sbix');sbix.strikes={128:strike};font['sbix']=sbix
                addOpenTypeFeaturesFromString(font,features([f'f{s:02}' for s in range(60)]))
                font.save(OUTPUT/f'{name}.ttf')
    (ROOT/'Shared/Resources/MotionTimeline.json').write_text(json.dumps({'fps':FPS,'period':PERIOD,'plans':plans},separators=(',',':'))+'\n',encoding='utf-8')
    # XcodeGen includes this generated settings fragment in both Info.plists.
    paths=[p.name for p in sorted(OUTPUT.glob('*.ttf'))]
    (ROOT/'motion-fonts.yml').write_text('targets:\n  DragonIsland:\n    info:\n      properties:\n        UIAppFonts: &motionFonts\n'+''.join(f'          - {n}\n' for n in paths)+'  DragonIslandWidget:\n    info:\n      properties:\n        UIAppFonts: *motionFonts\n',encoding='utf-8')
    print(f'Motion resources: {len(artwork)} PNG poses, {len(plans)} plans, {len(paths)} fonts; native timer rendering.')


if __name__=='__main__':main()
