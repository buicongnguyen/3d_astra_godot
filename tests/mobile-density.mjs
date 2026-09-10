import {chromium,devices} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const url=process.env.TEST_URL||'http://127.0.0.1:4176/3d_astra_godot/';
fs.mkdirSync('test-results',{recursive:true});
const browser=await chromium.launch({headless:true,executablePath:process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined,args:['--enable-unsafe-swiftshader']});
try{
 const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:3,hasTouch:true,isMobile:true,userAgent:devices['Pixel 7'].userAgent});
 const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
 const state=()=>page.evaluate(()=>window.frontierState);
 const press=async text=>{
   await page.waitForFunction(t=>window.frontierState?.buttons.some(b=>b.text===t),text);
   const s=await state(),b=s.buttons.find(b=>b.text===text);
   assert.ok(b.x>=0&&b.y>=0&&b.x+b.w<=s.viewport[0]+1&&b.y+b.h<=s.viewport[1]+1,`${text} fits logical viewport`);
   await page.touchscreen.tap(b.x+b.w/2,b.y+b.h/2);
   await page.waitForFunction(n=>window.frontierState.ui_action_serial>n,s.ui_action_serial);
 };
 await page.goto(url+'?test=1');await page.waitForFunction(()=>window.frontierState?.ready,null,{timeout:90000});
 assert.deepEqual((await state()).viewport,[390,844]);
 await press('Deploy expedition');assert.equal((await state()).started,true);
 for(const viewport of [{width:320,height:568},{width:390,height:844},{width:800,height:360}]){
   await page.setViewportSize(viewport);await page.waitForFunction(v=>frontierState.viewport[0]===v.width&&frontierState.viewport[1]===v.height,viewport);
   let s=await state();
   assert.ok(s.buttons.filter(b=>['Home','−','+','Pause','Keys','Objectives'].includes(b.text)).every(b=>b.w>=44&&b.h>=44&&b.x>=0&&b.x+b.w<=viewport.width),'phone header controls fit and have 44px targets');
   assert.equal(s.objectives_visible,false);
   await press('Objectives');s=await state();assert.equal(s.objectives_visible,true);
   const [x,y,w,h]=s.objectives_rect;
   assert.ok(x>=0&&y>=0&&x+w<=viewport.width&&y+h<=viewport.height,'objectives popup fits');
   const orders=snapshot=>snapshot.entities.filter(e=>snapshot.selected.includes(e.id)).map(e=>[e.id,e.orders]);
   await page.touchscreen.tap(x+w/2,y+h/2);await page.waitForTimeout(180);
   assert.deepEqual((await state()).selected,s.selected,'popup taps preserve selection');
   assert.deepEqual(orders(await state()),orders(s),'popup taps do not issue battlefield orders');
   await press('Objectives');assert.equal((await state()).objectives_visible,false);
 }
 await page.setViewportSize({width:390,height:844});await page.waitForFunction(()=>frontierState.viewport[0]===390&&frontierState.viewport[1]===844);
 await press('More actions');assert.equal((await state()).action_page,1);
 await press('Previous');await press('Info & stats');await press('Close field guide');
 await page.screenshot({path:'test-results/density-portrait.png'});
 await page.setViewportSize({width:844,height:390});
 await page.waitForFunction(()=>window.frontierState.viewport[0]===844&&window.frontierState.viewport[1]===390);
 await press('Pause');await press('Army & graphics settings');await press('Cancel');await press('Resume');
 assert.equal((await state()).paused,false);
 await page.screenshot({path:'test-results/density-landscape.png'});
 assert.deepEqual(errors,[]);
 console.log('Android Chrome DPR 3: logical viewport, touch actions, paging, guide, rotation and modal footers passed');
}finally{await browser.close();}
