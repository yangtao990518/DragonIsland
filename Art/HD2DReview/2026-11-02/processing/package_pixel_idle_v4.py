from pathlib import Path
import json,hashlib,zipfile,subprocess,bisect
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parent/'hd2d-characters-2026-11-02'
FFMPEG=r'E:/ai_workspace/ios_ldd/tools/python-animation/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 source=json.loads((ROOT/'extraction-analysis.json').read_text(encoding='utf-8'));edits=json.loads((ROOT/'eye-only-retiming-v4.json').read_text(encoding='utf-8'));assert sha(source['source'])==source['source_sha256']
 validation={};pack=ROOT/'characters-v4'
 for name in ['dafeiyu','xiaobai']:
  prior=json.loads((ROOT/'characters-v2'/name/'manifest.json').read_text(encoding='utf-8'));manifest=dict(prior);atlases=[];frames=[];outside_changes=0;alpha_changes=0;motion={}
  target=pack/name/'atlases';target.mkdir(parents=True,exist_ok=True)
  for page in range(60):
   sheet=Image.new('RGBA',(1280,1440));images=[]
   for cell in range(4):
    index=page*4+cell;im=Image.open(ROOT/name/'master-rgba-v4'/f'{index:04d}.png').convert('RGBA');old=np.asarray(Image.open(ROOT/name/'master-rgba-v2'/f'{index:04d}.png').convert('RGBA'));a=np.asarray(im);delta=np.any(a!=old,axis=2)
    outside=delta.copy();outside[155:290,275:410]=False;outside_changes+=int(outside.sum());alpha_changes+=int(np.count_nonzero(a[:,:,3]!=old[:,:,3]))
    assert not outside.any() and np.array_equal(a[:,:,3],old[:,:,3])
    x=cell%2*640;y=cell//2*720;sheet.paste(im,(x,y));images.append(im)
    entry=dict(prior['frames'][index]);entry['retimedStartMs']=entry['sourceStartMs'];entry['retimedDurationMs']=entry['originalDurationMs'];entry['eyeSourceIndex']=edits['records'][name][index]['eyeSource'];entry['rgbaSHA256']=hashlib.sha256(im.tobytes()).hexdigest();frames.append(entry)
   path=target/f'{page:03d}.webp';sheet.save(path,format='WEBP',lossless=True,method=4,exact=True)
   with Image.open(path) as restored:
    for cell,im in enumerate(images):
     x=cell%2*640;y=cell//2*720;assert restored.crop((x,y,x+640,y+720)).tobytes()==im.tobytes()
   atlases.append({'file':f'atlases/{page:03d}.webp','sha256':sha(path),'size':[1280,1440]})
  manifest.update({'id':name+'-hd2d-idle-v4','eyeMaskFix':'Union of target and registered donor footprint; full inner/outer lash coverage','blinkRetimedDurationMs':4097,'bodyOriginalTimingPreserved':True,'eyePatchesOnly':True,'noWholeBodyRetiming':True,'eyeRetiming':'closing 120ms, hold 100ms, opening 180ms; later closed source eyes replaced with registered original open eyes; body stays on original timeline','blinkPhases':[], 'timelines':{'original':'Original unedited eye/pose frames retained separately in v2 matting masters','blink-fixed':'sourceStartMs + originalDurationMs; only eye RGB is locally edited'},'atlases':atlases,'frames':frames})
  (pack/name/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
  validation[name]={'frames':240,'losslessAtlasRoundTrips':240,'alphaChangedPixels':alpha_changes,'changedPixelsOutsideFaceRegion':outside_changes,'bodyTiming':'source PTS unchanged','blinkRetimingAffectsWholeBody':False}
  print(name,'240 source-timed frames packaged, body/alpha preserved',flush=True)
 preview=ROOT/'HD2D-characters-idle-eye-only-v4.mp4';assert subprocess.run([FFMPEG,'-hide_banner','-loglevel','error','-i',str(preview),'-f','null','-'],capture_output=True).returncode==0
 report={'sourceSHA256':source['source_sha256'],'characters':validation,'durationSeconds':4.097,'previewEncodedLoopSeconds':246/60,'previewRepeats':2,'previewSHA256':sha(preview),'knownLimit':'Original source breathing/hair movement and loop boundary are retained; not a guaranteed motionless or hand-animated source.'}
 (ROOT/'eye-only-v4-validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
 notes=ROOT/'README-v4.txt';notes.write_text('HD-2D 人物待机 v4（修复 v3 睁眼后眼角残留黑点）\n身体完整保留原片240帧、4.097秒原时序。上一版压缩眨眼区间时连带加快整个人物，产生突然跳动，已撤销。\n本版补全左右眼眼角及睫毛覆盖，合并当前帧与对齐眼部区域，避免闭眼末端残留。只将原视频中的眼部区域对齐并重排：闭合120ms、闭眼100ms、睁开180ms；长闭眼剩余部分用原片睁眼区域对齐替换。没有AI重画。眼部以外逐帧像素与原抠像母版相同，轮廓透明度逐像素不变。\n保留源视频原有的身体、头发、衣服运动；不承诺原AI素材完全没有轻微形变。\n每个角色60张无损WebP图集、240个完整RGBA帧，manifest保留原PTS和眼部源帧编号。MP4为深色底预览，60Hz连续两轮约8.2秒，不是透明素材。\n复现脚本中的本机路径需按使用电脑修改，依赖Pillow、NumPy、OpenCV、PyMatting和FFmpeg。原始抠像母版、源视频和旧版预览均未覆盖。\n',encoding='utf-8')
 bundle=ROOT/'HD2D-characters-idle-eye-only-v4.zip'
 with zipfile.ZipFile(bundle,'w',zipfile.ZIP_DEFLATED) as z:
  for path in sorted(pack.rglob('*')):
   if path.is_file():z.write(path,str(path.relative_to(ROOT)))
  for path in [notes,ROOT/'extraction-analysis.json',ROOT/'eye-only-retiming-v4.json',ROOT/'eye-only-v4-validation.json']:
   z.write(path,path.name)
  for filename in ['analyze_pixel_video.py','process_pixel_idle_matte.py','fix_pixel_idle_eye_only_v4.py','package_pixel_idle_v4.py']:
   z.write(Path(__file__).resolve().parent/filename,'reproduction/'+filename)
 with zipfile.ZipFile(bundle) as z:assert z.testzip() is None
 print('PASS package validation;',bundle.stat().st_size,'bytes',flush=True)
if __name__=='__main__':main()
