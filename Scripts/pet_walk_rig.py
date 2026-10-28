"""Review-only walking rig using the restored painted attachments.

No production asset is changed. The old rig supplies its float texture rasterizer;
this module replaces the motion, skin deformation and clothing/shoe composition.
"""
import importlib.util
import math
from pathlib import Path
import numpy as np
from PIL import Image
from animation_runtime import REPOSITORY

BASE = REPOSITORY / 'output/pet-walk-batch2'
spec = importlib.util.spec_from_file_location('archived_pet_walk_rig', BASE / 'walk-rig-v3-stable/rig.py')
legacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(legacy)
FPS = 60
CYCLE = 96
DUTY = .62
GROUND = 590.
SS = 6
REGION = (200, 420, 450, 614)
CFG = {
    'xiaobai': dict(name='小白', hips=[(308., 455.), (321., 455.)], l1=58.5, l2=58.5,
                    a=30., lift=5., thigh_width=24., shin_width=22., shoe_width=44.,
                    shoe_anchor=(.24, .12), bob=3.2),
    'dafeiyu': dict(name='大肥鱼', hips=[(283., 509.), (298., 509.)], l1=31., l2=31.,
                    a=20., lift=3., thigh_width=21., shin_width=19., shoe_width=38.,
                    shoe_anchor=(.34, .075), bob=2.6),
}
ASSETS = legacy.ASSETS
TORSO = legacy.TORSO
GARMENT_REMOVED_PIXELS = {}

# Only orphan pixels left by the old leg-cut polygons are removed. The separate
# triangular underlay is itself a disconnected remnant; it is not a full lining.
front = np.array(TORSO['xiaobai']['front'])
GARMENT_REMOVED_PIXELS['front_orphans'] = int(np.count_nonzero(front[510:610, 270:321, 3]))
front[510:610, 270:321] = 0
TORSO['xiaobai']['front'] = Image.fromarray(front)
GARMENT_REMOVED_PIXELS['disconnected_underlay'] = int(np.count_nonzero(np.asarray(TORSO['xiaobai']['back'])[:, :, 3]))
TORSO['xiaobai']['back'] = Image.new('RGBA', (896, 640))

def ease(t):
    t = np.clip(t, 0., 1.)
    return t * t * t * (10 + t * (-15 + 6 * t))

# Open the painted cut caps with a short alpha overlap. The continuous shin ends
# inside the existing cuff/anklet, rather than in the middle of the shoe upper.
for role, c in CFG.items():
    for side in ['near', 'far']:
        image = np.array(ASSETS[role][side + '-shoe'])
        alpha = ease(np.arange(image.shape[0]) / (image.shape[0] * c['shoe_anchor'][1]))
        image[:, :, 3] = np.round(image[:, :, 3] * alpha[:, None]).astype(np.uint8)
        ASSETS[role][side + '-shoe'] = Image.fromarray(image)

SOLE = {}
for role, c in CFG.items():
    for side in ['near', 'far']:
        image = ASSETS[role][side + '-shoe']
        ys, xs = np.where(np.asarray(image.getchannel('A')) > 100)
        selected = ys > image.height * .75
        SOLE[role, side] = np.c_[xs[selected], ys[selected]]

def gait(role, tick):
    c = CFG[role]
    cycle = tick / CYCLE
    body_y = c['bob'] * math.cos(4 * math.pi * (cycle-(DUTY-.5)/2))
    stride = 2 * c['a'] / DUTY
    root = cycle * stride
    result = []
    for number, side, offset in [(0, 'far', .5), (1, 'near', 0.)]:
        p = (cycle + offset) % 1
        stance = p < DUTY
        if stance:
            x = c['a'] - stride * p
            lift = 0.
            angle = -2 * (1 - ease(p / .10)) if p < .10 else 2 * ease((p - (DUTY - .10)) / .10)
        else:
            u = (p - DUTY) / (1 - DUTY)
            velocity = -2 * c['a'] * (1 - DUTY) / DUTY
            x = -c['a'] + velocity * u + (2 * c['a'] - velocity) * ease(u)
            # Fourth power makes lift, velocity and acceleration zero at contact.
            lift = c['lift'] * math.sin(math.pi * u) ** 4
            angle = 2 * (1 - ease(u / .3)) if u < .3 else (-2 * ease((u - .7) / .3) if u > .7 else 0.)
        image = ASSETS[role][side + '-shoe']
        scale = c['shoe_width'] / image.width
        anchor = np.array([image.width * c['shoe_anchor'][0], image.height * c['shoe_anchor'][1]])
        theta = math.radians(angle)
        rotation = np.array([[math.cos(theta), -math.sin(theta)], [math.sin(theta), math.cos(theta)]])
        lowest = float(((SOLE[role, side] - anchor) @ rotation.T * scale)[:, 1].max())
        hip = np.array([c['hips'][number][0], c['hips'][number][1] + body_y])
        ankle = np.array([hip[0] + x, GROUND - lowest - lift])
        delta = ankle - hip
        distance = float(np.linalg.norm(delta))
        assert distance < c['l1'] + c['l2'] - .1, (role, tick, side, distance)
        along = (c['l1'] ** 2 - c['l2'] ** 2 + distance ** 2) / (2 * distance)
        unit = delta / distance
        knee = hip + along * unit + math.sqrt(c['l1'] ** 2 - along ** 2) * np.array([unit[1], -unit[0]])
        flex = 180 - math.degrees(math.acos(np.clip((c['l1'] ** 2 + c['l2'] ** 2 - distance ** 2) / (2 * c['l1'] * c['l2']), -1, 1)))
        result.append(dict(side=side, phase=p, stance=stance, hip=hip, knee=knee, ankle=ankle,
                           angle=float(angle), shoe_anchor=anchor, shoe_scale=scale, root=root, lift=lift,
                           knee_flex_degrees=flex, sole_lowest=ankle[1] + lowest))
    return result, root, body_y

def hermite(start, end, start_tangent, end_tangent, u):
    u = np.asarray(u)[:, None]
    point = (2*u**3-3*u**2+1)*start + (u**3-2*u**2+u)*start_tangent + (-2*u**3+3*u**2)*end + (u**3-u**2)*end_tangent
    derivative = (6*u**2-6*u)*start + (3*u**2-4*u+1)*start_tangent + (-6*u**2+6*u)*end + (3*u**2-2*u)*end_tangent
    return point, derivative

def paint_skin_mesh(canvas, role, pose):
    """One continuous texture along a centerline with a continuous knee tangent."""
    c = CFG[role]
    image = ASSETS[role][pose['side'] + '-skin']
    vs = np.linspace(0., float(image.height), 33)
    us = np.linspace(0., float(image.width), 3)
    source = np.array([[[u, v] for u in us] for v in vs])
    s = (vs / image.height - .04) / .92
    upper = (pose['knee'] - pose['hip']) / c['l1']
    lower = (pose['ankle'] - pose['knee']) / c['l2']
    tangent = upper + lower
    tangent /= np.linalg.norm(tangent)
    center = np.zeros((len(vs), 2))
    derivative = np.zeros_like(center)
    first = s <= .5
    center[first], derivative[first] = hermite(pose['hip'], pose['knee'], upper*c['l1'], tangent*c['l1'], s[first]*2)
    center[~first], derivative[~first] = hermite(pose['knee'], pose['ankle'], tangent*c['l2'], lower*c['l2'], (s[~first]-.5)*2)
    direction = derivative / np.linalg.norm(derivative, axis=1)[:, None]
    normal = np.c_[direction[:, 1], -direction[:, 0]]
    width = c['thigh_width'] + (c['shin_width']-c['thigh_width']) * ease(s)
    lateral = (us / image.width - .5)[None, :] * width[:, None]
    world = center[:, None, :] + lateral[:, :, None] * normal[:, None, :]
    destination = (world - np.array(REGION[:2])) * SS
    skin = np.zeros_like(canvas)
    for row in range(len(vs)-1):
        for col in range(len(us)-1):
            for triangle in [[(row,col),(row+1,col),(row,col+1)], [(row+1,col),(row+1,col+1),(row,col+1)]]:
                src = np.array([source[r,k] for r,k in triangle])
                dst = np.array([destination[r,k] for r,k in triangle])
                legacy.paint_textured_triangle(skin, image, src, dst)
    canvas[:] = skin + canvas * (1-skin[:, :, 3:4])

legacy.CFG = CFG
legacy.CYCLE = CYCLE
legacy.DUTY = DUTY
legacy.SS = SS
legacy.REGION = REGION
legacy.gait = gait
legacy.paint_skin_mesh = paint_skin_mesh
leg_layer = legacy.leg_layer

PETS = {role: [Image.open(BASE / (role+'-walk') / 'frames' / f'{i:03d}.png').convert('RGBA') for i in range(12)] for role in CFG}

def rope_y(image):
    alpha = np.asarray(image.getchannel('A'))[420:535, 439:442]
    ys, xs = np.where(alpha > 50)
    if len(ys) == 0:
        raise ValueError('Cannot locate leash at the join')
    return float(np.average(ys + 420, weights=alpha[ys, xs]))

ROPE_Y = {role: [rope_y(image) for image in images] for role, images in PETS.items()}

def shift_body(image, y):
    return image.convert('RGBa').transform(image.size, Image.Transform.AFFINE,
        (1,0,0,0,1,-y), Image.Resampling.BILINEAR).convert('RGBA')

def pet_layer(role, tick, body_y):
    index = int(tick / CYCLE * 12) % 12
    image = PETS[role][index]
    delta = ROPE_Y[role][0] + body_y - ROPE_Y[role][index]
    # Deform only the existing rope corridor. The pet, its paws and the long
    # sagging outer rope remain at their authored positions.
    data = np.asarray(image, dtype=np.float32) / 255.
    data[:, :, :3] *= data[:, :, 3:4]
    yy, xx = np.mgrid[400:640, 440:896]
    weight = 1-ease((xx-440)/120.)
    sampled = legacy.sample_texture(data, xx+.5, yy+.5-delta*weight)
    result = Image.fromarray(np.round(np.clip(sampled,0,1)*255).astype(np.uint8), 'RGBa').convert('RGBA')
    return result, index, float(delta)

def character(role, tick, high=None):
    if high is None:
        high, poses, root, body_y = leg_layer(role, tick, high_resolution=True)
    else:
        poses, root, body_y = gait(role, tick)
    canvas = Image.new('RGBA', (896,640))
    canvas.alpha_composite(shift_body(TORSO[role]['back'], body_y))
    legs = high.resize((REGION[2]-REGION[0], REGION[3]-REGION[1]), Image.Resampling.LANCZOS).convert('RGBA')
    canvas.alpha_composite(legs, REGION[:2])
    canvas.alpha_composite(shift_body(TORSO[role]['front'], body_y))
    canvas.paste((0,0,0,0), (440,400,896,640))
    pet, _, _ = pet_layer(role, tick, body_y)
    canvas.alpha_composite(pet, (440,400))
    return canvas, poses, root
