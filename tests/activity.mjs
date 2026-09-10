import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';
fs.mkdirSync('test-results',{recursive:true});
const browser=await chromium.launch({headless:true,executablePath:process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined,args:['--enable-unsafe-swiftshader']});
try{
  for(const mobile of [false,true]){
    const page=await browser.newPage({viewport:{width:1280,height:800},hasTouch:mobile,isMobile:mobile,deviceScaleFactor:mobile?Number(process.env.MOBILE_DPR||3):1});
    const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
    const state=()=>page.evaluate(()=>window.frontierState);
    const cmd=async c=>{await page.evaluate(c=>window.frontierCommand(JSON.stringify(c)),c);await page.waitForTimeout(200);};
    const click=async text=>{
      for(let i=0;i<12;i++){
        const s=await state(),b=s.buttons.find(b=>b.text===text);
        if(b){
          assert.ok(b.x>=0 && b.y>=0 && b.x+b.w<=s.viewport[0]+1 && b.y+b.h<=s.viewport[1]+1,`${text} fits`);
          if(mobile)assert.ok(b.h>=44 && b.w>=44);
          await page[mobile?'touchscreen':'mouse'][mobile?'tap':'click'](b.x+b.w/2,b.y+b.h/2);
          await page.waitForFunction(n=>window.frontierState.ui_action_serial>n,s.ui_action_serial);return;
        }
        const next=s.buttons.find(b=>b.text==='More actions'&&!b.disabled);assert.ok(next,`${text} reachable`);
        await page[mobile?'touchscreen':'mouse'][mobile?'tap':'click'](next.x+next.w/2,next.y+next.h/2);await page.waitForTimeout(250);
      }
      assert.fail(`Missing ${text}`);
    };
    await page.goto((process.env.TEST_URL||'http://127.0.0.1:4176/3d_astra_godot/')+'?test=1');
    await page.waitForFunction(()=>window.frontierState?.ready,null,{timeout:90000});
    await cmd({action:'stage',index:1});await cmd({action:'start',manual_clock:true});
    for(const viewport of mobile?[{width:320,height:568},{width:390,height:844},{width:844,height:390}]:[{width:1280,height:800}]){
      await page.setViewportSize(viewport);await page.waitForFunction(v=>window.frontierState.viewport[0]===v.width&&window.frontierState.viewport[1]===v.height,viewport);
      await cmd({action:'activity_setup'});await cmd({action:'step',seconds:.8});
      await page.waitForFunction(()=>window.frontierState.activity.workers.some(w=>w.mining));
      let s=await state();const w=s.entities.find(e=>s.selected.includes(e.id)),r=s.entities.find(e=>e.id===w.resource),hq=s.entities.find(e=>e.type==='hq'&&e.team===0),site=s.entities.filter(e=>!e.complete).at(-1);
      assert.ok(s.activity.resources.includes(r.id));
      assert.ok(s.activity.buildings.some(e=>e.id===site.id && e.progress>0));
      await page.screenshot({path:`test-results/activity-harvest-${viewport.width}.png`});
      await cmd({action:'order',order:{type:'stop'}});
      await page.waitForFunction(()=>window.frontierState.activity.resources.length===0);
      await cmd({action:'select',ids:[hq.id]});
      const offset=mobile&&viewport.width>viewport.height?150*34/viewport.height:0;
      await cmd({action:'camera',x:hq.x+offset,z:hq.z+5,zoom:34});
      await page.waitForFunction(id=>window.frontierState.activity.buildings.some(e=>e.id===id),hq.id);
      if(mobile)assert.equal((await state()).action_page,0);
      await page.screenshot({path:`test-results/activity-production-${viewport.width}.png`});
      const money=(await state()).alloy;
      await click('Cancel Harvester #1 · refund');
      s=await state();assert.equal(s.alloy,money+50);assert.equal(s.entities.find(e=>e.id===hq.id).queue.length,1);
      await click('Cancel Harvester #1 · refund');
      assert.equal((await state()).entities.find(e=>e.id===hq.id).queue.length,0);
      await cmd({action:'select',ids:[site.id]});
      const paid=(await state()).alloy;await click('Cancel site · 75% refund');
      assert.equal((await state()).alloy,paid+75);
      await cmd({action:'step',seconds:.1});
      await page.waitForFunction(id=>!window.frontierState.activity.buildings.some(e=>e.id===id),site.id);
      assert.deepEqual(errors,[]);console.log(`Activity bars, cancellation and resource feedback passed ${viewport.width}x${viewport.height}`);
    }
    await page.close();
  }
}finally{await browser.close();}
