"""Port restored historical scripts without touching the verified source archives or PNGs."""
from pathlib import Path
import argparse
import ast
import hashlib
import json
import animation_runtime as runtime

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    environment = runtime.check()
    root = runtime.REPOSITORY
    report = {'environment': environment, 'scripts': [], 'apply': args.apply}
    old_sources = 'C:/Users/yangtao/.codex/generated_images/01a1761a-5068-7a11-b414-ddd80d16b390'
    old_ffmpeg = 'D:/tools/剪映/JianyingPro/8.2.0.13017/ffmpeg.exe'
    for directory in ['ride-batch1', 'pet-walk-batch2', 'dafeiyu']:
        for script in (root / 'output' / directory).rglob('*.py'):
            before = script.read_text(encoding='utf-8')
            after = before.replace(old_sources, runtime.SOURCES.as_posix())
            after = after.replace(old_ffmpeg, Path(runtime.ffmpeg()).as_posix())
            after = after.replace('C:/Windows/Fonts/msyh.ttc', runtime.FONT.as_posix())
            after = after.replace("'h264_nvenc'", repr(runtime.ENCODER))
            # Source processors are intentionally not executed. Existing split PNGs
            # are restored; generating them again would require the old processor.
            processor_dependency = 'generate2dsprite' in after
            ast.parse(after, filename=str(script))
            if before != after or processor_dependency:
                report['scripts'].append({'path': script.relative_to(root).as_posix(),
                    'changed': before != after, 'source_sha256': hashlib.sha256(before.encode()).hexdigest(),
                    'ported_sha256': hashlib.sha256(after.encode()).hexdigest(),
                    'requires_unavailable_legacy_processor': processor_dependency})
            if args.apply and before != after:
                script.write_text(after, encoding='utf-8', newline='\n')
    destination = root / 'output/animation-local-port.json'
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    main()
