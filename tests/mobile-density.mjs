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
