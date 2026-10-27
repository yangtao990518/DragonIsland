"""Assemble individually generated walk keyposes after keying and alignment."""
import argparse
from pathlib import Path
from PIL import Image


def assemble(folder, output):
    cells=[]
    for index in range(4):
        image=Image.open(folder/str(index)/'clean.png').convert('RGBA')
        box=image.getchannel('A').getbbox()
        if not box:raise ValueError('Empty generated keypose')
        cells.append(image.crop(box))
    # The single-image edits were delivered at a different resolution from
    # their reference crop. Normalize that image-resolution difference only.
    common_height=560
    normalized=[cell.resize((round(cell.width*common_height/cell.height),common_height),Image.Resampling.LANCZOS) for cell in cells]
    if max(c.width for c in normalized)>468:
        scale=468/max(c.width for c in normalized)
        normalized=[cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.LANCZOS) for cell in normalized]
    atlas=Image.new('RGB',(1024,1280),'#FF00FF')
    for index,cell in enumerate(normalized):
        atlas.paste(cell,((index%2)*512+(512-cell.width)//2,(index//2)*640+600-cell.height),cell)
    output.parent.mkdir(parents=True,exist_ok=True)
    atlas.save(output)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('folder',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args();assemble(args.folder,args.output)
