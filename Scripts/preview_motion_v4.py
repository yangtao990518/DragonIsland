#!/usr/bin/env python3
"""Render the actual compiled motion timelines for visual review (not iOS QA)."""
from pathlib import Path
from PIL import Image, ImageDraw
import prepare_motion as motion

ROOT = Path(__file__).resolve().parents[1]
output = ROOT/'build/motion-v4-preview'
output.mkdir(parents=True, exist_ok=True)
artwork = {motion.key(action, i): Image.open(motion.ART/path).convert('RGBA')
           for action, info in motion.MANIFEST['actions'].items()
           for i, path in enumerate(info['frames'])}
for action in ('walk_right', 'walk_left', 'roll'):
    timeline = motion.preview_frames()[action]
    frames = []
    # Every third native 30Hz sample; time remains real-time, never sped up.
    for index in range(0, len(timeline), 3):
        image = motion.render_frame(artwork, timeline[index], scene='meadow').convert('RGB')
        frames.append(image.resize((720, 384), Image.Resampling.NEAREST))
    frames[0].save(output/f'{action}-travel.gif', save_all=True,
                   append_images=frames[1:], duration=100, loop=0)
    contact = Image.new('RGB', (4*360, 4*212), '#14111c')
    draw = ImageDraw.Draw(contact)
    for i in range(16):
        index = round(i*(len(frames)-1)/15)
        contact.paste(frames[index].resize((360,192)), ((i%4)*360,(i//4)*212+20))
        draw.text(((i%4)*360+5,(i//4)*212+3),f'{action} {index/10:.1f}s',fill='white')
    contact.save(output/f'{action}-travel-contact.jpg')
print('Saved real-time walking and travelling-roll review GIFs and contacts.')
