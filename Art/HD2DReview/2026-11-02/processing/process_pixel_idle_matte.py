"""Source-contour pixel idle matting. Never redraw poses or erode final alpha.

Uses the reviewed measured-plate/closed-form/color-unmix family, adapted to
this video's two fixed halves. Old dance/dog crops and timing are not reused.
"""
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor
import argparse, hashlib, json, os, sys, time

os.environ.setdefault('NUMBA_NUM_THREADS', '2')
os.environ.setdefault('OPENBLAS_NUM_THREADS', '2')
WORKSPACE = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(WORKSPACE / 'tools/python-matting'))
sys.path.insert(0, str(WORKSPACE / 'tools/python-animation'))
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from pymatting import estimate_alpha_cf, estimate_foreground_ml, ichol

ROOT = Path(__file__).resolve().parent / 'hd2d-characters-2026-11-02'
SPEC = {'dafeiyu': (64, 48, 496, 696), 'xiaobai': (704, 40, 1184, 696)}
VERSION = 'pixel-idle-source-cf-unmix-v2'

def read_rgb(name, index):
    return np.asarray(Image.open(ROOT / 'source-rgb' / f'{index:04d}.png').convert('RGB'))[SPEC[name][1]:SPEC[name][3], SPEC[name][0]:SPEC[name][2]]

def plate_and_trimap(rgb):
    c = rgb.astype(np.float64) / 255
    h, w = c.shape[:2]
    yy, xx = np.mgrid[-1:1:complex(h), -1:1:complex(w)]
    def basis(x, y): return np.stack([np.ones_like(x), x, y, x*x, x*y, y*y], axis=-1)
    sample = c[::6, ::6]
    green = sample[:, :, 1] - np.maximum(sample[:, :, 0], sample[:, :, 2]) > .15
    a = basis(xx[::6, ::6], yy[::6, ::6])[green]
    b = sample[green]
    weights = np.ones(len(a))
    for _ in range(5):
        coefficients = np.linalg.lstsq(a * weights[:, None], b * weights[:, None], rcond=None)[0]
        error = np.max(np.abs(a @ coefficients - b), axis=1)
        sigma = max(.003, float(np.median(error)) * 1.4826)
        weights = np.minimum(1, 2.5 * sigma / np.maximum(error, 1e-8))
    plate = np.clip(basis(xx, yy) @ coefficients, 0, 1)
    difference = np.max(np.abs(c - plate), axis=2)
    hsv = cv2.cvtColor(c.astype(np.float32), cv2.COLOR_RGB2HSV)
    screen_hue = (hsv[:, :, 0] > 70) & (hsv[:, :, 0] < 175) & (hsv[:, :, 1] > .15)
    # Erosion supplies confidence seeds ONLY. No delivered silhouette erosion.
    core = cv2.erode((~screen_hue).astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
    tri = np.full((h, w), .5, np.float64)
    tri[difference < .018] = 0
    tri[core] = 1
    blue = (c[:, :, 2] - c[:, :, 1] > .045) & (c[:, :, 2] - c[:, :, 0] > .065)
    warm = (c[:, :, 0] > .45) & (c[:, :, 0] - c[:, :, 1] > .025) & (c[:, :, 0] - c[:, :, 2] > .045)
    pale = (c.min(2) > .70) & (c.max(2)-c.min(2) < .16) & (c[:, :, 1]-np.maximum(c[:, :, 0], c[:, :, 2]) < .01)
    tri[blue | warm | pale] = 1
    # AI/compression darkens green in enclosed hair gaps. Bright-plate-only
    # seeds leave these opaque. These characters contain blue/purple, white,
    # and warm skin, so confidently green-dominant samples are screen seeds
    # even when dark. Blue/cyan tips (B >= G) remain untouched/unknown.
    screen = screen_hue & (hsv[:, :, 1] > .25) & (c[:, :, 1] > .15) & (c[:, :, 1]-np.maximum(c[:, :, 0], c[:, :, 2]) > .055)
    tri[screen] = 0
    return plate, tri

def alpha_path(name, index): return ROOT / name / 'alpha-v2' / f'{index:04d}.npz'

def solve_alpha(job):
    name, index = job
    cv2.setNumThreads(1)
    path = alpha_path(name, index)
    if path.exists(): return name, index, 0.
    start = time.perf_counter()
    rgb = read_rgb(name, index)
    _, tri = plate_and_trimap(rgb)
    def preconditioner(matrix):
        return ichol(matrix, max_nnz=min(8_000_000, max(100_000, matrix.nnz * 12)))
    alpha = estimate_alpha_cf(rgb.astype(np.float64)/255, tri, preconditioner=preconditioner,
        laplacian_kwargs={'epsilon': 1e-6}, cg_kwargs={'maxiter': 2000, 'rtol': 1e-5})
    np.savez_compressed(path, alpha=np.clip(alpha, 0, 1).astype(np.float32))
    return name, index, time.perf_counter()-start

def align_neighbor(rgb, neighbor, alpha):
    h, w = rgb.shape[:2]
    flow_w = min(256, w); flow_h = round(h * flow_w / w)
    current = cv2.cvtColor(cv2.resize(rgb, (flow_w, flow_h)), cv2.COLOR_RGB2GRAY)
    other = cv2.cvtColor(cv2.resize(neighbor, (flow_w, flow_h)), cv2.COLOR_RGB2GRAY)
    flow = cv2.calcOpticalFlowFarneback(current, other, None, .5, 3, 15, 3, 5, 1.2, 0)
    flow = cv2.resize(flow, (w, h), interpolation=cv2.INTER_LINEAR)
    flow[:, :, 0] *= w/flow_w; flow[:, :, 1] *= h/flow_h
    yy, xx = np.mgrid[:h, :w].astype(np.float32)
    mx, my = xx+flow[:, :, 0], yy+flow[:, :, 1]
    warped = cv2.remap(alpha.astype(np.float32), mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
    colors = cv2.remap(neighbor.astype(np.float32), mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
    weight = .12*np.exp(-np.mean((rgb.astype(np.float32)-colors)**2, axis=2)/100)
    return warped, weight

def finish_frame(job):
    name, index = job
    cv2.setNumThreads(1)
    target = ROOT / name / 'master-rgba-v2' / f'{index:04d}.png'
    if target.exists(): return name, index, 0.
    start = time.perf_counter()
    rgb = read_rgb(name, index)
    alpha = np.load(alpha_path(name, index))['alpha']
    total, weights = alpha.copy(), np.ones_like(alpha)
    for neighbor in (index-1, index+1):
        if 0 <= neighbor < 240:
            warped, weight = align_neighbor(rgb, read_rgb(name, neighbor), np.load(alpha_path(name, neighbor))['alpha'])
            total += warped*weight; weights += weight
    # Only stabilize uncertain edge alpha, never RGB poses or frame positions.
    band = cv2.dilate(((alpha > .001) & (alpha < .999)).astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
    alpha = np.where(band, total/weights, alpha).astype(np.float64)
    plate, tri = plate_and_trimap(rgb)
    alpha[tri == 0] = 0; alpha[tri == 1] = 1
    alpha[alpha < .002] = 0; alpha[alpha > .998] = 1
    c = rgb.astype(np.float64)/255
    fg = estimate_foreground_ml(c, alpha, n_small_iterations=10, n_big_iterations=4)
    physical = (c-(1-alpha[:, :, None])*plate)/np.maximum(alpha[:, :, None], .005)
    mix = np.clip((alpha-.02)/.18, 0, 1)[:, :, None]
    fg = np.clip(fg*(1-mix)+physical*mix, 0, 1)
    distance = cv2.distanceTransform((alpha > .98).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
    protected = distance > 6
    # Residual screen green correction at the outer edge; no contour change,
    # no nearest-neighbor RGB painting and no change to genuine cyan/blue.
    edge = np.clip((4-distance)/3, 0, 1)
    spill = np.maximum(fg[:, :, 1]-np.maximum(fg[:, :, 0], fg[:, :, 2]), 0)*edge
    fg[:, :, 1] -= spill
    fg[:, :, 0] += spill*.25; fg[:, :, 2] += spill*.25
    fg = np.clip(fg, 0, 1)
    fg[protected] = c[protected]
    fg[alpha == 0] = 0
    rgba = np.round(np.dstack([fg, alpha])*255).astype(np.uint8)
    assert np.array_equal(rgba[:, :, :3][protected], rgb[protected])
    half = np.zeros((720, 640, 4), np.uint8)
    x0, y0, x1, y1 = SPEC[name]; offset = 0 if name == 'dafeiyu' else 640
    half[y0:y1, x0-offset:x1-offset] = rgba
    Image.fromarray(half).save(target, compress_level=2)
    return name, index, time.perf_counter()-start

def qc_board(indices):
    width, height = 1440, len(indices)*370
    board = Image.new('RGB', (width, height), '#202331')
    d = ImageDraw.Draw(board); font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 17)
    for row, index in enumerate(indices):
        for c, name in enumerate(SPEC):
            im = Image.open(ROOT/name/'master-rgba-v2'/f'{index:04d}.png')
            for j, color in enumerate(((0, 0, 0), (255, 255, 255))):
                tile = Image.new('RGBA', im.size, (*color, 255)); tile.alpha_composite(im)
                tile = tile.convert('RGB'); tile.thumbnail((350, 330), Image.Resampling.NEAREST)
                x=(c*2+j)*360; y=row*370
                board.paste(tile, (x+(360-tile.width)//2, y+32))
                d.text((x+6, y+5), f'{name} #{index} / {"black" if j == 0 else "white"}', fill='white', font=font)
    board.save(ROOT/'matte-pilot-black-white-v2.png')

def main():
    p=argparse.ArgumentParser(); p.add_argument('--pilot', action='store_true'); p.add_argument('--workers', type=int, default=3)
    args=p.parse_args()
    source=json.loads((ROOT/'extraction-analysis.json').read_text(encoding='utf-8'))
    assert source['source_sha256'] == hashlib.sha256(Path(source['source']).read_bytes()).hexdigest()
    assert len(source['frames']) == 240, 'New source needs separate reviewed configuration'
    for name in SPEC:
        for part in ('alpha-v2', 'master-rgba-v2'): (ROOT/name/part).mkdir(parents=True, exist_ok=True)
    identity=ROOT/'matte-cache-identity-v2.json'
    expected={'version': VERSION, 'sourceSHA256': source['source_sha256'], 'fixedWorkCrops': {n:list(v) for n,v in SPEC.items()}}
    if identity.exists(): assert json.loads(identity.read_text(encoding='utf-8')) == expected
    else: identity.write_text(json.dumps(expected, indent=2), encoding='utf-8')
    indices=[0,28,90,199,239] if args.pilot else list(range(240))
    alpha_indices=sorted({j for i in indices for j in (i-1,i,i+1) if 0 <= j < 240})
    start=time.perf_counter()
    for function, frames, stage in ((solve_alpha, alpha_indices, 'alpha'), (finish_frame, indices, 'foreground')):
        jobs=[(name,i) for name in SPEC for i in frames]
        with ProcessPoolExecutor(max_workers=args.workers) as pool:
            for done, (name,index,seconds) in enumerate(pool.map(function,jobs),1):
                if args.pilot or done%24==0 or done==len(jobs):
                    record={'stage':stage,'done':done,'total':len(jobs),'character':name,'sourceIndex':index,'frameSeconds':round(seconds,2),'elapsedSeconds':round(time.perf_counter()-start,1)}
                    (ROOT/'matte-progress-v2.json').write_text(json.dumps(record),encoding='utf-8')
                    print(json.dumps(record),flush=True)
    qc_board([0,28,90,199,239])

if __name__ == '__main__': main()
