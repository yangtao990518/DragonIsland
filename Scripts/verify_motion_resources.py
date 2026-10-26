#!/usr/bin/env python3
"""Inspect actual compiled PNG font tiles; this is not an iOS rendering test."""
import hashlib
from io import BytesIO
import json
from pathlib import Path
from PIL import Image
from fontTools.ttLib import TTFont

ROOT=Path(__file__).resolve().parents[1]
folder=ROOT/'Shared/Resources/MotionFonts'
files=sorted(folder.glob('*.ttf'))
if len(files)!=181:raise ValueError('Expected three 60-phase banks and one gate font')
direct=0;references=0;unique=set()
for path in files:
    with TTFont(path) as font:
        if 'sbix' not in font:continue
        for strike in font['sbix'].strikes.values():
            for glyph in strike.glyphs.values():
                if glyph.graphicType=='dupe':references+=1
                elif glyph.graphicType=='png ':
                    with Image.open(BytesIO(glyph.imageData)) as image:
                        rgba=image.convert('RGBA')
                        if rgba.size!=(180,96) or rgba.getchannel('A').getextrema()!=(255,255):
                            raise ValueError(f'Incomplete or transparent coverage in {path.name}')
                    direct+=1;unique.add(hashlib.sha256(glyph.imageData).hexdigest())
if direct==0:raise ValueError('No motion artwork in generated fonts')
report={'fonts':len(files),'fontBytesPerBundle':sum(path.stat().st_size for path in files),
        'directBitmaps':direct,'uniqueBitmaps':len(unique),'duplicateReferences':references,
        'all180x96Opaque':True,'scope':'Compiled font resources only; iOS playback is not verified.'}
destination=ROOT/'output/verification/motion-font-verification.json'
destination.parent.mkdir(parents=True,exist_ok=True)
destination.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report))
