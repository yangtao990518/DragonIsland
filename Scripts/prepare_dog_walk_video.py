"""Encode the accepted alpha clip as a real, silent H.264 comparison video.

Uses the same 60 FPS playhead, complete round trip, dimensions and black stage
as the app's image-sequence preview. No generated poses or green-screen plate.
Requires ffmpeg only when rebuilding this committed app-only MP4.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from PIL import Image
from prepare_motion import ROOT, daily_leg, load_daily_art


def encode(ffmpeg, output):
    clip = load_daily_art('dafeiyu')['pet_walk']
    frames = daily_leg('pet_walk', 'right', clip, fps=60) + daily_leg('pet_walk', 'left', clip, fps=60)
    art = {f'Motion_pet_walk_{direction}_{i:03}': image.resize((560, 390), Image.Resampling.LANCZOS)
           for direction in ('right', 'left') for i, image in enumerate(clip[direction])}
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [ffmpeg, '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pixel_format', 'rgb24',
               '-video_size', '900x480', '-framerate', '60', '-i', 'pipe:0', '-an',
               '-c:v', 'libx264', '-preset', 'medium', '-crf', '19', '-pix_fmt', 'yuv420p',
               '-movflags', '+faststart', str(output)]
    with subprocess.Popen(command, stdin=subprocess.PIPE) as process:
        for frame in frames:
            stage = Image.new('RGBA', (900, 480), (0, 0, 0, 255))
            stage.alpha_composite(art[frame['asset']], (170 + frame['x'] * 5, 75))
            process.stdin.write(stage.convert('RGB').tobytes())
        process.stdin.close()
        if process.wait() != 0:
            raise RuntimeError('ffmpeg failed')
    report = {'fps': 60, 'durationSeconds': 20, 'frames': len(frames), 'size': [900, 480],
              'codec': 'H.264', 'background': 'black', 'audio': False, 'appOnly': True,
              'source': 'Art/DailyMotions/manifest.json#dafeiyu-dog',
              'sourceSHA256': hashlib.sha256((ROOT / 'Art/DailyMotions/manifest.json').read_bytes()).hexdigest(),
              'sha256': hashlib.sha256(output.read_bytes()).hexdigest(), 'bytes': output.stat().st_size}
    output.with_suffix('.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--ffmpeg', default='ffmpeg')
    parser.add_argument('--output', type=Path, default=ROOT / 'App/Resources/DafeiyuDogWalkTest.mp4')
    args = parser.parse_args()
    encode(args.ffmpeg, args.output)
