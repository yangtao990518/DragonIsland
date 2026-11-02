const indexAt=(starts,t)=>{let i=0;while(i+1<starts.length&&starts[i+1]<=t)i++;return i;};
export function sample(c,action,t,repeat,catalog){
 if(action==='walk'){const phase=repeat?t%catalog.cycleSeconds:Math.min(t,catalog.cycleSeconds-.000001);return{frame:Math.floor(phase/catalog.cycleSeconds*4)%4,count:4,phase,complete:!repeat&&t>=catalog.cycleSeconds};}
 if(action==='death'){const d=catalog.death;return{frame:Math.min(5,Math.floor(t/d.duration*6)),count:6,phase:t,complete:t>=d.duration};}
 const s=c.combat,phase=repeat?t%s.repeatAfter:t;return{frame:indexAt(s.starts,Math.min(phase,s.duration)),count:s.frames.length,phase,complete:!repeat&&t>=s.repeatAfter+.2};
}
export async function preload(catalog,load){const entries=await Promise.all(catalog.combatAssets.map(async s=>[s.id,{...s,image:await load('assets/monsters/'+s.file)}]));const a=Object.fromEntries(entries);a.fireball={image:await load('assets/flight.png'),cell:[96,96],columns:4,frameCount:16,anchor:[67,48]};return a;}
function cell(ctx,a,index,x,y,unit=1,anchor=a.anchor,alpha=1,rotation=0){ctx.save();ctx.globalAlpha=alpha;ctx.translate(Math.round(x),Math.round(y));if(rotation)ctx.rotate(rotation);ctx.drawImage(a.image,index%a.columns*a.cell[0],Math.floor(index/a.columns)*a.cell[1],...a.cell,-anchor[0]*unit,-anchor[1]*unit,a.cell[0]*unit,a.cell[1]*unit);ctx.restore();}
export function body(ctx,c,pose,x,y,unit,assets){const a=assets[c.combat.asset];cell(ctx,a,c.combat.frames[pose.frame],x,y,unit);}
export function effects(ctx,c,pose,x,y,target,assets){
 const s=c.combat,age=pose.phase-s.release,unit=c.previewSize*2.5/96,origin={x:x+24*unit,y:y-43*unit};let targetHit=false,projectileVisible=false,healing=false;
 if(s.effect==='healing-pulse'){
  if(age>=0&&age<.54){const a=assets[s.effect];cell(ctx,a,Math.min(3,Math.floor(age/.54*4)),x,y+4,unit*1.3,[48,65],Math.min(1,(.54-age)/.14));healing=true;}
  return{targetHit,projectileVisible,healing};
 }
 if(s.kind==='attack'){return{targetHit:age>=0&&age<.15,projectileVisible,healing};}
 const id=s.effect,a=assets[id],anchor=id==='bone-arrow'?[75,48]:id==='fireball'?[67,48]:[62,48];
 if(age<0&&age>-.20&&s.kind==='cast')cell(ctx,a,Math.floor(pose.phase*14)%a.frameCount,origin.x,origin.y,.25+(.20+age)*2.3,anchor,.75);
 for(let i=0;i<s.eliteProjectiles;i++){
  const start=i*.055,local=age-start,ty=target.y-80+(i-(s.eliteProjectiles-1)/2)*15,dx=target.x-origin.x,dy=ty-origin.y,distance=Math.hypot(dx,dy),flight=distance/(s.kind==='shoot'?520:420);
  if(local>=0&&local<flight){const q=local/flight;cell(ctx,a,Math.floor(local*(id==='fireball'?30:14))%a.frameCount,origin.x+dx*q,origin.y+dy*q,id==='bone-arrow'?.65:.7,anchor,1,Math.atan2(dy,dx));projectileVisible=true;}
  if(local>=flight&&local<flight+.15)targetHit=true;
 }
 return{targetHit,projectileVisible,healing};
}
export function death(ctx,c,t,x,y,catalog,assets,drawWalk){const d=catalog.death,alpha=t<d.flashEnd?1:Math.max(0,1-(t-d.flashEnd)/(d.bodyGone-d.flashEnd));
 if(alpha>0){ctx.save();ctx.globalAlpha=alpha;drawWalk(t<d.flashEnd?'white':'normal');ctx.restore();}
 const age=t-d.debrisStart;if(age>=0&&t<d.debrisEnd){const a=assets[d.asset],q=age/(d.debrisEnd-d.debrisStart);cell(ctx,a,Math.min(5,Math.floor(q*6)),x,y-17,c.previewSize*2.5/96*1.15,[48,48],Math.min(1,(1-q)*3));}
 return{deathBodyVisible:alpha>0,deathFXVisible:age>=0&&t<d.debrisEnd};
}
