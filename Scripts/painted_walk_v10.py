"""Four poses painted as one consistent sheet; neural 60fps review export."""
import numpy as np
from PIL import Image
import painted_walk_v8 as pipeline
from painted_pet_walk import cv2,premult

pipeline.OUT=pipeline.SOURCE.parent/'walk-painted-v10'
pipeline.FILES={'xiaobai':'exec-d75e07ae-f58c-4bb6-a1ef-5c3c898f3c3a.png',
                'dafeiyu':'exec-e3f3a6d3-45bc-4afb-81bf-16a2e1e4caee.png'}

def keys(role):
    sheet=Image.open(pipeline.SOURCE/'generated'/pipeline.FILES[role]).convert('RGBA')
    folder=pipeline.OUT/role/'inputs';folder.mkdir(parents=True,exist_ok=True)
    result=[]
    for index in range(4):
        x=index%2;y=index//2;w=sheet.width//2;h=sheet.height//2
        image=sheet.crop((x*w,y*h,(x+1)*w,(y+1)*h))
        rgba=np.array(image)
        # The generated sheets contain low-alpha matte noise. Suppress that
        # noise before downsampling so it cannot become a bright moving fringe.
        alpha=np.clip((rgba[:,:,3].astype(float)-80)*255/160,0,255)
        count,labels,stats,_=cv2.connectedComponentsWithStats((alpha>100).astype('uint8'),8)
        keep=np.zeros(alpha.shape,np.uint8)
        for label in range(1,count):
            if stats[label,cv2.CC_STAT_AREA]>=150:keep[labels==label]=255
        keep=cv2.dilate(keep,np.ones((3,3),np.uint8))
        alpha*=keep/255
        rgba[:,:,3]=np.round(alpha).astype('uint8');rgba[rgba[:,:,3]==0]=0
        image=Image.fromarray(rgba).convert('RGBa').resize((512,384),Image.Resampling.LANCZOS).convert('RGBA')
        image.save(folder/f'painted-{index}.png')
        result.append(premult(image))
    return result

pipeline.material_keys=keys
if __name__=='__main__':pipeline.main()
