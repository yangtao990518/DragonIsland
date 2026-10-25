#!/usr/bin/env python3
"""Small, actual-system review sheets; originals are uploaded separately."""
from pathlib import Path
import json,re
from PIL import Image,ImageDraw

root=Path('output');dest=root/'verification';dest.mkdir(exist_ok=True)
pages=['world','characters','tasks','detail','gallery-chibi','gallery-standing','about']
contact=Image.new('RGB',(7*240,2*550),'#34323a');d=ImageDraw.Draw(contact)
for theme,row in [('dark',0),('light',1)]:
    for column,page in enumerate(pages):
        p=root/f'previews/{page}-{theme}.png'
        if not p.exists():continue
        im=Image.open(p);im.thumbnail((235,515));x=column*240;y=row*550
        contact.paste(im,(x,y+25));d.text((x+4,y+5),f'{page}-{theme}',fill='white')
contact.save(dest/'pages-contact.png')
manifest=json.loads((root/'ui-test-attachments/manifest.json').read_text())
islands=Image.new('RGB',(1000,330),'#34323a');d=ImageDraw.Draw(islands)
for group in manifest:
    for a in group['attachments']:
        name=a['suggestedHumanReadableName'];p=root/'ui-test-attachments'/a['exportedFileName']
        m=re.match(r'automatic-island-(\d+)-(\d+)_',name)
        if m:
            row,index=map(int,m.groups())
            if row<3 and index%2==0:
                im=Image.open(p).crop((295,40,435,150)).resize((100,79))
                x=index//2*100;y=row*110
                islands.paste(im,(x,y+22));d.text((x+3,y+4),f'{row}-{index}',fill='white')
        elif name.startswith('system-island-expanded'):
            Image.open(p).crop((0,0,1206,540)).save(dest/'system-island-expanded.png')
        elif name.startswith('live-session-before-home'):
            Image.open(p).save(dest/'live-session-before-home.png')
islands.save(dest/'system-island-contact.png')
font=Path('Shared/Resources/MotionFonts/font-summary.json')
if font.exists():(dest/'font-summary.json').write_bytes(font.read_bytes())
