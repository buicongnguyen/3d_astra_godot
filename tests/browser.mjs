import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const url=process.env.TEST_URL||'http://127.0.0.1:4176/3d_astra_godot/';
fs.mkdirSync('test-results',{recursive:true});
const browser=await chromium.launch({headless:true,executablePath:process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined,args:['--enable-unsafe-swiftshader']});
const reports=[];
try {
for(const mobile of [false,true]){
 console.log(`Starting ${mobile?'mobile':'desktop'} gameplay checks; mobile DPR ${process.env.MOBILE_DPR||3}`);
 const context=await browser.newContext({viewport:mobile?{width:390,height:844}:{width:1280,height:800},hasTouch:mobile,isMobile:mobile,deviceScaleFactor:mobile?Number(process.env.MOBILE_DPR||3):1});
 const page=await context.newPage();const errors=[];
 page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});page.on('response',r=>{if(r.status()>=400)errors.push(`${r.status()} ${r.url()}`);});
 const state=()=>page.evaluate(()=>window.frontierState);
 const cmd=async o=>{await page.evaluate(o=>window.frontierCommand(JSON.stringify(o)),o);await page.waitForTimeout(120);};
 const clickVisible=async text=>{
   await page.waitForFunction(t=>window.frontierState?.buttons.some(b=>b.text===t),text);
   const snapshot=await state();const serial=snapshot.ui_action_serial;
   const b=snapshot.buttons.find(b=>b.text===text);assert(b,`button ${text}`);
   const p={x:b.x+b.w/2,y:b.y+b.h/2};
   if(mobile)await page.touchscreen.tap(p.x,p.y);else await page.mouse.click(p.x,p.y);
   await page.waitForFunction(serial=>window.frontierState.ui_action_serial>serial,serial);
 };
 const press=async text=>{
   let s=await state();
   if(mobile && !s.buttons.some(b=>b.text===text)) {
     while((await state()).action_page>0)await clickVisible('Previous');
     for(let i=0;i<s.action_pages;i++){
       s=await state();
       if(s.buttons.some(b=>b.text===text))break;
       if(s.action_page<s.action_pages-1)await clickVisible('More actions');
     }
   }
   await clickVisible(text);
 };
 try {
 await page.goto(url+'?test=1');
 await page.waitForFunction(()=>window.frontierState?.ready,null,{timeout:90000});
 if(mobile)assert.deepEqual((await state()).viewport,[390,844],'HUD uses logical phone pixels');
 assert.equal((await state()).models,18);
 await page.screenshot({path:`test-results/${mobile?'mobile':'desktop'}-briefing.png`});
 // Intro stays paused; its footer controls remain fixed on short displays.
 await press('Army & graphics settings');assert.equal((await state()).settings_open,true);
 await press('High contrast: Gold / Violet');
 await press('Apply settings');assert.equal((await state()).settings.player,3);assert.equal((await state()).started,false);
 await press('Deploy expedition');assert.equal((await state()).started,true);
 await page.waitForFunction(()=>window.frontierState.time>0); // normal matches advance in real time
 await cmd({action:'start',manual_clock:true}); // UI checks advance time explicitly, independent of software-renderer speed
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
 if(mobile)assert.equal((await state()).action_page,1,'queue changes preserve the current action page');
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
 console.log(`Production controls passed (${mobile?'mobile':'desktop'})`);
 await cmd({action:'start'}); // exercise real-time pause behavior independently of deterministic production checks
 const runningTime=(await state()).time;
 await page.waitForFunction(t=>window.frontierState.time>t,runningTime);
 await press('Pause');let time=(await state()).time;
 await page.waitForTimeout(300);assert.equal((await state()).time,time);
 await press('Army & graphics settings');await press('Cancel');assert.equal((await state()).paused,true);
 await press('Resume');assert.equal((await state()).paused,false);
 await page.waitForFunction(t=>window.frontierState.time>t,time);
 await cmd({action:'start',manual_clock:true});
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
   await press('Cancel');await press('Resume');
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
 await cmd({action:'select',ids:[production.id]});
 await press('Anti-tank soldier · 125/50');await cmd({action:'step',seconds:15});
 assert.ok((await state()).entities.some(e=>e.type==='antitank'&&e.team===0));
 await cmd({action:'heavy_setup'});
 const foundry=(await state()).entities.find(e=>e.type==='foundry'&&e.team===0);
 await cmd({action:'select',ids:[foundry.id]});
 await press('Battle tank · 275/125');assert.match((await state()).notice,/Upgrade Foundry to level 3/);
 await press('Upgrade L2 · 100/50');await cmd({action:'step',seconds:21});
 await press('Upgrade L3 · 200/100');await cmd({action:'step',seconds:31});
 await press('Battle tank · 275/125');await cmd({action:'step',seconds:21});
 assert.ok((await state()).entities.some(e=>e.type==='tank'&&e.team===0));
 await page.screenshot({path:`test-results/${mobile?'mobile':'desktop'}-heavy.png`});
 if(mobile){
   console.log('Progression passed; checking viewport matrix');
   // Inspect actual canvas coordinates without auto-scrolling hidden controls into view.
   for(const viewport of [{width:320,height:568},{width:390,height:844},{width:667,height:375},{width:844,height:390},{width:768,height:1024}]){
     await page.setViewportSize(viewport);await page.waitForTimeout(350);
     const fits=(b,r=[0,0,viewport.width,viewport.height])=>{
       assert.ok(b.x>=r[0]-1 && b.y>=r[1]-1 && b.x+b.w<=r[0]+r[2]+1 && b.y+b.h<=r[1]+r[3]+1,`${b.text} clipped at ${viewport.width}x${viewport.height}: ${JSON.stringify(b)} in ${r}`);
       assert.ok(b.h>=44,`${b.text} touch height`);
     };
     for(const type of ['worker','hq','barracks','foundry','medic','tank','antitank']){
       const entity=(await state()).entities.find(e=>e.type===type&&e.team===0);
       await cmd({action:'select',ids:[entity.id]});
       const names=new Set();
       for(let p=0;p<(await state()).action_pages;p++){
         const s=await state();assert.equal(s.mobile_layout,true);
         for(const b of s.action_buttons){fits(b);fits(b,s.action_rect);names.add(b.text);}
         for(const text of ['Previous','More actions'])fits(s.buttons.find(b=>b.text===text));
         if(p<s.action_pages-1)await clickVisible('More actions');
       }
       assert.ok(names.has('Info & stats'),`${type} guide reachable`);
       if(type==='medic')assert.ok(names.has('Support'));
     }
     await press('Pause');
     for(const text of ['Resume','Army & graphics settings'])fits((await state()).buttons.find(b=>b.text===text));
     await press('Army & graphics settings');
     for(const text of ['Apply settings','Cancel'])fits((await state()).buttons.find(b=>b.text===text));
     await press('Cancel');await press('Resume');
     await page.screenshot({path:`test-results/mobile-controls-${viewport.width}x${viewport.height}.png`});
     console.log(`Visible controls passed: ${viewport.width}x${viewport.height}`);
   }
   await page.setViewportSize({width:390,height:844});await page.waitForTimeout(350);
 }
 await cmd({action:'camera',x:-20,z:18,zoom:48});
 await page.screenshot({path:`test-results/${mobile?'mobile':'desktop'}-game.png`});
 await cmd({action:'outcome',team:1});assert.equal((await state()).result,'victory');
 await press('New expedition');assert.equal((await state()).started,false);
 // The UI callback acknowledges restart before the next render refresh recreates models.
 await page.waitForFunction(()=>window.frontierState.models===18);
 assert.equal((await state()).settings.player,3);
 await page.reload();await page.waitForFunction(()=>window.frontierState?.ready,null,{timeout:90000});assert.equal((await state()).settings.player,3);
 assert.deepEqual(errors,[]);reports.push({mobile,passed:true,errors});
 }catch(e){await page.screenshot({path:`test-results/${mobile?'mobile':'desktop'}-failure.png`});console.error(JSON.stringify(await state()));console.error(errors);throw e;}
 await context.close();
}
console.log(JSON.stringify(reports,null,2));
}finally{await browser.close();}
