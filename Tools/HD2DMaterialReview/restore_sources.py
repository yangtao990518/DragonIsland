"""Restore verified source packages after git pull. Python standard library only."""
from pathlib import Path
import hashlib,json,os,argparse
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check-parts',action='store_true',help='verify concatenated parts without writing');args=parser.parse_args()
 repo=Path(__file__).resolve().parents[2];index=repo/'Art/HD2DReview/2026-11-02/source-parts.json';data=json.loads(index.read_text(encoding='utf-8'))
 for item in data['files']:
  dest=(repo/item['path']).resolve();assert dest.is_relative_to(repo.resolve())
  if dest.exists() and not args.check_parts:
   if hashlib.sha256(dest.read_bytes()).hexdigest()==item['sha256']:print('Already verified:',item['path']);continue
   raise RuntimeError('Preserving different existing file; move it aside before restoring: '+str(dest))
  digest=hashlib.sha256();size=0;tmp=dest.with_name(dest.name+'.restoring');dest.parent.mkdir(parents=True,exist_ok=True)
  output=None if args.check_parts else tmp.open('wb')
  try:
   for part in item['parts']:
    path=(repo/part['path']).resolve();assert path.is_relative_to(repo.resolve());block=path.read_bytes();assert len(block)==part['bytes'] and hashlib.sha256(block).hexdigest()==part['sha256'],('Damaged part',part['path']);digest.update(block);size+=len(block)
    if output:output.write(block)
  finally:
   if output:output.close()
  assert size==item['bytes'] and digest.hexdigest()==item['sha256'],('Package hash mismatch',item['path'])
  if not args.check_parts:os.replace(tmp,dest)
  print('Parts verified:' if args.check_parts else 'Restored:',item['path'],size)
if __name__=='__main__':main()
