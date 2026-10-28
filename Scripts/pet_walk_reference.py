"""Review-only native-art walking study.

The original painted limb is deformed in its original two-dimensional plane.
There are no replacement skin tubes, resized shoes or frame-indexed pet feet.
"""
import importlib.util
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from animation_runtime import REPOSITORY

BASE = REPOSITORY / 'output/pet-walk-batch2'
OUT = BASE / 'walk-reference-v6'
FPS = 60
CYCLE = 96
DUTY = .64
SS = 3
REGION = (210, 420, 805, 615)
spec = importlib.util.spec_from_file_location('reference_raster', BASE/'walk-rig-v3-stable/rig.py')
raster = importlib.util.module_from_spec(spec)
spec.loader.exec_module(raster)
raster.REGION, raster.SS = REGION, SS

def ease(x):
    x = np.clip(x, 0., 1.)
    return x*x*x*(10+x*(-15+6*x))

def rotation(angle):
    return np.array([[math.cos(angle), -math.sin(angle)], [math.sin(angle), math.cos(angle)]])

def direction(v):
    return math.atan2(v[1], v[0])

def cut(image, polygon):
    mask = Image.new('L', (image.width*4, image.height*4))
    ImageDraw.Draw(mask).polygon([(round(x*4), round(y*4)) for x,y in polygon], fill=255)
    mask = mask.resize(image.size, Image.Resampling.LANCZOS)
    rgba = np.array(image)
    rgba[:,:,3] = np.round(rgba[:,:,3]*np.asarray(mask,dtype=float)/255).astype('uint8')
    return Image.fromarray(rgba), mask

def shift(image, dx=0., dy=0.):
    return image.convert('RGBa').transform(image.size, Image.Transform.AFFINE,
        (1,0,-dx,0,1,-dy), Image.Resampling.BILINEAR).convert('RGBA')

def image_layer(canvas):
    image = Image.fromarray(np.round(np.clip(canvas,0,1)*255).astype('uint8'), 'RGBa')
    return image.resize((REGION[2]-REGION[0],REGION[3]-REGION[1]),Image.Resampling.LANCZOS).convert('RGBA')

class NativeLimb:
    def __init__(self, name, source, polygon, joints, foot_y, bend=1, length_scale=1., human=False, shoe=None):
        self.name = name
        self.source, self.mask = cut(source, polygon)
        if human:
            rgba=np.array(self.source)
            rgb=rgba[:,:,:3].astype(int)
            skin=(rgb[:,:,0]>rgb[:,:,2]+5)&(rgb[:,:,0]>=rgb[:,:,1]-2)&(rgb[:,:,0]>145)&(rgba[:,:,3]>0)
            edge=np.array(Image.fromarray(skin.astype('uint8')*255).filter(ImageFilter.MaxFilter(5)))
            if shoe:
                _,shoemask=cut(source,shoe)
                edge[foot_y-3:]=np.asarray(shoemask)[foot_y-3:]
            else:edge[foot_y-3:]=255
            rgba[:,:,3]=np.minimum(rgba[:,:,3],edge)
            self.source=Image.fromarray(rgba)
        self.joints = np.array(joints,dtype=float)
        self.l1, self.l2 = np.linalg.norm(np.diff(self.joints,axis=0),axis=1)*length_scale
        self.bend = bend
        self.foot_y = foot_y
        self.length_scale = length_scale
        self.human=human
        box = self.source.getbbox()
        self.box = box
        self.art = self.source.crop(box)
        alpha = np.array(self.source.getchannel('A'))
        ys,xs = np.where((alpha>120)&(np.indices(alpha.shape)[0]>=foot_y))
        self.sole = np.c_[xs,ys]
        # A modest grid retains the original contour and pigmentation. All skin,
        # sock and shoe pixels share one mesh, including the ankle transition.
        xx = np.linspace(box[0],box[2],math.ceil((box[2]-box[0])/7)+1)
        yy = np.linspace(box[1],box[3],math.ceil((box[3]-box[1])/6)+1)
        self.grid = np.stack(np.meshgrid(xx,yy),axis=-1)
        h,k,a = self.joints
        p = self.grid
        along_upper = np.sum((p-h)*(k-h),axis=-1)/np.dot(k-h,k-h)
        self.knee_weight = ease((along_upper-.72)/.56)
        self.foot_weight = ease((p[:,:,1]-(foot_y-6))/12.)
        self.rest_angles = [direction(k-h),direction(a-k)]

    def solve(self, hip, x, lift, angle=0., ground=590.):
        hip = np.array(hip,dtype=float)
        r = rotation(angle)
        bottom = ((self.sole-self.joints[2])@r.T)[:,1].max()
        ankle = np.array([hip[0]+x,ground-bottom-lift])
        delta = ankle-hip
        distance = np.linalg.norm(delta)
        if distance >= self.l1+self.l2-.01:
            raise ValueError((self.name,'unreachable',distance,self.l1+self.l2))
        unit = delta/distance
        along = (self.l1*self.l1-self.l2*self.l2+distance*distance)/(2*distance)
        knee = hip+along*unit+self.bend*math.sqrt(max(0.,self.l1*self.l1-along*along))*np.array([unit[1],-unit[0]])
        return dict(hip=hip,knee=knee,ankle=ankle,angle=angle,ground=ground,
            sole=ankle[1]+bottom,lift=lift,extension_margin=self.l1+self.l2-distance)

    def vertices(self, pose):
        h,k,a = self.joints
        target = [pose['hip'],pose['knee'],pose['ankle']]
        angles = np.array([direction(target[1]-target[0])-self.rest_angles[0],
            direction(target[2]-target[1])-self.rest_angles[1],pose['angle']])
        angles = np.unwrap(angles)
        transforms = []
        for i,(origin,end) in enumerate(zip([h,k,a],target)):
            scale = self.length_scale if i<2 else 1.
            transforms.append((self.grid-origin)@rotation(angles[i]).T*scale+end)
        # Rotation-normalized blending avoids the pinched knee produced by
        # ordinary two-bone linear blend skinning, while retaining native UVs.
        w = self.knee_weight[:,:,None]
        merged = transforms[0]*(1-w)+transforms[1]*w
        f = self.foot_weight[:,:,None]
        output=merged*(1-f)+transforms[2]*f
        if self.human:
            end=494 if self.name.startswith('xiaobai') else 512
            weight=ease((self.grid[:,:,1]-end)/17)[:,:,None]
            fixed=self.grid+(pose['hip']-h)
            output=fixed*(1-weight)+output*weight
        return output

    def paint(self, canvas, pose):
        world = self.vertices(pose)
        destination = (world-np.array(REGION[:2]))*SS
        source = self.grid-np.array(self.box[:2])
        layer = np.zeros_like(canvas)
        for row in range(source.shape[0]-1):
            for col in range(source.shape[1]-1):
                for tri in [[(row,col),(row+1,col),(row,col+1)],[(row+1,col),(row+1,col+1),(row,col+1)]]:
                    raster.paint_textured_triangle(layer,self.art,
                        np.array([source[r,c] for r,c in tri]),np.array([destination[r,c] for r,c in tri]))
        canvas[:] = layer+canvas*(1-layer[:,:,3:4])

SOURCES = {r:Image.open(BASE/(r+'-walk')/'frames/000.png').convert('RGBA') for r in ['xiaobai','dafeiyu']}
CFG = {'xiaobai':dict(name='小白',a=21.,hips=[(300.,465.),(315.,465.)],bob=.8,lift=4.),
       'dafeiyu':dict(name='大肥鱼',a=12.,hips=[(281.,497.),(310.,497.)],bob=.5,lift=2.5)}

# The proximal roots extend behind the original garments; the visible leg,
# sock and shoe retain the original artwork's size. No tube reconstruction.
HUMAN_SPEC = {
 'xiaobai':dict(polygon=[(299,466),(326,463),(337,480),(338,507),(344,542),(351,551),(368,561),(378,570),(378,583),(365,590),(315,594),(306,582),(307,560),(313,547),(302,524),(298,506),(301,489)],
    joints=[(315,462),(320,508),(334,550)],foot_y=550,scale=1.,
    shoe=[(314,547),(343,546),(354,557),(373,565),(380,579),(371,591),(315,594),(307,582),(309,562)]),
 'dafeiyu':dict(polygon=[(285,500),(318,500),(324,520),(326,535),(334,541),(328,550),(338,555),(352,558),(363,570),(361,585),(345,594),(293,592),(282,581),(283,561),(291,550),(287,531)],
    joints=[(306,496),(311,520),(316,541)],foot_y=543,scale=1.06,shoe=None)}
HUMAN = {}
BODY = {}
for role,c in CFG.items():
    s = HUMAN_SPEC[role]
    HUMAN[role] = {side:NativeLimb(role+'-'+side,SOURCES[role],s['polygon'],s['joints'],s['foot_y'],1,s['scale'],True,s['shoe']) for side in ['far','near']}
    if role=='xiaobai':
        HUMAN[role]['far']=NativeLimb(role+'-far',SOURCES[role],
            [(285,477),(306,477),(313,492),(304,510),(289,530),(279,546),(283,562),(285,574),(278,581),(252,583),(239,568),(229,545),(240,527),(263,503),(281,489)],
            [(301,462),(277,510),(260,543)],544,1,1.07,True,
            [(242,541),(271,544),(272,557),(279,564),(283,573),(280,579),(266,581),(253,576),(245,567),(239,556)])
    body = Image.open(BASE/'gait-revision'/role/'body-foreground.png').convert('RGBA')
    body.paste((0,0,0,0),(540,380,896,640))
    if role=='xiaobai':
        body.paste((0,0,0,0),(270,510,321,610))
        # Keep the painted opening and garter with the garment, hiding the rig
        # roots behind its actual edge rather than a flat rectangular cap.
        patch = SOURCES[role].crop((278,451,342,491))
        data = np.array(patch)
        data[:,:,3] = np.round(data[:,:,3]* (1-ease((np.arange(patch.height)+451-482)/9))[:,None]).astype('uint8')
        body.alpha_composite(Image.fromarray(data),(278,451))
    BODY[role] = body

PET_SPEC = {
 'xiaobai':dict(offset=0.,front=dict(poly=[(696,512),(716,515),(722,530),(730,546),(739,555),(754,560),(758,568),(751,578),(735,582),(722,579),(713,570),(708,553),(698,542)],joints=[(707,522),(717,547),(733,567)],foot=561),
    hind=dict(poly=[(606,516),(632,511),(641,524),(641,538),(628,550),(619,557),(618,565),(626,573),(621,580),(605,580),(594,573),(594,561),(599,545)],joints=[(626,523),(613,548),(610,568)],foot=564),
    far=dict(poly=[(665,541),(689,541),(699,549),(690,558),(686,563),(693,571),(695,578),(684,581),(666,579),(657,572),(660,556)],joints=[(685,545),(674,560),(678,573)],foot=566)),
 'dafeiyu':dict(offset=0.,front=dict(poly=[(675,525),(690,521),(704,526),(711,540),(716,555),(724,567),(737,579),(740,588),(731,596),(712,595),(698,585),(689,573),(681,557),(675,541)],joints=[(688,530),(700,558),(717,584)],foot=577),
    hind=dict(poly=[(590,531),(611,525),(623,533),(624,545),(613,555),(605,566),(604,575),(599,582),(585,583),(577,576),(578,562),(582,547)],joints=[(610,537),(598,554),(592,573)],foot=568),
    far=dict(poly=[(622,548),(644,546),(652,556),(656,569),(667,578),(665,585),(651,589),(636,584),(628,573),(624,562)],joints=[(636,549),(641,567),(653,581)],foot=575))}
PET = {}; PET_BODY = {}
for role,specification in PET_SPEC.items():
    PET[role] = {}
    source = SOURCES[role]
    for name,prefix in [('hind-far','hind'),('front-far','far'),('hind-near','hind'),('front-near','front')]:
        s = specification[prefix]
        joint = np.array(s['joints'],dtype=float)
        chord = joint[2]-joint[0]
        bend = 1 if np.dot(joint[1]-(joint[0]+chord/2),[chord[1],-chord[0]])>=0 else -1
        PET[role][name] = NativeLimb(role+'-'+name,source,s['poly'],s['joints'],s['foot'],bend,1.04)
    # Erase the protruding source limbs with their painted outlines, leaving
    # curved haunches/shoulders instead of cutting the whole pet at one y value.
    body = source.copy(); body.paste((0,0,0,0),(0,0,540,640))
    data = np.array(body)
    yy,xx = np.indices(data.shape[:2])
    removal = np.zeros(data.shape[:2],dtype=float)
    for prefix in ['front','hind','far']:
        limb = PET[role]['front-near' if prefix=='front' else 'hind-near' if prefix=='hind' else 'front-far']
        root = limb.joints[0]
        start = {'front':550 if role=='xiaobai' else 561,'hind':539 if role=='xiaobai' else 549,'far':546 if role=='xiaobai' else 551}[prefix]
        region = np.asarray(limb.mask.filter(ImageFilter.MaxFilter(5)),dtype=float)/255
        removal = np.maximum(removal,region*ease((yy-start)/9))
    data[:,:,3] = np.round(data[:,:,3]*(1-removal)).astype('uint8')
    PET_BODY[role] = Image.fromarray(data)

def step(phase,a,duty,lift):
    p=phase%1
    if p<duty:
        return a-2*a*p/duty,0.,True
    u=(p-duty)/(1-duty)
    velocity=-2*a*(1-duty)/duty
    x=-a+velocity*u+(2*a-velocity)*ease(u)
    return float(x),lift*math.sin(math.pi*u)**2,False

def poses(role,tick):
    c=CFG[role]; cycle=tick/CYCLE
    root=cycle*2*c['a']/DUTY
    bob=-c['bob']*math.cos(4*math.pi*cycle)
    humans=[]; pets=[]
    for i,(side,phase) in enumerate([('far',.5),('near',0.)]):
        x,lift,stance=step(cycle+phase,c['a'],DUTY,c['lift'])
        hip=np.array(c['hips'][i])+[0,bob]
        limb=HUMAN[role][side]
        angle=math.radians(-24) if role=='xiaobai' and side=='far' else 0.
        pose=limb.solve(hip,x,lift,angle)
        pose.update(stance=stance,side=side)
        humans.append((limb,pose))
    duty=.68; petcycle=cycle*2
    amplitude=(2*c['a']/DUTY)*duty/4
    for name,phase in [('hind-far',.75),('front-far',.5),('hind-near',.25),('front-near',0.)]:
        limb=PET[role][name]
        hip=limb.joints[0].copy()
        if name=='hind-far': hip+=(-10,3)
        hip += (0,10 if role=='xiaobai' else -4)
        x,lift,stance=step(petcycle+phase,amplitude,duty,2.5)
        # Maintain each painted paw's native contact depth. The far legs stay
        # shorter in the picture, as in the reference's three-quarter view.
        depth={'front-near':0,'front-far':-6,'hind-near':-8 if role=='dafeiyu' else -1,'hind-far':-7}[name]
        offset=10 if role=='xiaobai' else -4
        ground=float(limb.sole[:,1].max())+offset
        if name=='hind-far':ground-=3
        bias={'front-near':19. if role=='xiaobai' else 19.,'front-far':-5. if role=='xiaobai' else 7.,'hind-near':-10.,'hind-far':-10.}[name]
        pose=limb.solve(hip,x+bias,lift,0.,ground)
        pose.update(stance=stance,side=name)
        pets.append((limb,pose))
    return humans,pets,root,bob

def character(role,tick):
    humans,pets,root,bob=poses(role,tick)
    canvas=np.zeros(((REGION[3]-REGION[1])*SS,(REGION[2]-REGION[0])*SS,4),np.float32)
    for limb,pose in humans: limb.paint(canvas,pose)
    output=Image.new('RGBA',(896,640)); output.alpha_composite(image_layer(canvas),REGION[:2])
    output.alpha_composite(shift(BODY[role],dy=bob))
    canvas.fill(0)
    for limb,pose in pets: limb.paint(canvas,pose)
    output.alpha_composite(image_layer(canvas),REGION[:2])
    output.alpha_composite(shift(PET_BODY[role],dy=10 if role=='xiaobai' else -4))
    # Existing slack rope keeps both endpoints, with a subpixel vertical warp.
    source=raster.texture(SOURCES[role]);yy,xx=np.mgrid[400:535,430:575]
    dy=bob*(1-ease((xx-410)/240))
    rope=raster.sample_texture(source,xx+.5,yy+.5-dy)
    rope=Image.fromarray(np.round(np.clip(rope,0,1)*255).astype('uint8'),'RGBa').convert('RGBA')
    output.paste((0,0,0,0),(430,400,575,535));output.alpha_composite(rope,(430,400))
    return output,humans,pets,root

def audit():
    OUT.mkdir(exist_ok=True)
    for role in CFG:
        for tick in range(CYCLE): poses(role,tick)
        board=Image.new('RGB',(1600,1000),'#181d2f');draw=ImageDraw.Draw(board)
        for i,tick in enumerate([0,12,24,36,48,60,72,84]):
            art,*_=character(role,tick)
            art.save(OUT/f'{role}-key-{tick:02}.png')
            for row,crop in enumerate([(225,450,420,608),(570,505,780,607)]):
                image=art.crop(crop).resize((390,316 if row==0 else 190),Image.Resampling.LANCZOS)
                x=(i%4)*400;y=(i//4)*500
                board.paste(image,(x,y+(0 if row==0 else 305)),image)
            draw.text(((i%4)*400+8,(i//4)*500+5),f'{tick}/96',fill='white')
        board.save(OUT/f'{role}-key-audit.png')
        print(role,'all poses reachable',[(name,limb.l1+limb.l2) for name,limb in HUMAN[role].items()],flush=True)

if __name__=='__main__':audit()
