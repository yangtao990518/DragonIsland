"""Continuous character and quadruped cutouts; no neural tweened feet.

Every human leg and animal limb is a complete, character-specific painting.
The torso covers rounded overlap caps. Supporting soles stay in world space.
The compositor returns transparent RGBA frames for review and future approval.
"""
import math
import numpy as np
from PIL import Image,ImageDraw
import painted_walk_v11 as human
import pet_walk_reference as native
from painted_pet_walk import OUT as SOURCE

OUT=SOURCE.parent/'walk-painted-v12'
CFG=human.CFG;CYCLE=96;FPS=60;DUTY=human.DUTY
PET_CYCLE=48;PET_DUTY=.68
PET_LIFT=1.8
# The same rasterizer serves both actor regions, with independent canvases.
native.REGION=(130,220,550,368);native.SS=4
native.raster.REGION=native.REGION;native.raster.SS=4
PETS={
 'xiaobai':dict(file='exec-0ac280f5-10a1-4882-98dc-42f5ba6adbb7.png',scale=.18,xy=(308,210),body_bottom=620,limb_scale=.17,
    homes={'front-near':(478,302),'front-far':(465,298),'hind-near':(440,302),'hind-far':(428,298)},
    parts={'front-near':dict(box=(145,635,415,995),joints=[(255,685),(260,815),(290,929)]),
           'front-far':dict(box=(440,635,738,995),joints=[(555,685),(554,805),(598,921)]),
           'hind-near':dict(box=(1135,635,1430,995),joints=[(1236,685),(1270,810),(1296,924)]),
           'hind-far':dict(box=(1135,635,1430,995),joints=[(1236,685),(1270,810),(1296,924)])}),
 'dafeiyu':dict(file='exec-fe80b765-bd8a-4135-90c0-0457595859c0.png',scale=.2,xy=(291,205),body_bottom=620,limb_scale=.16,
    homes={'front-near':(470,301),'front-far':(457,297),'hind-near':(407,301),'hind-far':(394,297)},
    parts={'front-near':dict(box=(110,620,420,995),joints=[(220,680),(260,820),(305,935)]),
           'front-far':dict(box=(435,620,745,995),joints=[(550,680),(590,820),(620,927)]),
           'hind-near':dict(box=(810,620,1085,995),joints=[(970,680),(930,810),(920,935)]),
           'hind-far':dict(box=(1185,620,1435,995),joints=[(1300,680),(1280,810),(1330,935)])})}
BODY={};LIMBS={};END={}

for role,c in PETS.items():
    source=human.clean(Image.open(SOURCE/'generated'/c['file']))
    body=source.copy();body.paste((0,0,0,0),(0,c['body_bottom'],source.width,source.height))
    body=human.scale_to(body,c['scale'],(0,0),c['xy']);BODY[role]=body
    alpha=np.array(body.getchannel('A'));rows=np.flatnonzero(alpha[250:310,355]>120)+250
    if not len(rows):raise ValueError(('pet leash stub missing',role))
    END[role]=float(np.median(rows))
    LIMBS[role]={};lengths={}
    for name in ['front-near','front-far','hind-near','hind-far']:
        spec=c['parts'][name]
        part=Image.new('RGBA',source.size);part.alpha_composite(source.crop(spec['box']),spec['box'][:2])
        joints=np.array(spec['joints'],float);scale=c['limb_scale']
        ys=np.where(np.array(part.getchannel('A'))>120)[0]
        total=(float(ys.max())-joints[0,1])*scale
        group=name.split('-')[0]
        if name.endswith('near'):lengths[group]=total
        else:scale*=lengths[group]/total
        home=np.array(c['homes'][name],float)
        part=human.scale_to(part,scale,joints[0],home)
        if name.endswith('far'):
            rgba=np.array(part);rgba[:,:,:3]=np.round(rgba[:,:,:3]*.92).astype('uint8');part=Image.fromarray(rgba)
        points=home+(joints-joints[0])*scale
        bend=-1 if group=='front' else 1
        LIMBS[role][name]=human.KitLimb(role+'-'+name,part,[(0,0),(640,0),(640,384),(0,384)],points,round(points[2,1]),bend,1.,False)

def step(phase,a,lift):
    p=phase%1
    if p<PET_DUTY:return a-2*a*p/PET_DUTY,0.,True
    u=(p-PET_DUTY)/(1-PET_DUTY);v=-2*a*(1-PET_DUTY)/PET_DUTY
    return float(-a+v*u+(2*a-v)*native.ease(u)),float(lift*math.sin(math.pi*u)**4),False

def pet_poses(role,tick):
    cycle=tick/PET_CYCLE
    amplitude=(2*CFG[role]['a']/DUTY)*PET_DUTY/4
    raw=[];requirements=[]
    for name,phase in [('hind-far',.75),('front-far',.5),('hind-near',.25),('front-near',0.)]:
        limb=LIMBS[role][name];x,lift,stance=step(cycle+phase,amplitude,PET_LIFT)
        ground=350. if name.startswith('front') else 348.
        if name.endswith('far'):ground-=4
        bottom=(limb.sole-limb.joints[2])[:,1].max();ankle_y=ground-bottom
        reach=limb.l1+limb.l2-.35
        if abs(x)>=reach:raise ValueError(('pet stride exceeds limb',role,name,x,reach))
        requirements.append(ankle_y-lift-math.sqrt(reach*reach-x*x)-limb.joints[0,1])
        raw.append((name,x,lift,stance,ground))
    maximum=max(requirements)
    bob=maximum+.35*math.log(sum(math.exp((y-maximum)/.35) for y in requirements))
    result=[]
    for name,x,lift,stance,ground in raw:
        limb=LIMBS[role][name]
        pose=limb.solve(limb.joints[0]+[0,bob],x,lift,0.,ground)
        pose.update(stance=stance,side=name);result.append((limb,pose))
    return result,bob

def character(role,tick):
    humans,root,bob=human.poses(role,tick);pets,petbob=pet_poses(role,tick)
    height=(native.REGION[3]-native.REGION[1])*4;width=(native.REGION[2]-native.REGION[0])*4
    layer=np.zeros((height,width,4),np.float32)
    for limb,pose in humans:limb.paint(layer,pose)
    output=Image.new('RGBA',(640,384));output.alpha_composite(native.image_layer(layer),native.REGION[:2])
    output.alpha_composite(native.shift(human.BODY[role],dy=bob))
    layer.fill(0)
    for limb,pose in pets:limb.paint(layer,pose)
    output.alpha_composite(native.image_layer(layer),native.REGION[:2])
    output.alpha_composite(native.shift(BODY[role],dy=petbob))
    # Bridge only the short gap between the two existing painted leash pieces.
    start_x,start_y=human.ROPE[role]['start'];start_y+=bob
    end_x,end_y=355.,END[role]+petbob
    rope=Image.new('RGBA',(640*4,384*4));draw=ImageDraw.Draw(rope)
    points=[]
    for t in np.linspace(0,1,50):
        x=start_x+(end_x-start_x)*t;y=start_y+(end_y-start_y)*t+.8*math.sin(math.pi*t)
        points.append((round(x*4),round(y*4)))
    draw.line(points,fill=tuple(human.ROPE[role]['colour'])+(255,),width=9 if role=='dafeiyu' else 7,joint='curve')
    output.alpha_composite(rope.resize(output.size,Image.Resampling.LANCZOS))
    return output,humans,root,bob

if __name__=='__main__':
    OUT.mkdir(exist_ok=True)
    for role in CFG:
        for tick in range(96):human.poses(role,tick);pet_poses(role,tick)
        for tick in [0,6,12,18,24,30,36,42]:
            image,*_=character(role,tick);image.save(OUT/f'{role}-key-{tick:02}.png')
        print(role,'all human and pet poses reachable',flush=True)
