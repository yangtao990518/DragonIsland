"""Character-specific painted cutouts, continuous contacts, and painted pets.

The kit contains completed legless garments and full overlapping thigh caps.
No leg silhouette is cut out of the dress and no generic skin texture is used.
"""
import math,json
import numpy as np
from PIL import Image,ImageDraw,ImageFont
import pet_walk_reference as native
import painted_pet_walk as paint
from animation_runtime import FONT

OUT=paint.OUT.parent/'walk-painted-v11'
FPS=60;CYCLE=96;DUTY=.64
native.REGION=(130,220,330,368);native.SS=4
native.raster.REGION=native.REGION;native.raster.SS=4
CFG={'xiaobai':dict(name='小白',a=19.,lift=1.8,hips=[(222.,253.),(239.,253.)],
    file='exec-1c526681-8c89-4fcc-b397-51e21d5569af.png',body_scale=.406,body_xy=(10,13),body_bottom=830,leg_scale=.313,
    parts={'near':dict(box=(425,825,650,1195),joints=[(510,850),(526,955),(541,1089)]),
           'far':dict(box=(700,825,930,1195),joints=[(786,850),(800,955),(817,1089)])}),
 'dafeiyu':dict(name='大肥鱼',a=14.,lift=1.8,hips=[(182.,281.),(204.,281.)],
    file='exec-6ff35da1-8063-478b-b28b-7454e9e5fcd4.png',body_scale=.375,body_xy=(10,7),body_bottom=880,leg_scale=.265,
    parts={'near':dict(box=(320,882,575,1195),joints=[(420,900),(431,951),(440,1010)]),
           'far':dict(box=(735,882,985,1195),joints=[(813,900),(828,951),(839,1010)])})}

def clean(image):
    rgba=np.array(image.convert('RGBA'));alpha=np.clip((rgba[:,:,3].astype(float)-65)*255/175,0,255)
    count,labels,stats,_=paint.cv2.connectedComponentsWithStats((alpha>100).astype('uint8'),8)
    keep=np.zeros(alpha.shape,np.uint8)
    for label in range(1,count):
        if stats[label,paint.cv2.CC_STAT_AREA]>=150:keep[labels==label]=255
    keep=paint.cv2.dilate(keep,np.ones((3,3),np.uint8))
    rgba[:,:,3]=np.round(alpha*keep/255).astype('uint8');rgba[rgba[:,:,3]==0]=0
    return Image.fromarray(rgba)

def scale_to(image,scale,source_anchor,target_anchor):
    sx,sy=source_anchor;tx,ty=target_anchor
    return image.convert('RGBa').transform((640,384),Image.Transform.AFFINE,
        (1/scale,0,sx-tx/scale,0,1/scale,sy-ty/scale),Image.Resampling.BICUBIC).convert('RGBA')

BODY={};LIMBS={};ROPE={}

class KitLimb(native.NativeLimb):
    """Transport the whole native painting along a smooth anatomical curve."""
    @staticmethod
    def curve(h,k,a,s):
        l1=np.linalg.norm(k-h);l2=np.linalg.norm(a-k);split=l1/(l1+l2)
        upper=(k-h)/l1;lower=(a-k)/l2;tangent=(upper+lower);tangent/=np.linalg.norm(tangent)
        first=s<=split
        u=np.where(first,s/split,(s-split)/(1-split))[:,None]
        start=np.where(first[:,None],h,k);end=np.where(first[:,None],k,a)
        ta=np.where(first[:,None],upper*l1,tangent*l2);tb=np.where(first[:,None],tangent*l1,lower*l2)
        point=(2*u**3-3*u**2+1)*start+(u**3-2*u**2+u)*ta+(-2*u**3+3*u**2)*end+(u**3-u**2)*tb
        derivative=(6*u*u-6*u)*start+(3*u*u-4*u+1)*ta+(-6*u*u+6*u)*end+(3*u*u-2*u)*tb
        derivative/=np.maximum(np.linalg.norm(derivative,axis=1)[:,None],1e-8)
        return point,np.c_[derivative[:,1],-derivative[:,0]]
    def vertices(self,pose):
        points=self.grid.reshape(-1,2)
        h,k,a=self.joints
        parameter=(points[:,1]-h[1])/(a[1]-h[1])
        for _ in range(4):
            center,normal=self.curve(h,k,a,parameter)
            left,_=self.curve(h,k,a,parameter-.0001)
            right,_=self.curve(h,k,a,parameter+.0001)
            derivative=(right-left)/.0002
            parameter+=np.sum((points-center)*derivative,axis=1)/np.maximum(np.sum(derivative*derivative,axis=1),1e-4)
        center,normal=self.curve(h,k,a,parameter)
        offset=np.sum((points-center)*normal,axis=1)
        target,target_normal=self.curve(pose['hip'],pose['knee'],pose['ankle'],parameter)
        curved=target+offset[:,None]*target_normal
        foot=(points-a)@native.rotation(pose['angle']).T+pose['ankle']
        weight=native.ease((points[:,1]-a[1]+6)/10)[:,None]
        return (curved*(1-weight)+foot*weight).reshape(self.grid.shape)
for role,c in CFG.items():
    source=clean(Image.open(paint.OUT/'generated'/c['file']))
    body=source.copy();body.paste((0,0,0,0),(0,c['body_bottom'],source.width,source.height))
    body=scale_to(body,c['body_scale'],(0,0),c['body_xy'])
    alpha=np.asarray(body.getchannel('A'));ys=np.flatnonzero(alpha[250:300,329]>120)+250
    if not len(ys):raise ValueError(('missing leash endpoint',role))
    rope_y=float(np.median(ys));colour=[190,169,241] if role=='xiaobai' else [35,208,250]
    body.paste((0,0,0,0),(330,0,640,384));BODY[role]=body
    ROPE[role]=dict(start=(329.,rope_y),colour=colour)
    LIMBS[role]={}
    near_total=None
    for side in ['near','far']:
        i=0 if side=='far' else 1
        spec=c['parts'][side];part=Image.new('RGBA',source.size);part.alpha_composite(source.crop(spec['box']),spec['box'][:2])
        if role=='xiaobai':
            rgba=np.array(part);rgb=rgba[:,:,:3].astype(int)
            skin=(rgb[:,:,0]>rgb[:,:,2]+7)&(rgb[:,:,0]>=rgb[:,:,1]-2)&(rgb[:,:,0]>145)&(rgba[:,:,3]>0)
            mask=paint.cv2.dilate(skin.astype('uint8'),np.ones((5,5),np.uint8))
            if side=='far':mask[885:925]=1
            mask[1000:]=1
            rgba[:,:,3]*=mask;part=Image.fromarray(rgba)
        joints=np.array(spec['joints'],float)
        anchor=np.array(c['hips'][i]);scale=c['leg_scale']
        ys=np.where(np.array(part.getchannel('A'))>120)[0]
        total=(float(ys.max())-joints[0,1])*scale
        if side=='near':near_total=total
        elif role=='dafeiyu':scale*=near_total/total
        part=scale_to(part,scale,joints[0],anchor)
        points=anchor+(joints-joints[0])*scale
        LIMBS[role][side]=KitLimb(role+'-'+side,part,[(0,0),(640,0),(640,384),(0,384)],points,round(points[2,1]),1,1.,False)

# The artwork's upper cap is an overlap boundary, not the anatomical hip.
# Dafeiyu's hip sits inside the dress. Extending only this hidden bone keeps
# her visible short thighs/socks unchanged and avoids squatting to reach a
# crossed step. Foot centres converge toward the projected centre of travel.
CFG['dafeiyu']['foot_x_bias']=[9.,-9.]
CFG['dafeiyu']['hips']=[(x,y-24.) for x,y in CFG['dafeiyu']['hips']]
for limb in LIMBS['dafeiyu'].values():
    limb.joints[0,1]-=24.
    limb.l1,limb.l2=np.linalg.norm(np.diff(limb.joints,axis=0),axis=1)

def step(phase,a,lift):
    p=phase%1
    if p<DUTY:return a-2*a*p/DUTY,0.,True
    u=(p-DUTY)/(1-DUTY);v=-2*a*(1-DUTY)/DUTY
    return float(-a+v*u+(2*a-v)*native.ease(u)),float(lift*math.sin(math.pi*u)**4),False

def poses(role,tick):
    c=CFG[role];cycle=tick/CYCLE;raw=[];requirements=[]
    for i,(side,phase) in enumerate([('far',.5),('near',0.)]):
        limb=LIMBS[role][side];x,lift,stance=step(cycle+phase,c['a'],c['lift'])
        x+=c.get('foot_x_bias',[0.,0.])[i]
        bottom=(limb.sole-limb.joints[2])[:,1].max();ankle_y=350.-bottom
        reach=limb.l1+limb.l2-.4
        if abs(x)>=reach:raise ValueError(('stride too large',role,x,reach))
        requirements.append(ankle_y-lift-math.sqrt(reach*reach-x*x))
        raw.append((side,x,lift,stance))
    maximum=max(requirements)
    hip_y=maximum+.5*math.log(sum(math.exp((y-maximum)/.5) for y in requirements))
    bob=hip_y-c['hips'][1][1];root=cycle*2*c['a']/DUTY;result=[]
    for i,(side,x,lift,stance) in enumerate(raw):
        limb=LIMBS[role][side];pose=limb.solve(np.array([c['hips'][i][0],hip_y]),x,lift,0.,350.)
        pose.update(stance=stance,side=side);result.append((limb,pose))
    return result,root,bob

def pet_frame(role,tick):
    return Image.open(paint.OUT.parent/'walk-painted-v10'/role/'frames-60fps'/f'{(tick*2)%96+1:03}.png').convert('RGB')

def character(role,tick):
    limbs,root,bob=poses(role,tick)
    canvas=np.zeros(((native.REGION[3]-native.REGION[1])*4,(native.REGION[2]-native.REGION[0])*4,4),np.float32)
    for limb,pose in limbs:limb.paint(canvas,pose)
    art=Image.new('RGBA',(640,384));art.alpha_composite(native.image_layer(canvas),native.REGION[:2]);art.alpha_composite(native.shift(BODY[role],dy=bob))
    output=Image.new('RGB',art.size,'#192033');output.paste(art,(0,0),art)
    pet=pet_frame(role,tick);pet_crop=pet.crop((340,195,512,365))
    output.paste(pet_crop,(360,195))
    # Preserve the source long rope; bridge its last 30 px to the painted pet.
    pixels=np.array(pet);column=pixels[270:297,340,:].astype(int)
    rope_mask=(column.max(axis=1)>120)&(column[:,2]>column[:,0]-25)
    rows=np.flatnonzero(rope_mask)+270
    end_y=float(np.median(rows)) if len(rows) else 288.
    x0,y0=ROPE[role]['start'];y0+=bob;x1,y1=360.,end_y
    layer=Image.new('RGBA',(640*4,384*4));draw=ImageDraw.Draw(layer)
    points=[]
    for t in np.linspace(0,1,50):
        x=x0+(x1-x0)*t;y=y0+(y1-y0)*t+1.2*math.sin(math.pi*t)
        points.append((round(x*4),round(y*4)))
    draw.line(points,fill=tuple(ROPE[role]['colour'])+(255,),width=7,joint='curve')
    layer=layer.resize(output.size,Image.Resampling.LANCZOS)
    output.paste(layer,(0,0),layer)
    return output,limbs,root,bob

def audit():
    OUT.mkdir(exist_ok=True)
    for role in CFG:
        for tick in range(CYCLE):poses(role,tick)
        board=Image.new('RGB',(1600,1440),'#192033');draw=ImageDraw.Draw(board);font=ImageFont.truetype(str(FONT),18)
        for i,tick in enumerate(range(0,96,6)):
            image,*_=character(role,tick);image.save(OUT/f'{role}-audit-{tick:02}.png')
            crop=image.crop((145,235,310,368)).resize((400,322),Image.Resampling.LANCZOS)
            x=(i%4)*400;y=(i//4)*360;board.paste(crop,(x,y+30));draw.text((x+8,y+4),f'{tick}/96',font=font,fill='white')
        board.save(OUT/f'{role}-leg-audit.png')
        print(role,'all poses reachable and key audit saved',flush=True)

if __name__=='__main__':audit()
