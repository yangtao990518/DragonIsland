"""Keep full-resolution extracted frames in lossless source atlases, with PTS."""
import argparse
import json
import math
from pathlib import Path
import shutil
from fractions import Fraction
import av
import numpy as np
from PIL import Image
from process_daily_video import digest, load_report, write_json

ROOT = Path(__file__).resolve().parents[1]
GRID = (3, 4)


def package(out):
    out = Path(out); report = load_report(out); count = report['frame_count']
    source_frames = out / 'frames-source-rgba'
    if len(list(source_frames.glob('*.png'))) != count: raise ValueError('All source frames must be matted before packaging')
    union = None
    for i in range(count):
        with Image.open(source_frames / f'{i:04}.png') as im:
            box = im.getchannel('A').getbbox()
            if box is None: raise ValueError(('Empty foreground', i))
            union = box if union is None else (min(union[0], box[0]), min(union[1], box[1]), max(union[2], box[2]), max(union[3], box[3]))
    width, height = report['dimensions']
    crop = [max(0, union[0]-12), max(0, union[1]-12), min(width, union[2]+12), min(height, union[3]+12)]
    w, h = crop[2]-crop[0], crop[3]-crop[1]
    destination = ROOT / 'Art/VideoActions' / report['id']; destination.mkdir(parents=True, exist_ok=True)
    atlas_dir = destination / 'atlases'; atlas_dir.mkdir(exist_ok=True)
    records, atlases = [], []
    for start in range(0, count, GRID[0]*GRID[1]):
        sheet = Image.new('RGBA', (w*GRID[0], h*GRID[1])); expected = []
        for i in range(start, min(start+GRID[0]*GRID[1], count)):
            image = Image.open(source_frames / f'{i:04}.png').convert('RGBA')
            native_sha = __import__('hashlib').sha256(image.tobytes()).hexdigest()
            image = image.crop(crop); cell = i-start; x, y = cell%GRID[0]*w, cell//GRID[0]*h
            sheet.paste(image, (x,y)); expected.append((i, native_sha))
            records.append(dict(report['frames'][i], atlas=len(atlases), rect=[x,y,w,h], rgba_sha256=native_sha))
        relative = f'atlases/{len(atlases):03}.webp'; path = destination / relative
        sheet.save(path, 'WEBP', lossless=True, exact=True, method=4)
        # Reconstruct native transparent canvases and verify every pixel after
        # lossless compression, including all hair/tail/foot edge pixels.
        with Image.open(path) as restored:
            for i, sha in expected:
                cell = i-start; x, y = cell%GRID[0]*w, cell//GRID[0]*h
                original = Image.new('RGBA',(width,height)); original.paste(restored.crop((x,y,x+w,y+h)),crop[:2])
                assert __import__('hashlib').sha256(original.tobytes()).hexdigest() == sha, ('Native RGBA mismatch', i)
        atlases.append(dict(path=relative, sha256=digest(path), bytes=path.stat().st_size))
        if len(atlases)%10==0: print('Lossless source atlas',report['id'],len(atlases),flush=True)
    shutil.copy2(report['source'], destination / 'source.mp4')
    assert digest(destination/'source.mp4') == report['source_sha256']
    manifest = dict(schemaVersion=1, id=report['id'], characterID='dafeiyu', action=report['id'].split('-')[-1],
                    title=report['title'], sourceVideo='source.mp4', sourceFilename=Path(report['source']).name,
                    sourceSHA256=report['source_sha256'], sourceSize=report['dimensions'],
                    timeBase=report['time_base'], firstPTS=report['first_pts'], frames=records,
                    frameCount=count, durationMs=report['duration_seconds']*1000,
                    videoTrackDurationMs=report['video_track_duration_seconds']*1000,
                    finalPictureContainerHoldMs=report['final_picture_container_hold_seconds']*1000,
                    cellSize=[w,h], grid=list(GRID), uniformCrop=crop, atlases=atlases,
                    nativeResolution=True, lossless=True, fullOriginalRange=True,
                    generatedPoses=False, upscaled=False, playback='once_then_hold',
                    method='closed-form alpha + aligned adjacent alpha + multilevel foreground recovery')
    write_json(destination/'manifest.json',manifest)
    print('Packaged every native frame',report['id'],count,crop,flush=True)
    return manifest


def preview(out):
    out=Path(out); report=load_report(out); path=out/'full-original-timing.mp4'
    scale=48_000_000; tb=Fraction(*report['time_base'])
    source_pts=[Fraction(f['pts']-report['first_pts'])*tb for f in report['frames']]
    end=Fraction(str(report['duration_seconds']))
    pts=[round(p*scale) for p in source_pts]; ends=pts[1:]+[round(end*scale)]
    durations=dict(zip(pts,[b-a for a,b in zip(pts,ends)]))
    with av.open(str(path),'w',options={'video_track_timescale':str(scale),'movflags':'+faststart'}) as movie:
        stream=movie.add_stream('libx264',rate=60); stream.width,stream.height=report['dimensions']
        stream.pix_fmt='yuv420p'; stream.time_base=Fraction(1,scale); stream.codec_context.time_base=Fraction(1,scale)
        stream.codec_context.max_b_frames=0;stream.options={'crf':'18','preset':'medium'}
        def mux(packets):
            for packet in packets:
                tick=round(Fraction(packet.pts)*packet.time_base*scale)
                packet.duration=round(Fraction(durations[tick],scale)/packet.time_base)
                movie.mux(packet)
        for i,tick in enumerate(pts):
            art=Image.open(out/'frames-source-rgba'/f'{i:04}.png').convert('RGBA')
            background=Image.new('RGBA',art.size,'#192033');background.alpha_composite(art)
            frame=av.VideoFrame.from_ndarray(np.asarray(background.convert('RGB')),format='rgb24')
            frame.pts=tick; frame.time_base=Fraction(1,scale); mux(stream.encode(frame))
        mux(stream.encode())
    decoded_count=0
    with av.open(str(path)) as movie:
        stream=movie.streams.video[0]
        actual=float(stream.duration*stream.time_base)
        assert abs(actual-report['duration_seconds'])<.000002,(actual,report['duration_seconds'])
        for i,frame in enumerate(movie.decode(stream)):
            assert abs(float(frame.pts*frame.time_base)-float(source_pts[i]))<.000002
            decoded_count+=1
        assert decoded_count==report['frame_count']
    write_json(out/'preview-verification.json',dict(frames=decoded_count,duration_seconds=actual,sourcePTSMatch=True,fullyDecoded=True,sha256=digest(path)))
    print('Preview verified at original PTS',path,actual,flush=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('out',type=Path);p.add_argument('--preview-only',action='store_true')
    args=p.parse_args()
    if not args.preview_only:package(args.out)
    preview(args.out)
