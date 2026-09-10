import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const browser=await chromium.launch({headless:true,executablePath:process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined,args:['--enable-unsafe-swiftshader']});
fs.mkdirSync('test-results',{recursive:true});
const page=await browser.newPage({viewport:{width:1280,height:800}});
const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
const state=()=>page.evaluate(()=>window.frontierState);
const cmd=async command=>{await page.evaluate(c=>window.frontierCommand(JSON.stringify(c)),command);await page.waitForTimeout(180);};
const press=async key=>{await page.keyboard.press(key);await page.waitForTimeout(200);};
const selected=async()=> (await state()).selected;
const click=async text=>{
  let b=(await state()).buttons.find(b=>b.text===text);assert.ok(b,`button ${text}`);
  for(let i=0;i<15&&(b.y<100||b.y+b.h>650)&&text!=='Keys';i++){
    await page.mouse.move(700,400);await page.mouse.wheel(0,b.y<100?-240:240);await page.waitForTimeout(180);
    b=(await state()).buttons.find(b=>b.text===text);
  }
  await page.mouse.click(b.x+b.w/2,b.y+b.h/2);await page.waitForTimeout(250);
};
try {
  await page.goto((process.env.TEST_URL||'http://127.0.0.1:4176/3d_astra_godot/')+'?test=1');
  await page.waitForFunction(()=>window.frontierState?.ready,null,{timeout:90000});
  await cmd({action:'start',manual_clock:true});await cmd({action:'progression_setup'});await cmd({action:'heavy_setup'});
  let s=await state();const own=s.entities.filter(e=>e.team===0),workers=own.filter(e=>e.type==='worker').map(e=>e.id),army=own.filter(e=>['ranger','vanguard'].includes(e.type)).map(e=>e.id);
  const hq=own.find(e=>e.type==='hq'),barracks=own.find(e=>e.type==='barracks'),foundry=own.find(e=>e.type==='foundry');
  await press('F2');assert.deepEqual(await selected(),army);
  await press('Control+Digit1');assert.deepEqual((await state()).groups['49'],army);
  await press('F3');assert.deepEqual(await selected(),workers);await press('Shift+Digit1');await press('Backquote');assert.deepEqual(await selected(),[]);
  await press('Digit1');assert.deepEqual(new Set(await selected()),new Set([...army,...workers]));
  await press('Control+a');assert.equal((await selected()).length,army.length+workers.length);
  await press('F1');const idle=(await selected())[0];assert.ok(workers.includes(idle));await press('Period');assert.notEqual((await selected())[0],idle);
  await press('z');assert.deepEqual(await selected(),workers);
  await press('F4');assert.ok((await selected()).includes(foundry.id));
  for(const [key,e] of [['h',hq],['j',barracks],['k',foundry]]){await press(key);assert.deepEqual(await selected(),[e.id]);}
  await press('b');assert.ok(workers.includes((await selected())[0]));
  for(const [key,type] of [['q','relay'],['e','barracks'],['r','foundry'],['t','tower'],['y','hq']]){
    await press(key);s=await state();assert.equal(s.mode,'build');assert.equal(s.building_type,type);await press('Escape');
  }
  await press('h');await page.keyboard.down('q');await page.keyboard.down('q');await page.keyboard.up('q');await page.waitForTimeout(200);
  assert.equal((await state()).entities.find(e=>e.id===hq.id).queue.length,1,'holding Q trains once');
  await press('Backspace');assert.equal((await state()).entities.find(e=>e.id===hq.id).queue.length,0);
  // Upgrade gates must be satisfied via the normal U command before advanced training.
  await press('u');assert.equal((await state()).entities.find(e=>e.id===hq.id).upgrading,true);
  await press('Backspace');assert.equal((await state()).entities.find(e=>e.id===hq.id).upgrading,false);
  for(const key of ['h','j','k']){
    await press(key);await press('u');await cmd({action:'step',seconds:60});
  }
  await press('h');await press('u');await cmd({action:'step',seconds:60});
  await press('k');await press('u');await cmd({action:'step',seconds:60});
  for(const [building,types] of [['j',['vanguard','ranger','medic','antitank']],['k',['breaker','upgrade','engineer','tank']]]){
    await press(building);
    for(const [i,type] of types.entries()){
      await press(['q','e','r','t'][i]);s=await state();
      assert.equal(s.entities.find(e=>e.id===s.selected[0]).queue.at(-1),type,`${building} ${type}: ${s.notice}`);await press('Backspace');
    }
  }
  await press('F2');
  for(const [key,mode] of [['m','move'],['f','attack'],['r','support'],['c','context']]){await press(key);assert.equal((await state()).mode,mode);await press('Escape');}
  // C must reach the click handler and issue gather; M must override even a resource target.
  await press('F3');const deposit=(await state()).entities.find(e=>e.type==='alloy');
  await press('c');await page.mouse.click(...deposit.screen);await page.waitForTimeout(200);
  assert.equal((await state()).entities.find(e=>e.id===workers[0]).orders[0],'gather');
  for(let i=0;i<30&&!(await state()).entities.find(e=>e.id===workers[0]).carry;i++)await cmd({action:'step',seconds:1});
  assert.ok((await state()).entities.find(e=>e.id===workers[0]).carry>0);
  await press('m');await press('v');assert.equal((await state()).mode,'');
  assert.equal((await state()).entities.find(e=>e.id===workers[0]).orders[0],'deliver');
  await press('o');assert.ok((await state()).buttons.some(b=>b.text==='Queue: ON'));await press('o');
  await press('m');await page.mouse.click(...deposit.screen);await page.waitForTimeout(200);
  assert.equal((await state()).entities.find(e=>e.id===workers[0]).orders[0],'move');
  await press('x');assert.equal((await state()).entities.find(e=>e.id===workers[0]).orders.length,0);
  await press('h');await press('l');assert.equal((await state()).mode,'rally');
  await page.mouse.click(...deposit.screen);await page.waitForTimeout(200);assert.ok((await state()).entities.find(e=>e.id===hq.id).rally);assert.equal((await state()).mode,'');
  await press('Home');await press('Equal');await press('Minus');
  await press('Space');assert.equal((await state()).paused,true);const selection=await selected();await press('b');assert.deepEqual(await selected(),selection);await press('Space');assert.equal((await state()).paused,false);
  await press('Slash');assert.equal((await state()).guide_open,true);await page.screenshot({path:'test-results/pc-hotkey-guide.png'});
  await press('b');assert.deepEqual(await selected(),selection);await press('Escape');
  await press('i');await press('b');assert.deepEqual(await selected(),selection);await press('Escape');
  await click('Keys');await click('Select Harvesters [F3]');assert.deepEqual(await selected(),workers);
  await page.screenshot({path:'test-results/pc-hotkeys.png'});assert.deepEqual(errors,[]);
  console.log('PC shortcuts: selection, groups, build/train slots, upgrades/cancellation, repeat guard, gather/move/stop/rally, modal guards and buttons passed.');
}finally{await browser.close();}
