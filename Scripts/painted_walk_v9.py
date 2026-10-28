"""Original painted limb contours with a contact-constrained walking cycle.

Uses the v7 painted key-0 artwork directly. Bone lengths are measured inside
that artwork; body height follows the reachable support foot, rather than
compressing a long rig into a short chibi leg. Pet motion is the full painted
v8 neural interpolation. RGB review output is not an App asset payload.
"""
import json,math
import numpy as np
from PIL import Image,ImageDraw,ImageFilter,ImageFont
import pet_walk_reference as native
import painted_pet_walk as paint
from animation_runtime import FONT

OUT=paint.OUT.parent/'walk-painted-v9'
FPS=60;CYCLE=96;DUTY=.64
CFG={'xiaobai':dict(name='小白',a=20.,hips=[(201.,253.),(218.,253.)],lift=3.5,
    joints=[(218,253),(221,287),(226,319)],foot_y=320,
    near=[(207,263),(225,261),(229,280),(231,309),(235,320),(245,328),(256,333),(259,342),(252,348),(216,352),(208,344),(206,334),(211,320),(205,303),(207,282)],
    far=[(197,263),(216,270),(217,281),(209,291),(198,304),(184,316),(183,325),(190,335),(186,343),(179,348),(158,347),(147,336),(145,321),(152,308),(161,294),(175,282),(190,269)],
    shoe=[(215,315),(231,315),(237,323),(248,330),(258,336),(258,343),(251,350),(215,351),(210,343),(208,335),(210,326)]),
 'dafeiyu':dict(name='大肥鱼',a=14.,hips=[(174.,277.),(195.,277.)],lift=1.8,
    joints=[(195,277),(198,294),(201,311)],foot_y=310,
    near=[(178,278),(207,278),(213,299),(215,304),(218,309),(216,319),(224,321),(236,326),(242,335),(241,345),(225,353),(189,354),(180,346),(179,332),(182,319),(180,308),(177,294)],
    far=[(164,280),(180,283),(187,291),(188,301),(179,310),(172,317),(172,330),(167,339),(151,340),(141,334),(136,320),(135,306),(140,294),(153,288)],
    shoe=None)}
native.REGION=(120,240,290,365);native.SS=4
native.raster.REGION=native.REGION;native.raster.SS=native.SS
SOURCE={};LIMBS={};BODY={};BACK={};REFERENCE={}

class PaintedLimb(native.NativeLimb):
    def vertices(self,pose):
        output=super().vertices(pose)
        start,end=(270,280) if self.name.startswith('xiaobai') else (286,296)
        weight=native.ease((self.grid[:,:,1]-start)/(end-start))[:,:,None]
        root=self.grid+(pose['hip']-self.joints[0])
        return root*(1-weight)+output*weight

def mask_polygon(size,polygon):
    mask=Image.new('L',(size[0]*4,size[1]*4))
    ImageDraw.Draw(mask).polygon([(x*4,y*4) for x,y in polygon],fill=255)
    return mask.resize(size,Image.Resampling.LANCZOS)

for role,c in CFG.items():
    source=Image.open(paint.OUT/role/'keys/00.png').convert('RGBA')
    SOURCE[role]=source
    isolated,_=native.cut(source,c['near'])
    rgba=np.array(isolated);rgb=rgba[:,:,:3].astype(int)
    skin=(rgb[:,:,0]>rgb[:,:,2]+5)&(rgb[:,:,0]>=rgb[:,:,1]-2)&(rgb[:,:,0]>145)&(rgba[:,:,3]>0)
    edge=np.array(Image.fromarray(skin.astype('uint8')*255).filter(ImageFilter.MaxFilter(3)))
    if c['shoe']:
        edge[c['foot_y']-5:]=np.asarray(mask_polygon(source.size,c['shoe']))[c['foot_y']-5:]
    else:edge[c['foot_y']-5:]=255
    rgba[:,:,3]=np.minimum(rgba[:,:,3],edge)
    rgba[:273 if role=='xiaobai' else 286,:,3]=0
    isolated=Image.fromarray(rgba)
    LIMBS[role]={side:PaintedLimb(role+'-'+side,isolated,[(0,0),(512,0),(512,384),(0,384)],c['joints'],c['foot_y'],1,1.,False) for side in ['far','near']}
    far=LIMBS[role]['far']
    colour=np.array(far.art);colour[:,:,:3]=np.round(colour[:,:,:3]*.94).astype('uint8');far.art=Image.fromarray(colour)
    # Both old painted leg silhouettes are removed, but the original garment
    # keeps its genuine edge. The lining goes behind the moving legs.
    removal=np.array(isolated.getchannel('A'))>8
    old_far,_=native.cut(source,c['far']);far_data=np.array(old_far);rgb=far_data[:,:,:3].astype(int)
    skin=(rgb[:,:,0]>rgb[:,:,2]+5)&(rgb[:,:,0]>=rgb[:,:,1]-2)&(rgb[:,:,0]>140)&(far_data[:,:,3]>0)
    ownership=np.array(Image.fromarray(skin.astype('uint8')*255).filter(ImageFilter.MaxFilter(3)))>0
    ownership[310 if role=='xiaobai' else 286:]=True
    ownership[:273 if role=='xiaobai' else 286]=False
    removal|=ownership&(far_data[:,:,3]>8)
    removal=np.asarray(Image.fromarray(removal.astype('uint8')*255).filter(ImageFilter.MaxFilter(3)),dtype=float)/255
    removal=removal.copy();removal[:273 if role=='xiaobai' else 286]=0
    rgba=np.array(source);rgba[:,:,3]=np.round(rgba[:,:,3]*(1-removal)).astype('uint8')
    rgba[:,340:]=0
    body=Image.fromarray(rgba);back=Image.new('RGBA',source.size)
    if role=='xiaobai':
        lining=mask_polygon(source.size,[(210,276),(216,329),(181,329),(183,314),(196,293)])
        layer=body.copy();layer.putalpha(Image.fromarray(np.round(np.asarray(body.getchannel('A'),dtype=float)*np.asarray(lining)/255).astype('uint8')))
        back.alpha_composite(layer)
        rgba=np.array(body);rgba[:,:,3]=np.round(rgba[:,:,3]*(1-np.asarray(lining,dtype=float)/255)).astype('uint8');body=Image.fromarray(rgba)
    BODY[role]=body;BACK[role]=back

def step(phase,a,lift):
    p=phase%1
    if p<DUTY:return a-2*a*p/DUTY,0.,True
    u=(p-DUTY)/(1-DUTY);v=-2*a*(1-DUTY)/DUTY
    x=-a+v*u+(2*a-v)*native.ease(u)
    # Zero contact velocity and acceleration in the vertical component.
    return float(x),float(lift*math.sin(math.pi*u)**4),False

def poses(role,tick):
    c=CFG[role];cycle=tick/CYCLE;raw=[]
    for side,offset in [('far',.5),('near',0.)]:
        x,lift,stance=step(cycle+offset,c['a'],c['lift']);raw.append((side,x,lift,stance))
    limb=LIMBS[role]['near'];ground=350.
    bottom=(limb.sole-limb.joints[2])[:,1].max();ankle_y=ground-bottom
    reach=limb.l1+limb.l2-.35
    requirements=np.array([ankle_y-lift-math.sqrt(reach*reach-x*x) for _,x,lift,_ in raw])
    maximum=float(requirements.max())
    hip_y=maximum+.5*math.log(float(np.exp((requirements-maximum)/.5).sum()))
    bob=hip_y-c['hips'][1][1]
    root=cycle*2*c['a']/DUTY
    result=[]
    for number,(side,x,lift,stance) in enumerate(raw):
        hip=np.array([c['hips'][number][0],hip_y])
        pose=LIMBS[role][side].solve(hip,x,lift,0.,ground)
        pose.update(stance=stance,side=side)
        result.append((LIMBS[role][side],pose))
    return result,root,bob

def character(role,tick):
    limbs,root,bob=poses(role,tick)
    canvas=np.zeros(((native.REGION[3]-native.REGION[1])*native.SS,(native.REGION[2]-native.REGION[0])*native.SS,4),np.float32)
    art=Image.new('RGBA',(512,384))
    art.alpha_composite(native.shift(BACK[role],dy=bob))
    for limb,pose in limbs:limb.paint(canvas,pose)
    art.alpha_composite(native.image_layer(canvas),native.REGION[:2])
    art.alpha_composite(native.shift(BODY[role],dy=bob))
    # Smoothly join the moving hand to the stationary painted pet harness.
    yy,xx=np.mgrid[195:305,255:380]
    dy=bob*(1-native.ease((xx-250)/130))
    rope=native.raster.sample_texture(native.raster.texture(SOURCE[role]),xx+.5,yy+.5-dy)
    rope=Image.fromarray(np.round(np.clip(rope,0,1)*255).astype('uint8'),'RGBa').convert('RGBA')
    art.paste((0,0,0,0),(255,195,380,305));art.alpha_composite(rope,(255,195))
    output=Image.new('RGB',art.size,'#192033');output.paste(art,(0,0),art)
    petpath=paint.OUT.parent/'walk-painted-v8'/role/'frames-60fps'/f'{tick%96+1:03}.png'
    pet=Image.open(petpath).convert('RGB')
    output.paste(pet.crop((340,195,512,365)),(340,195))
    return output,limbs,root,bob

def audit():
    OUT.mkdir(exist_ok=True)
    for role in CFG:
        board=Image.new('RGB',(1600,1440),'#192033');draw=ImageDraw.Draw(board)
        font=ImageFont.truetype(str(FONT),18)
        for col,tick in enumerate(range(0,96,6)):
            image,*_=character(role,tick)
            image.save(OUT/f'{role}-audit-{tick:02}.png')
            crop=image.crop((120,245,280,365)).resize((400,300),Image.Resampling.LANCZOS)
            x=(col%4)*400;y=(col//4)*360
            board.paste(crop,(x,y+30));draw.text((x+8,y+4),f'{tick}/96',fill='white',font=font)
        board.save(OUT/f'{role}-leg-audit.png')
        print(role,'anatomy key audit saved',flush=True)

if __name__=='__main__':audit()
