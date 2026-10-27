#!/usr/bin/env python3
"""Small, actual-system review sheets; originals are uploaded separately."""
from pathlib import Path
import json,re
from PIL import Image,ImageDraw

root=Path('output');dest=root/'verification';dest.mkdir(exist_ok=True)
pages=['world','characters','tasks','alarms','detail','gallery-chibi','gallery-standing','about']
contact=Image.new('RGB',(len(pages)*240,3*550),'#34323a');d=ImageDraw.Draw(contact)
for theme,row in [('dark',0),('light',1)]:
    for column,page in enumerate(pages):
        p=root/f'previews/{page}-{theme}.png'
        if not p.exists():continue
        im=Image.open(p);im.thumbnail((235,515));x=column*240;y=row*550
        contact.paste(im,(x,y+25));d.text((x+4,y+5),f'{page}-{theme}',fill='white')
for column,name in enumerate(('about-scene-meadow','tasks-scene-meadow','about-scene-night','tasks-scene-night')):
    p=root/f'previews/{name}.png'
    if p.exists():
        im=Image.open(p);im.thumbnail((235,515));x=column*240;y=1100
        contact.paste(im,(x,y+25));d.text((x+4,y+5),name,fill='white')
contact.save(dest/'pages-contact.png')
manifest=json.loads((root/'ui-test-attachments/manifest.json').read_text())
islands=Image.new('RGB',(1000,600),'#34323a');d=ImageDraw.Draw(islands)
for group in manifest:
    for a in group['attachments']:
        name=a['suggestedHumanReadableName'];p=root/'ui-test-attachments'/a['exportedFileName']
        m=re.match(r'automatic-island-(\d+)-(\d+)_',name)
        if m:
            row,index=map(int,m.groups())
            if row<3 and index%2==0:
                im=Image.open(p).crop((180,40,500,160)).resize((200,75))
                x=(index//2%5)*200;y=(row*2+index//10)*100
                islands.paste(im,(x,y+22));d.text((x+3,y+4),f'{row}-{index}',fill='white')
        elif name.startswith('system-island-expanded'):
            Image.open(p).crop((0,0,1206,620)).save(dest/'system-island-expanded.png')
        elif name.startswith('live-session-before-home'):
            Image.open(p).save(dest/'live-session-before-home.png')
        elif name.startswith('character-alarm-scheduled') or name.startswith('one-minute-system-alarm-fired'):
            Image.open(p).save(dest/(name.split('_')[0]+'.png'))
        elif name.startswith('scene-'):
            title=re.match(r'(scene-(?:meadow|night)-(?:compact|expanded))',name)
            if title:
                crop=(170,35,1036,180) if title[1].endswith('compact') else (0,0,1206,620)
                Image.open(p).crop(crop).save(dest/f'{title[1]}.png')
islands.save(dest/'system-island-contact.png')
font=Path('Shared/Resources/MotionFonts/font-summary.json')
if font.exists():(dest/'font-summary.json').write_bytes(font.read_bytes())
