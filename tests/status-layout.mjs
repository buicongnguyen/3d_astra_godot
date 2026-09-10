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
   await cmd({action:'activity_setup'});
   let s=await state();const h=s.entities.find(e=>e.type==='hq'&&e.team===0);
   for(let i=0;i<3;i++)await cmd({action:'train',id:h.id,type:'worker'});
   await cmd({action:'select',ids:[h.id]});
   const check=async()=>{
    const s=await state(),r=s.selection_info_rect,a=s.action_rect;
    assert.equal(s.selection_info_lines,1,'activity stays on one line');
    assert.ok(s.stat_cells.every(c=>c.lines===2&&c.text_width<=c.w+1&&c.x>=0&&c.x+c.w<=viewport.width&&c.y+c.h<=r[1]),JSON.stringify(s.stat_cells));
    assert.ok(r[1]+r[3]<=a[1]||r[0]+r[2]<=a[0],'stats do not overlap commands');
    if(mobile)assert.ok(s.action_buttons.every(b=>b.x>=a[0]&&b.y>=a[1]&&b.y+b.h<=a[1]+a[3]+1),JSON.stringify({a,buttons:s.action_buttons}));
    return s;
   };
   s=await check();const q=s.queue_buttons;assert.equal(q.length,5);
   assert.ok(q.every(b=>b.w>=44&&b.h>=44&&b.y===q[0].y&&b.x>=0&&b.x+b.w<=viewport.width-10&&b.y+b.h<=viewport.height-10),JSON.stringify(q));
   assert.ok(q.every(b=>s.selection_info_rect[1]+s.selection_info_rect[3]<=b.y),'queue below activity');
   assert.ok(q.every(b=>b.y+b.h<=s.action_rect[1]||b.x+b.w<=s.action_rect[0]),'queue separate from commands');
   await page.screenshot({path:`test-results/status-queue-${viewport.width}x${viewport.height}.png`});
   const b=q[4],money=s.alloy;await page[mobile?'touchscreen':'mouse'][mobile?'tap':'click'](b.x+b.w/2,b.y+b.h/2);
   await page.waitForFunction(n=>frontierState.alloy===n+50,money);
   assert.equal((await state()).entities.find(e=>e.id===h.id).queue.length,4);
   await cmd({action:'patrol_setup'});
   for(const type of ['medic','tank','group']){
    const units=(await state()).entities.filter(e=>e.team===0&&['worker','ranger','tank','medic'].includes(e.type));
    await cmd({action:'select',ids:type==='group'?units.map(e=>e.id):[units.find(e=>e.type===type).id]});await check();
   }
   assert.deepEqual(errors,[]);console.log(`Compact stats and five visible queue items passed ${viewport.width}x${viewport.height}`);
  }
  await page.close();
 }
}finally{await browser.close();}
