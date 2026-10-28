"""Reference-calibrated walking prototype with original shoes and pet parts.

Human shoes/socks, thigh ornaments and pet paws use the original action artwork.
Skin proportions are calibrated by opaque width; pet poses are continuous.
"""
import importlib.util
import math
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
from animation_runtime import REPOSITORY

BASE=REPOSITORY/'output/pet-walk-batch2'
OUT=BASE/'walk-native-v5'
FPS=60; CYCLE=96; DUTY=.62; GROUND=590.; SS=3
REGION=(200,390,805,615)
spec=importlib.util.spec_from_file_location('native_raster',BASE/'walk-rig-v3-stable/rig.py')
raster=importlib.util.module_from_spec(spec);spec.loader.exec_module(raster)
raster.REGION=REGION;raster.SS=SS
SOURCES={r:Image.open(BASE/(r+'-walk')/'frames/000.png').convert('RGBA') for r in ['xiaobai','dafeiyu']}

def ease(x):
    x=np.clip(x,0.,1.);return x*x*x*(10+x*(-15+6*x))

def mask_art(image,polygon):
    mask=Image.new('L',(image.width*4,image.height*4))
    ImageDraw.Draw(mask).polygon([(round(x*4),round(y*4)) for x,y in polygon],fill=255)
    mask=mask.resize(image.size,Image.Resampling.LANCZOS)
    data=np.array(image);data[:,:,3]=np.round(data[:,:,3].astype(float)*np.asarray(mask)/255).astype('uint8')
    return Image.fromarray(data),mask

def centerline(hip,knee,ankle,s):
    l1=np.linalg.norm(knee-hip);l2=np.linalg.norm(ankle-knee);split=l1/(l1+l2)
    upper=(knee-hip)/l1;lower=(ankle-knee)/l2
    tangent=(upper+lower);tangent/=np.linalg.norm(tangent)
    centers=[];normals=[]
    for value in np.asarray(s):
        if value<=split:
            u=value/split;a,b=hip,knee;ta,tb=upper*l1,tangent*l1
        else:
            u=(value-split)/(1-split);a,b=knee,ankle;ta,tb=tangent*l2,lower*l2
        p=(2*u**3-3*u**2+1)*a+(u**3-2*u**2+u)*ta+(-2*u**3+3*u**2)*b+(u**3-u**2)*tb
        d=(6*u*u-6*u)*a+(3*u*u-4*u+1)*ta+(-6*u*u+6*u)*b+(3*u*u-2*u)*tb
        d/=np.linalg.norm(d);centers.append(p);normals.append([d[1],-d[0]])
    return np.array(centers),np.array(normals)

def premult(image):
    data=np.asarray(image,dtype=np.float32)/255.;data[:,:,:3]*=data[:,:,3:4];return data

class Limb:
    def __init__(self,name,image,polygon,joints,shoe_polygon,shoe_anchor,shoe_scale=1.,top_padding=8):
        self.name=name;self.joints=np.array(joints,dtype=float)
        self.l1=float(np.linalg.norm(self.joints[1]-self.joints[0]));self.l2=float(np.linalg.norm(self.joints[2]-self.joints[1]));self.length=self.l1+self.l2;self.rest_length=self.length
        chord=self.joints[2]-self.joints[0];unit=chord/np.linalg.norm(chord)
        self.bend=1 if np.dot(self.joints[1]-(self.joints[0]+chord/2),[unit[1],-unit[0]])>=0 else -1
        isolated,self.mask=mask_art(image,polygon)
        self.padding=top_padding
        width=90;height=math.ceil(self.length)+top_padding+8
        self.s=(np.arange(height)+.5-top_padding)/self.length
        centers,normals=centerline(*self.joints,self.s)
        lateral=np.arange(width)+.5-width/2
        xy=centers[:,None,:]+normals[:,None,:]*lateral[None,:,None]
        data=raster.sample_texture(premult(isolated),xy[:,:,0],xy[:,:,1])
        self.skin=Image.fromarray(np.round(np.clip(data,0,1)*255).astype('uint8'),'RGBa').convert('RGBA')
        shoe,shoe_mask=mask_art(image,shoe_polygon)
        box=shoe.getbbox();self.shoe=shoe.crop(box);self.shoe_anchor=np.array(shoe_anchor)-np.array(box[:2]);self.shoe_scale=shoe_scale
        alpha=np.asarray(self.shoe.getchannel('A'));ys,xs=np.where(alpha>90)
        self.sole=np.c_[xs,ys];self.sole=self.sole[ys>self.shoe.height*.55]
        self.source_width=float(np.max(np.count_nonzero(np.asarray(self.skin.getchannel('A'))>90,axis=1)))

    def solve(self,hip,x,lift,angle,ground=GROUND):
        theta=math.radians(angle);rotation=np.array([[math.cos(theta),-math.sin(theta)],[math.sin(theta),math.cos(theta)]])
        lowest=float(((self.sole-self.shoe_anchor)@rotation.T*self.shoe_scale)[:,1].max())
        ankle=np.array([hip[0]+x,ground-lowest-lift]);delta=ankle-hip;distance=float(np.linalg.norm(delta))
        if distance>=self.length-.05:
            raise ValueError((self.name,'overextended',round(distance,3),round(self.length,3)))
        unit=delta/distance;along=(self.l1**2-self.l2**2+distance**2)/(2*distance)
        knee=hip+along*unit+self.bend*math.sqrt(max(0,self.l1**2-along**2))*np.array([unit[1],-unit[0]])
        return dict(hip=hip,knee=knee,ankle=ankle,angle=angle,sole=ankle[1]+lowest,ground=ground,lift=lift,extension_margin=self.length-distance)

    def paint(self,canvas,pose):
        image=self.skin
        vs=np.linspace(0.,float(image.height),29);us=np.array([0.,image.width/2,float(image.width)])
        s=(vs-self.padding)/self.rest_length
        centers,normals=centerline(pose['hip'],pose['knee'],pose['ankle'],s)
        # Offsets are source pixels. No width normalization or extra shin taper.
        world=centers[:,None,:]+normals[:,None,:]*(us-image.width/2)[None,:,None]
        source=np.array([[[u,v] for u in us] for v in vs]);dest=(world-np.array(REGION[:2]))*SS
        skin=np.zeros_like(canvas)
        for row in range(len(vs)-1):
            for col in range(2):
                for tri in [[(row,col),(row+1,col),(row,col+1)],[(row+1,col),(row+1,col+1),(row,col+1)]]:
                    raster.paint_textured_triangle(skin,image,np.array([source[r,c] for r,c in tri]),np.array([dest[r,c] for r,c in tri]))
        canvas[:]=skin+canvas*(1-skin[:,:,3:4])
        theta=math.radians(pose['angle']);matrix=np.array([[math.cos(theta),-math.sin(theta)],[math.sin(theta),math.cos(theta)]])*self.shoe_scale
        raster.paint_attachment(canvas,self.shoe,matrix,pose['ankle']-matrix@self.shoe_anchor)

HUMAN={};PET={};PET_BODY={};BODY={};HIP_ROOT={}
CFG={'xiaobai':dict(name='小白',a=24.,hips=[(303.,483.),(314.,482.)],bob=2.),
     'dafeiyu':dict(name='大肥鱼',a=12.,hips=[(284.,515.),(309.,513.)],bob=1.2)}

human_specs={
'xiaobai':dict(
 near=[[(301,478),(330,470),(338,486),(336,514),(343,547),(340,556),(321,557),(313,541),(301,519),(299,504),(304,489)],[(314,480),(318,515),(335,551)]],
 far=[[(287,482),(303,481),(309,497),(300,513),(282,534),(275,545),(278,553),(259,559),(243,548),(240,537),(250,521),(269,500),(280,491)],[(303,480),(282,512),(261,542)]],
 shoe=[(314,547),(343,546),(354,557),(373,565),(380,579),(371,591),(315,594),(307,582),(309,562)],anchor=(334,549)),
'dafeiyu':dict(
 near=[[(291,510),(312,509),(320,515),(325,534),(320,544),(303,545),(294,536),(290,522)],[(306,512),(311,526),(316,540)]],
 far=[[(267,511),(287,511),(294,524),(285,534),(275,539),(258,530),(256,521)],[(281,512),(274,524),(265,533)]],
 shoe=[(299,534),(324,534),(329,546),(325,553),(345,555),(360,568),(360,584),(345,592),(295,590),(284,580),(285,561),(292,549)],anchor=(316,537))}

for role,c in CFG.items():
    source=SOURCES[role];s=human_specs[role];HUMAN[role]={}
    for side in ['far','near']:
        poly,joints=s[side]
        HUMAN[role][side]=Limb(role+'-'+side,source,poly,joints,s['shoe'],s['anchor'],.96 if side=='far' else 1.,24 if role=='xiaobai' else 12)
        # A photographed bent contour is not an anatomical branch selector.
        # Both human knees bend forward, never one forward and one backward.
        HUMAN[role][side].bend=1
    if role=='dafeiyu':
        far=HUMAN[role]['far'];factor=HUMAN[role]['near'].length/far.length
        far.l1*=factor;far.l2*=factor;far.length=far.l1+far.l2
    # Original torso/garments remain; old erased-foot remnants are not reused.
    body=Image.open(BASE/'gait-revision'/role/'body-foreground.png').convert('RGBA')
    if role=='xiaobai':
        data=np.array(body);data[510:610,270:321]=0;body=Image.fromarray(data)
    body.paste((0,0,0,0),(540,380,896,640));BODY[role]=body
    patch=Image.new('RGBA',source.size)
    if role=='xiaobai':
        box=(282,452,348,499);piece=source.crop(box);rgba=np.array(piece)
        weight=1-ease((np.arange(piece.height)+box[1]-485)/14.)
        rgba[:,:,3]=np.round(rgba[:,:,3]*weight[:,None]).astype('uint8')
        patch.alpha_composite(Image.fromarray(rgba),box[:2])
    HIP_ROOT[role]=patch

def calibrated_skin(limb,role,side):
    """Calibrate actual opaque width, rather than compressing a padded image.

    The previous taper mistake is excluded: every visible row gets the measured
    thigh/calf/ankle width once. Original ornament pixels are retained separately.
    """
    native=limb.skin.copy()
    paint=Image.open(BASE/'walk-rig-v2'/role/(side+'-skin.png')).convert('RGBA')
    array=np.asarray(paint);target=Image.new('RGBA',native.size)
    thigh,ankle=(36.,24.) if role=='xiaobai' else (29.,25.)
    for y in range(target.height):
        s=(y+.5-limb.padding)/limb.rest_length
        t=(s+.30)/1.35
        if not 0<t<1:continue
        source_y=min(paint.height-1,round(t*(paint.height-1)))
        xs=np.flatnonzero(array[source_y,:,3]>15)
        if not len(xs):continue
        desired=thigh+(ankle-thigh)*ease((s-.25)/.75)
        desired*=ease(t/.035)*ease((1-t)/.035)
        w=max(1,round(desired))
        row=paint.crop((int(xs.min()),source_y,int(xs.max()+1),source_y+1)).resize((w,1),Image.Resampling.LANCZOS)
        target.alpha_composite(row,((target.width-w)//2,y))
    if role=='xiaobai' and side=='near':
        pixels=np.asarray(native);alpha=np.asarray(target.getchannel('A'))
        band=np.zeros(alpha.shape,dtype=float)
        lo=max(0,limb.padding-8);hi=min(native.height,limb.padding+13)
        pigment=(pixels[:,:,2]>pixels[:,:,0].astype(int)+3)|(pixels[:,:,0]<140)
        band[lo:hi]=pigment[lo:hi]*pixels[lo:hi,:,3]/255.*alpha[lo:hi]/255.
        decoration=native.copy();decoration.putalpha(Image.fromarray(np.round(band*255).astype('uint8')))
        target.alpha_composite(decoration)
    limb.skin=target

for role in HUMAN:
    for side,limb in HUMAN[role].items():calibrated_skin(limb,role,side)

pet_specs={
'xiaobai':dict(offset=13.,
 front_poly=[(692,518),(714,516),(725,536),(734,550),(745,558),(757,563),(758,573),(748,583),(721,584),(708,575),(704,560),(691,547)],
 front_joints=[(704,526),(714,550),(732,568)],front_shoe=[(708,557),(759,557),(759,585),(708,585)],front_anchor=(731,566),
 hind_poly=[(614,521),(640,520),(644,537),(634,548),(622,552),(617,565),(626,572),(620,582),(603,580),(594,571),(598,552),(605,538)],
 hind_joints=[(628,527),(613,549),(611,569)],hind_shoe=[(599,559),(617,558),(620,569),(627,574),(619,583),(601,581),(593,571)],hind_anchor=(609,568),
 far_poly=[(658,542),(699,542),(699,586),(658,586)],
 far_joints=[(687,544),(674,560),(678,575)],far_shoe=[(659,560),(699,560),(699,586),(659,586)],far_anchor=(679,574)),
'dafeiyu':dict(offset=-4.,
 front_poly=[(673,520),(740,520),(740,600),(673,600)],
 front_joints=[(688,529),(697,555),(714,582)],front_shoe=[(683,567),(741,567),(741,599),(683,599)],front_anchor=(714,582),
 hind_poly=[(592,530),(621,526),(630,539),(623,550),(609,559),(603,567),(606,575),(600,584),(585,584),(578,575),(580,558),(586,543)],
 hind_joints=[(614,537),(600,554),(592,575)],hind_shoe=[(583,563),(602,562),(605,572),(606,579),(597,587),(583,585),(576,575)],hind_anchor=(592,574),
 far_poly=[(621,548),(671,548),(671,592),(621,592)],
 far_joints=[(641,551),(642,567),(652,581)],far_shoe=[(626,567),(671,567),(671,593),(626,593)],far_anchor=(650,581))}

for role,s in pet_specs.items():
    source=SOURCES[role];PET[role]={}
    for name,prefix in [('front-near','front'),('hind-near','hind'),('hind-far','far'),('front-far','front')]:
        points=s[prefix+'_shoe'];left=min(p[0] for p in points)-2;right=max(p[0] for p in points)+2;top=min(p[1] for p in points);bottom=max(p[1] for p in points)+2
        rectangle=[(left,top),(right,top),(right,bottom),(left,bottom)]
        PET[role][name]=Limb(role+'-'+name,source,s[prefix+'_poly'],s[prefix+'_joints'],rectangle,s[prefix+'_anchor'],.88 if name=='front-far' else 1.)
    pet=source.copy();pet.paste((0,0,0,0),(0,0,540,640))
    removal=Image.new('L',source.size)
    for prefix in ['front','hind','far']:
        for suffix in ['_poly','_shoe']:
            _,mask=mask_art(source,s[prefix+suffix]);removal=Image.fromarray(np.maximum(np.asarray(removal),np.asarray(mask)))
    # Keep the original painted shoulders, haunches and harness in the torso.
    # Only the protruding lower legs are removed; this avoids empty neck/hip cuts.
    removal=np.array(removal);removal[:550]=0;removal=Image.fromarray(removal)
    data=np.array(pet);data[:,:,3]=np.round(data[:,:,3]*(1-np.asarray(removal)/255.)).astype('uint8')
    # The remaining lower-paw antialias fringe must be removed too. Keeping even
    # a thin original diagonal edge here creates a stationary ghost leg.
    data[550:]=0
    original=np.array(source)
    if role=='dafeiyu':
        data[550:555,625:695]=original[550:555,625:695]
        cyan=(original[:,:,2].astype(int)>original[:,:,0]+25)&(original[:,:,1].astype(int)>original[:,:,0]+25)
        cyan[:545]=False;cyan[564:]=False;cyan[:,:650]=False
        cyan=np.asarray(Image.fromarray(cyan.astype('uint8')*255).filter(ImageFilter.MaxFilter(3)))>0
        data[cyan]=original[cyan]
    PET_BODY[role]=Image.fromarray(data)

def step(phase,a,duty,lift):
    p=phase%1
    if p<duty:return a-2*a*p/duty,0.,0.,True
    u=(p-duty)/(1-duty);v=-2*a*(1-duty)/duty
    x=-a+v*u+(2*a-v)*ease(u)
    return float(x),lift*math.sin(math.pi*u)**4,0.,False

def poses(role,tick):
    c=CFG[role];cycle=tick/CYCLE;root=cycle*2*c['a']/DUTY
    body_y=c['bob']*math.cos(4*math.pi*(cycle-.06));human=[];pet=[]
    for number,side,offset in [(0,'far',.5),(1,'near',0.)]:
        x,lift,angle,stance=step(cycle+offset,c['a'],DUTY,3. if role=='xiaobai' else 1.5)
        hip=np.array(c['hips'][number])+[0,body_y]
        pose=HUMAN[role][side].solve(hip,x,lift,angle);pose.update(stance=stance,side=side);human.append((HUMAN[role][side],pose))
    petcycle=cycle*2;petduty=.66;pet_a=(2*c['a']/DUTY)*petduty/4
    pet_y=.55*math.cos(4*math.pi*petcycle)
    offset=pet_specs[role]['offset']
    for name,phase in [('hind-far',.75),('front-far',.5),('hind-near',.25),('front-near',0.)]:
        limb=PET[role][name]
        source_hip=limb.joints[0].copy()
        if name=='front-far':source_hip+=(-15,-1)
        if name=='hind-far':source_hip=PET[role]['hind-near'].joints[0]+(-12,10 if role=='xiaobai' else 12)
        hip=source_hip+[0,offset+pet_y]
        x,lift,angle,stance=step(petcycle+phase,pet_a,petduty,2.4)
        # Preserve the original three-quarter view: rear/far paw contacts lie
        # farther up the picture than the closest front paw.
        depth={'front-near':0,'front-far':-4,'hind-near':0 if role=='xiaobai' else -10,'hind-far':-4 if role=='xiaobai' else -9}[name]
        pose=limb.solve(hip,x,lift,angle,GROUND+depth);pose.update(stance=stance,side=name);pet.append((limb,pose))
    return human,pet,root,body_y,offset+pet_y

def blank():
    return np.zeros(((REGION[3]-REGION[1])*SS,(REGION[2]-REGION[0])*SS,4),np.float32)

def image_layer(canvas):
    image=Image.fromarray(np.round(np.clip(canvas,0,1)*255).astype('uint8'),'RGBa')
    return image.resize((REGION[2]-REGION[0],REGION[3]-REGION[1]),Image.Resampling.LANCZOS).convert('RGBA')

def shift(image,y):
    return image.convert('RGBa').transform(image.size,Image.Transform.AFFINE,(1,0,0,0,1,-y),Image.Resampling.BILINEAR).convert('RGBA')

def character(role,tick):
    human,pet,root,bob,petbob=poses(role,tick)
    legs=blank()
    for limb,pose in human:limb.paint(legs,pose)
    output=Image.new('RGBA',(896,640));output.alpha_composite(image_layer(legs),REGION[:2]);output.alpha_composite(shift(HIP_ROOT[role],bob));output.alpha_composite(shift(BODY[role],bob))
    # Clear the old pet and bridge the existing rope to the stabilized pet body.
    petlegs=blank()
    for limb,pose in pet:limb.paint(petlegs,pose)
    petimage=Image.new('RGBA',(896,640));petimage.alpha_composite(image_layer(petlegs),REGION[:2]);petimage.alpha_composite(shift(PET_BODY[role],petbob))
    output.alpha_composite(petimage)
    # The reference's continuous rope is translated with a gradual falloff from
    # the moving hand to the pet collar; no source-frame changes are involved.
    source=premult(SOURCES[role]);yy,xx=np.mgrid[395:535,410:650]
    dy=bob+(petbob-bob)*ease((xx-410)/240)
    rope=raster.sample_texture(source,xx+.5,yy+.5-dy)
    rope=Image.fromarray(np.round(np.clip(rope,0,1)*255).astype('uint8'),'RGBa').convert('RGBA')
    # Only the free rope corridor, before the pet's body, is replaced.
    output.paste((0,0,0,0),(430,400,575,535));output.alpha_composite(rope.crop((20,5,165,140)),(430,400))
    return output,human,pet,root

if __name__=='__main__':
    OUT.mkdir(exist_ok=True)
    for role in CFG:
        for tick in range(CYCLE):poses(role,tick)
        print(role,'motion reachable',[(name,round(limb.source_width,2),round(limb.length,2)) for name,limb in HUMAN[role].items()])
