import * as earth from './earth-skills.js';
import {frameIndex as fxIndex} from './fx60.js';
import * as runes from './rune-swords.js';
// Presentation study of the existing mechanics from the confirmed Nov-2 base.
const grow=(base,n)=>base*(1+(n-1)*.18);
const levels=(base,cooldown,extra)=>Array.from({length:5},(_,i)=>({level:i+1,count:i+1,damage:grow(base,i+1),displayDamage:Math.floor(grow(base,i+1)),cooldown,...extra}));
export const definitions={
 ...earth.definitions,
 lightning:{title:'雷电术',tag:'雷系 · 定点落雷',unit:'道',countLabel:'每轮落雷',intervalLabel:'释放间隔',interval:'4.6',levelNames:['','初雷','双重落雷','三重雷击','四重雷阵','五芒星雷爆'],captions:['','一道落雷，先预警，再命中。','两道落雷，依次击落。','三道雷击，扩大目标选取范围。','四道雷击，覆盖更宽的目标区。','五道落雷，追加五芒星范围雷爆。'],effects:['','定点雷击','定点雷击','定点雷击','定点雷击','五芒星雷爆'],levels:levels(32,4.6,{speed:0}),maxFeature:'五芒星雷爆',note:'满级追加五芒星雷爆，额外伤害倍率160%。落雷前0.5秒预警；雷爆在本轮约1.2秒时命中。'},
 'orbit-swords':{title:'环绕剑',tag:'剑系 · 常驻剑阵',unit:'柄',countLabel:'常驻剑数',intervalLabel:'环绕周期',interval:'2.6',levelNames:['','一剑护身','双剑环绕','三剑轮舞','四剑成阵','五剑·月牙'],captions:['','一柄剑，沿正圆护身。','两柄剑，均分环绕位置。','三柄剑，前后交替穿行。','四柄剑，持续轮转护身。','五柄剑，周期释放月牙剑气。'],effects:['','接触斩击','接触斩击','接触斩击','接触斩击','月牙剑气'],levels:levels(16,0,{speed:0}),maxFeature:'月牙剑气',note:'剑阵常驻，每2.6秒环绕一周。满级每轮五柄剑依次放出月牙剑气；背后的剑按位置被角色遮挡。'},
 'seeking-swords':{title:'追踪剑',tag:'剑系 · 追踪弹体',unit:'柄',countLabel:'每轮剑数',intervalLabel:'释放间隔',interval:'5.5',levelNames:['','寻锋','双剑寻敌','三剑追踪','四剑齐发','五剑合一'],captions:['','一柄灵剑，转向追踪目标。','两柄灵剑，各自追向目标。','三柄追踪剑，依次出手。','四柄追踪剑，展开剑光。','先发五剑，再蓄力合成重剑。'],effects:['','追踪命中','追踪命中','追踪命中','追踪命中','五剑合一'],levels:levels(32,5.5,{speed:330,hitRadius:7,shotStagger:.055,angleOffsetStep:.04}),maxFeature:'五剑合一',note:'满级在本轮2.4秒开始合剑、3.24秒发射独立造型的合剑。合剑伤害倍率250%，不会替换前面五柄追踪剑。'}
};
definitions['seeking-swords']=runes.definition;
export async function preload(image){await earth.loadGeometry();const ids=['lightning-strike','lightning-star','orbit-blade','orbit-crescent','seeking-flight','seeking-merged',...earth.assetIDs];return Object.fromEntries(await Promise.all(ids.map(async id=>[id,await image(id+'.png')])));}
const radius=(x,y)=>Math.hypot(x,y);
function segment(p,a,b){const dx=b.x-a.x,dy=b.y-a.y,n=dx*dx+dy*dy;const t=n?Math.max(0,Math.min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/n)):0;return radius(p.x-a.x-t*dx,p.y-a.y-t*dy);}
export function createState(skill,level){
 if(skill==='seeking-swords')return runes.createState(level);
 if(earth.definitions[skill])return earth.createState(skill,level);
 const player=skill==='orbit-swords'?{x:400,y:165}:{x:115,y:172};
 const points=skill==='orbit-swords'?[[498,165],[435,256],[303,178],[366,72],[470,94]]:skill==='lightning'?[[480,182],[505,185],[530,178],[544,190],[560,180]]:[[501,172],[530,137],[530,209],[565,172],[560,248]];
 const s={skill,level,player,time:0,nextCast:.22,queued:[],shots:[],hits:[],numbers:[],enemies:points.map(([x,y],id)=>({x,y,id,hitAt:-99})),volleys:0,emitted:0,collisionCount:0,splashCount:0,strikes:[],stars:[],charges:[],crescents:[],blades:[],lastBladeHit:{},lightningEmitted:0,starBursts:0,crescentsFired:0,mergedEmitted:0};
 if(skill==='orbit-swords'){updateBlades(s);s.emitted=level;s.volleys=1;}return s;
}
function updateBlades(s){s.blades=Array.from({length:s.level},(_,i)=>{const a=-Math.PI/2+s.time*2*Math.PI/2.6+i*2*Math.PI/s.level;return {blade:true,x:s.player.x+Math.cos(a)*87,y:s.player.y+Math.sin(a)*87,angle:a};});}
function cast(s){
 const spec=definitions[s.skill],l=spec.levels[s.level-1],p=s.player;const near=s.enemies.slice().sort((a,b)=>radius(a.x-p.x,a.y-p.y)-radius(b.x-p.x,b.y-p.y));const target=near[0];s.volleys++;
 if(s.skill==='lightning'){
  const r=42*(1+(s.level-1)*.25);const candidates=s.enemies.filter(e=>((e.x-target.x)/r)**2+((e.y-target.y)/(r*.34))**2<=1).sort((a,b)=>radius(a.x-target.x,a.y-target.y)-radius(b.x-target.x,b.y-target.y));
  for(let i=0;i<s.level;i++){const angle=i*2*Math.PI/s.level;const at=candidates[i]??{x:target.x+Math.cos(angle)*r*.65,y:target.y+Math.sin(angle)*r*.65*.34};s.strikes.push({...at,born:s.time+i*.025,hit:false,counted:false});}
  if(s.level===5)s.stars.push({x:target.x,y:target.y,born:s.time+.78,hit:false,counted:false});
 }else{
  for(let i=0;i<s.level;i++){const aim=near[i%near.length];s.queued.push({at:s.time+i*.055,angle:Math.atan2(aim.y-p.y,aim.x-p.x)+(i-(s.level-1)/2)*.04,targetID:aim.id,merged:false});}
  if(s.level===5){s.charges.push({born:s.time+2.4});s.queued.push({at:s.time+3.24,angle:Math.atan2(target.y-p.y,target.x-p.x),targetID:target.id,merged:true});}
 }
}
export function advance(s,dt,{auto,hurt}){
 if(s.skill==='seeking-swords'){runes.advance(s,dt,{auto,hurt});return;}
 if(earth.definitions[s.skill]){earth.advance(s,dt,{auto,hurt});return;}
 const oldTime=s.time;s.time+=dt;const d=definitions[s.skill].levels[s.level-1],p=s.player;
 if(s.skill==='orbit-swords'){
  updateBlades(s);
  for(const b of s.blades){const dir={x:Math.cos(b.angle),y:Math.sin(b.angle)};const a={x:p.x+70*dir.x,y:p.y+70*dir.y},z={x:p.x+104*dir.x,y:p.y+104*dir.y};for(const enemy of s.enemies)if(segment(enemy,a,z)<19&&s.time-(s.lastBladeHit[enemy.id]??-99)>=.22){hurt(s,enemy,d.damage);s.lastBladeHit[enemy.id]=s.time;s.collisionCount++;}}
  if(s.level===5)for(let cycle=Math.max(0,Math.floor(oldTime/2.6)-1);cycle<=Math.floor(s.time/2.6);cycle++)for(let i=0;i<5;i++){const fired=cycle*2.6+2.12+i*.04;if(oldTime<fired&&s.time>=fired){const angle=-Math.PI/2+(2.12+i*.04)*2*Math.PI/2.6+i*2*Math.PI/5;s.crescents.push({born:fired,angle,x:p.x+106*Math.cos(angle),y:p.y+106*Math.sin(angle),hitIDs:new Set()});s.crescentsFired++;}}
  for(const c of s.crescents){const age=s.time-c.born;c.x=p.x+(106+54*Math.min(1,age/.34))*Math.cos(c.angle);c.y=p.y+(106+54*Math.min(1,age/.34))*Math.sin(c.angle);for(const enemy of s.enemies)if(!c.hitIDs.has(enemy.id)&&radius(enemy.x-c.x,enemy.y-c.y)<38){hurt(s,enemy,d.damage);c.hitIDs.add(enemy.id);s.collisionCount++;}}
  s.crescents=s.crescents.filter(c=>s.time-c.born<.5);
 }else{
  if(s.time>=s.nextCast){cast(s);s.nextCast=auto?s.nextCast+d.cooldown:Infinity;}
  for(const q of s.queued)if(q.at<=s.time&&!q.sent){q.sent=true;const speed=q.merged?390:330;s.shots.push({x:p.x+16,y:p.y,vx:Math.cos(q.angle)*speed,vy:Math.sin(q.angle)*speed,angle:q.angle,born:s.time,targetID:q.targetID,merged:q.merged,dead:false});if(q.merged)s.mergedEmitted++;else s.emitted++;}
  s.queued=s.queued.filter(q=>!q.sent);
  for(const shot of s.shots){const old={x:shot.x,y:shot.y};const target=s.enemies[shot.targetID],speed=shot.merged?390:330;const dx=target.x-shot.x,dy=target.y-shot.y,length=radius(dx,dy)||1,blend=Math.min(1,dt*7);shot.vx=shot.vx*(1-blend)+dx/length*speed*blend;shot.vy=shot.vy*(1-blend)+dy/length*speed*blend;shot.x+=shot.vx*dt;shot.y+=shot.vy*dt;shot.angle=Math.atan2(shot.vy,shot.vx);const hits=s.enemies.filter(e=>segment(e,old,shot)<14+(shot.merged?17:7)).sort((a,b)=>radius(a.x-old.x,a.y-old.y)-radius(b.x-old.x,b.y-old.y));if(hits.length){hurt(s,hits[0],d.damage*(shot.merged?2.5:1));s.hits.push({x:hits[0].x,y:hits[0].y,born:s.time,large:false});s.collisionCount++;shot.dead=true;}if(s.time-shot.born>(shot.merged?3.4:2))shot.dead=true;}
  s.shots=s.shots.filter(p=>!p.dead);
  for(const strike of s.strikes){const age=s.time-strike.born;if(age>=0&&!strike.counted){strike.counted=true;s.emitted++;s.lightningEmitted++;}if(age>=.5&&!strike.hit){strike.hit=true;for(const enemy of s.enemies)if(radius(enemy.x-strike.x,enemy.y-strike.y)<26){hurt(s,enemy,d.damage);s.collisionCount++;}}}
  for(const star of s.stars){const age=s.time-star.born;if(age>=0&&!star.counted){star.counted=true;s.starBursts++;}if(age>=.42&&!star.hit){star.hit=true;for(const enemy of s.enemies)if(((enemy.x-star.x)/84)**2+((enemy.y-star.y)/(84*.34))**2<1){hurt(s,enemy,d.damage*1.6,true);s.collisionCount++;}}}
  s.strikes=s.strikes.filter(c=>s.time-c.born<1.817);s.stars=s.stars.filter(c=>s.time-c.born<1.817);s.charges=s.charges.filter(c=>s.time-c.born<.84);
 }
 s.hits=s.hits.filter(h=>s.time-h.born<.15);s.numbers=s.numbers.filter(n=>s.time-n.born<.64);
}
const strikeStarts=[0,.12,.25,.4,.5,.54,.58,.64,.74,.86,1,1.13,1.3,1.47,1.65,1.8];
const starStarts=[0,.09,.18,.27,.36,.42,.47,.53,.61,.72,.86,1.02,1.2,1.4,1.58,1.74];
function glow(ctx,x,y,r,strength){const g=ctx.createRadialGradient(x,y,0,x,y,r);g.addColorStop(0,`rgba(96,197,252,${strength})`);g.addColorStop(1,'rgba(81,155,237,0)');ctx.fillStyle=g;ctx.beginPath();ctx.arc(x,y,r,0,Math.PI*2);ctx.fill();}
export function drawBlade(ctx,b,s,{tile,assets}){glow(ctx,b.x,b.y,15,.07);tile(ctx,assets.fx['orbit-blade'],fxIndex(assets.fx['orbit-blade'],s.time,Math.floor(s.time*30)%16),b.x,b.y,63,[48,44],b.angle+Math.PI/2);}
export function render(ctx,s,{tile,assets,frameAt}){
 if(s.skill==='seeking-swords'){runes.render(ctx,s,{tile,assets});return;}
 if(earth.definitions[s.skill]){earth.render(ctx,s,{assets,frameAt});return;}
 const a=assets.fx,t=s.time;
 for(const c of s.strikes){const age=t-c.born;if(age<0)continue;glow(ctx,c.x,c.y+16,30,.10);tile(ctx,a['lightning-strike'],fxIndex(a['lightning-strike'],age,frameAt(strikeStarts,age)),c.x,c.y+18,122,[48,82]);}
 for(const c of s.stars){const age=t-c.born;if(age<0)continue;glow(ctx,c.x,c.y+18,95,age>.42&&age<.8?.18:.06);tile(ctx,a['lightning-star'],fxIndex(a['lightning-star'],age,frameAt(starStarts,age)),c.x,c.y+18,190,[48,72]);}
 for(const c of s.crescents)tile(ctx,a['orbit-crescent'],fxIndex(a['orbit-crescent'],t-c.born,Math.min(15,Math.floor((t-c.born)/.5*16))),c.x,c.y,72,[48,48],c.angle);
 for(const c of s.charges){const age=t-c.born;if(age<0)continue;const progress=Math.min(1,age/.84),cx=s.player.x+16,cy=s.player.y;glow(ctx,cx,cy,54,.08+progress*.13);for(let i=0;i<5;i++){const angle=i*Math.PI*2/5+progress*.6,dist=48*(1-progress)**1.4;tile(ctx,a['seeking-flight'],Math.floor(t*30)%16,cx+Math.cos(angle)*dist,cy+Math.sin(angle)*dist,36*(1-.28*progress),[55,50],0,1-progress*.7);}if(progress>.68)tile(ctx,a['seeking-merged'],Math.floor(t*30)%16,cx,cy,70,[77,51],0,(progress-.68)/.32);}
 for(const c of s.shots){glow(ctx,c.x,c.y,c.merged?34:16,c.merged?.14:.07);tile(ctx,a[c.merged?'seeking-merged':'seeking-flight'],Math.floor((t-c.born)*30)%16,c.x,c.y,c.merged?70:48,c.merged?[77,51]:[74,50],c.angle);}
 for(const c of s.hits){const age=t-c.born;const sheet=s.skill==='seeking-swords'?assets.legacyFx['orbit-crescent']:(a['orbit-hit']??a['orbit-crescent']);tile(ctx,sheet,fxIndex(sheet,age,Math.min(7,Math.floor(age/.15*8))),c.x,c.y,24,[48,48],0,1-age/.15);}
}
