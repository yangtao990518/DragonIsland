// Offline deterministic atlas export. No gallery font, backdrop or stock actor.
import { allIds, loadEffect, renderFrames } from '../ThirdParty/PixelFX/tools/lib/fxlib.mjs';
import { encodePNG } from '../ThirdParty/PixelFX/tools/lib/png.mjs';
import { mkdirSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, resolve } from 'node:path';
const root = resolve(import.meta.dirname, '..'), out = join(root, 'Art/PixelFX');
const hash = b => createHash('sha256').update(b).digest('hex');
mkdirSync(out, { recursive: true });
const upstream = JSON.parse(readFileSync(join(root,'ThirdParty/PixelFX/UPSTREAM.json')));
const categories={fire:'火焰',ice:'冰霜',lightning:'雷电',water:'水流',nature:'自然',arcane:'奥术',holy:'圣光',shadow:'暗影',melee:'近战',projectiles:'投射',explosions:'爆破',scifi:'科技',impacts:'冲击',spawn:'召唤',status:'状态',weather:'天候',ui:'能量',pickups:'灵物',transitions:'幻境',critters:'灵兽',moves:'连招'};
const clips=[], skills=[];
const shape=JSON.parse(readFileSync(existsSync(join(out,'actor-mask.json')) ? join(out,'actor-mask.json') : join(root,'Art/PixelFXMasters/actor-mask.json')));
const actor={mask:{w:shape.w,h:shape.h,data:Uint8Array.from(shape.mask)},pixels:Uint32Array.from(shape.pixels),x:-Math.floor(shape.w/2),y:-shape.h,w:shape.w,h:shape.h,k:2,head:[0,-shape.h],chest:[0,-Math.round(shape.h*.68)]};
for (const id of allIds()) {
  const name=id.replaceAll('/','-'), folder=join(out,name), cache=join(folder,'clip.json');
  if (existsSync(cache)) {
    const saved=JSON.parse(readFileSync(cache));
    if(saved.source_commit!==upstream.commit) throw Error('Use a new asset version for another upstream');
    clips.push(saved.clip); skills.push(saved.skill); console.log('cached',id); continue;
  }
  const fx=await loadEffect(id), r=renderFrames(fx,{fps:60,actor:false,options:{text:'',actor}});
  const cols=Math.max(1,Math.min(8,Math.floor(1024/r.w))), rows=Math.max(1,Math.min(8,Math.floor(1024/r.h)));
  const capacity=cols*rows, pages=[]; mkdirSync(folder,{recursive:true});
  for(let start=0;start<r.n;start+=capacity){
    const width=cols*r.w,height=rows*r.h, buffer=new Uint8Array(width*height*4);
    for(let j=0;j<capacity&&start+j<r.n;j++){
      const frame=r.frames[start+j].clear;
      for(let y=0;y<r.h;y++) buffer.set(frame.subarray(y*r.w*4,(y+1)*r.w*4),((Math.floor(j/cols)*r.h+y)*width+(j%cols)*r.w)*4);
    }
    const file=`${name}/atlas-${String(pages.length).padStart(2,'0')}.png`,data=encodePNG(width,height,buffer);
    writeFileSync(join(out,file),data);pages.push({file,sha256:hash(data)});
  }
  const category=id.split('/')[0],tags=fx.meta.tags??[];
  const profile=/heal|blessing|healing/.test(id)?'heal':category==='critters'?'orbit':category==='moves'?'zone':tags.includes('projectile')||category==='projectiles'?'projectile':tags.includes('aura')||category==='status'?'aura':'zone';
  const skill={id:name,source_id:id,title:fx.meta.name,category,category_title:categories[category]??category,profile,loop:fx.meta.loop,duration:r.n/60,description:fx.meta.desc};
  const clip={id:name,kind:'pixel',cell_size:[r.w,r.h],grid:[cols,rows],pivot:[fx.meta.origin[0]/r.w,1-fx.meta.origin[1]/r.h],duration_ms:r.n*1000/60,frame_count:r.n,unique_count:r.n,pages,frames:Array.from({length:r.n},(_,i)=>({source_index:i,cell:i,start_ms:i*1000/60,duration_ms:1000/60}))};
  clips.push(clip);skills.push(skill);writeFileSync(cache,JSON.stringify({source_commit:upstream.commit,clip,skill}));
  console.log(id,r.n,'frames',pages.length,'pages');
}
writeFileSync(join(out,'manifest.json'),JSON.stringify({schema_version:1,source:upstream,export_fps:60,stock_actor:false,background:false,skills,clips}));
console.log('EXPORTED',clips.length,'effects');
