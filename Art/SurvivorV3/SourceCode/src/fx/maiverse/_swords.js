// Original local sword-magic studies. Trails, cooling light and impact glints use
// PixelFX / Sprite Fusion techniques, MIT, Copyright (c) 2026 Hugo Duprez.
import { fit, clamp, smooth, ease, TAU, Rng, sparkle } from '../../core/index.js';
export const BLUE=['#09162e','#103866','#1463af','#258fe5','#57bcff','#a7e4ff','#effcff'];
export const KINDS=['orbit','seeking'];
export const ORBIT_CYCLE=2.6;
const wrap=(t,period)=>((t%period)+period)%period;
export function orbitAttackAge(t,fireAt){return wrap(t-fireAt+.13,ORBIT_CYCLE)-.13;}
export function spec(kind,level){
 if(!KINDS.includes(kind)||!Number.isInteger(level)||level<1||level>5)throw Error('Invalid sword spell');
 return {kind,level,swords:level,blueSwordSilhouette:true,orientation:kind==='orbit'?'radial-outward':'flight-direction',orbitGeometry:kind==='orbit'?'top-down-circle':null,swordLightShape:kind==='orbit'?'crescent':null,finisher:level===5,
  swordLightAttacks:kind==='orbit'&&level===5?5:0,mergedAttacks:kind==='seeking'&&level===5?1:0,
  persistent:kind==='orbit',loop:kind==='orbit',attacksRepeat:kind==='orbit'&&level===5,attackInterval:kind==='orbit'&&level===5?ORBIT_CYCLE:null,
  duration:kind==='orbit'?ORBIT_CYCLE:level===5?5.2:3.4};
}
export function metaFor(kind,level){const s=spec(kind,level);return {
 name:`${kind==='orbit'?'Orbiting swords':'Seeking sword energy'} / Lv.${level}`,
 desc:kind==='orbit'?`${level} persistent outward-facing swords orbit continuously; level five repeats five blue crescent waves every ${ORBIT_CYCLE}s until stopped.`:`${level} blue sword-shaped projectiles seek marked targets with curved luminous trails; level five adds a five-into-one strike.`,
 size:[480,360],origin:[240,180],duration:s.duration,fps:60,loop:s.loop,bg:'dark',tags:['sword','blue','magic',kind,'levels'],options:{palette:BLUE,seed:91,kind,level}
};}
const randomCache=new Map();
function particles(seed){if(!randomCache.has(seed)){
 const r=new Rng(seed);randomCache.set(seed,Array.from({length:22},()=>({a:r.range(0,TAU),v:r.range(25,90),life:r.range(.3,.65),size:r.range(.7,1.8)})));
 }return randomCache.get(seed);}
function ring(p,x,y,rx,ry,C,a=1){if(a<=0||rx<1)return;let prev;
 for(let i=0;i<=56;i++){const theta=i*TAU/56,pt=[x+Math.cos(theta)*rx,y+Math.sin(theta)*ry];if(prev)p.line(...prev,...pt,C,a);prev=pt;}}
function rune(p,x,y,r,t,C,a,round=false){
 ring(p,x,y,r,round?r:r*.62,C[2],a*.45);ring(p,x,y,r*.86,round?r*.86:r*.53,C[3],a*.25);
 for(let i=0;i<8;i++){const q=i*TAU/8+t*.3,c=Math.cos(q),s=Math.sin(q),sy=round?1:.62;p.line(x+c*(r-3),y+s*(r-3)*sy,x+c*(r+3),y+s*(r+3)*sy,C[4],a*.6);}
}
// Origin at the guard, tip facing +x. The guard/hilt remain visible in energy form.
export function sword(p,x,y,angle,size,C,a=1,energy=false){
 if(a<=0||size<.05)return;
 const cs=Math.cos(angle),sn=Math.sin(angle),pt=(u,v)=>[x+(u*cs-v*sn)*size,y+(u*sn+v*cs)*size];
 const poly=(pts,col,k=1)=>p.poly(pts.map(q=>pt(...q)),col,a*k),line=(u,v,uu,vv,col,k=1)=>p.line(...pt(u,v),...pt(uu,vv),col,a*k);
 poly([[-1,-5],[23,-4],[34,0],[23,4],[-1,5]],C[0]);
 poly([[0,-3],[23,-3],[32,0],[23,1],[0,1]],C[energy?3:5]);
 poly([[0,1],[23,1],[31,0],[23,3],[0,4]],C[energy?2:3]);
 line(2,-3,23,-3,C[6]);line(23,-3,32,0,C[5]);line(1,0,26,0,C[energy?4:6]);
 poly([[-5,-10],[-1,-10],[2,-5],[2,5],[-1,10],[-5,10],[-3,3],[-3,-3]],C[1]);
 line(-4,-8,-1,-6,C[4]);line(-1,-6,0,6,C[5]);line(0,6,-4,8,C[3]);
 poly([[-13,-2],[-4,-2],[-4,2],[-13,2]],C[2]);line(-12,-1,-5,-1,C[4]);
 poly([[-17,0],[-14,-3],[-11,0],[-14,3]],C[4]);
 const gem=pt(-1,0);p.ellipse(...gem,2*size,2*size,C[6],a);
 if(energy){const mid=pt(13,0);p.glow(...mid,15*size,C[3],.19*a);}
}
function swordAtTip(p,point,angle,size,C,a=1){sword(p,point.x-Math.cos(angle)*34*size,point.y-Math.sin(angle)*34*size,angle,size,C,a,true);}
function behindHilt(path,size,flight){return tt=>{
 const q=path(tt),angle=angleOf(path,Math.min(tt,flight-.01)),distance=51*size;
 return {x:q.x-Math.cos(angle)*distance,y:q.y-Math.sin(angle)*distance};
};}
function ribbon(p,path,time,span,width,C,alpha=1){
 if(time<=0||alpha<=0)return;const steps=20;
 let previous;
 for(let i=0;i<=steps;i++){
  const f=i/steps,tt=time-span*(1-f);if(tt<0)continue;const q=path(tt);
  if(previous){
   const dx=q.x-previous.x,dy=q.y-previous.y,len=Math.hypot(dx,dy)||1,nx=-dy/len,ny=dx/len,w=width*f*.5;
   const v=[[previous.x+nx*w,previous.y+ny*w],[q.x+nx*w,q.y+ny*w],[q.x-nx*w,q.y-ny*w],[previous.x-nx*w,previous.y-ny*w]];
   p.poly(v,C[2],alpha*f*.85);
   const inner=.43*w;
   p.poly([[previous.x+nx*inner,previous.y+ny*inner],[q.x+nx*inner,q.y+ny*inner],[q.x-nx*inner,q.y-ny*inner],[previous.x-nx*inner,previous.y-ny*inner]],C[3],alpha*f*.95);
   p.line(previous.x,previous.y,q.x,q.y,C[4],alpha*f);
   if(width>4&&i%3===0)p.glow(q.x,q.y,4+width*.25,C[3],alpha*f*.12);
   if(i>steps*.7)p.line(previous.x,previous.y-1,q.x,q.y-1,C[5],alpha*f*.6);
  }previous=q;
 }
}
function impact(p,x,y,t,C,seed=91,power=1){
 if(t<0||t>.85)return;const f=t/.85;
 if(t<.28){const k=1-t/.28;ring(p,x,y,(5+23*ease.outCubic(t/.28))*power,(4+18*ease.outCubic(t/.28))*power,C[4],k);
  p.glow(x,y,27*power,C[3],.28*k);sparkle(p,x,y,10*power*k,C[6],C[4],k);
 }
 const qs=particles(seed);
 for(let i=0;i<qs.length;i++){
  const q=qs[i];if(t>q.life)continue;const d=q.v*(1-Math.exp(-t*3))/3*power,xx=x+Math.cos(q.a)*d,yy=y+Math.sin(q.a)*d;
  const a=1-smooth(q.life*.3,q.life,t);p.line(xx,yy,xx-Math.cos(q.a)*(3+i%3)*power,yy-Math.sin(q.a)*(3+i%3)*power,C[i%3?4:6],a);
 }
 void f;
}
export function orbitPoint(t,i,count){const phase=-Math.PI/2+t*TAU/ORBIT_CYCLE+i*TAU/count,angle=Math.atan2(Math.sin(phase),Math.cos(phase));return {x:Math.cos(phase)*72,y:Math.sin(phase)*72,angle,swordAngle:angle};}
export function orbitPlan(level){return Array.from({length:level},(_,i)=>({index:i,fireAt:level===5?2.12+i*.04:null}));}
function orbit(p,t,o,C){
 const level=o.level;
 // Eight identical marks rotate by exactly one eighth-turn per cycle.
 rune(p,0,0,72,t*TAU/(8*ORBIT_CYCLE*.3),C,.65,true);
 const sorted=orbitPlan(level).map(e=>({...e,point:orbitPoint(t,e.index,level)})).sort((a,b)=>a.point.y-b.point.y);
 for(const event of sorted){
  const i=event.index,q=event.point,a=1,far=q.y<0;
  // Only a narrow light trace follows the orbit: no stacked translucent swords.
  const path=tt=>orbitPoint(tt,i,level);
  ribbon(p,path,t+ORBIT_CYCLE,.16,2.5,C,a*(far?.35:.6));
  // Top-down diagram: the blade axis always points away from the center.
  sword(p,q.x,q.y,q.swordAngle,1,C,a);
  if(event.fireAt!==null){
   const age=orbitAttackAge(t,event.fireAt),start=orbitPoint(event.fireAt,i,level),dx=Math.cos(start.angle),dy=Math.sin(start.angle);
   const flight=.34,path=tt=>({x:start.x+dx*(34+54*clamp(tt/flight)),y:start.y+dy*(34+54*clamp(tt/flight))});
   if(age>=-.13&&age<0)p.glow(q.x+Math.cos(q.angle)*28,q.y+Math.sin(q.angle)*28,13,C[3],.32*smooth(-.13,0,age));
   if(age>=0&&age<flight+.16){const fade=1-smooth(flight,flight+.16,age),point=path(age);
    crescentWave(p,point,start.angle,10+22*clamp(age/flight),C,fade);
   }
   const hit=path(flight);impact(p,hit.x,hit.y,age-flight,C,o.seed+i,.65);
  }
 }
}
// A traveling crescent, with a bright bowed cutting edge and two cooling echoes.
// Its leading point faces the direction of flight; both horns trail behind it.
export function crescentWave(p,point,angle,r,C,alpha=1){
 const dx=Math.cos(angle),dy=Math.sin(angle),nx=-dy,ny=dx,span=1.28;
 const at=(a,rad,lag)=>[point.x+dx*(rad*Math.cos(a)-r-lag)+nx*rad*Math.sin(a),point.y+dy*(rad*Math.cos(a)-r-lag)+ny*rad*Math.sin(a)];
 for(const [lag,opacity,thickness] of [[13,.16,3],[6,.34,4],[0,1,7]]){
  let prev;
  for(let i=0;i<=36;i++){
   const theta=-span+i*2*span/36,taper=Math.pow(Math.max(0,Math.cos(theta/span*Math.PI/2)),.75),w=.3+thickness*taper;
   const outer=at(theta,r,lag),inner=at(theta,r-w,lag),rim=at(theta,r-1.1,lag);
   if(prev){
    p.poly([prev.outer,outer,inner,prev.inner],C[lag?2:3],alpha*opacity);
    if(lag===0){p.line(...prev.rim,...rim,C[5],alpha*taper);if(i%4===0)p.glow(...rim,5,C[3],alpha*taper*.16);}
   }prev={outer,inner,rim};
  }
 }
}
export function seekingPlan(level){return Array.from({length:level},(_,i)=>{
 const y=(i-(level-1)/2)*34;return {index:i,start:{x:-133-Math.abs(y)*.18,y},target:{x:135,y:(i-(level-1)/2)*22},summonAt:.18+i*.055,fireAt:.95+i*.16,flight:.55};
});}
function bezier(a,b,c,d,u){const q=1-u;return {x:q*q*q*a.x+3*q*q*u*b.x+3*q*u*u*c.x+u*u*u*d.x,y:q*q*q*a.y+3*q*q*u*b.y+3*q*u*u*c.y+u*u*u*d.y};}
export function seekingPoint(event,age){
 const u=clamp(age/event.flight),sign=event.index%2?1:-1;
 return bezier(event.start,{x:event.start.x+100,y:event.start.y+sign*48},{x:event.target.x-90,y:event.target.y-sign*38},event.target,ease.inOutSine(u));
}
function angleOf(path,t){const a=path(Math.max(0,t-.008)),b=path(t+.008);return Math.atan2(b.y-a.y,b.x-a.x);}
function seeking(p,t,o,C){
 const plan=seekingPlan(o.level);
 for(const e of plan){
  const age=t-e.fireAt,path=tt=>seekingPoint(e,tt);
  if(t>=e.summonAt&&age<0){
   const a=smooth(e.summonAt,e.summonAt+.22,t),theta=Math.atan2(e.target.y-e.start.y,e.target.x-e.start.x);
   rune(p,e.start.x-23,e.start.y,13,t,C,a*.7);swordAtTip(p,e.start,theta,.84,C,a);
   if(age>-.18)p.glow(e.start.x-10,e.start.y,18,C[3],.25*smooth(-.18,0,age));
  }
  if(age>=0&&age<e.flight+.18){
   const a=1-smooth(e.flight,e.flight+.18,age),q=path(age),theta=angleOf(path,Math.min(age,e.flight-.01));
   ribbon(p,behindHilt(path,.84,e.flight),Math.min(age,e.flight),.21,8,C,a);swordAtTip(p,q,theta,.84,C,a);
  }
  impact(p,e.target.x,e.target.y,age-e.flight,C,o.seed+e.index,.8);
 }
 if(o.level===5)fusion(p,t,o,C,plan);
}
export const FUSION={gatherAt:2.4,mergeAt:3.02,fireAt:3.24,flight:.54,start:{x:-72,y:0},target:{x:135,y:0}};
function fusion(p,t,o,C,plan){
 const f=FUSION;if(t<f.gatherAt)return;
 if(t<f.mergeAt){
  const u=smooth(f.gatherAt+.12,f.mergeAt,t),a=smooth(f.gatherAt,f.gatherAt+.12,t);
  rune(p,f.start.x-32,0,24+12*(1-u),t,C,a);
  for(const e of plan){
   const q={x:e.start.x+(f.start.x-e.start.x)*u,y:e.start.y*(1-u)};
   const path=tt=>{const v=smooth(f.gatherAt+.12,f.mergeAt,tt);return {x:e.start.x+(f.start.x-e.start.x)*v,y:e.start.y*(1-v)};};
   ribbon(p,path,t,.12,4,C,a*.8);swordAtTip(p,q,0,.68,C,a*(1-smooth(.72,1,u)));
  }
  p.glow(f.start.x-25,0,27,C[3],.2*u);return;
 }
 const age=t-f.fireAt,path=tt=>({x:f.start.x+(f.target.x-f.start.x)*ease.inOutSine(clamp(tt/f.flight)),y:0});
 if(age<0){const u=smooth(f.mergeAt,f.fireAt,t);swordAtTip(p,f.start,0,2.15,C,smooth(f.mergeAt,f.mergeAt+.08,t));
  rune(p,f.start.x-40,0,31,t,C,.8);sparkle(p,f.start.x-20,0,8+u*5,C[6],C[4],.8);return;}
 if(age<f.flight+.2){const a=1-smooth(f.flight,f.flight+.2,age);ribbon(p,behindHilt(path,2.15,f.flight),Math.min(age,f.flight),.23,19,C,a);swordAtTip(p,path(age),0,2.15,C,a);}
 impact(p,f.target.x,f.target.y,age-f.flight,C,o.seed+55,1.5);
}
export function drawLevel(p,t,o){const s=spec(o.kind,o.level),C=fit(o.palette,7);
 if(s.loop){const tt=Math.round(wrap(t,s.duration)*1e9)/1e9;orbit(p,tt>=s.duration?0:tt,o,C);return;}
 if(t<=0||t>=s.duration)return;seeking(p,t,o,C);
}
