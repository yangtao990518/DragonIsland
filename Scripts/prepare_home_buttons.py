"""Extract the approved generated button sheet and build transparent UI assets.

Only fixed cropping, uniform scaling and padding; no repainting or color keying.
The blank plaques align at 50%/84% so labels remain native SwiftUI text.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'Art/UI/HomeButtons'
NAMES = ['actions', 'scene', 'island']
REGIONS = {
    'fantasy': [(320, 0, 750, 354), (320, 354, 750, 672), (320, 672, 750, 1024)],
    'candy': [(775, 0, 1200, 360), (775, 360, 1200, 677), (775, 677, 1200, 1024)],
}
PLAQUES = {'fantasy': [(533, 309), (533, 631), (533, 951)],
           'candy': [(981, 309), (981, 632), (981, 951)]}


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def import_sheet(source):
    ART.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, ART / 'source-sheet.png')
    sheet = Image.open(source).convert('RGBA')
    if sheet.size != (1536, 1024): raise ValueError('Unexpected approved sheet dimensions')
    entries = []
    for theme, regions in REGIONS.items():
        for action, region, plaque in zip(NAMES, regions, PLAQUES[theme]):
            part = sheet.crop(region)
            box = part.getchannel('A').getbbox()
            part = part.crop(box)
            factor = min(396 / part.width, 396 / part.height)
            size = (round(part.width * factor), round(part.height * factor))
            part = part.resize(size, Image.Resampling.LANCZOS)
            cx = (plaque[0] - region[0] - box[0]) * factor
            cy = (plaque[1] - region[1] - box[1]) * factor
            position = (round(224 - cx), round(448 * .84 - cy))
            if min(position) < 0 or position[0] + size[0] > 448 or position[1] + size[1] > 448:
                raise ValueError(('Button exceeds uniform canvas', theme, action, position, size))
            canvas = Image.new('RGBA', (448, 448))
            canvas.alpha_composite(part, position)
            name = f'{theme}-{action}.png'; canvas.save(ART / name, optimize=True)
            entries.append(dict(theme=theme, action=action, file=name, crop=list(region),
                                labelAnchor=[.5, .84], sha256=digest(ART / name)))
    (ART / 'manifest.json').write_text(json.dumps(dict(version=1, sourceSHA256=digest(ART/'source-sheet.png'),
        characterID='dafeiyu', canvas=[448,448], entries=entries), ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def prepare():
    from prepare_assets import imageset, APP
    info = json.loads((ART / 'manifest.json').read_text(encoding='utf-8'))
    for item in info['entries']:
        path = ART / item['file']
        if digest(path) != item['sha256']: raise ValueError('Button asset digest mismatch')
        name = 'HomeButton' + item['theme'].title() + item['action'].title()
        imageset(APP, name, Image.open(path).convert('RGBA'), 80)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--sheet', type=Path)
    args = parser.parse_args()
    if args.sheet: import_sheet(args.sheet)
    prepare()
