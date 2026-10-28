"""Temporary pose sketches for imagegen; these are never rendered as assets."""
from PIL import Image,ImageDraw
from painted_pet_walk import OUT

def thick_leg(draw,points,width,colour):
    draw.line(points,fill=colour,width=width,joint='curve')
    for x,y in points:
        draw.ellipse((x-width/2,y-width/2,x+width/2,y+width/2),fill=colour)

def guides(role):
    source=Image.open(OUT/role/'keys/00.png').convert('RGBA')
    outputs=[]
    for phase in range(4):
        passing=phase%2==1
        body=source.copy();mask=Image.new('L',source.size);md=ImageDraw.Draw(mask)
        if role=='dafeiyu':
            md.rectangle((130,282,258,365),fill=255)
            shoe=source.crop((179,309,246,355));anchor=(23,16)
            paths=[
                [[(180,269),(172,294),(158,324)],[(196,269),(203,294),(218,324)]],
                [[(180,269),(196,294),(205,320)],[(196,269),(196,294),(196,324)]],
                [[(180,269),(198,294),(213,324)],[(196,269),(186,294),(167,324)]],
                [[(180,269),(192,296),(202,324)],[(196,269),(206,294),(190,319)]]][phase]
            width=22
        else:
            md.polygon([(199,250),(224,250),(230,275),(239,308),(263,330),(261,356),(145,356),(147,325),(162,309),(180,284)],fill=255)
            shoe=source.crop((206,317,259,353));anchor=(20,8)
            paths=[
                [[(202,248),(190,287),(175,325)],[(220,248),(226,287),(235,325)]],
                [[(202,248),(208,287),(213,320)],[(220,248),(220,287),(215,325)]],
                [[(205,248),(225,286),(235,325)],[(220,248),(208,287),(183,325)]],
                [[(205,248),(213,285),(218,325)],[(220,248),(222,286),(204,320)]]][phase]
            width=23
        # Pet body is retained as pose guide. Its lower limbs will be repainted.
        md.rectangle((345,318,510,360),fill=255)
        body.putalpha(Image.composite(Image.new('L',body.size),body.getchannel('A'),mask))
        art=Image.new('RGBA',source.size);draw=ImageDraw.Draw(art)
        for i,points in enumerate(paths):
            thick_leg(draw,points,width,'#f2cbb2' if i==0 else '#ffe4c9')
            x,y=points[-1]
            art.alpha_composite(shoe,(x-anchor[0],y-anchor[1]))
        if role=='dafeiyu':
            legs=[[(375,304),(365,326),(356,344)],[(465,304),(478,326),(488,344)],
                  [(383,305),(391,326),(403,344)],[(455,304),(452,325),(440,344)]]
        else:
            legs=[[(395,303),(388,325),(379,343)],[(460,302),(472,325),(482,343)],
                  [(400,302),(408,326),(421,343)],[(449,302),(445,325),(434,343)]]
        if passing:
            for i,points in enumerate(legs):
                points[-1]=(points[0][0]+(-2 if i%2 else 3),342-(3 if i in [0,3] else 0))
        if phase==0:
            for points in legs:points[-1]=(round(2*points[0][0]-points[-1][0]),points[-1][1])
        for i,points in enumerate(legs):
            thick_leg(draw,points,15,'#d1b5a8' if i<2 and role=='dafeiyu' else '#cfc6e5' if i<2 else '#fff3e6' if role=='dafeiyu' else '#fcf5ff')
            x,y=points[-1];draw.ellipse((x-9,y-5,x+13,y+6),fill='#fff4ed' if role=='dafeiyu' else '#fffaff')
        art.alpha_composite(body)
        outputs.append(art)
    sheet=Image.new('RGBA',(source.width*2,source.height*2))
    for i,art in enumerate(outputs):sheet.alpha_composite(art,((i%2)*source.width,(i//2)*source.height))
    sheet.save(OUT/f'{role}-four-pose-guide.png')

if __name__=='__main__':
    for role in ['xiaobai','dafeiyu']:guides(role)
