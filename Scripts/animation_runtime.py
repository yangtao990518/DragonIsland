"""Local preview paths. Importing this module creates no assets or caches."""
import os
from pathlib import Path
import shutil
import subprocess

REPOSITORY = Path(__file__).resolve().parents[1]
WORKSPACE = REPOSITORY.parent
SOURCES = Path(os.environ.get('DRAGON_GENERATED_SOURCES', REPOSITORY / 'output/animation-generated-sources'))
FONT = Path(os.environ.get('DRAGON_FONT', 'C:/Windows/Fonts/msyh.ttc'))
ENCODER = os.environ.get('DRAGON_VIDEO_ENCODER', 'libx264')

def ffmpeg():
    candidates = [os.environ.get('DRAGON_FFMPEG'), shutil.which('ffmpeg'),
                  WORKSPACE / 'tools/ffmpeg/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe']
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return str(candidate)
    raise FileNotFoundError('Set DRAGON_FFMPEG to a full FFmpeg build with libx264.')

def check():
    import PIL
    import numpy
    executable = ffmpeg()
    encoders = subprocess.check_output([executable, '-hide_banner', '-encoders'], text=True, encoding='utf-8')
    if ENCODER not in encoders:
        raise RuntimeError(f'FFmpeg does not provide {ENCODER}')
    if not FONT.is_file():
        raise FileNotFoundError('Set DRAGON_FONT to an available Chinese font.')
    return {'Pillow': PIL.__version__, 'NumPy': numpy.__version__, 'ffmpeg': executable,
            'encoder': ENCODER, 'font': str(FONT), 'generated_sources': str(SOURCES)}
