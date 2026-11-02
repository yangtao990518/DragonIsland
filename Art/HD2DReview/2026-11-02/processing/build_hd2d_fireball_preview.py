"""Deterministic sprite-sheet cleanup/extraction and a labeled animation preview.

All creative fire pixels originate in built-in image_gen. This script never
draws replacement flames. It preserves fixed slots, defines emission anchors,
and displays the assets on a neutral diagnostic stage, not an engine capture.
"""
from pathlib import Path
import json, hashlib, bisect, math, subprocess, zipfile
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent / 'hd2d-fireball-2026-11-02'
FFMPEG = Path(r'E:/ai_workspace/ios_ldd/tools/python-animation/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe')
IDLE = ROOT.parent/'hd2d-characters-2026-11-02'
FONT = r'C:/Windows/Fonts/msyh.ttc'
SIZE = 96
IMPACT_TICKS = [1,1,2,2,3,3,3,3,3,3,4,4,5,5,6,6]
IMPACT_DURATIONS = [t/60 for t in IMPACT_TICKS]

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def write_json(path,data): path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def prepare(kind):
    folder=ROOT/kind
    source=Image.open(folder/'processor-qc/raw-sheet-clean.png').convert('RGBA')
    # Warm fire has no blue/purple material. Undo residual magenta mixing on
    # anti-aliased edge pixels using C = alpha*F + (1-alpha)*magenta, rather
    # than shaving off the silhouette. Interior cream/orange pixels stay exact.
    pixels=np.asarray(source).astype(np.float64)/255
    excess=pixels[:,:,2]-pixels[:,:,1]
    edge=(excess>15/255)&(pixels[:,:,3]>0)
    fraction=np.clip(1-excess,.005,1)
    screen=np.array([1,0,1],np.float64)
    foreground=(pixels[:,:,:3]-(1-fraction[:,:,None])*screen)/fraction[:,:,None]
    pixels[:,:,:3][edge]=np.clip(foreground[edge],0,1)
    pixels[:,:,3][edge]*=fraction[edge]
    pixels[pixels[:,:,3]==0]=0
    source=Image.fromarray(np.rint(pixels*255).astype(np.uint8),'RGBA')
    source.save(folder/'source-descreened.png')
    raw=Image.open(folder/'raw-sheet.png');w,h=raw.size
    frames=[];entries=[];slot_rects=[]
    target=folder/'frames';target.mkdir(exist_ok=True)
    # The contact star and the initial expanding ground ring need a common
    # emission point. Integer shifts are calibrated to those visible features;
    # no per-frame bbox centering, no scaling to fit each effect's own bounds.
    impact_offsets=[(1,7),(0,7),(0,2),(0,0),(0,3),(0,1),(0,1),(0,0)]+[(0,0)]*8
    for index in range(16):
        c=index%4;r=index//4
        rect=[round(c*w/4),round(r*h/4),round((c+1)*w/4),round((r+1)*h/4)]
        slot=source.crop(rect).resize((SIZE,SIZE),Image.Resampling.NEAREST)
        offset=impact_offsets[index] if kind=='impact' else (0,0)
        final=Image.new('RGBA',(SIZE,SIZE));final.paste(slot,offset)
        a=np.asarray(final);mask=a[:,:,3]>0
        assert not mask[0].any() and not mask[-1].any() and not mask[:,0].any() and not mask[:,-1].any(),(kind,index,'clipped')
        assert np.count_nonzero(mask)>0
        # No retained magenta background, including enclosed holes.
        rgb=a[:,:,:3].astype(np.int16)
        assert not np.any((rgb[:,:,0]>170)&(rgb[:,:,2]>150)&(rgb[:,:,1]<90)&mask),(kind,index,'magenta')
        path=target/f'{index:02d}.png';final.save(path)
        frames.append(final);slot_rects.append(rect)
        entries.append({'index':index,'file':f'frames/{index:02d}.png','sha256':sha(path),
                        'sourceRect':rect,'integerTranslation':list(offset),
                        'durationMs':1000/30 if kind=='flight' else IMPACT_DURATIONS[index]*1000})
    assert len({im.tobytes() for im in frames})==16,(kind,'duplicate frames')
    sheet=Image.new('RGBA',(SIZE*4,SIZE*4))
    for i,im in enumerate(frames):sheet.paste(im,(i%4*SIZE,i//4*SIZE))
    sheet.save(folder/'sheet-transparent.png')
    anchor=[67,48] if kind=='flight' else [49,80]
    manifest={'id':'hd2d-fireball-'+kind+'-v1','status':'visual sample; not integrated into game',
              'creativeSource':'built-in image_gen','rawSHA256':sha(folder/'raw-sheet.png'),
              'frameCount':16,'cellSize':[SIZE,SIZE],'anchorPixels':anchor,
              'anchorMeaning':'hot projectile head' if kind=='flight' else 'fixed ground emission point',
              'loop':kind=='flight','durationMs':sum(f['durationMs'] for f in entries),
              'frameExtraction':'fixed equal source slots, one shared nearest-neighbor scale; no per-frame bbox fitting',
              'generatedIntermediateFrames':False,'residualMagentaMethod':'warm-palette physical color unmix on blue-excess edge pixels only','frames':entries}
    write_json(folder/'manifest.json',manifest)
    # Transparent APNG uses actual authored poses, with extra end hold only
    # for isolated inspection of the one-shot impact.
    samples=[im.resize((288,288),Image.Resampling.NEAREST) for im in frames]
    delays=[f['durationMs'] for f in entries]
    if kind=='impact':
        samples.append(Image.new('RGBA',(288,288)));delays.append(650)
    samples[0].save(folder/'animation.apng',format='PNG',save_all=True,append_images=samples[1:],
                    duration=delays,loop=0,disposal=0,blend=0)
    return frames,manifest

def scaled(im,size):return im.resize((size,size),Image.Resampling.NEAREST)

def stamp(base,im,point,anchor,size,glow=0):
    sprite=scaled(im,size);x=round(point[0]-anchor[0]*size/SIZE);y=round(point[1]-anchor[1]*size/SIZE)
    if glow:
        # Preview-only emission derived from the finished image alpha, never
        # baked into the sharp sprite. This is not a 3D engine lighting test.
        layer=Image.new('RGBA',base.size);layer.alpha_composite(sprite,(x,y))
        alpha=layer.getchannel('A').filter(ImageFilter.GaussianBlur(max(2,size/20)))
        warm=Image.new('RGBA',base.size,(255,119,24,0));warm.putalpha(alpha.point(lambda a:round(a*glow)))
        base.alpha_composite(warm)
    base.alpha_composite(sprite,(x,y))

def make_preview(flight,impact):
    font=ImageFont.truetype(FONT,26);small=ImageFont.truetype(FONT,18);caption=ImageFont.truetype(FONT,16)
    idle_meta=json.loads((IDLE/'extraction-analysis.json').read_text(encoding='utf-8'))
    starts=[f['pts_seconds'] for f in idle_meta['frames']]
    actors=[Image.open(IDLE/'dafeiyu/master-rgba-v4'/f'{i:04d}.png').convert('RGBA').resize((128,144),Image.Resampling.NEAREST) for i in range(240)]
    impact_starts=[];at=0
    for duration in IMPACT_DURATIONS:impact_starts.append(at);at+=duration
    base=Image.new('RGBA',(1280,720),(15,21,31,255));d=ImageDraw.Draw(base)
    d.text((32,22),'火球 · HD-2D 动画样板',font=font,fill='#eaf0f9')
    d.text((845,31),'素材预览 · 非游戏实机画面',font=small,fill='#a8b7cc')
    for rect in [(28,82,1252,350),(28,370,626,674),(648,370,1252,674)]:
        d.rounded_rectangle(rect,radius=16,fill='#1b2433',outline='#344154',width=1)
    d.text((50,102),'正常尺寸示意：飞行 → 命中 → 余烬',font=small,fill='#dbe6f7')
    d.text((50,388),'飞行细节 · 16帧循环',font=small,fill='#dbe6f7')
    d.text((670,388),'命中细节 · 16帧展开与消散',font=small,fill='#dbe6f7')
    d.text((32,690),'角色沿用确认稿；柔光为预览叠加，火焰本体保持清晰像素。',font=caption,fill='#9baec5')
    # Quiet neutral ground strip, purely a diagnostic display surface.
    d.line((70,303,1190,303),fill='#38465b',width=1)
    path=ROOT/'fireball-HD2D-animation-preview-v1.mp4'
    p=subprocess.Popen([str(FFMPEG),'-y','-hide_banner','-loglevel','error','-f','rawvideo','-pix_fmt','rgb24',
                        '-s','1280x720','-r','60','-i','-','-an','-c:v','libx264','-preset','medium',
                        '-crf','15','-pix_fmt','yuv420p','-movflags','+faststart',str(path)],stdin=subprocess.PIPE,stderr=subprocess.PIPE)
    screenshots=[]
    for index in range(576):
        t=index/60;phase=t%2.4;im=base.copy()
        body=min(239,bisect.bisect_right(starts,t%4.097)-1);im.alpha_composite(actors[body],(110,155))
        fly_index=int(t*30)%16
        if .15<=phase<.9:
            progress=(phase-.15)/.75
            stamp(im,flight[int((phase-.15)*30)%16],(245+755*progress,251+44*progress),(67,48),40,.22)
        hit=phase-.9
        if 0<=hit<at:
            hit_index=bisect.bisect_right(impact_starts,hit)-1
            stamp(im,impact[hit_index],(1000,295),(49,80),104,.24)
        stamp(im,flight[fly_index],(411,544),(67,48),288,.08)
        detail=(t+.15)%1.9
        if detail<at:
            hit_index=bisect.bisect_right(impact_starts,detail)-1
            stamp(im,impact[hit_index],(948,645),(49,80),288,.10)
        if index in [40,69,89]:screenshots.append((index,im.copy()))
        p.stdin.write(im.convert('RGB').tobytes())
    p.stdin.close();error=p.stderr.read();assert p.wait()==0,error
    check=subprocess.run([str(FFMPEG),'-hide_banner','-loglevel','error','-i',str(path),'-f','null','-'],capture_output=True)
    assert check.returncode==0,check.stderr
    for index,im in screenshots:im.convert('RGB').save(ROOT/f'preview-frame-{index:03d}.png')
    return path

def main():
    flight,fm=prepare('flight');impact,hm=prepare('impact');preview=make_preview(flight,impact)
    readme=ROOT/'README.md';readme.write_text(
        '# 火球 HD-2D 动画样板 v1\n\n飞行和命中为内置 image_gen 分别生成的两张4×4原画。原始图、最终提示词均保留。使用 generate2dsprite 的去底色工具，再按原图固定网格拆帧；没有逐帧外接框居中、缩放，也没有用程序绘制替代火焰。\n\n'
        '飞行：16个独立姿态，30姿态/秒，单轮约0.533秒。命中：16个独立姿态，约0.9秒，各阶段按manifest时长播放，命中前两帧很短，后期余烬较慢。所有正式帧96×96直通RGBA，最近邻缩放。火球头部锚点(67,48)，爆炸地面发射点(49,80)。早期爆炸帧按发射点做少量整数平移，后期余烬不重新居中。\n\n'
        'MP4以60Hz编码展示同一批姿态，不声称每秒60个独立手绘姿态；包含正常尺寸示意和两块放大动画。角色使用用户已确认的v4待机，顶部为中性测试台合成，非模拟器截图、非正式战场或真正3D照明测试。柔光只在预览显示层叠加，透明素材本体不含模糊光晕。\n\n'
        '本次仅提供视觉样板，未替换现有游戏技能、未生成IPA。后续需在战场中验证透视遮挡、光影、伤害时点、受击闪红与多人多技能性能。\n',encoding='utf-8')
    validation={'creativeGeneration':'built-in image_gen','flightFrames':16,'impactFrames':16,
                'allFramesUnique':True,'allFramesTransparentMarginSafe':True,'magentaResidualCheck':'passed',
                'fixedCell':[96,96],'previewFPS':60,'previewFrames':576,'previewDurationSeconds':9.6,
                'previewDecode':'passed','previewSHA256':sha(preview),'runtimeIntegrated':False}
    write_json(ROOT/'validation.json',validation)
    bundle=ROOT/'fireball-HD2D-sample-v1.zip'
    with zipfile.ZipFile(bundle,'w',zipfile.ZIP_DEFLATED) as z:
        for kind in ['flight','impact']:
            for name in ['raw-sheet.png','prompt-used.txt','sheet-transparent.png','manifest.json','animation.apng']:
                p=ROOT/kind/name;z.write(p,str(p.relative_to(ROOT)))
            for p in sorted((ROOT/kind/'frames').glob('*.png')):z.write(p,str(p.relative_to(ROOT)))
        for p in [readme,ROOT/'validation.json']:z.write(p,p.name)
        z.write(Path(__file__).resolve(),'reproduction/build_hd2d_fireball_preview.py')
    print(json.dumps({'preview':str(preview),'bundle':str(bundle),'bundleBytes':bundle.stat().st_size,'validation':validation},ensure_ascii=False),flush=True)

if __name__=='__main__':main()
