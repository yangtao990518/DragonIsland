"""Full-source survivor video import, fixed-cell matting and lossless atlases.

Source decode/PTS lives in process_daily_video.analyze. No clipping, speed or
interpolation options. All paths are explicit and work on another computer.
"""
import argparse
from concurrent.futures import ProcessPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import time

os.environ.setdefault('NUMBA_NUM_THREADS', '2')
os.environ.setdefault('OPENBLAS_NUM_THREADS', '1')
import cv2
import numpy as np
from PIL import Image, ImageDraw

VERSION = 'survivor-fixed-cells-cf-screen-foreground-v2'
ALPHA_VERSION = 'survivor-fixed-cells-cf-foreground-v1'
RGBA_FOLDER = 'rgba-v2'
ACTORS = [
    ('dafeiyu-run', [656, 14, 992, 369], .43, 'actor'),
    ('demon-run', [288, 398, 626, 706], .43, 'actor'),
    ('mushroom-run', [656, 398, 992, 706], .50, 'actor'),
]


def dump(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def prepare(work):
    work = Path(work)
    entries = []
    for source_id in ('actors', 'thunder'):
        report = load(work / source_id / 'extraction-analysis.json')
        if report['dimensions'] != [1280, 720]:
            raise ValueError('Review fixed video cells for this source resolution first')
        if sha(report['source']) != report['source_sha256']:
            raise ValueError('Source has changed')
        clips = ACTORS if source_id == 'actors' else [
            (f'thunder-{i+1}', box, .5, 'light') for i, box in enumerate([
                [0, 0, 427, 360], [427, 0, 853, 360], [853, 0, 1280, 360],
                [213, 360, 640, 720], [640, 360, 1067, 720]])]
        for clip_id, box, pivot_x, kind in clips:
            target = work / 'clips' / clip_id
            target.mkdir(parents=True, exist_ok=True)
            identity = {'version': ALPHA_VERSION, 'source_sha256': report['source_sha256'], 'crop': box}
            if (target / 'identity.json').exists() and load(target / 'identity.json') != identity:
                raise ValueError('Use a new directory for changed processing settings')
            dump(target / 'identity.json', identity)
            for name in ('rgb', 'alpha', RGBA_FOLDER):
                (target / name).mkdir(exist_ok=True)
            for frame in report['frames']:
                dest = target / 'rgb' / f'{frame["index"]:04d}.png'
                if dest.exists():
                    continue
                image = Image.open(work / source_id / 'source-rgb' / dest.name)
                image.crop(box).save(dest, compress_level=1)
            record = {'id': clip_id, 'source': source_id, 'kind': kind, 'source_crop': box,
                      'pivot_x': pivot_x, 'frame_count': report['frame_count'],
                      'duration_ms': report['duration_seconds'] * 1000, 'frames': report['frames']}
            dump(target / 'clip.json', record)
            entries.append(record)
    dump(work / 'clips.json', entries)
    print('Prepared', len(entries), 'fixed regions, all original frames', flush=True)


def trimap(rgb, light=False):
    c = rgb.astype(np.float64) / 255
    r, g, b = c[:, :, 0], c[:, :, 1], c[:, :, 2]
    dominant = g - np.maximum(r, b)
    candidate = (dominant < .12).astype(np.uint8)
    interior = cv2.erode(candidate, np.ones((3, 3), np.uint8)) > 0
    outside = cv2.dilate(candidate, np.ones((11, 11), np.uint8)) == 0
    tri = np.full(g.shape, .5, dtype=np.float64)
    tri[outside] = 0
    tri[interior] = 1
    # Confidence seeds only; no operation erodes the final alpha contour.
    pure_screen = (g > .3) & (np.maximum(r, b) < .10)
    tri[pure_screen] = 0
    if light:
        # Violet/white light cores anchor alpha; blue halos remain unknown.
        core = ((b > .65) & (b > g + .35) & (r > .3)) | (np.minimum(r, np.minimum(g, b)) > .91)
        tri[core] = 1
    else:
        blue = (b > .4) & (b > g + .2)
        tri[blue] = 1
    if not np.any(tri == 1) or not np.any(tri == 0):
        raise ValueError('Cannot identify foreground/background confidence')
    return tri


def alpha_task(args):
    directory, index, light = args
    path = Path(directory)
    dest = path / 'alpha' / f'{index:04d}.npy'
    if dest.exists():
        return 0.
    from pymatting import estimate_alpha_cf, ichol
    cv2.setNumThreads(1)
    began = time.perf_counter()
    rgb = np.array(Image.open(path / 'rgb' / f'{index:04d}.png').convert('RGB'))
    def preconditioner(matrix):
        return ichol(matrix, max_nnz=min(4_000_000, max(100_000, matrix.nnz * 12)))
    alpha = estimate_alpha_cf(rgb.astype(np.float64) / 255, trimap(rgb, light),
                             preconditioner=preconditioner,
                             laplacian_kwargs={'epsilon': 1e-6},
                             cg_kwargs={'maxiter': 2000, 'rtol': 1e-5})
    np.save(dest, np.clip(alpha, 0, 1).astype(np.float32))
    return time.perf_counter() - began


def foreground_task(args):
    directory, index, count, light = args
    from pymatting import estimate_foreground_ml
    from process_daily_video import aligned_alpha
    cv2.setNumThreads(1)
    path = Path(directory)
    dest = path / RGBA_FOLDER / f'{index:04d}.png'
    if dest.exists():
        return 0.
    began = time.perf_counter()
    rgb = np.array(Image.open(path / 'rgb' / f'{index:04d}.png').convert('RGB'))
    alpha = np.load(path / 'alpha' / f'{index:04d}.npy')
    total, weights = alpha.copy(), np.ones_like(alpha)
    for neighbor in (index-1, index+1):
        if 0 <= neighbor < count:
            other = np.array(Image.open(path / 'rgb' / f'{neighbor:04d}.png').convert('RGB'))
            warped, weight = aligned_alpha(rgb, other, np.load(path / 'alpha' / f'{neighbor:04d}.npy'))
            total += warped * weight
            weights += weight
    band = cv2.dilate(((alpha > .001) & (alpha < .999)).astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
    stable = np.where(band, np.clip(total / weights, 0, 1), alpha).astype(np.float64)
    confidence = trimap(rgb, light)
    stable[confidence == 0] = 0
    stable[confidence == 1] = 1
    colors = rgb.astype(np.float64) / 255
    foreground, background = estimate_foreground_ml(colors, stable, return_background=True,
                                                    n_small_iterations=10, n_big_iterations=4)
    # Known green screen, and these reviewed blue/violet/orange actors contain
    # no green material. Bound alpha by C=aF+(1-a)B with Fg<=max(Fr,Fb).
    # This fixes overestimated edge alpha without eroding a final contour or
    # painting neighbouring colors onto the source. Keep all original pixels.
    cap_r = 1 - (colors[:,:,1]-colors[:,:,0]) / np.maximum(.01, background[:,:,1]-background[:,:,0])
    cap_b = 1 - (colors[:,:,1]-colors[:,:,2]) / np.maximum(.01, background[:,:,1]-background[:,:,2])
    cap = np.clip(np.maximum(cap_r, cap_b), 0, 1)
    stable = np.minimum(stable, cap)
    # Solve foreground with the estimated local screen fixed, regularized by
    # the PyMatting ML foreground prior; no crude channel clamp/despill.
    a = stable[:,:,None]
    regularization = 1e-5
    foreground = (a*(colors-(1-a)*background) + regularization*foreground) / (a*a+regularization)
    stable[stable < .002] = 0
    stable[stable > .998] = 1
    foreground[stable == 0] = 0
    rgba = np.dstack([np.rint(np.clip(foreground, 0, 1) * 255).astype('uint8'),
                      np.rint(stable * 255).astype('uint8')])
    Image.fromarray(rgba).save(dest, compress_level=2)
    return time.perf_counter() - began


def matte(work, workers=3, pilot=False):
    work = Path(work)
    clips = load(work / 'clips.json')
    tasks = []
    for clip in clips:
        path = work / 'clips' / clip['id']
        (path / RGBA_FOLDER).mkdir(exist_ok=True)
        count = clip['frame_count']
        indices = sorted({0, count // 4, count // 2, count * 3 // 4, count - 1}) if pilot else list(range(count))
        light = clip['kind'] == 'light'
        tasks.append((clip, path, indices, light))
    with ProcessPoolExecutor(max_workers=workers) as pool:
        for clip, path, indices, light in tasks:
            context = sorted({n for i in indices for n in (i-1, i, i+1) if 0 <= n < clip['frame_count']})
            for j, _ in enumerate(pool.map(alpha_task, [(str(path), i, light) for i in context]), 1):
                if j % 40 == 0 or j == len(context):
                    print(clip['id'], 'alpha', j, '/', len(context), flush=True)
            for j, _ in enumerate(pool.map(foreground_task, [(str(path), i, clip['frame_count'], light) for i in indices]), 1):
                if j % 40 == 0 or j == len(indices):
                    print(clip['id'], 'foreground', j, '/', len(indices), flush=True)
    board = Image.new('RGB', (1200, len(clips) * 210), '#111827')
    draw = ImageDraw.Draw(board)
    for row, (clip, path, indices, _) in enumerate(tasks):
        picked = [indices[round(i * (len(indices)-1) / 4)] for i in range(5)]
        for col, index in enumerate(picked):
            im = Image.open(path / RGBA_FOLDER / f'{index:04d}.png').convert('RGBA')
            im.thumbnail((230, 175))
            x, y = col * 240, row * 210
            draw.text((x+5, y+3), f'{clip["id"]} {index}', fill='white')
            board.paste(im, (x+(240-im.width)//2, y+24), im)
    board.save(work / ('pilot-matted-v2.png' if pilot else 'full-matted-v2.png'))
    dump(work / ('pilot-matting-v2.json' if pilot else 'full-matting-v2.json'),
         {'method': VERSION, 'full_original_range': not pilot, 'rgba_folder': RGBA_FOLDER,
          'foreground_and_alpha_solved_separately': True, 'fixed_local_screen_color_constraint': True,
          'contour_erosion': False, 'generated_poses': False})


def pack(work, output):
    work, output = Path(work), Path(output)
    output.mkdir(parents=True, exist_ok=True)
    records = []
    sources = {}
    (output / 'Sources').mkdir(exist_ok=True)
    import shutil
    for name in ('actors', 'thunder'):
        report = load(work / name / 'extraction-analysis.json')
        if sha(report['source']) != report['source_sha256']:
            raise ValueError('Source hash mismatch')
        dest = output / 'Sources' / (name + '.mp4')
        if not dest.exists(): shutil.copyfile(report['source'], dest)
        if sha(dest) != report['source_sha256']: raise ValueError('Archived source mismatch')
        sources[name] = {'path': 'Sources/' + dest.name, 'sha256': sha(dest),
                         'original_filename': Path(report['source']).name,
                         'frame_count': report['frame_count'], 'duration_ms': report['duration_seconds']*1000,
                         'time_base': report['time_base'], 'full_original_range': True}
    for clip in load(work / 'clips.json'):
        path = work / 'clips' / clip['id']
        images = []
        union = None
        for i in range(clip['frame_count']):
            im = Image.open(path / RGBA_FOLDER / f'{i:04d}.png').convert('RGBA')
            images.append(im)
            b = im.getchannel('A').getbbox()
            if b: union = b if union is None else (min(union[0],b[0]),min(union[1],b[1]),max(union[2],b[2]),max(union[3],b[3]))
        if union is None: raise ValueError('Empty clip')
        full_w, full_h = images[0].size
        box = [max(0,union[0]-8), max(0,union[1]-8), min(full_w,union[2]+8), min(full_h,union[3]+8)]
        width, height = box[2]-box[0], box[3]-box[1]
        # Exactly one crop across the WHOLE clip, never recenter individual frames.
        cells, unique, indices = {}, [], []
        for im in images:
            im = im.crop(box)
            digest = hashlib.sha256(im.tobytes()).hexdigest()
            if digest not in cells:
                cells[digest] = len(unique); unique.append(im)
            indices.append(cells[digest])
        grid = [max(1, min(4, 1024 // width)), max(1, min(4, 1024 // height))]
        capacity = grid[0] * grid[1]
        pages = []
        folder = output / clip['id']; folder.mkdir(exist_ok=True)
        for begin in range(0, len(unique), capacity):
            atlas = Image.new('RGBA', (width*grid[0], height*grid[1]))
            for offset, im in enumerate(unique[begin:begin+capacity]):
                atlas.paste(im, ((offset%grid[0])*width, (offset//grid[0])*height))
            dest = folder / f'atlas-{len(pages):02d}.webp'
            atlas.save(dest, lossless=True, method=6)
            pages.append({'file': f'{clip["id"]}/{dest.name}', 'sha256': sha(dest)})
        # Ground/contact pivot stays constant across every source frame.
        if clip['kind'] == 'actor':
            pivot_source = [full_w * clip['pivot_x'], union[3]-2]
        else:
            pivot_source = [full_w*.5, union[3]-max(8,(union[3]-union[1])*.1)]
        pivot = [(pivot_source[0]-box[0])/width, 1-(pivot_source[1]-box[1])/height]
        frames = [{'source_index': f['index'], 'cell': indices[f['index']],
                   'start_ms': f['start_seconds']*1000, 'duration_ms': f['duration_ms']}
                  for f in clip['frames']]
        record = {'id': clip['id'], 'kind': clip['kind'], 'source': clip['source'],
                  'source_crop_xyxy': clip['source_crop'], 'uniform_trim_xyxy': box,
                  'cell_size': [width, height], 'grid': grid, 'pivot': pivot,
                  'frame_count': len(frames), 'unique_count': len(unique),
                  'duration_ms': clip['duration_ms'], 'pages': pages, 'frames': frames}
        records.append(record)
        print('PACKED', clip['id'], len(frames), 'frames', len(unique), 'unique', [width,height], len(pages), 'pages', flush=True)
    dump(output / 'manifest.json', {'schema_version': 1, 'method': VERSION, 'sources': sources,
                                    'clips': records, 'dropped_frames': 0, 'synthesized_frames': 0,
                                    'playback_speed': 1, 'final_contour_erosion': False,
                                    'foreground_and_alpha_solved_separately': True})


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['prepare', 'matte', 'pack'])
    parser.add_argument('work', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--workers', type=int, default=3)
    parser.add_argument('--pilot', action='store_true')
    args = parser.parse_args()
    if args.command == 'prepare': prepare(args.work)
    elif args.command == 'matte': matte(args.work, args.workers, args.pilot)
    elif args.output: pack(args.work, args.output)
    else: parser.error('--output required for pack')
