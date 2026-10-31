"""Recover the user's earlier small bubble artwork; no generation or repaint."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
from PIL import Image
from process_survivor_videos import alpha_task, foreground_task, RGBA_FOLDER, VERSION


def prepare(source, work, output):
    source, work, output = Path(source), Path(work), Path(output)
    raw = source.read_bytes()
    output.mkdir(parents=True, exist_ok=True)
    for folder in ('rgb', 'alpha', RGBA_FOLDER): (work / folder).mkdir(parents=True, exist_ok=True)
    image = Image.open(source).convert('RGB')
    if image.size != (1983, 793): raise ValueError('Review the earlier bubble source dimensions/crop first')
    crop = [95, 330, 285, 455]
    identity = {'source_sha256': hashlib.sha256(raw).hexdigest(), 'crop': crop, 'method': VERSION}
    cache = work / 'identity.json'
    if cache.exists() and json.loads(cache.read_text(encoding='utf-8')) != identity:
        raise ValueError('Use a new work directory for a different bubble source or method')
    cache.write_text(json.dumps(identity), encoding='utf-8')
    image.crop(crop).save(work / 'rgb/0000.png')
    alpha_task((str(work), 0, False))
    foreground_task((str(work), 0, 1, False))
    rgba = Image.open(work / RGBA_FOLDER / '0000.png').convert('RGBA')
    bounds = rgba.getchannel('A').getbbox()
    trim = [max(0,bounds[0]-6), max(0,bounds[1]-6), min(rgba.width,bounds[2]+6), min(rgba.height,bounds[3]+6)]
    rgba = rgba.crop(trim)
    dest = output / 'water-bubble.png'; rgba.save(dest)
    archive = output / 'water-bubble-source.png'
    if archive.exists() and archive.read_bytes() != raw: raise ValueError('Refuse to replace a different bubble master')
    if not archive.exists(): shutil.copyfile(source, archive)
    pivot = [(155-crop[0]-trim[0])/rgba.width, 1-(390-crop[1]-trim[1])/rgba.height]
    manifest = {'method': VERSION, 'source': archive.name, 'source_sha256': hashlib.sha256(raw).hexdigest(),
                'crop_xyxy': crop, 'trim_xyxy': trim, 'file': dest.name,
                'sha256': hashlib.sha256(dest.read_bytes()).hexdigest(), 'size': list(rgba.size),
                'pivot': pivot, 'native_direction': 'left', 'generated_poses': False,
                'description': 'Earlier first-level water bubble, explicitly requested again for the basic attack'}
    (output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(manifest, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(); prepare(args.source, args.work, args.output)
