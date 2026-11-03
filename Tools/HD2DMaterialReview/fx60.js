// Only newly generated original drawings are selected here. No tween/optical flow.
let database={assets:{}};
export async function upgrade(assets,image){
 assets.legacyFx={...assets.fx};
 const response=await fetch('assets/fx60/manifest.json');if(!response.ok)throw Error('60帧素材清单加载失败');database=await response.json();
 if(database.pending.length||database.issues.length)throw Error('60帧素材尚未完成检查');
 await Promise.all(Object.entries(database.assets).map(async([id,spec])=>{const sheet=await image('fx60/'+spec.file);sheet.fx60=spec;if(id==='flight'||id==='impact')assets[id]=sheet;else assets.fx[id]=sheet;}));
}
export function frameIndex(sheet,time,legacy=0){const m=sheet.fx60;if(!m)return legacy;const t=m.loop?((time%m.duration)+m.duration)%m.duration:Math.max(0,time);return Math.min(m.count-1,Math.floor(t*60+1e-7));}
export function sourceRect(sheet,index){const columns=sheet.fx60?.columns??4;return[index%columns*96,Math.floor(index/columns)*96,96,96];}
export function extentFor(id,fallback){return database.assets[id]?.extent??fallback;}
export function summary(){return{fps:60,method:'original-drawings',assets:Object.fromEntries(Object.entries(database.assets).map(([id,m])=>[id,{count:m.count,duration:m.duration,fps:m.fps}])),deferred:database.deferred};}
