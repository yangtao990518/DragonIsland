"""Build App atlas copies; the native lossless video sources remain unchanged."""
import json
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
CATALOG=ROOT/'Art/VideoActions/manifest.json'


def video_manifests(character_id=None):
    if not CATALOG.exists():return []
    result=[]
    for entry in json.loads(CATALOG.read_text(encoding='utf-8'))['clips']:
        path=CATALOG.parent/entry['manifest']
        info=json.loads(path.read_text(encoding='utf-8'))
        if character_id is None or info['characterID']==character_id:result.append((path,info))
    return result


def main():
    destination=ROOT/'App/Resources/VideoActionAtlases';destination.mkdir(exist_ok=True)
    clips=[]
    for path,info in video_manifests():
        columns,rows=info['grid'];native_w,native_h=info['cellSize']
        h=min(640,native_h);w=round(native_w*h/native_h)
        names=[]
        for j,atlas in enumerate(info['atlases']):
            sheet=Image.open(path.parent/atlas['path']).convert('RGBA')
            result=Image.new('RGBA',(w*columns,h*rows))
            for cell in range(columns*rows):
                image=sheet.crop((cell%columns*native_w,cell//columns*native_h,(cell%columns+1)*native_w,(cell//columns+1)*native_h))
                if image.size!=(w,h):image=image.convert('RGBa').resize((w,h),Image.Resampling.LANCZOS).convert('RGBA')
                result.paste(image,(cell%columns*w,cell//columns*h))
            name=f'{info["id"]}-atlas-{j:03}';result.save(destination/(name+'.png'),compress_level=6);names.append(name)
        clips.append(dict(id=info['id'],action=info['action'],characterID=info['characterID'],title=info['title'],
                          durationMs=info['durationMs'],frameCount=info['frameCount'],cellSize=[w,h],grid=info['grid'],atlases=names,
                          frameStartMs=[f['start_seconds']*1000 for f in info['frames']],
                          frameDurationsMs=[f['duration_ms'] for f in info['frames']]))
        print('App full-PTS clip ready',info['id'],info['frameCount'],flush=True)
    (ROOT/'App/Resources/VideoActions.json').write_text(json.dumps(clips,ensure_ascii=False,separators=(',',':'))+'\n',encoding='utf-8')


if __name__=='__main__':main()
