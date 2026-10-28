"""Full-range video decode and source-faithful alpha/foreground matting.

Source PTS and every decoded frame are retained. This tool deliberately has no
start/end clipping or speed option. The approved dog-walk exception is separate.
"""
import argparse
from concurrent.futures import ProcessPoolExecutor
from fractions import Fraction
import hashlib
import json
import os
from pathlib import Path
import time

os.environ.setdefault('NUMBA_NUM_THREADS', '2')
os.environ.setdefault('OPENBLAS_NUM_THREADS', '2')
import av
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

VERSION = 'full-video-cf-foreground-v1'


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''): h.update(block)
    return h.hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def load_report(out):
    return json.loads((Path(out) / 'extraction-analysis.json').read_text(encoding='utf-8'))


def analyze(source, out, clip_id, title):
    source, out = Path(source).resolve(), Path(out)
    sha = digest(source)
    previous=out/'extraction-analysis.json'
    if previous.exists() and load_report(out)['source_sha256']!=sha:
        raise ValueError('Use a new output directory for a different source; existing caches are preserved.')
    with av.open(str(source)) as container:
        stream = container.streams.video[0]
        tb = Fraction(stream.time_base)
        declared = Fraction(stream.duration or 0) * tb
        container_duration = Fraction(container.duration or 0, av.time_base)
        if max(declared, container_duration) > 20:
            raise ValueError(f'Video exceeds 20 seconds ({float(max(declared, container_duration)):.6f}); confirm scope first.')
        out.mkdir(parents=True, exist_ok=True)
        raw = out / 'source-rgb'; raw.mkdir(exist_ok=True)
        pts, durations, sizes = [], [], set()
        for i, frame in enumerate(container.decode(stream)):
            if frame.pts is None: raise ValueError(('Missing source PTS', i))
            if Fraction(frame.time_base) != tb: raise ValueError('Changing source time base')
            pts.append(frame.pts); durations.append(frame.duration or 0)
            bgr = frame.to_ndarray(format='bgr24'); sizes.add((frame.width, frame.height))
            if not cv2.imwrite(str(raw / f'{i:04}.png'), bgr, [cv2.IMWRITE_PNG_COMPRESSION, 1]):
                raise IOError(('PNG write failed', i))
            if i % 120 == 0: print('Decoded original frame', clip_id, i, flush=True)
        if not pts or len(sizes) != 1: raise ValueError('Empty video or changing frame size')
        if any(b <= a for a, b in zip(pts, pts[1:])): raise ValueError('Non-increasing presentation timestamps')
        native_end = max(pts[-1] + durations[-1], (stream.start_time or pts[0]) + (stream.duration or 0))
        # The original player holds its final picture through the container's
        # short audio tail. Preserve that presentation hold without new frames.
        end = max(Fraction(native_end), Fraction(pts[0]) + container_duration / tb)
        if end <= pts[-1]: raise ValueError('Missing final frame duration')
        durations = [b - a for a, b in zip(pts, pts[1:])] + [end - pts[-1]]
        total = Fraction(end - pts[0]) * tb
        if total > 20: raise ValueError('Decoded duration exceeds 20 seconds; confirm scope first.')
        width, height = next(iter(sizes))
        records = [dict(index=i, pts=p, duration_ticks=int(d) if d.denominator == 1 else float(d),
                        start_seconds=float((p - pts[0]) * tb), duration_ms=float(d * tb * 1000))
                   for i, (p, d) in enumerate(zip(pts, map(Fraction, durations)))]
    assert digest(source) == sha
    info = dict(id=clip_id, title=title, source=str(source), source_sha256=sha,
                source_bytes=source.stat().st_size, dimensions=[width, height],
                time_base=[tb.numerator, tb.denominator], first_pts=pts[0],
                frame_count=len(records), frames=records, duration_seconds=float(total),
                container_duration_seconds=float(container_duration),
                video_track_duration_seconds=float((native_end-pts[0])*tb),
                final_picture_container_hold_seconds=float((end-native_end)*tb),
                uniform_crop_xyxy=[0, 0, width, height], source_frame_range=[0, len(records)],
                full_original_range=True, dropped_frames=0, synthesized_frames=0,
                playback_speed=1, cache_version=VERSION)
    write_json(out / 'extraction-analysis.json', info)
    contact_board(out, rgba=False)
    print('FULL SOURCE', clip_id, len(records), 'frames,', float(total), 'seconds, duration ticks', sorted(set(durations)), flush=True)


def trimap(rgb):
    # The approved blue/cyan/white/skin character has no green costume.
    # Morphology defines solver confidence only; never the final silhouette.
    hsv = cv2.cvtColor(rgb.astype(np.float32) / 255, cv2.COLOR_RGB2HSV)
    green = (hsv[:, :, 0] >= 70) & (hsv[:, :, 0] <= 175) & (hsv[:, :, 1] > .15) & (hsv[:, :, 2] > .12)
    seed = (~green).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(seed, 8)
    good = np.flatnonzero(stats[:, cv2.CC_STAT_AREA] >= 64); good = good[good != 0]
    seed = np.isin(labels, good).astype(np.uint8)
    interior = cv2.erode(seed, np.ones((7, 7), np.uint8))
    outside = 1 - cv2.dilate(seed, np.ones((7, 7), np.uint8))
    tri = np.full(seed.shape, .5, np.float64); tri[outside > 0] = 0; tri[interior > 0] = 1
    c = rgb.astype(np.float32) / 255
    blue = (c[:, :, 2] - c[:, :, 1] > .18) & (c[:, :, 2] - c[:, :, 0] > .20) & (hsv[:, :, 0] >= 195) & (hsv[:, :, 0] <= 265)
    tri[blue] = 1
    pure = (c[:, :, 1] > .40) & (np.maximum(c[:, :, 0], c[:, :, 2]) < .07)
    screen = (hsv[:, :, 0] >= 85) & (hsv[:, :, 0] <= 165) & (hsv[:, :, 1] > .28) & (hsv[:, :, 2] > .10)
    tri[pure | screen] = 0
    return tri


def rgb_frame(out, index):
    image = cv2.imread(str(Path(out) / 'source-rgb' / f'{index:04}.png'))
    if image is None: raise IOError(('Missing source frame', index))
    return cv2.cvtColor(image, cv2.COLOR_BGR2RGB)


def alpha_task(args):
    out, index = args
    from pymatting import estimate_alpha_cf, ichol
    cv2.setNumThreads(1)
    path = Path(out) / 'alpha-solved' / f'{index:04}.npy'
    if path.exists(): return index, 0.
    then = time.perf_counter(); rgb = rgb_frame(out, index)
    def preconditioner(matrix):
        # PyMatting's generic default reserves 250M entries (~6 GB) per solve.
        # Bound sparse factor capacity for this edge band, not image resolution.
        return ichol(matrix, max_nnz=min(8_000_000, max(100_000, matrix.nnz * 12)))
    a = estimate_alpha_cf(rgb.astype(np.float64) / 255, trimap(rgb), preconditioner=preconditioner,
                         laplacian_kwargs={'epsilon': 1e-6}, cg_kwargs={'maxiter': 2000, 'rtol': 1e-5})
    np.save(path, np.clip(a, 0, 1).astype(np.float32))
    return index, time.perf_counter() - then


def aligned_alpha(rgb, neighbor, alpha):
    h, w = rgb.shape[:2]; flow_w = min(640, w); flow_h = round(h * flow_w / w)
    current = cv2.cvtColor(cv2.resize(rgb, (flow_w, flow_h)), cv2.COLOR_RGB2GRAY)
    other = cv2.cvtColor(cv2.resize(neighbor, (flow_w, flow_h)), cv2.COLOR_RGB2GRAY)
    flow = cv2.calcOpticalFlowFarneback(current, other, None, .5, 3, 19, 3, 5, 1.2, 0)
    flow = cv2.resize(flow, (w, h), interpolation=cv2.INTER_LINEAR)
    flow[:, :, 0] *= w / flow_w; flow[:, :, 1] *= h / flow_h
    yy, xx = np.mgrid[:h, :w].astype(np.float32); mx, my = xx + flow[:, :, 0], yy + flow[:, :, 1]
    warped = cv2.remap(alpha.astype(np.float32), mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
    colors = cv2.remap(neighbor.astype(np.float32), mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
    weight = .22 * np.exp(-np.mean((rgb.astype(np.float32) - colors) ** 2, axis=2) / 144)
    return warped, weight


def foreground_task(args):
    out, index, count = args
    from pymatting import estimate_foreground_ml
    cv2.setNumThreads(1)
    path = Path(out) / 'frames-source-rgba' / f'{index:04}.png'
    if path.exists(): return index, 0.
    then = time.perf_counter(); rgb = rgb_frame(out, index)
    a = np.load(Path(out) / 'alpha-solved' / f'{index:04}.npy')
    summed, weights = a.copy(), np.ones_like(a)
    for n in [index - 1, index + 1]:
        if not 0 <= n < count: continue  # No invented context beyond either endpoint.
        warped, weight = aligned_alpha(rgb, rgb_frame(out, n), np.load(Path(out) / 'alpha-solved' / f'{n:04}.npy'))
        summed += warped * weight; weights += weight
    band = cv2.dilate(((a > .001) & (a < .999)).astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
    stable = np.where(band, np.clip(summed / weights, 0, 1), a).astype(np.float64)
    confidence = trimap(rgb); stable[confidence == 0] = 0; stable[confidence == 1] = 1
    foreground = estimate_foreground_ml(rgb.astype(np.float64) / 255, stable, n_small_iterations=10, n_big_iterations=4)
    stable[stable < .002] = 0; stable[stable > .998] = 1; foreground[stable == 0] = 0
    rgba = np.dstack([np.round(np.clip(foreground, 0, 1) * 255).astype(np.uint8), np.round(stable * 255).astype(np.uint8)])
    Image.fromarray(rgba).save(path, compress_level=2)
    return index, time.perf_counter() - then


def matte(out, workers=2, pilot=False):
    out = Path(out); report = load_report(out)
    if digest(report['source']) != report['source_sha256']: raise ValueError('Source hash mismatch')
    identity=dict(source_sha256=report['source_sha256'],method=VERSION)
    identity_path=out/'cache-identity.json'
    if identity_path.exists() and json.loads(identity_path.read_text(encoding='utf-8'))!=identity:
        raise ValueError('Matting cache identity mismatch; use a new output directory.')
    write_json(identity_path,identity)
    count = report['frame_count']
    for name in ['alpha-solved', 'frames-source-rgba']: (out / name).mkdir(exist_ok=True)
    key = sorted(set([0, count // 4, count // 2, count * 3 // 4, count - 1]))
    frames = key if pilot else list(range(count))
    alpha_frames = sorted({n for i in frames for n in [i - 1, i, i + 1] if 0 <= n < count})
    for function, args, label in [(alpha_task, [(str(out), i) for i in alpha_frames], 'alpha'),
                                  (foreground_task, [(str(out), i, count) for i in frames], 'foreground')]:
        with ProcessPoolExecutor(max_workers=workers) as pool:
            for done, (index, seconds) in enumerate(pool.map(function, args), 1):
                if pilot or done % 24 == 0 or done == len(args):
                    print(report['id'], label, f'{done}/{len(args)}', 'source', index, 'seconds', round(seconds, 2), flush=True)
    contact_board(out, rgba=True, indices=frames if pilot else None)
    write_json(out / 'matting-report.json', dict(method=VERSION, source_sha256=report['source_sha256'],
               frame_count=count, processed_frames=frames, full_original_range=not pilot,
               duration_seconds=report['duration_seconds'], final_contour_erosion=False,
               generated_poses=False, foreground_and_alpha_solved_separately=True,
               aligned_neighbor_alpha_only=True, first_and_last_frames_preserved=True,
               status='pilot_review' if pilot else 'full_range_review'))
    assert digest(report['source']) == report['source_sha256']


def contact_board(out, rgba=False, indices=None):
    out = Path(out); report = load_report(out); count = report['frame_count']
    ticks = indices or sorted(set(round(i * (count - 1) / 15) for i in range(16)))
    board = Image.new('RGB', (1280, ((len(ticks) + 3) // 4) * 230), '#192033'); d = ImageDraw.Draw(board)
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 15) if Path('C:/Windows/Fonts/msyh.ttc').exists() else ImageFont.load_default()
    for j, tick in enumerate(ticks):
        frame = Image.open(out / ('frames-source-rgba' if rgba else 'source-rgb') / f'{tick:04}.png').convert('RGBA')
        frame.thumbnail((316, 190), Image.Resampling.LANCZOS)
        x, y = (j % 4) * 320, (j // 4) * 230
        d.text((x + 6, y + 4), f'{tick}/{count} · {report["frames"][tick]["start_seconds"]:.3f}s', font=font, fill='white')
        board.paste(frame, (x + (320 - frame.width) // 2, y + 32), frame)
    board.save(out / ('matted-contact.png' if rgba else 'source-contact.png'))


def main():
    p = argparse.ArgumentParser(); commands = p.add_subparsers(dest='command', required=True)
    a = commands.add_parser('analyze'); a.add_argument('source', type=Path); a.add_argument('out', type=Path)
    a.add_argument('--id', required=True); a.add_argument('--title', required=True)
    m = commands.add_parser('matte'); m.add_argument('out', type=Path); m.add_argument('--workers', type=int, default=2); m.add_argument('--pilot', action='store_true')
    args = p.parse_args()
    if args.command == 'analyze': analyze(args.source, args.out, args.id, args.title)
    else: matte(args.out, args.workers, args.pilot)


if __name__ == '__main__': main()
