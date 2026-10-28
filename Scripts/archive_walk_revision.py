"""Package local source work and the latest previews without deleting trials."""
import argparse,hashlib,json,shutil,zipfile
from pathlib import Path
from animation_runtime import REPOSITORY

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--revision',choices=['v11','v12','v13'],default='v13');args=parser.parse_args()
    revision=args.revision
    base=REPOSITORY/'output/pet-walk-batch2'
    current=base/('walk-painted-'+revision)
    destination=REPOSITORY/'AnimationDrafts/2026-10-28';destination.mkdir(exist_ok=True)
    files=set((base/'walk-painted-v7/generated').glob('*.png'))
    files.add(base/'walk-painted-v7/generation-prompts.json')
    files.update((base/'walk-painted-v7').glob('*pose-guide.png'))
    for role in ['xiaobai','dafeiyu']:
        files.update((base/'walk-painted-v7'/role/'keys').glob('*.png'))
        if revision=='v11':
            files.update((base/'walk-painted-v10'/role/'inputs').glob('*.png'))
            files.update((base/'walk-painted-v10'/role/'frames-60fps').glob('*.png'))
        files.update((current/role/'frames-60fps').glob('*.png'))
        files.add(current/role/'joints.json')
    files.update(current.glob('*.json'))
    files.add(current/'reference-comparison.png')
    if (current/'stride-key-review.png').exists():files.add(current/'stride-key-review.png')
    for pattern in ['*walk*.py','animation_runtime.py','port_animation_drafts.py','fetch_animation_rife.py']:
        files.update((REPOSITORY/'Scripts').glob(pattern))
    records=[]
    archive=destination/('sources.zip' if revision=='v11' else f'sources-{revision}.zip')
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as target:
        for file in sorted(files):
            relative=file.relative_to(REPOSITORY).as_posix()
            records.append(dict(path=relative,bytes=file.stat().st_size,sha256=sha(file)))
            target.write(file,relative)
    with zipfile.ZipFile(archive) as check:
        assert check.testzip() is None
        for record in records:
            assert hashlib.sha256(check.read(record['path'])).hexdigest()==record['sha256']
    previews=destination/'previews';previews.mkdir(exist_ok=True);videos=[]
    for name in [f'pet-walk-full-{revision}.mp4',f'human-feet-{revision}.mp4',f'pet-feet-{revision}.mp4']:
        source=current/name;target=previews/name;shutil.copy2(source,target)
        videos.append(dict(path='previews/'+name,bytes=target.stat().st_size,sha256=sha(target)))
    review=json.loads((current/'verification.json').read_text(encoding='utf-8'))
    manifest=dict(status=review.get('status','unaccepted_local_draft'),revision=revision,branch='codex/character-chat',base_commit='bafc996fb3a70cace014d182163af863e90c1713',
        archive=dict(path=archive.name,bytes=archive.stat().st_size,sha256=sha(archive)),files=records,previews=videos,
        original_archive_modified=False,ios_integrated=False,ipa_generated=False,normal_speed_playback_review=False,
        user_feedback=review.get('user_feedback'))
    latest=destination/'manifest.json'
    if latest.exists():
        previous=json.loads(latest.read_text(encoding='utf-8')).get('revision')
        if previous and previous!=revision:
            old=destination/f'manifest-{previous}.json'
            if not old.exists():shutil.copy2(latest,old)
    latest.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Archived',len(records),'source paths;',archive.stat().st_size,'bytes; ZIP CRC + source SHA256 + three previews verified',flush=True)

if __name__=='__main__':main()
