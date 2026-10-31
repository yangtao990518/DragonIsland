"""Review all imported clips at original PTS; this is NOT App footage."""
import argparse
from fractions import Fraction
import json
from pathlib import Path
import av
import numpy as np
from PIL import Image, ImageDraw


def preview(work):
    work = Path(work)
    clips = json.loads((work / 'clips.json').read_text(encoding='utf-8'))
    records = clips[0]['frames']
    durations = {round(f['start_seconds'] * 1_000_000): round(f['duration_ms'] * 1000) for f in records}
    target = work / 'all-clips-original-timing.mp4'
    with av.open(str(target), 'w', options={'video_track_timescale': '1000000', 'movflags': '+faststart'}) as output:
        stream = output.add_stream('libx264', rate=60)
        stream.width, stream.height, stream.pix_fmt = 1280, 720, 'yuv420p'
        stream.time_base = stream.codec_context.time_base = Fraction(1, 1_000_000)
        stream.options = {'crf': '19', 'preset': 'fast', 'bf': '0'}

        def mux(packet):
            start = round(float(packet.pts * packet.time_base) * 1_000_000)
            packet.duration = round(durations[start] / 1_000_000 / float(packet.time_base))
            output.mux(packet)

        for index, record in enumerate(records):
            board = Image.new('RGB', (1280, 720), '#14212b')
            draw = ImageDraw.Draw(board)
            for n, clip in enumerate(clips):
                x, y = n % 4 * 320, n // 4 * 360
                draw.text((x+12, y+8), clip['id'], fill='#aad5ff')
                image = Image.open(work / 'clips' / clip['id'] / 'rgba-v2' / f'{index:04d}.png').convert('RGBA')
                image.thumbnail((304, 315))
                board.paste(image, (x+(320-image.width)//2, y+32+(315-image.height)//2), image)
            frame = av.VideoFrame.from_ndarray(np.array(board), format='rgb24')
            frame.pts, frame.time_base = round(record['start_seconds'] * 1_000_000), Fraction(1, 1_000_000)
            for packet in stream.encode(frame): mux(packet)
        for packet in stream.encode(): mux(packet)
    with av.open(str(target)) as result:
        stream = result.streams.video[0]
        frames = list(result.decode(video=0))
        duration = float(stream.duration * stream.time_base)
        assert len(frames) == len(records)
        assert abs(duration - clips[0]['duration_ms']/1000) < 0.0001
        report = {'preview': target.name, 'scope': 'source-matte-review-not-app-footage',
                  'frame_count': len(frames), 'stream_duration_seconds': duration,
                  'source_duration_seconds': clips[0]['duration_ms']/1000}
        (work / 'preview-check.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
        print(json.dumps(report), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('work', type=Path)
    preview(parser.parse_args().work)
