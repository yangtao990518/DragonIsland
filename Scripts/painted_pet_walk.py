"""Stabilise painted key poses and interpolate a review-only 60fps cycle.

All anatomical silhouettes come from the imagegen sheets; no limb is replaced
by a tube or split into independent shin/shoe attachments. Source files remain
unchanged, and output is deliberately outside all App resource manifests.
"""
import hashlib,json,math,sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from animation_runtime import REPOSITORY,FONT

sys.path.insert(0,str(REPOSITORY.parent/'tools/python-animation'))
import cv2
BASE=REPOSITORY/'output/pet-walk-batch2'
OUT=BASE/'walk-painted-v7'
FPS=60; CYCLE=96
CFG={'xiaobai':dict(name='小白',a=21.,duty=.64),'dafeiyu':dict(name='大肥鱼',a=14.,duty=.64)}

def ease(x):
    x=np.clip(x,0.,1.);return x*x*x*(10+x*(-15+6*x))

def premult(image):
    a=np.array(image,dtype=np.float32)/255
    a[:,:,:3]*=a[:,:,3:4]
    return a

def unpremult(a):
    a=np.clip(a,0,1).copy()
    a[:,:,:3]/=np.maximum(a[:,:,3:4],1/255.)
    return Image.fromarray(np.round(np.clip(a,0,1)*255).astype('uint8'))

def gray(rgba):
    # Alpha participates in flow so thin shoe/leg outlines remain trackable.
    return cv2.cvtColor(np.round(rgba[:,:,:3]*255).astype('uint8'),cv2.COLOR_RGB2GRAY)

def align_matrix(source,reference,box):
    mask=np.zeros(source.shape[:2],np.uint8);mask[box[1]:box[3],box[0]:box[2]]=255
    sift=cv2.SIFT_create(nfeatures=1800,contrastThreshold=.015)
    ks,ds=sift.detectAndCompute(gray(source),mask)
    kr,dr=sift.detectAndCompute(gray(reference),mask)
    matches=cv2.BFMatcher().knnMatch(ds,dr,k=2)
    matches=[m for m,n in matches if m.distance<.74*n.distance]
    if len(matches)<5:raise ValueError(('not enough upper-body registration matches',len(matches)))
    src=np.float32([ks[m.queryIdx].pt for m in matches]);dst=np.float32([kr[m.trainIdx].pt for m in matches])
    matrix,inliers=cv2.estimateAffinePartial2D(src,dst,method=cv2.RANSAC,ransacReprojThreshold=2.,maxIters=4000)
    scale=float(np.linalg.norm(matrix[:,0]));angle=math.degrees(math.atan2(matrix[1,0],matrix[0,0]))
    if not .90<scale<1.10 or abs(angle)>5:raise ValueError(('bad registration',scale,angle))
    return matrix,dict(matches=len(matches),inliers=int(inliers.sum()),scale=scale,angle_degrees=angle,matrix=matrix.tolist())

def clean_key(path):
    rgba=np.array(Image.open(path).convert('RGBA'))
    count,labels,stats,_=cv2.connectedComponentsWithStats((rgba[:,:,3]>25).astype('uint8'),8)
    keep=np.zeros(rgba.shape[:2],bool)
    for label in range(1,count):
        if stats[label,cv2.CC_STAT_AREA]>=80:keep|=labels==label
    # Keep native antialiasing immediately around substantial painted pieces.
    keep=cv2.dilate(keep.astype('uint8'),np.ones((3,3),np.uint8))>0
    rgba[~keep]=0
    rgba[rgba[:,:,3]<5]=0
    return premult(Image.fromarray(rgba))

def remap(source,mx,my):
    return cv2.remap(source,mx.astype('float32'),my.astype('float32'),cv2.INTER_LINEAR,borderMode=cv2.BORDER_CONSTANT)

def stabilise(role):
    paths=sorted((OUT/role/'keys').glob('*.png'))
    keys=[clean_key(p) for p in paths];reference=keys[0]
    h,w=reference.shape[:2];yy,xx=np.mgrid[:h,:w].astype('float32')
    result=[];report=[]
    for i,key in enumerate(keys):
        if i==0:
            human=pet=np.array([[1.,0.,0.],[0.,1.,0.]])
            metrics={'reference':True}
        else:
            human,hm=align_matrix(key,reference,(40,5,300,235))
            pet,pm=align_matrix(key,reference,(365,205,507,299))
            metrics=dict(human=hm,pet=pm)
        ih=cv2.invertAffineTransform(human);ip=cv2.invertAffineTransform(pet)
        p=ease((xx-275)/100)
        hx=ih[0,0]*xx+ih[0,1]*yy+ih[0,2];hy=ih[1,0]*xx+ih[1,1]*yy+ih[1,2]
        px=ip[0,0]*xx+ip[0,1]*yy+ip[0,2];py=ip[1,0]*xx+ip[1,1]*yy+ip[1,2]
        aligned=remap(key,hx*(1-p)+px*p,hy*(1-p)+py*p)
        # Keep at least one support sole on the common contact plane without
        # moving heads or hips. The small correction is spread over the entire
        # painted lower body, not applied as a disconnected shoe translation.
        offsets=[]
        mx=xx.copy();my=yy.copy()
        for left,right,top in [(120,285,265 if role=='xiaobai' else 280),(345,508,300)]:
            src=np.where(aligned[top:,left:right,3]>.5)[0]+top
            ref=np.where(reference[top:,left:right,3]>.5)[0]+top
            offset=float(ref.max()-src.max())
            region=(xx>=left)&(xx<right)
            yweight=ease((yy-(top-20))/(float(ref.max())-(top-20)))
            my-=region*yweight*offset
            offsets.append(offset)
        aligned=remap(aligned,mx,my)
        # Preserve original key-0 upper artwork exactly. The lower garment,
        # complete painted legs, and pet haunches retain their coherent poses.
        boundary=np.where(xx<325,235.,290.)
        weight=ease((yy-boundary)/22)[:,:,None]
        aligned=reference*(1-weight)+aligned*weight
        unpremult(aligned).save(OUT/role/f'stabilised-{i:02}.png')
        result.append(aligned)
        report.append(dict(key=i,registration=metrics,sole_vertical_corrections=offsets))
    return result,report

def flow_pair(a,b):
    engine=cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM)
    engine.setFinestScale(0)
    engine.setGradientDescentIterations(40)
    engine.setVariationalRefinementIterations(8)
    forward=engine.calc(gray(a),gray(b),None)
    backward=engine.calc(gray(b),gray(a),None)
    return forward,backward

def interpolate(a,b,forward,backward,t):
    if t==0:return a.copy()
    h,w=a.shape[:2];yy,xx=np.mgrid[:h,:w].astype('float32')
    ax=xx.copy();ay=yy.copy();bx=xx.copy();by=yy.copy()
    for _ in range(4):
        f=remap(forward,ax,ay);g=remap(backward,bx,by)
        ax=xx-t*f[:,:,0];ay=yy-t*f[:,:,1]
        bx=xx-(1-t)*g[:,:,0];by=yy-(1-t)*g[:,:,1]
    wa=remap(a,ax,ay);wb=remap(b,bx,by)
    # Use bidirectional geometric consistency to reduce duplicate outlines
    # in disoccluded toes, crossing legs and thin leash edges.
    fa=remap(forward,ax,ay);ga=remap(backward,ax+fa[:,:,0],ay+fa[:,:,1])
    gb=remap(backward,bx,by);fb=remap(forward,bx+gb[:,:,0],by+gb[:,:,1])
    ca=np.exp(-np.linalg.norm(fa+ga,axis=2)/3.)
    cb=np.exp(-np.linalg.norm(gb+fb,axis=2)/3.)
    alpha=(1-t)*ca;beta=t*cb
    weight=beta/np.maximum(alpha+beta,1e-5)
    return wa*(1-weight[:,:,None])+wb*weight[:,:,None]

def render():
    report={}
    for role in CFG:
        keys,registration=stabilise(role)
        flows=[flow_pair(keys[i],keys[(i+1)%8]) for i in range(8)]
        folder=OUT/role/'frames-60fps';folder.mkdir(exist_ok=True)
        hashes=[]
        for tick in range(CYCLE):
            key=tick//12;t=(tick%12)/12
            image=unpremult(interpolate(keys[key],keys[(key+1)%8],*flows[key],t))
            image.save(folder/f'{tick:03}.png')
            hashes.append(hashlib.sha256(image.tobytes()).hexdigest())
        report[role]=dict(registration=registration,unique_frames=len(set(hashes)),hashes=hashes)
        print(role,'96 continuously interpolated frames saved',flush=True)
    (OUT/'interpolation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')

if __name__=='__main__':render()
