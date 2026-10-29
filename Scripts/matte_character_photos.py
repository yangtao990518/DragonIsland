"""Extract display alpha from the supplied white plates; never redraw the subject."""
import json
import hashlib
from pathlib import Path
import cv2
import numpy as np
from PIL import Image
from pymatting import estimate_alpha_cf
from pymatting.preconditioner import ichol

ROOT=Path(__file__).resolve().parents[1]
# Reviewed white background anchors; coordinates survive component relabeling.
SEEDS=json.loads((ROOT/'Art/CharacterPhotos/matting-seeds.json').read_text(encoding='utf-8'))

def extract(path, destination, source_hash):
    seeds=SEEDS[path.relative_to(ROOT).as_posix()]
    if hashlib.sha256(path.read_bytes()).hexdigest()!=source_hash or seeds['sha256']!=source_hash:
        raise ValueError('Reviewed background seeds do not match the supplied plate: '+str(path))
    rgb=np.array(Image.open(path).convert('RGB'))
    values=rgb.astype(np.int16)
    white=((values.min(2)>=245)&(values.max(2)-values.min(2)<=9)).astype('uint8')
    _,labels=cv2.connectedComponents(white,connectivity=8)
    border=np.unique(np.concatenate((labels[0],labels[-1],labels[:,0],labels[:,-1])))
    enclosed=[int(labels[y,x]) for x,y in seeds['backgroundHoleSeeds']]
    if any(label==0 for label in enclosed):
        raise ValueError('Background anchor is not on the reviewed white plate')
    bg=np.isin(labels,list(border[border!=0])+enclosed).astype('uint8')
    kernel=np.ones((5,5),np.uint8)
    tri=np.full(bg.shape,.5)
    tri[cv2.erode(bg,kernel)>0]=0
    tri[cv2.erode(1-bg,kernel)>0]=1
    def preconditioner(matrix):
        return ichol(matrix,max_nnz=min(8_000_000,max(100_000,matrix.nnz*12)))
    alpha=estimate_alpha_cf(rgb.astype('float64')/255,tri,
        laplacian_kwargs={'epsilon':1e-6},cg_kwargs={'maxiter':2000,'rtol':1e-5},
        preconditioner=preconditioner)
    alpha[alpha<.002]=0;alpha[alpha>.998]=1
    # Recover the foreground against the known white plate. No pose/color edit.
    fg=np.clip((rgb/255-(1-alpha[:,:,None]))/np.maximum(alpha[:,:,None],1e-6),0,1)
    fg[alpha==0]=0
    result=Image.fromarray(np.dstack((np.round(fg*255).astype('uint8'),np.round(alpha*255).astype('uint8'))),'RGBA')
    destination.parent.mkdir(parents=True,exist_ok=True)
    result.save(destination)
    return result

def main():
    catalog=json.loads((ROOT/'Shared/Resources/Characters.json').read_text(encoding='utf-8'))
    for character in catalog:
        for photo in character.get('artworks',[]):
            source=ROOT/photo['source']
            output=source.parent/'transparent'/source.name
            image=extract(source,output,photo['sha256'])
            print('Transparent display copy',output.relative_to(ROOT),image.getbbox(),flush=True)
            board=Image.new('RGBA',(image.width*2,image.height))
            for index,color in enumerate(('#181629','#e9e0f7')):
                background=Image.new('RGBA',image.size,color);background.alpha_composite(image)
                board.paste(background,(index*image.width,0))
            target=ROOT/'output/photo-alpha-review'/character['id']/source.name
            target.parent.mkdir(parents=True,exist_ok=True);board.convert('RGB').save(target)

if __name__=='__main__':main()
