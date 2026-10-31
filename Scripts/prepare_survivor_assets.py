"""Build App-only PNG atlas pages from the full-source lossless masters."""
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def prepare(root=ROOT):
    root = Path(root)
    source = root / 'Art/Survivor'
    target = root / 'App/Resources/SurvivorGame'
    manifest = json.loads((source / 'manifest.json').read_text(encoding='utf-8'))
    assert manifest['dropped_frames'] == 0 and manifest['synthesized_frames'] == 0
    assert manifest['playback_speed'] == 1
    for record in manifest['sources'].values():
        assert record['full_original_range'] and record['duration_ms'] <= 20000
        assert hashlib.sha256((source / record['path']).read_bytes()).hexdigest() == record['sha256']
    required = {'dafeiyu-run', 'demon-run', 'mushroom-run'} | {f'thunder-{n}' for n in range(1, 6)}
    assert {clip['id'] for clip in manifest['clips']} == required
    target.mkdir(parents=True, exist_ok=True)
    for clip in manifest['clips']:
        origin = manifest['sources'][clip['source']]
        assert clip['frame_count'] == origin['frame_count'] == len(clip['frames'])
        assert abs(clip['duration_ms'] - origin['duration_ms']) < .001
        end = 0
        for index, frame in enumerate(clip['frames']):
            assert frame['source_index'] == index and frame['duration_ms'] > 0
            assert abs(frame['start_ms'] - end) < .01
            assert 0 <= frame['cell'] < clip['unique_count']
            end = frame['start_ms'] + frame['duration_ms']
        assert abs(end - clip['duration_ms']) < .01
        for page in clip['pages']:
            path = Path(page['file'])
            assert not path.is_absolute() and '..' not in path.parts
            raw = (source / path).read_bytes()
            assert hashlib.sha256(raw).hexdigest() == page['sha256']
            image = Image.open(source / path)
            assert image.mode == 'RGBA'
            assert image.size == tuple(a*b for a,b in zip(clip['cell_size'], clip['grid']))
            assert image.getchannel('A').getextrema()[0] == 0
            dest = target / path.with_suffix('.png')
            dest.parent.mkdir(parents=True, exist_ok=True)
            # Deterministic conversion, no quantization or resizing.
            image.save(dest, compress_level=6)
            page['file'] = path.with_suffix('.png').as_posix()
            page['source_sha256'] = page['sha256']
            page['sha256'] = hashlib.sha256(dest.read_bytes()).hexdigest()
    (target / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False), encoding='utf-8')
    print('Survivor: 8 full-source clips, App-only lossless PNG atlases')


if __name__ == '__main__':
    prepare()
