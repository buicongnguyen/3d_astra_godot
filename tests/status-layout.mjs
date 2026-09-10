import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';
fs.mkdirSync('test-results',{recursive:true});
const browser=await chromium.launch({headless:true,executablePath:process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined,args:['--enable-unsafe-swiftshader']});
try{
 for(const mobile of [false,true]){
  const page=await browser.newPage({viewport:{width:1280,height:800},isMobile:mobile,hasTouch:mobile,deviceScaleFactor:mobile?Number(process.env.MOBILE_DPR||3):1});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  const state=()=>page.evaluate(()=>window.frontierState);
  const cmd=async c=>{await page.evaluate(c=>window.frontierCommand(JSON.stringify(c)),c);await page.waitForTimeout(180);};
  await page.goto((process.env.TEST_URL||'http://127.0.0.1:4176/3d_astra_godot/')+'?test=1');
  await page.waitForFunction(()=>window.frontierState?.ready,null,{timeout:90000});
  await cmd({action:'stage',index:1});await cmd({action:'start',manual_clock:true});
  for(const viewport of mobile?[{width:320,height:568},{width:390,height:844},{width:667,height:375},{width:844,height:390},{width:768,height:1024}]:[{width:1280,height:800},{width:1024,height:768}]){
   await cmd({action:'restart'});await cmd({action:'start',manual_clock:true});
   await page.setViewportSize(viewport);await page.waitForFunction(v=>frontierState.viewport[0]===v.width&&frontierState.viewport[1]===v.height,viewport);
   let initial=await state();const core=initial.entities.find(e=>e.type==='hq'&&e.team===0);
   await cmd({action:'select',ids:[core.id]});initial=await state();
   const commands=s=>s.action_buttons.map(b=>[b.text,b.x,b.y,b.w,b.h]);
   const idleCommands=commands(initial);
   await cmd({action:'activity_setup'});
   let s=await state();const h=s.entities.find(e=>e.type==='hq'&&e.team===0);
   for(let i=0;i<3;i++)await cmd({action:'train',id:h.id,type:'worker'});
   await cmd({action:'select',ids:[h.id]});
   assert.deepEqual(commands(await state()),idleCommands,'queueing preserves commands');
   await cmd({action:'step',seconds:4});
   const check=async()=>{
    const s=await state(),r=s.selection_info_rect,a=s.action_rect;
    assert.equal(s.selection_info_lines,1,'activity stays on one line');
    assert.ok(s.stat_cells.every(c=>c.lines===2&&c.text_width<=c.w+1&&c.x>=0&&c.x+c.w<=viewport.width&&c.y+c.h<=r[1]),JSON.stringify(s.stat_cells));
    assert.deepEqual(s.stat_icons.slice(0,3),['health','shield','crosshair'],'selected stats have consistent icons');
    assert.ok(s.action_buttons.every(b=>b.icon&&b.caption_fits&&b.h>=44),'command icons and complete labels fit tap targets: '+JSON.stringify(s.action_buttons));
    assert.ok(r[1]+r[3]<=a[1]||r[0]+r[2]<=a[0],'stats do not overlap commands');
    if(mobile){
     assert.ok(s.action_buttons.every(b=>b.x>=a[0]&&b.x+b.w<=a[0]+a[2]+1&&b.y>=a[1]&&b.y+b.h<=a[1]+a[3]+1),JSON.stringify({a,buttons:s.action_buttons}));
     if(s.action_buttons.length>=2)assert.ok(s.action_buttons[0].y===s.action_buttons[1].y&&s.action_buttons[0].x+s.action_buttons[0].w<s.action_buttons[1].x,'two separate command tiles per row');
    }
    return s;
   };
   s=await check();const q=s.queue_buttons;assert.equal(q.length,5);
   assert.ok(q.every(b=>b.w>=44&&b.h>=44&&b.y===q[0].y&&b.x>=0&&b.x+b.w<=viewport.width-10&&b.y+b.h<=viewport.height-10),JSON.stringify(q));
   assert.ok(q.every(b=>s.selection_info_rect[1]+s.selection_info_rect[3]<=b.y),'queue below activity');
   assert.ok(q.every(b=>b.y+b.h<=s.action_rect[1]||b.x+b.w<=s.action_rect[0]),'queue separate from commands');
   await page.screenshot({path:`test-results/status-queue-${viewport.width}x${viewport.height}.png`});
   assert.ok(q.every(b=>b.display_text===''&&b.work_icon),'queue uses unit icons instead of verbose labels');
   assert.ok(q[0].work_progress>0&&q[0].work_progress<1,'blocks represent progress');
   const b=q[4],money=s.alloy;await page[mobile?'touchscreen':'mouse'][mobile?'tap':'click'](b.red_rect[0]+b.red_rect[2]/2,b.red_rect[1]+b.red_rect[3]/2);
   await page.waitForFunction(n=>frontierState.alloy===n+50,money);
   assert.equal((await state()).entities.find(e=>e.id===h.id).queue.length,4);
   assert.equal((await state()).queue_buttons[0].work_progress,q[0].work_progress,'last-item tap leaves active job intact');
   assert.deepEqual(commands(await state()),idleCommands,'cancelling preserves commands');
   for(let i=0;i<4;i++){
    const before=await state(),b=before.queue_buttons[0];
    await page[mobile?'touchscreen':'mouse'][mobile?'tap':'click'](b.red_rect[0]+b.red_rect[2]/2,b.red_rect[1]+4);
    await page.waitForFunction(n=>frontierState.ui_action_serial>n,before.ui_action_serial);
   }
   assert.deepEqual(commands(await state()),idleCommands,'emptying the queue preserves commands');
   await page.keyboard.press('u');await page.waitForFunction(()=>frontierState.queue_buttons.some(b=>b.text==='Cancel upgrade'));
   assert.deepEqual(commands(await state()),idleCommands,'upgrading preserves commands');
   const upgrade=(await state()).queue_buttons[0],paid=(await state()).alloy;
   await page[mobile?'touchscreen':'mouse'][mobile?'tap':'click'](upgrade.red_rect[0]+upgrade.red_rect[2]/2,upgrade.red_rect[1]+4);
   await page.waitForFunction(n=>frontierState.alloy===n+200,paid);
   assert.deepEqual(commands(await state()),idleCommands,'cancelling upgrades preserves commands');
   await cmd({action:'patrol_setup'});
   for(const type of ['worker','medic','tank','group']){
    const units=(await state()).entities.filter(e=>e.team===0&&['worker','ranger','tank','medic'].includes(e.type));
    await cmd({action:'select',ids:type==='group'?units.map(e=>e.id):[units.find(e=>e.type===type).id]});await check();
   }
   assert.deepEqual(errors,[]);console.log(`Compact stats and five visible queue items passed ${viewport.width}x${viewport.height}`);
  }
  await page.close();
 }
}finally{await browser.close();}
