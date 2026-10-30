"""Import a full scene without matting or synthesized frames; retain source PTS.

Native PNGs are local working files. The original MP4, crop, RGB frame hashes,
full timing and one App JPEG per original frame are portable source assets.
Normal builds only copy the reviewed App frames, never decode the MP4.
"""
import argparse
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'Art/HomeScenes/dafeiyu-touch'
DEST = ROOT / 'App/Resources/HomeScenes'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def movie_duration(path):
    """ISO BMFF mvhd duration, including the original short audio tail."""
    data = path if isinstance(path, bytes) else Path(path).read_bytes()
    def boxes(start, end):
        while start + 8 <= end:
            size, kind = struct.unpack_from('>I4s', data, start)
            header = 8
            if size == 1:
                size = struct.unpack_from('>Q', data, start + 8)[0]; header = 16
            if size == 0: size = end - start
            if size < header or start + size > end: raise ValueError('Invalid MP4 atom')
            yield kind, start + header, start + size
            start += size
    for kind, start, end in boxes(0, len(data)):
        if kind == b'moov':
            for child, a, b in boxes(start, end):
                if child == b'mvhd':
                    offset = a + (20 if data[a] == 1 else 12)
                    scale = struct.unpack_from('>I', data, offset)[0]
                    duration = struct.unpack_from('>Q' if data[a] == 1 else '>I', data, offset + 4)[0]
                    return Fraction(duration, scale)
    raise ValueError('Missing MP4 movie duration')


def store_source_parts(source):
    data = Path(source).read_bytes(); parts = []
    directory = ART / 'SourceParts'; directory.mkdir(parents=True, exist_ok=True)
    size = 4 * 1024 * 1024
    for i, start in enumerate(range(0, len(data), size)):
        path = directory / f'source-{i:03d}.bin'
        path.write_bytes(data[start:start + size])
        parts.append({'file': 'SourceParts/' + path.name, 'sha256': sha(path), 'bytes': path.stat().st_size})
    return parts


def source_data(info):
    chunks = []
    for part in info['sourceParts']:
        path = ART / part['file']
        if sha(path) != part['sha256']: raise ValueError('Source chunk digest mismatch')
        chunks.append(path.read_bytes())
    data = b''.join(chunks)
    if hashlib.sha256(data).hexdigest() != info['sourceSHA256']: raise ValueError('Reassembled source digest mismatch')
    return data


def import_video(source, ffmpeg, native_dir):
    source = Path(source).resolve(); native_dir = Path(native_dir)
    duration = movie_duration(source)
    if not 0 < duration <= 20: raise ValueError('Full video must be at most 20 seconds')
    original_sha = sha(source)
    if (ART / 'manifest.json').exists():
        previous = json.loads((ART / 'manifest.json').read_text(encoding='utf-8'))
        if previous['sourceSHA256'] != original_sha: raise ValueError('Refuse to overwrite another source')
    native_dir.mkdir(parents=True, exist_ok=True)
    crop = [1176, 0, 1854, 2160]  # User approved v3 on 2026-10-30.
    expression = f'crop={crop[2]}:{crop[3]}:{crop[0]}:{crop[1]}'
    command = [str(ffmpeg), '-hide_banner', '-loglevel', 'error', '-i', str(source), '-map', '0:v:0']
    print('Decode all native frames with the approved fixed crop', flush=True)
    subprocess.run(command + ['-vf', expression, '-pix_fmt', 'rgb24', '-fps_mode', 'passthrough',
                              '-start_number', '0', '-compression_level', '3', '-y', str(native_dir / '%04d.png')], check=True)
    result = subprocess.run(command + ['-vf', expression, '-pix_fmt', 'rgb24', '-c:v', 'rawvideo',
        '-fps_mode', 'passthrough', '-enc_time_base', 'demux', '-f', 'framemd5', '-'], capture_output=True, check=True)
    text = result.stdout.decode('utf-8')
    (native_dir / 'source-timing.framemd5').write_text(text, encoding='utf-8')
    tb = Fraction(next(line.split(':', 1)[1].strip() for line in text.splitlines() if line.startswith('#tb')))
    rows = [[part.strip() for part in line.split(',')] for line in text.splitlines() if line and not line.startswith('#')]
    first_pts = int(rows[0][2]); frames = []
    runtime_dir = ART / 'Frames'; runtime_dir.mkdir(parents=True, exist_ok=True)
    for index, row in enumerate(rows):
        pts, packet_duration = int(row[2]), int(row[3])
        start = (pts - first_pts) * tb
        end = (int(rows[index + 1][2]) - first_pts) * tb if index + 1 < len(rows) else max(duration, start + packet_duration * tb)
        if end <= start: raise ValueError('Invalid source PTS')
        path = native_dir / f'{index:04d}.png'
        with Image.open(path) as image:
            image = image.convert('RGB')
            if image.size != tuple(crop[2:]): raise ValueError('Unexpected native dimensions')
            pixel_hash = hashlib.md5(image.tobytes()).hexdigest()
            if pixel_hash != row[5]: raise ValueError(f'Native decoded pixels differ: {index}')
            name = f'DafeiyuHomeTouch_{index:04d}.jpg'
            image.resize((1030, 1200), Image.Resampling.LANCZOS).save(runtime_dir / name, quality=90, subsampling=0, optimize=True)
        frames.append(dict(index=index, pts=pts, startMs=float(start * 1000), durationMs=float((end - start) * 1000),
                           nativeRGBMD5=pixel_hash, file='Frames/' + name, sha256=sha(runtime_dir / name)))
        if index % 60 == 0: print('Verified native RGB and prepared App frame', index, '/', len(rows), flush=True)
    if sha(source) != original_sha: raise ValueError('Original source changed')
    source_parts = store_source_parts(source)
    write_json(ART / 'manifest.json', dict(version=1, id='dafeiyu-home-touch', characterID='dafeiyu',
        title='窗边触屏', sourceVideo='source.mp4', sourceSHA256=original_sha, sourceBytes=source.stat().st_size,
        sourceParts=source_parts,
        sourceSize=[3840, 2160], uniformCrop=crop, nativeFrameSize=crop[2:], runtimeFrameSize=[1030, 1200],
        timeBase=[tb.numerator, tb.denominator], firstPTS=first_pts, frameCount=len(frames),
        durationMs=frames[-1]['startMs'] + frames[-1]['durationMs'], containerDurationMs=float(duration * 1000),
        fullOriginalRange=True, playbackSpeed=1, droppedFrames=0, synthesizedFrames=0,
        frames=frames, playback='once-on-entry-and-tap; hold final frame; no forced loop',
        audio='Source audio preserved in source.mp4; image-sequence home scene is silent',
        framing='Approved v3: legs, right foot and headphones visible; left fingertips leave frame at maximum reach'))
    prepare()
    print('Complete:', len(frames), 'frames;', float(duration), 'seconds;', sum(p.stat().st_size for p in runtime_dir.glob('*.jpg')), 'App bytes', flush=True)


def prepare():
    manifest_path = ART / 'manifest.json'
    if not manifest_path.exists(): return
    info = json.loads(manifest_path.read_text(encoding='utf-8'))
    DEST.mkdir(parents=True, exist_ok=True)
    for frame in info['frames']:
        source = ART / frame['file']
        if sha(source) != frame['sha256']: raise ValueError('App source frame digest mismatch')
        shutil.copyfile(source, DEST / source.name)
    clip = dict(id=info['id'], characterID=info['characterID'], title=info['title'], frameCount=info['frameCount'],
        frameSize=info['runtimeFrameSize'], durationMs=info['durationMs'],
        frameNames=[Path(f['file']).stem for f in info['frames']],
        frameStartMs=[f['startMs'] for f in info['frames']], frameDurationsMs=[f['durationMs'] for f in info['frames']])
    write_json(DEST / 'HomeScenes.json', [clip])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path)
    parser.add_argument('--ffmpeg', type=Path)
    parser.add_argument('--native-dir', type=Path)
    parser.add_argument('--restore-source', type=Path, help='Reassemble the exact original MP4 from portable chunks')
    args = parser.parse_args()
    if args.restore_source:
        info = json.loads((ART / 'manifest.json').read_text(encoding='utf-8'))
        data = source_data(info)
        if args.restore_source.exists() and sha(args.restore_source) != info['sourceSHA256']:
            raise ValueError('Refuse to overwrite a different existing file')
        args.restore_source.parent.mkdir(parents=True, exist_ok=True)
        args.restore_source.write_bytes(data)
        print('Original MP4 restored with verified SHA256')
    elif args.source:
        if not args.ffmpeg or not args.native_dir: parser.error('Import requires --ffmpeg and --native-dir')
        import_video(args.source, args.ffmpeg, args.native_dir)
    else: prepare()
