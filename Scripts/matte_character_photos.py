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
# Reviewed enclosed background holes, keyed to these immutable supplied plates.
# These are connected white regions, never painted outlines or erased colors.
HOLES={
 'sea-breeze.png':[31,67,79,93,96,99,101,104,105,108,112,115,118,120,128,133,137,140,141,145,149,150,169,174,175,194,198,199,207,209,212,213,233,235,237,243,253,262,263,266,273,321,332,421,511,557,583,633,765],
 'standing.png':[119,166,196,204,201,162,171,199,236],
 'chibi.png':[129,132,197,201,191],
 'omelet.png':[128,172,175,187,189,190,191,193,242,250,289,340,323,348,344],
 'white-dragon.png':[],
}

def extract(path, destination, source_hash):
    if hashlib.sha256(path.read_bytes()).hexdigest()!=source_hash:
        raise ValueError('Reviewed background seeds do not match the supplied plate: '+str(path))
    rgb=np.array(Image.open(path).convert('RGB'))
    values=rgb.astype(np.int16)
    white=((values.min(2)>=245)&(values.max(2)-values.min(2)<=9)).astype('uint8')
    _,labels=cv2.connectedComponents(white,connectivity=8)
    border=np.unique(np.concatenate((labels[0],labels[-1],labels[:,0],labels[:,-1])))
    bg=np.isin(labels,list(border[border!=0])+HOLES[path.name]).astype('uint8')
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
