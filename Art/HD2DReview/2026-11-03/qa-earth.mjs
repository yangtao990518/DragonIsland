import {chromium} from 'file:///C:/Users/yangtao/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs';
import fs from 'node:fs';fs.mkdirSync('qa',{recursive:true});
const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});const page=await browser.newPage({viewport:{width:1440,height:1000},deviceScaleFactor:1});const errors=[],checks=[],results={};page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=400)errors.push(r.status()+' '+r.url());});
const check=(c,m)=>{if(!c)throw Error(m);checks.push(m);};const state=()=>page.evaluate(()=>fireballStudy.snapshot);const play=async()=>{if(!(await state()).playing)await page.locator('#play').click();};
try{
 await page.goto('http://127.0.0.1:8768/#earth-spikes');await page.waitForFunction(()=>window.fireballStudy?.snapshot.ready);check((await state()).skill==='earth-spikes','earth deep link');check(await page.locator('[data-skill]').count()===8,'eight skills');await page.locator('#auto').uncheck();
 for(const id of ['earth-spikes','stone-fist','boulder','quicksand']){
  await page.locator('[data-skill="'+id+'"]').click();await page.locator('#replay').click();await play();await page.waitForFunction(()=>fireballStudy.snapshot.elapsed>=3.25);await page.locator('#play').click();const s=await state();results[id]=s;
  for(const row of s.stages){const n=row.level;check(row.volleys===1,id+' single round level '+n);check(row.collisions>0,id+' actual collision level '+n);
   if(id==='earth-spikes'){check(row.pillarEruptions===n,id+' pillar count '+n);check(row.pillarExplosions===(n===5?5:0),id+' explosions '+n);}
   if(id==='stone-fist'){check(row.fistHits===(n===5?2:1),id+' fist count '+n);check(row.shockwaves===(n===5?1:0),id+' wave '+n);}
   if(id==='boulder'){check(row.mainBoulders===1,id+' main rock '+n);check(row.companionBoulders===(n===5?2:0),id+' companions '+n);check(row.shockwaves===(n===5?1:0),id+' wave '+n);}
   if(id==='quicksand'){check(row.sandPulses===6,id+' six pulses '+n);check(row.sandRebounds===(n===5?1:0),id+' rebound '+n);check(row.pullDistance>0,id+' actual pull '+n);}
  }
  for(let n=1;n<=5;n++){await page.locator('[role=tab][data-level="'+n+'"]').click();check((await state()).selected===n,id+' switch level '+n);check(!(await page.locator('#count').innerText()).startsWith('5 ')||n===5||id==='earth-spikes',id+' count label '+n);}
  await page.locator('[role=tab][data-level="5"]').click();await page.locator('#replay').click();const shotAt=id==='earth-spikes'?2.05:id==='stone-fist'?1.12:id==='boulder'?1.36:2.43;await page.waitForFunction(t=>fireballStudy.snapshot.elapsed>=t,shotAt);await page.locator('#play').click();await page.locator('.study').screenshot({path:'qa/earth-'+id+'.png'});
 }
 const before=(await state()).elapsed;await page.waitForTimeout(180);check((await state()).elapsed===before,'pause stable');await page.locator('#speed').selectOption('0.5');check((await state()).speed===.5,'slow play');await page.locator('#hero').selectOption('xiaobai');await page.locator('#theme').click();await page.setViewportSize({width:390,height:844});await page.screenshot({path:'qa/earth-mobile.png',fullPage:true});check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'mobile no overflow');
 for(const id of ['fireball','lightning','orbit-swords','seeking-swords']){await page.locator('[data-skill="'+id+'"]').click();check((await state()).skill===id,'previous skill '+id);}
 await page.goto('http://127.0.0.1:8768/monsters.html');await page.waitForFunction(()=>window.monsterStudy?.snapshot.ready);check((await page.evaluate(()=>monsterStudy.snapshot.count))===20,'monster roster preserved');await page.locator('[data-action=death]').click();await page.waitForFunction(()=>monsterStudy.snapshot.actionComplete&&!monsterStudy.snapshot.playing);check(!(await page.evaluate(()=>monsterStudy.snapshot.deathBodyVisible)),'monster death preserved');
 check(errors.length===0,'no browser errors');fs.writeFileSync('qa/earth-results.json',JSON.stringify({passed:true,nativeBase:'ad965b1',checks,results,errors},null,2));console.log('EARTH QA PASSED',checks.length);
}finally{await browser.close();}
