import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const url=process.env.TEST_URL||'http://127.0.0.1:4176/3d_astra_godot/';
fs.mkdirSync('test-results',{recursive:true});
const browser=await chromium.launch({headless:true,executablePath:process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined,args:['--enable-unsafe-swiftshader']});
const reports=[];
try {
for(const mobile of [false,true]){
 const context=await browser.newContext({viewport:mobile?{width:390,height:844}:{width:1280,height:800},hasTouch:mobile,isMobile:mobile,deviceScaleFactor:1});
 const page=await context.newPage();const errors=[];
 page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});page.on('response',r=>{if(r.status()>=400)errors.push(`${r.status()} ${r.url()}`);});
 const state=()=>page.evaluate(()=>window.frontierState);
 const cmd=async o=>{await page.evaluate(o=>window.frontierCommand(JSON.stringify(o)),o);await page.waitForTimeout(120);};
 const press=async text=>{
   await page.waitForFunction(t=>window.frontierState?.buttons.some(b=>b.text===t),text);
   const snapshot=await state();const serial=snapshot.ui_action_serial;
   const b=snapshot.buttons.find(b=>b.text===text);assert(b,`button ${text}`);
   const p={x:b.x+b.w/2,y:b.y+b.h/2};
   if(mobile)await page.touchscreen.tap(p.x,p.y);else await page.mouse.click(p.x,p.y);
   await page.waitForFunction(serial=>window.frontierState.ui_action_serial>serial,serial);
 };
 try {
 await page.goto(url+'?test=1');
 await page.waitForFunction(()=>window.frontierState?.ready,null,{timeout:90000});
 assert.equal((await state()).models,18);
 await page.screenshot({path:`test-results/${mobile?'mobile':'desktop'}-briefing.png`});
 // Intro stays paused; scrolling exposes its controls on short displays.
 await press('Army & graphics settings');assert.equal((await state()).settings_open,true);
 await press('High contrast: Gold / Violet');
 await press('Apply settings');assert.equal((await state()).settings.player,3);assert.equal((await state()).started,false);
 await press('Deploy expedition');assert.equal((await state()).started,true);
 await cmd({action:'start'}); // deterministic UI checks, AI remains covered in GDScript matches
 let s=await state();const worker=s.entities.find(e=>e.type==='worker'&&e.team===0);const deposit=s.entities.find(e=>e.type==='alloy');
 await cmd({action:'select',ids:[worker.id]});
 if(mobile)await page.touchscreen.tap(...deposit.screen);else await page.mouse.click(...deposit.screen,{button:'right'});
 await page.waitForTimeout(150);assert.equal((await state()).entities.find(e=>e.id===worker.id).orders[0],'gather');
 const before=(await state()).alloy;await cmd({action:'step',seconds:45});assert.ok((await state()).alloy>before);
 const hq=(await state()).entities.find(e=>e.type==='hq'&&e.team===0);
 const roof=(await state()).building_probes.find(b=>b.id===hq.id).screen;
 if(mobile)await page.touchscreen.tap(...roof);else await page.mouse.click(...roof);
 await page.waitForFunction(id=>window.frontierState.selected.length===1&&window.frontierState.selected[0]===id,hq.id);
 await press('Harvester · 50/0');assert.equal((await state()).population.reserved,1);
 await press('Cancel #1');assert.equal((await state()).population.reserved,0);
 await press('Harvester · 50/0');await cmd({action:'step',seconds:9});assert.equal((await state()).population.used,8);
 const production=(await state()).entities.find(e=>e.type==='barracks'&&e.team===0);
 await cmd({action:'select',ids:[production.id]});
 for(let i=0;i<3;i++)await press('Ranger · 100/25');
 await cmd({action:'select',ids:[worker.id]});
 await press('Foundry 200/100');
 await page.waitForFunction(()=>window.frontierState.notice.includes('25 energy more to build Foundry'));
 assert.equal((await state()).mode,'');
 await page.screenshot({path:`test-results/${mobile?'mobile':'desktop'}-construction-feedback.png`});
 await cmd({action:'select',ids:[production.id]});
 for(let i=0;i<3;i++)await press('Cancel #1');
 await press('Pause');let time=(await state()).time;
 await page.waitForTimeout(300);assert.equal((await state()).time,time);
 await press('Army & graphics settings');await press('Cancel');assert.equal((await state()).paused,true);
 await press('Resume');assert.equal((await state()).paused,false);
 if(!mobile){
   const army=(await state()).entities.filter(e=>e.team===0&&['ranger','vanguard'].includes(e.type)).map(e=>e.id);
   await cmd({action:'select',ids:army});
   await page.keyboard.press('Shift+Digit1');await page.waitForFunction(()=>window.frontierState.groups['49']?.length===3);await cmd({action:'select',ids:[]});await page.keyboard.press('Digit1');await page.waitForFunction(()=>window.frontierState.selected.length===3);
   await page.keyboard.press('q');await page.waitForTimeout(150);assert.equal((await state()).mode,'attack');await page.keyboard.press('Escape');
 }else{
   const client=await context.newCDPSession(page);
   const focus=(await state()).focus;
   await client.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:160,y:320,id:1}]});
   await client.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:220,y:355,id:1}]});
   await client.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
   await page.waitForTimeout(200);assert.notDeepEqual((await state()).focus,focus);
   const zoom=(await state()).zoom;
   await client.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:100,y:330,id:1},{x:250,y:330,id:2}]});
   await client.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:75,y:330,id:1},{x:280,y:330,id:2}]});
   await client.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
   await page.waitForTimeout(200);assert.ok((await state()).zoom<zoom);
   await page.setViewportSize({width:844,height:390});await page.waitForTimeout(400);
   await press('Pause');await press('Army & graphics settings');
   await page.screenshot({path:'test-results/mobile-landscape-settings.png'});
   // Scroll the Godot ScrollContainer to its footer, then cancel.
   await page.mouse.move(500,260);await page.mouse.wheel(0,550);await page.waitForTimeout(350);await press('Cancel');await press('Resume');
   await page.setViewportSize({width:390,height:844});await page.waitForTimeout(400);
 }
 // Progress through the real upgrade and production controls on both input modes.
 await cmd({action:'progression_setup'});
 await cmd({action:'select',ids:[hq.id]});
 assert.match((await state()).selection_info,/Shield.*ATK/);
 await press('Info & stats');assert.equal((await state()).guide_open,true);
 const guideTime=(await state()).time;await page.waitForTimeout(180);assert.equal((await state()).time,guideTime);
 await page.screenshot({path:`test-results/${mobile?'mobile':'desktop'}-field-guide.png`});
 await press('Close field guide');assert.equal((await state()).paused,false);
 await press('Upgrade L2 · 200/100');assert.equal((await state()).entities.find(e=>e.id===hq.id).upgrading,true);
 await press('Cancel upgrade');assert.equal((await state()).entities.find(e=>e.id===hq.id).upgrading,false);
 await press('Upgrade L2 · 200/100');await cmd({action:'step',seconds:21});assert.equal((await state()).tech_level,2);
 await cmd({action:'select',ids:[production.id]});
 await press('Medic · 100/50');assert.match((await state()).notice,/Upgrade Barracks to level 2/);
 await press('Upgrade L2 · 100/50');await cmd({action:'step',seconds:21});
 await press('Medic · 100/50');await cmd({action:'step',seconds:13});
 assert.ok((await state()).entities.some(e=>e.type==='medic'&&e.team===0));
 await cmd({action:'support_setup'});
 const ally=(await state()).entities.find(e=>e.type==='ranger'&&e.team===0);
 await press('Support');
 if(mobile)await page.touchscreen.tap(...ally.screen);else await page.mouse.click(...ally.screen);
 await page.waitForFunction(()=>window.frontierState.entities.some(e=>e.type==='medic'&&e.orders[0]==='support'));
 await cmd({action:'step',seconds:2});assert.ok((await state()).entities.find(e=>e.id===ally.id).hp>20);
 await page.screenshot({path:`test-results/${mobile?'mobile':'desktop'}-medic-support.png`});
 await cmd({action:'select',ids:[hq.id]});
 await press('Upgrade L3 · 350/175');await cmd({action:'step',seconds:31});assert.equal((await state()).tech_level,3);
 await cmd({action:'camera',x:-20,z:18,zoom:48});
 await page.screenshot({path:`test-results/${mobile?'mobile':'desktop'}-game.png`});
 await cmd({action:'outcome',team:1});assert.equal((await state()).result,'victory');
 await press('New expedition');assert.equal((await state()).started,false);assert.equal((await state()).models,18);
 assert.equal((await state()).settings.player,3);
 await page.reload();await page.waitForFunction(()=>window.frontierState?.ready,null,{timeout:90000});assert.equal((await state()).settings.player,3);
 assert.deepEqual(errors,[]);reports.push({mobile,passed:true,errors});
 }catch(e){await page.screenshot({path:`test-results/${mobile?'mobile':'desktop'}-failure.png`});console.error(JSON.stringify(await state()));console.error(errors);throw e;}
 await context.close();
}
console.log(JSON.stringify(reports,null,2));
}finally{await browser.close();}
