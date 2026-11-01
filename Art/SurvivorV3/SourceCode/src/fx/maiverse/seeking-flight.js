import {sword,BLUE} from './_swords.js';
import {fit,TAU} from '../../core/index.js';
export const meta={name:'seeking-flight',desc:'Approved sword silhouette, reusable native projectile without baked demonstration path.',size:[200,96],origin:[158,48],duration:1.2,loop:true,fps:60,bg:'dark',tags:['sword','native-module'],options:{palette:BLUE,seed:91}};
export function draw(p,t,o){const C=fit(o.palette,7),size=.84,guard=-27*size;
for(let i=0;i<90;i++){const u=i/90,x=guard-7-i,y=Math.sin(u*8-t*TAU/1.2*2)*3*(1-u);p.beam(x,y,x-2,y,Math.max(1,(1-u)*5),C[u>.7?2:3],1-u*.8);if(i%6<3)p.line(x,y-1,x-3,y-1,C[4],(1-u)*.8);}
sword(p,guard,0,0,size,C,1,true);}
