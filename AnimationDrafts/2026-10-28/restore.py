"""Restore this unaccepted local draft, keeping any conflicting local edits."""
import argparse,hashlib,json,zipfile
from pathlib import Path

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--verify-only',action='store_true');parser.add_argument('--overwrite',action='store_true')
    parser.add_argument('--destination',type=Path,default=Path(__file__).resolve().parents[2]);args=parser.parse_args()
    home=Path(__file__).resolve().parent;manifest=json.loads((home/'manifest.json').read_text(encoding='utf-8'))
    archive=home/manifest['archive']['path'];assert digest(archive)==manifest['archive']['sha256']
    root=args.destination.resolve();conflicts=[];count=0
    with zipfile.ZipFile(archive) as source:
        assert source.testzip() is None
        for record in manifest['files']:
            relative=Path(record['path']);assert not relative.is_absolute() and '..' not in relative.parts
            target=(root/relative).resolve();assert target.is_relative_to(root)
            data=source.read(record['path']);assert hashlib.sha256(data).hexdigest()==record['sha256']
            if not args.verify_only:
                if target.exists() and digest(target)!=record['sha256'] and not args.overwrite:conflicts.append(record['path']);continue
                if not target.exists() or digest(target)!=record['sha256']:
                    target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
            count+=1
    for record in manifest['previews']:assert digest(home/record['path'])==record['sha256']
    print('Verified',count,'source paths and',len(manifest['previews']),'previews. Status: unaccepted local draft.')
    if conflicts:print('Preserved conflicting files:',*conflicts,sep='\n');raise SystemExit(1)

if __name__=='__main__':main()
