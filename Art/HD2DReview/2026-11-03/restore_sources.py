from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parent
for entry in json.loads((root/'source-parts.json').read_text(encoding='utf-8'))['files']:
 target=root/entry['file'];target.parent.mkdir(parents=True,exist_ok=True);pieces=[]
 for part in entry['parts']:
  data=(root/part['path']).read_bytes();assert len(data)==part['bytes'] and hashlib.sha256(data).hexdigest()==part['sha256'],part['path'];pieces.append(data)
 data=b''.join(pieces);assert len(data)==entry['bytes'] and hashlib.sha256(data).hexdigest()==entry['sha256'];target.write_bytes(data);print('Verified',entry['file'],len(data))
