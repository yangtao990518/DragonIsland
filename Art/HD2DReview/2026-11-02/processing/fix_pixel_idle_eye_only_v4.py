"""Preserve every body frame/PTS; retime only registered eye patches from source."""
from pathlib import Path
import sys,json,bisect,subprocess,hashlib
sys.path.insert(0,r'E:/ai_workspace/ios_ldd/tools/python-matting')
sys.path.insert(0,r'E:/ai_workspace/ios_ldd/tools/python-animation')
import cv2,numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parent/'hd2d-characters-2026-11-02'
CONFIG={
 'dafeiyu':{'head':(280,165,405,280),'eyes':[(294,210,349,253),(339,204,383,250)]},
 'xiaobai':{'head':(280,160,405,270),'eyes':[(293,205,347,244),(338,198,380,242)]}}
FFMPEG=r'E:/ai_workspace/ios_ldd/tools/python-animation/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe'

def eye_source(t,starts):
 # Only the eyes use a shorter timeline. The body never skips/accelerates.
 if t<.6 or t>=2.8:return min(239,bisect.bisect_right(starts,t)-1)
 if t<.72:src=.6+(t-.6)/.12*(starts[45]-.6)
 elif t<.82:src=starts[45]+(t-.72)/.10*(starts[145]-starts[45])
 elif t<1.0:src=starts[145]+(t-.82)/.18*(starts[167]-starts[145])
 else:src=starts[167]
 return min(239,bisect.bisect_right(starts,src+1e-8)-1)

def transform_patch(base,donor,spec):
 x0,y0,x1,y1=spec['head'];b=base[y0:y1,x0:x1,:3];s=donor[y0:y1,x0:x1,:3]
 gray_b=cv2.cvtColor(b,cv2.COLOR_RGB2GRAY).astype(np.float32)/255
 gray_s=cv2.cvtColor(s,cv2.COLOR_RGB2GRAY).astype(np.float32)/255
 fitmask=np.full(gray_b.shape,255,np.uint8)
 eyemask=np.zeros(gray_b.shape,np.float32)
 for a,c,z,q in spec['eyes']:
  fitmask[max(0,c-y0-6):q-y0+6,max(0,a-x0-6):z-x0+6]=0
  eyemask[c-y0:q-y0,a-x0:z-x0]=1
 # Smooth only patch seams; never blend full poses or alter silhouette.
 eyemask=cv2.GaussianBlur(eyemask,(7,7),1.1)
 warp=np.eye(2,3,dtype=np.float32)
 try:score,warp=cv2.findTransformECC(gray_b,gray_s,warp,cv2.MOTION_EUCLIDEAN,(cv2.TERM_CRITERIA_EPS|cv2.TERM_CRITERIA_COUNT,60,1e-5),fitmask,3)
 except cv2.error:score=-1
 assert abs(float(warp[0,2]))<10 and abs(float(warp[1,2]))<10,(warp,score)
 warped=cv2.warpAffine(s,warp,(x1-x0,y1-y0),flags=cv2.INTER_CUBIC|cv2.WARP_INVERSE_MAP,borderMode=cv2.BORDER_REFLECT_101)
 mask=cv2.warpAffine(eyemask,warp,(x1-x0,y1-y0),flags=cv2.INTER_LINEAR|cv2.WARP_INVERSE_MAP,borderMode=cv2.BORDER_CONSTANT)
 # Cover both the donor footprint AND target closed-eye lashes.
 # A donor-only narrow mask left the inner-corner lash tip behind.
 mask=np.maximum(mask,eyemask)
 mask[mask<.002]=0
 result=base.copy();region=result[y0:y1,x0:x1,:3]
 region[:]=np.clip(np.rint(warped*mask[:,:,None]+region*(1-mask[:,:,None])),0,255).astype(np.uint8)
 outside=np.ones(base.shape[:2],bool);outside[y0:y1,x0:x1]=mask==0
 assert np.array_equal(result[outside],base[outside])
 assert np.array_equal(result[:,:,3],base[:,:,3])
 return result,{'score':float(score),'warp':warp.tolist(),'changedPixels':int(np.count_nonzero(np.any(result!=base,axis=2)))}

def main():
 cv2.setNumThreads(2)
 report=json.loads((ROOT/'extraction-analysis.json').read_text(encoding='utf-8'));starts=[f['pts_seconds'] for f in report['frames']]
 records={};allframes={}
 for name,spec in CONFIG.items():
  source=[np.asarray(Image.open(ROOT/name/'master-rgba-v2'/f'{i:04d}.png').convert('RGBA')) for i in range(240)]
  output=ROOT/name/'master-rgba-v4';output.mkdir(exist_ok=True);records[name]=[];allframes[name]=[]
  for i,t in enumerate(starts):
   j=eye_source(t,starts)
   if i==j:result=source[i].copy();q={'score':1,'changedPixels':0}
   else:result,q=transform_patch(source[i],source[j],spec)
   Image.fromarray(result).save(output/f'{i:04d}.png',compress_level=2)
   allframes[name].append(result);records[name].append({'bodySource':i,'eyeSource':j,'sourcePTS':report['frames'][i]['pts'],**q})
  print(name,'complete; every body frame unchanged outside eyes',flush=True)
 (ROOT/'eye-only-retiming-v4.json').write_text(json.dumps({'method':'Registered eye-only patches from original frames; original whole-body PTS untouched','durationSeconds':4.097,'records':records},indent=2),encoding='utf-8')
 times=[.58,.65,.70,.75,.80,.85,.90,.95,1.0,1.1,1.5,2.0,2.6,2.8,3.0]
 board=Image.new('RGB',(1250,6*160),'#202331');d=ImageDraw.Draw(board)
 for n,name in enumerate(CONFIG):
  for k,t in enumerate(times):
   i=min(239,bisect.bisect_right(starts,t)-1);im=Image.fromarray(allframes[name][i]);bg=Image.new('RGBA',im.size,(28,34,50,255));bg.alpha_composite(im)
   pic=bg.crop((285,195 if name=='dafeiyu' else 185,395,265 if name=='dafeiyu' else 255)).resize((250,140),Image.Resampling.NEAREST)
   x=k%5*250;y=(n*3+k//5)*160;board.paste(pic,(x,y+20));d.text((x+3,y+3),name+f' {t:.2f}s body{i} eye{records[name][i]["eyeSource"]}',fill='white')
 board.save(ROOT/'eye-only-v4-contact.png')
 # Full original PTS; repeat twice, with no body speed-up.
 fps=60;count=round(4.097*fps);sampled=[min(239,bisect.bisect_right(starts,i/fps)-1) for i in range(count)]
 path=ROOT/'HD2D-characters-idle-eye-only-v4.mp4'
 p=subprocess.Popen([FFMPEG,'-y','-hide_banner','-loglevel','error','-f','rawvideo','-pix_fmt','rgb24','-s','1280x720','-r',str(fps),'-i','-','-an','-c:v','libx264','-preset','medium','-crf','16','-pix_fmt','yuv420p','-movflags','+faststart',str(path)],stdin=subprocess.PIPE,stderr=subprocess.PIPE)
 for loop in range(2):
  for i in sampled:
   bg=Image.new('RGBA',(1280,720),(28,34,50,255))
   for x,name in enumerate(CONFIG):bg.alpha_composite(Image.fromarray(allframes[name][i]),(x*640,0))
   p.stdin.write(bg.convert('RGB').tobytes())
 p.stdin.close();error=p.stderr.read();assert p.wait()==0,error
 print(str(path),flush=True)
if __name__=='__main__':main()
