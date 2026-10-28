"""Longer grounded steps using the complete v12 character paintings.

Only travel and the hidden pelvis anchors change. Visible leg, sock, shoe and
paw paintings retain their size. This module leaves the v12 trial on disk.
"""
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import painted_walk_v12 as base
from animation_runtime import FONT

OUT = base.OUT.parent / 'walk-painted-v13'
CFG = base.CFG
CYCLE, FPS, DUTY = base.CYCLE, base.FPS, base.DUTY
human = base.human
LIMBS = base.LIMBS
pet_poses = base.pet_poses
character = base.character
base.PET_LIFT = 2.6

STRIDE = {'xiaobai': (25., 7.), 'dafeiyu': (18.5, 9.)}
for role, (amplitude, inset) in STRIDE.items():
    cfg = CFG[role]
    cfg['a'] = amplitude
    cfg['lift'] = 3.
    # Project both hidden hips onto their walking lanes. A foot offset alone
    # makes one leg overreach and the body duck when that foot moves forward.
    cfg['hips'] = [(x + dx, y) for (x, y), dx in
                   zip(cfg['hips'], (inset, -inset))]
    cfg['foot_x_bias'] = [0., 0.]
    for side, dx in [('far', inset), ('near', -inset)]:
        limb = human.LIMBS[role][side]
        limb.joints[0, 0] += dx
        limb.l1, limb.l2 = np.linalg.norm(np.diff(limb.joints, axis=0), axis=1)


def audit():
    OUT.mkdir(exist_ok=True)
    font = ImageFont.truetype(str(FONT), 18)
    board = Image.new('RGB', (1600, 1140), '#192033')
    draw = ImageDraw.Draw(board)
    stats = {}
    for row, role in enumerate(CFG):
        bobs = []
        for tick in range(CYCLE):
            poses, _, bob = human.poses(role, tick)
            pet_poses(role, tick)
            bobs.append(bob)
        for col, tick in enumerate([0, 24, 48, 72]):
            art, *_ = character(role, tick)
            art.save(OUT / f'{role}-key-{tick:02}.png')
            x, y = col * 400, row * 570
            draw.text((x + 8, y + 8), f'{CFG[role]["name"]} / {tick}/96',
                      font=font, fill='white')
            crop = art.crop((140, 230, 320, 368)).resize((400, 307), Image.Resampling.LANCZOS)
            board.paste(crop, (x, y + 40), crop)
            pet = art.crop((355, 220, 545, 368)).resize((260, 202), Image.Resampling.LANCZOS)
            board.paste(pet, (x + 70, y + 355), pet)
        stats[role] = dict(stance_ankle_travel_px=2*CFG[role]['a'],
                           root_travel_per_cycle_px=2*CFG[role]['a']/DUTY,
                           body_vertical_range_px=float(np.ptp(bobs)),
                           visible_artwork_rescaled=False)
    board.save(OUT / 'stride-key-review.png')
    (OUT / 'stride-change.json').write_text(json.dumps(stats, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(stats, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    audit()
