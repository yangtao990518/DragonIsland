#!/usr/bin/env python3
"""Import keyed ImageGen poses; only crop, scale, anchor and export pixels."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'Art/MotionV4'


def import_frames(processed):
    old = json.loads((ROOT/'Art/MotionV2/manifest.json').read_text())
    manifest = {'schemaVersion': 3, 'characterID': 'xiaobai',
                'artworkGeneration': 'built-in image_gen', 'canvas': [512, 640],
                'anchor': {'x': 256, 'groundY': 600},
                'status': 'V1.7_natural_gait_and_directional_travel_roll', 'actions': {}}
    for action in ('idle', 'turn_left'):
        info = dict(old['actions'][action])
        info['frames'] = ['../MotionV2/'+path for path in info['frames']]
        manifest['actions'][action] = info
    qc = {}
    for action in ('walk_right', 'walk_left', 'roll_right', 'roll_left'):
        walking = action.startswith('walk')
        count = 4 if walking else 12
        prefix = 'walk' if walking else 'roll'
        folder = processed/action
        metadata = json.loads((folder/'pipeline-meta.json').read_text())
        if metadata['edge_touch_frames']:
            raise ValueError(f'Clipped source cells in {action}')
        cells = []
        for i in range(count):
            image = Image.open(folder/f'{prefix}-{i+1}.png').convert('RGBA')
            box = image.getchannel('A').getbbox()
            if box is None:
                raise ValueError(f'Empty frame {action}/{i}')
            cells.append(image.crop(box))
        # One shared scale per action. Never inflate a crouched or rolled pose
        # independently to standing height; that would create size pumping.
        target_height = 520 if walking else 566
        scale = min(468/max(c.width for c in cells), target_height/max(c.height for c in cells))
        frames = []
        for cell in cells:
            size = (round(cell.width*scale), round(cell.height*scale))
            resized = cell.resize(size, Image.Resampling.LANCZOS)
            canvas = Image.new('RGBA', (512, 640))
            canvas.alpha_composite(resized, ((512-resized.width)//2, 600-resized.height))
            frames.append(canvas)
        if not walking:
            # The final accepted standing drawing also closes the entry pose.
            frames[0] = frames[-1].copy()
        durations = [400]*4 if walking else [200,400,400,550,550,550,550,550,400,400,250,200]
        paths = []
        for i, frame in enumerate(frames):
            path = f'frames/{action}/{i:03}.png'
            (ART/path).parent.mkdir(parents=True, exist_ok=True)
            frame.save(ART/path)
            paths.append(path)
        manifest['actions'][action] = {'frames': paths, 'frameDurationsMs': durations,
            'durationMs': sum(durations), 'loop': walking,
            'uniqueDrawings': len({frame.tobytes() for frame in frames}),
            'direction': action.split('_')[-1], 'mirrorAllowed': False,
            'note': 'Independently generated poses; no optical flow or blended intermediate poses.'}
        qc[action] = {'sourceGrid': [metadata['rows'], metadata['cols']],
            'edgeTouchFrames': metadata['edge_touch_frames'],
            'sharedImportScale': scale, 'bounds': [frame.getbbox() for frame in frames]}
        preview = ROOT/'build/motion-v4-preview'
        preview.mkdir(parents=True, exist_ok=True)
        contact = Image.new('RGB', (4*256, ((count+3)//4)*340), '#14111c')
        draw = ImageDraw.Draw(contact)
        rgb = []
        for i, frame in enumerate(frames):
            background = Image.new('RGBA', frame.size, '#14111c')
            background.alpha_composite(frame)
            contact.paste(background.convert('RGB').resize((256,320)), ((i%4)*256, (i//4)*340+20))
            draw.text(((i%4)*256+5, (i//4)*340+3), f'{action} {i:02}', fill='white')
            rgb.append(background.convert('RGB'))
        contact.save(preview/f'{action}-contact.jpg')
        rgb[0].save(preview/f'{action}.gif', save_all=True, append_images=rgb[1:], duration=durations, loop=0)
    (ART/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    (ART/'import-qc.json').write_text(json.dumps(qc, indent=2)+'\n', encoding='utf-8')
    print('Imported four true keyposes per walk direction and twelve-frame directional rolls.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('processed_root', type=Path)
    import_frames(parser.parse_args().processed_root)
