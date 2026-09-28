import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';
fs.mkdirSync('test-results',{recursive:true});
const browser=await chromium.launch({headless:true,executablePath:process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined,args:['--enable-unsafe-swiftshader']});
try{
 for(const mobile of [false,true]){
  const page=await browser.newPage({viewport:mobile?{width:390,height:844}:{width:1280,height:800},isMobile:mobile,hasTouch:mobile});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  const state=()=>page.evaluate(()=>frontierState);
  const cmd=async c=>{await page.evaluate(c=>frontierCommand(JSON.stringify(c)),c);await page.waitForTimeout(200);};
  const click=async text=>{
   const button=(await state()).buttons.find(b=>b.text===text&&!b.disabled);
   assert.ok(button,'button available: '+text);
   await page[mobile?'touchscreen':'mouse'][mobile?'tap':'click'](button.x+button.w/2,button.y+button.h/2);
   await page.waitForTimeout(200);
  };
  await page.goto((process.env.TEST_URL||'http://127.0.0.1:4176/3d_astra_godot/')+'?test=1');
  await page.waitForFunction(()=>window.frontierState?.ready,null,{timeout:90000});
  await click('Tiếng Việt');
  await page.waitForFunction(()=>frontierState.language==='vi');
  assert.equal((await state()).buttons.find(b=>b.text==='Start').display_text,'Bắt đầu');
  await page.screenshot({path:'test-results/language-start-'+(mobile?'mobile':'desktop')+'.png'});
  await page.waitForTimeout(1100);await page.reload();
  await page.waitForFunction(()=>window.frontierState?.language==='vi',null,{timeout:90000});
  await cmd({action:'start',manual_clock:true});
  await cmd({action:'activity_setup'});
  let s=await state(),core=s.entities.find(e=>e.type==='hq'&&e.team===0);
  await cmd({action:'select',ids:[core.id]});
  await page.waitForFunction(()=>frontierState.display_selection.includes('SỞ CHỈ HUY'));
  await click('Pause');await click('Army & graphics settings');
  await click('English');await click('Apply settings');
  await page.waitForFunction(()=>frontierState.language==='en');
  await click('Resume');
  assert.equal((await state()).entities.find(e=>e.id===core.id).queue.length,core.queue.length,'language switch preserves the production queue');
  await click('Pause');await click('Army & graphics settings');
  await click('Tiếng Việt');await click('Apply settings');await click('Resume');
  await cmd({action:'patrol_setup'});
  const sizes=mobile?[{width:320,height:568},{width:390,height:844},{width:844,height:390}]:[{width:1280,height:800},{width:1024,height:768}];
  for(const size of sizes){
   await page.setViewportSize(size);
   await page.waitForFunction(v=>frontierState.viewport[0]===v.width&&frontierState.viewport[1]===v.height,size);
   for(const type of ['worker','medic','tank','hq','barracks']){
    const e=(await state()).entities.find(e=>e.type===type&&e.team===0);if(!e)continue;
    await cmd({action:'select',ids:[e.id]});
    const s=await state();
    assert.ok(s.buttons.filter(b=>['Home','−','+','Pause','Keys','Previous','More actions'].includes(b.text)).every(b=>b.x>=0&&b.x+b.w<=size.width&&b.y>=0&&b.y+b.h<=size.height),'navigation and paging controls fit the viewport');
    assert.ok(s.action_buttons.every(b=>b.caption_fits&&b.h>=44),JSON.stringify({size,type,buttons:s.action_buttons}));
   }
   await page.screenshot({path:'test-results/language-actions-'+size.width+'x'+size.height+'.png'});
  }
  assert.deepEqual(errors,[]);console.log('Godot language switching, saved preference, queues and label fit passed: '+(mobile?'mobile':'desktop'));await page.close();
 }
}finally{await browser.close();}
