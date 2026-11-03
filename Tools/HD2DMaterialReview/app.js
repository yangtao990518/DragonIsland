import {definitions,preload as preloadExtra,createState as createExtraState,advance as advanceExtra,render as renderExtra,drawBlade} from './skills.js';
import {upgrade,frameIndex as fxIndex,sourceRect,summary as fxSummary} from './fx60.js';
import {installDownloads} from './source-download.js';
installDownloads();
const $ = s => document.querySelector(s);
const roman = ['', 'Ⅰ', 'Ⅱ', 'Ⅲ', 'Ⅳ', 'Ⅴ'];
const names = ['', '初燃', '双焰', '三重火光', '四重连焰', '五重焰爆'];
const captions = ['', '一颗火球，短促命中火花。', '两颗火球依次出手，分取目标。', '三颗火球，展开更密集的火线。', '四颗火球，连续压向木桩阵。', '五颗火球，命中时追加范围爆炸。'];
const impactTicks = [1,1,2,2,3,3,3,3,3,3,4,4,5,5,6,6];
let data, assets, selected = 5, playing = true, speed = 1, theme = 'dark', hero = 'dafeiyu', auto = true;
let selectedSkill='fireball',fireLevels;
let elapsed = 0, lastStamp = 0, ready = false, stages = [];
const WORLD = {w:800, h:330};
const player = {x:115,y:172};
const targetPoints = [{x:501,y:172},{x:530,y:137},{x:530,y:209},{x:565,y:172},{x:560,y:248}];
const image = path => new Promise((resolve,reject) => {const im=new Image();im.onload=()=>resolve(im);im.onerror=()=>reject(new Error(`素材无法加载：${path}`));im.src='assets/'+path;});
const clamp=(x,a,b)=>Math.max(a,Math.min(b,x));

function frameAt(starts,t) {let lo=0,hi=starts.length;while(lo<hi){const m=(lo+hi)>>1;if(starts[m]<=t)lo=m+1;else hi=m;}return Math.max(0,lo-1);}
const impactStarts = [];let impactDuration=0;for(const ticks of impactTicks){impactStarts.push(impactDuration);impactDuration+=ticks/60;}

function makeState(level) {
  if(selectedSkill!=='fireball')return createExtraState(selectedSkill,level);
  return {level,time:0,nextCast:.22,queued:[],shots:[],hits:[],numbers:[],enemies:targetPoints.map((p,i)=>({...p,id:i,hitAt:-99})),volleys:0,emitted:0,collisionCount:0,splashCount:0};
}
function enqueue(s) {
  const l=data.levels[s.level-1];
  const nearest=s.enemies.slice().sort((a,b)=>Math.hypot(a.x-player.x,a.y-player.y)-Math.hypot(b.x-player.x,b.y-player.y));
  for(let i=0;i<l.count;i++) {
    const target=nearest[i%nearest.length];
    const angle=Math.atan2(target.y-player.y,target.x-player.x)+(i-(l.count-1)/2)*l.angleOffsetStep;
    s.queued.push({at:s.time+i*l.shotStagger,angle});
  }
  s.volleys++;
}
function segmentDistance(p,a,b) {const dx=b.x-a.x,dy=b.y-a.y;const n=dx*dx+dy*dy;const t=n?clamp(((p.x-a.x)*dx+(p.y-a.y)*dy)/n,0,1):0;return Math.hypot(p.x-a.x-t*dx,p.y-a.y-t*dy);}
function hurt(s,enemy,amount,splash=false) {
  enemy.hitAt=s.time;
  const recent=s.numbers.find(n=>n.enemyID===enemy.id&&s.time-n.born<.12);
  if(recent){recent.amount+=amount;recent.splash=recent.splash&&splash;}
  else s.numbers.push({enemyID:enemy.id,x:enemy.x,y:enemy.y-44,amount,born:s.time,splash});
  if(splash)s.splashCount++;
}
function advance(s,dt) {
  if(selectedSkill!=='fireball'){advanceExtra(s,dt,{auto,hurt});return;}
  s.time+=dt;const l=data.levels[s.level-1];
  if(s.time>=s.nextCast){enqueue(s);s.nextCast=auto?s.nextCast+l.cooldown:Infinity;}
  for(const q of s.queued)if(q.at<=s.time&&!q.sent){q.sent=true;s.shots.push({x:player.x+16,y:player.y,vx:Math.cos(q.angle)*l.speed,vy:Math.sin(q.angle)*l.speed,angle:q.angle,born:s.time,dead:false});s.emitted++;}
  s.queued=s.queued.filter(q=>!q.sent);
  for(const shot of s.shots) {
    const old={x:shot.x,y:shot.y};shot.x+=shot.vx*dt;shot.y+=shot.vy*dt;
    const candidates=s.enemies.filter(e=>segmentDistance(e,old,shot)<l.hitRadius+14).sort((a,b)=>Math.hypot(a.x-old.x,a.y-old.y)-Math.hypot(b.x-old.x,b.y-old.y));
    if(candidates.length) {
      const enemy=candidates[0];hurt(s,enemy,l.damage);s.collisionCount++;
      if(l.explodes)for(const e of s.enemies)if(Math.hypot(e.x-enemy.x,e.y-enemy.y)<l.explosionRadius+14)hurt(s,e,l.damage*l.splashMultiplier,true);
      s.hits.push({x:enemy.x,y:enemy.y,born:s.time,large:l.explodes});shot.dead=true;
    }
    if(s.time-shot.born>=2)shot.dead=true;
  }
  s.shots=s.shots.filter(p=>!p.dead);s.hits=s.hits.filter(p=>s.time-p.born<(p.large?impactDuration:.12));s.numbers=s.numbers.filter(p=>s.time-p.born<.64);
}

function tile(ctx,sheet,index,x,y,size,anchor=[67,48],rotation=0,alpha=1) {
  anchor=sheet.fx60?.anchor??anchor;
  ctx.save();ctx.globalAlpha=alpha;ctx.translate(Math.round(x),Math.round(y));if(rotation)ctx.rotate(rotation);
  ctx.drawImage(sheet,...sourceRect(sheet,index),-anchor[0]*size/96,-anchor[1]*size/96,size,size);ctx.restore();
}
function halo(ctx,x,y,r,alpha) {
  const gradient=ctx.createRadialGradient(x,y,0,x,y,r);gradient.addColorStop(0,`rgba(255,163,61,${alpha})`);gradient.addColorStop(.45,`rgba(252,109,26,${alpha*.35})`);gradient.addColorStop(1,'rgba(247,91,25,0)');ctx.fillStyle=gradient;ctx.beginPath();ctx.arc(x,y,r,0,Math.PI*2);ctx.fill();
}
function body(ctx,x,y,t,mini=false) {
  const spec=data.heroes[hero];const index=frameAt(spec.starts,t%spec.duration);const page=Math.floor(index/spec.framesPerPage),cell=index%spec.framesPerPage;
  ctx.drawImage(assets.heroes[hero][page],cell%8*64,Math.floor(cell/8)*72,64,72,x-33,y-40,64,72);
}
function dummy(ctx,e,time) {
  const age=time-e.hitAt,flash=age<.18;
  const offset=flash?Math.sin(age/.18*Math.PI)*1.5:0;
  ctx.drawImage(flash?assets.redDummy:assets.dummy,e.x-22+offset,e.y-42,44,66);
}
function draw(stage) {
  const {canvas,state:s}=stage,ctx=canvas.getContext('2d');
  const width=Math.max(1,Math.round(canvas.clientWidth*devicePixelRatio)),height=Math.max(1,Math.round(canvas.clientHeight*devicePixelRatio));
  if(canvas.width!==width||canvas.height!==height){canvas.width=width;canvas.height=height;}
  ctx.imageSmoothingEnabled=false;ctx.setTransform(width/WORLD.w,0,0,height/WORLD.h,0,0);
  const light=theme==='light';
  const gradient=ctx.createLinearGradient(0,0,0,WORLD.h);gradient.addColorStop(0,light?'#e5e8dc':'#131d25');gradient.addColorStop(1,light?'#cddbd1':'#203232');ctx.fillStyle=gradient;ctx.fillRect(0,0,WORLD.w,WORLD.h);
  // Neutral review grid and planar shading, not a replacement game map.
  ctx.strokeStyle=light?'#5c726018':'#b1ba8c0b';ctx.lineWidth=.5;
  for(let y=34;y<330;y+=40){ctx.beginPath();ctx.moveTo(0,y);ctx.lineTo(800,y);ctx.stroke();}
  for(let x=-240;x<1050;x+=80){ctx.beginPath();ctx.moveTo(x+180,0);ctx.lineTo(x,330);ctx.stroke();}
  ctx.fillStyle=light?'#344a3220':'#00000044';
  for(const e of [s.player??player,...s.enemies]){ctx.beginPath();ctx.ellipse(e.x,e.y+22,e===player?20:15,5,0,0,Math.PI*2);ctx.fill();}
  if(selectedSkill==='fireball')for(const hit of s.hits){const age=s.time-hit.born;halo(ctx,hit.x,hit.y+16,hit.large?74:19,(hit.large?.20:.08)*Math.max(0,1-age/(hit.large?impactDuration:.12)));}
  const entities=[{...(s.player??player),player:true},...s.enemies,...(s.blades??[])].sort((a,b)=>a.y-b.y);
  for(const e of entities){if(e.player)body(ctx,e.x,e.y,elapsed);else if(e.blade)drawBlade(ctx,e,s,{tile,assets});else dummy(ctx,e,s.time);}
  if(selectedSkill!=='fireball')renderExtra(ctx,s,{tile,assets,frameAt});
  if(selectedSkill==='fireball')for(const shot of s.shots){halo(ctx,shot.x,shot.y,22,.11);tile(ctx,assets.flight,fxIndex(assets.flight,s.time-shot.born,Math.floor((s.time-shot.born)*30)%16),shot.x,shot.y,48,[67,48],shot.angle);}
  if(selectedSkill==='fireball')for(const hit of s.hits) {
    const age=s.time-hit.born;
    if(hit.large){const i=fxIndex(assets.impact,age,frameAt(impactStarts,age));tile(ctx,assets.impact,i,hit.x,hit.y+7,100,[49,80]);}
    else {const sheet=assets.fx['fireball-hit']??assets.impact;const i=fxIndex(sheet,age,age<.045?0:1);tile(ctx,sheet,i,hit.x,hit.y,52,[49,74],0,1-age/.15);}
  }
  ctx.font='bold 10px ui-monospace, Consolas, monospace';ctx.textAlign='center';ctx.lineJoin='round';ctx.lineWidth=2;
  if(!stage.mini)for(const n of s.numbers) {const age=s.time-n.born;ctx.save();ctx.globalAlpha=clamp((.64-age)/.2,0,1);ctx.strokeStyle=light?'#f5f0df':'#20221d';ctx.fillStyle=n.splash?(light?'#a15119':'#ffbd76'):(light?'#313b33':'#eee9db');const y=n.y-age*25;ctx.strokeText(String(Math.floor(n.amount)),n.x,y);ctx.fillText(String(Math.floor(n.amount)),n.x,y);ctx.restore();}
  ctx.textAlign='left';
  if(!stage.mini){ctx.font='10px "Microsoft YaHei",sans-serif';ctx.fillStyle=light?'#5e6a5e88':'#a9bcaa55';if(selectedSkill!=='orbit-swords'){ctx.fillText('施法侧',88,248);ctx.fillText('目标区',511,291);}}
  ctx.setTransform(1,0,0,1,0,0);
}

function renderAll(){if(!ready)return;for(const stage of stages)draw(stage);const main=stages[0].state;$('#status').textContent=!playing?'已暂停':selectedSkill==='orbit-swords'?'剑阵环绕':main.charges?.some(c=>main.time>=c.born)?'正在合剑':main.strikes?.some(c=>main.time>=c.born)?'落雷释放':main.zones?.length?(selectedSkill==='quicksand'?'流沙牵引':'土系释放'):main.hits.some(h=>h.large)?'命中焰爆':main.shots.length?'弹体飞行':'等待释放';}
function reset(){elapsed=0;for(const stage of stages)stage.state=makeState(stage.level);renderAll();}
function selectLevel(level,scroll=false) {
  selected=level;for(const tab of document.querySelectorAll('[role=tab]'))tab.setAttribute('aria-selected',String(Number(tab.dataset.level)===level));
  for(const card of document.querySelectorAll('.level-card')){card.classList.toggle('selected',Number(card.dataset.level)===level);card.setAttribute('aria-pressed',String(Number(card.dataset.level)===level));}
  const definition=selectedSkill==='fireball'?null:definitions[selectedSkill];const currentNames=definition?.levelNames??names;const currentCaptions=definition?.captions??captions;const unit=definition?.unit??'颗';const l=data.levels[level-1];$('#level-badge').textContent=roman[level];$('#level-title').textContent=`${level}级 · ${currentNames[level]}`;$('#level-caption').textContent=currentCaptions[level];$('#count').innerHTML=`${l.count??level} <small>${unit}</small>`;$('#damage').textContent=l.displayDamage;$('#effect').textContent=definition?definition.effects[level]:level===5?'范围焰爆':'命中火花';$('#main-stage').setAttribute('aria-label',`${level}级${definition?.title??'火球术'}动画预览`);
  stages[0].level=level;reset();if(scroll)document.querySelector('.study').scrollIntoView({behavior:'smooth',block:'start'});
}
function selectSkill(id){
  if(id!=='fireball'&&!definitions[id])return;
  selectedSkill=id;const def=definitions[id];data.levels=def?def.levels:fireLevels;
  for(const b of document.querySelectorAll('[data-skill]'))b.setAttribute('aria-pressed',String(b.dataset.skill===id));
  $('#skill-title').innerHTML=(def?.title??'火球术')+' <span>Ⅰ—Ⅴ</span>';
  $('#skill-tag').textContent=def?.tag??'焰系 · 自动弹体';
  $('#skill-lede').textContent=def?def.captions[5]:'一颗火光，逐级长成五重焰爆。看看每一级的飞行与命中。';
  $('#max-tag').textContent=def?.badge??(id==='fireball'?'焰爆':id==='lightning'?'雷爆':id==='orbit-swords'?'月牙':'合剑');$('#damage-label').textContent=def?.countNote?'基础伤害':'单颗伤害';$('#count-title').textContent=def?.countNote?'数量与体量成长':'数量成长，尺寸统一';$('#comparison-tag').textContent=def?.countNote?'同一时间 · 等级成长':'同一时间 · 同一尺寸';
  $('#count-label').textContent=def?.countLabel??'每轮数量';$('#interval-label').textContent=def?.intervalLabel??'释放间隔';$('#interval').innerHTML=(def?.interval??'1.3')+' <small>秒</small>';
  $('#auto').disabled=id==='orbit-swords';$('#auto').checked=id==='orbit-swords'||auto;$('#auto').nextElementSibling.textContent=id==='orbit-swords'?'常驻运转':'自动连发';
  $('#count-note').textContent=def?.countNote??(id==='orbit-swords'?'1—5级保持1—5柄剑均分环绕位置。旋转由运行时控制，剑身与光泽使用独立动画素材。':`1—5级每轮分别释放1—5${def?.unit??'颗'}。单个主体保持相同大小，等级差异体现为数量与满级追加效果。`);
  $('#feature-title').textContent=def?('满级 · '+def.maxFeature):'满级，命中才爆开';$('#feature-note').textContent=def?.note??'5级追加半径42的范围伤害，溅射倍率70%。低等级保留短促命中火花。';
  for(const card of document.querySelectorAll('.level-card')){
    const n=Number(card.dataset.level),l=data.levels[n-1],unit=def?.unit??'颗',count=l.count??n;
    card.querySelector('h3').textContent=roman[n]+' · '+(def?.levelNames??names)[n];
    card.querySelector('.card-heading span').textContent=n===5?(def?.maxFeature??'范围焰爆'):def?.countNote?(id==='earth-spikes'?count+'根岩柱':Math.round(l.scale*100)+'%范围/体量'):n+unit+(id==='lightning'?'落雷':id==='orbit-swords'?'环剑':id==='seeking-swords'?'追踪剑':'火球');
    card.querySelector('.card-bottom').innerHTML=`<span><b>${count}${unit}</b> / ${id==='orbit-swords'?'常驻':'每轮'}</span><span>${def?.countNote?'基础伤害':'伤害'} <b>${l.displayDamage}</b>${n===5?' ＋ 强化':''}</span>`;
    card.setAttribute('aria-label',`放大查看${n}级${def?.title??'火球术'}`);
  }
  selectLevel(selected);history.replaceState(null,'','#'+id);
}
function setPlaying(value){playing=value;$('#play-text').textContent=value?'暂停':'播放';$('#play-icon').textContent=value?'Ⅱ':'▶';$('#play').setAttribute('aria-label',value?'暂停动画':'播放动画');renderAll();}
function tick(stamp){const dt=lastStamp?Math.min((stamp-lastStamp)/1000,.05):0;lastStamp=stamp;if(ready&&playing&&!document.hidden){const step=dt*speed;elapsed+=step;for(const stage of stages)advance(stage.state,step);}renderAll();requestAnimationFrame(tick);}

async function boot() {
  try {
    data=await fetch('assets/study.json').then(r=>{if(!r.ok)throw Error('等级资料无法加载');return r.json();});
    fireLevels=data.levels;
    const [flight,impact,dummyImage,...heroImages]=await Promise.all([image('flight.png'),image('impact.png'),image('dummy.png'),...Object.values(data.heroes).flatMap(h=>h.atlases.map(image))]);
    assets={flight,impact,dummy:dummyImage,heroes:{dafeiyu:heroImages.slice(0,4),xiaobai:heroImages.slice(4,8)}};
    assets.fx=await preloadExtra(image);
    await upgrade(assets,image);
    const red=document.createElement('canvas');red.width=dummyImage.width;red.height=dummyImage.height;const rc=red.getContext('2d');rc.drawImage(dummyImage,0,0);rc.globalCompositeOperation='source-atop';rc.fillStyle='#f35d4dbb';rc.fillRect(0,0,red.width,red.height);assets.redDummy=red;
    stages=[{canvas:$('#main-stage'),level:5,mini:false,state:makeState(5)}];
    for(const l of data.levels) {
      const card=document.createElement('button');card.type='button';card.className='level-card'+(l.level===5?' selected':'');card.dataset.level=l.level;card.setAttribute('aria-pressed',String(l.level===5));card.setAttribute('aria-label',`放大查看${l.level}级火球`);
      card.innerHTML=`<div class="card-heading"><h3>${roman[l.level]} · ${names[l.level]}</h3><span>${l.level===5?'范围焰爆':l.level+'颗火球'}</span></div><canvas class="card-canvas" aria-label="${l.level}级同步动画"></canvas><div class="card-bottom"><span><b>${l.level}颗</b> / 每轮</span><span>伤害 <b>${l.displayDamage}</b>${l.level===5?' ＋ 溅射':''}</span></div>`;
      card.addEventListener('click',()=>selectLevel(l.level,true));$('#level-cards').append(card);stages.push({canvas:card.querySelector('canvas'),level:l.level,mini:true,state:makeState(l.level)});
    }
    for(const tab of document.querySelectorAll('[role=tab]')) {
      tab.addEventListener('click',()=>selectLevel(Number(tab.dataset.level)));
      tab.addEventListener('keydown',e=>{if(['ArrowRight','ArrowLeft','Home','End'].includes(e.key)){e.preventDefault();const n=e.key==='Home'?1:e.key==='End'?5:clamp(selected+(e.key==='ArrowRight'?1:-1),1,5);selectLevel(n);document.querySelector(`[role=tab][data-level="${n}"]`).focus();}});
    }
    for(const button of document.querySelectorAll('[data-skill]'))button.addEventListener('click',()=>selectSkill(button.dataset.skill));
    $('#play').addEventListener('click',()=>setPlaying(!playing));$('#replay').addEventListener('click',()=>{reset();setPlaying(true);});
    $('#speed').addEventListener('change',e=>{speed=Number(e.target.value);});
    $('#auto').addEventListener('change',e=>{auto=e.target.checked;reset();});
    $('#hero').addEventListener('change',e=>{hero=e.target.value;renderAll();});
    $('#theme').addEventListener('click',()=>{theme=theme==='dark'?'light':'dark';document.documentElement.dataset.theme=theme;$('#theme span').textContent=theme==='dark'?'浅色背景':'深色背景';$('#theme').setAttribute('aria-label',theme==='dark'?'切换浅色背景':'切换深色背景');renderAll();});
    $('#loading').classList.add('hidden');$('#play').disabled=false;$('#replay').disabled=false;ready=true;
    if(matchMedia('(prefers-reduced-motion: reduce)').matches)setPlaying(false);
    // Read-only inspection hook for reproducible local verification.
    window.fireballStudy={get snapshot(){return {ready,fx60:fxSummary(),skill:selectedSkill,selected,playing,elapsed,theme,speed,hero,auto,stages:stages.map(s=>({level:s.level,volleys:s.state.volleys,emitted:s.state.emitted,collisions:s.state.collisionCount,splash:s.state.splashCount,activeShots:s.state.shots.length,hitEffects:s.state.hits.length,bladeCount:s.state.blades?.length??0,lightningEmitted:s.state.lightningEmitted??0,starBursts:s.state.starBursts??0,crescentsFired:s.state.crescentsFired??0,mergedEmitted:s.state.mergedEmitted??0,peakActiveShots:s.state.peakActiveShots??0,pillarEruptions:s.state.pillarEruptions??0,pillarExplosions:s.state.pillarExplosions??0,fistHits:s.state.fistHits??0,mainBoulders:s.state.mainBoulders??0,companionBoulders:s.state.companionBoulders??0,shockwaves:s.state.shockwaves??0,sandPulses:s.state.sandPulses??0,sandRebounds:s.state.sandRebounds??0,pullDistance:s.state.pullDistance??0,enemies:s.state.enemies.map(e=>({id:e.id,x:e.x,y:e.y}))}))};}};
    const requested=location.hash.slice(1);if(definitions[requested])selectSkill(requested);
    renderAll();requestAnimationFrame(tick);
  } catch(error) {$('#loading').textContent='加载失败，请刷新重试。'+error.message;$('#loading').setAttribute('role','alert');console.error(error);}
}
boot();
