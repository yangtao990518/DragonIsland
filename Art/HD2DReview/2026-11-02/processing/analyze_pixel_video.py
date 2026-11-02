from pathlib import Path
import subprocess,re,json,hashlib,sys
sys.path.insert(0,str(Path('../tools/python-matting').resolve()));sys.path.insert(0,str(Path('../tools/python-animation').resolve()))
import numpy as np
from PIL import Image,ImageDraw,ImageFont
source=Path(r'E:\AI文件夹\像素人物.mp4');root=Path('output/hd2d-characters-2026-11-02');raw=root/'source-rgb';raw.mkdir(parents=True,exist_ok=True)
ffmpeg=r'E:\ai_workspace\ios_ldd\tools\python-animation\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe'
p=subprocess.run([ffmpeg,'-hide_banner','-i',str(source),'-map','0:v:0','-vf','showinfo','-fps_mode','passthrough','-compression_level','1','-start_number','0',str(raw/'%04d.png')],capture_output=True)
log=p.stderr.decode('utf-8','replace');(root/'decode-showinfo.log').write_text(log,encoding='utf-8');assert p.returncode==0,log[-2000:]
frames=[]
for line in log.splitlines():
 m=re.search(r'n:\s*(\d+)\s+pts:\s*(-?\d+)\s+pts_time:([\d.e+-]+)\s+duration:\s*(\d+)\s+duration_time:([\d.e+-]+)',line)
 if m:frames.append({'index':int(m[1]),'pts':int(m[2]),'pts_seconds':float(m[3]),'duration_ticks':int(m[4]),'duration_seconds':float(m[5])})
assert len(frames)==len(list(raw.glob('*.png'))) and frames
with Image.open(raw/'0000.png') as im:size=list(im.size)
report={'source':str(source),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'source_bytes':source.stat().st_size,'size':size,'time_base':re.search(r'config in time_base:\s*([^,]+)',log)[1],'frames':frames,'video_duration_from_last_frame':frames[-1]['pts_seconds']+frames[-1]['duration_seconds'],'original_full_frames_retained':True,'user_authorized_exception':'Shorten overly long eye-closed holds only; preserve full raw extraction and record derived source indices/timing.'}
(root/'extraction-analysis.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',18)
indices=list(dict.fromkeys([min(range(len(frames)),key=lambda i:abs(frames[i]['pts_seconds']-t)) for t in np.arange(0,4.01,.25)]))
board=Image.new('RGB',(1280,4*204),'#202331');draw=ImageDraw.Draw(board)
for k,i in enumerate(indices):
 im=Image.open(raw/f'{i:04d}.png');im.thumbnail((320,180));x=(k%4)*320;y=(k//4)*204
 board.paste(im,(x,y+24));draw.text((x+5,y+2),f'#{i}  t={frames[i]["pts_seconds"]:.3f}s',font=font,fill='white')
board.save(root/'source-contact-sheet.jpg',quality=94)
print(json.dumps({'frames':len(frames),'size':size,'duration':report['video_duration_from_last_frame'],'pts_first':frames[:3],'pts_last':frames[-1]},ensure_ascii=False))
