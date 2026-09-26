import {chromium} from 'playwright';
import assert from 'node:assert/strict';
const browser=await chromium.launch({headless:true,executablePath:process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined,args:['--enable-unsafe-swiftshader']});
try{
 for(const viewport of [{width:1280,height:800},{width:320,height:568},{width:844,height:390}]){
  const p=await browser.newPage({viewport}),errors=[];p.on('pageerror',e=>errors.push(e.message));p.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  const state=()=>p.evaluate(()=>window.frontierState);
  const click=async text=>{await p.waitForFunction(t=>window.frontierState.buttons.some(b=>b.text===t),text);const b=(await state()).buttons.find(b=>b.text===text);assert.ok(b.x>=0&&b.y>=0&&b.x+b.w<=viewport.width+1&&b.y+b.h<=viewport.height+1,text+' fits '+JSON.stringify(b));await p.mouse.click(b.x+b.w/2,b.y+b.h/2);return b;};
  await p.goto((process.env.TEST_URL||'http://127.0.0.1:4176/3d_astra_godot/')+'?test=1');await p.waitForFunction(()=>window.frontierState?.ready,null,{timeout:90000});await p.waitForFunction(v=>window.frontierState.viewport[0]===v.width&&window.frontierState.viewport[1]===v.height,viewport);
  let option=await click('Meridian Riverlands · 96×96');await p.waitForTimeout(200);await p.mouse.click(option.x+option.w/2,option.y+option.h+3+26*3.5);
  await p.waitForFunction(()=>window.frontierState.buttons.some(b=>b.text==='Frontier Expanse · 160×160'));
  await click('Start');await p.waitForFunction(()=>window.frontierState.started&&window.frontierState.map_id==='expanse');
  await click('Pause');await click('New game / choose map');await p.waitForFunction(()=>!window.frontierState.started&&window.frontierState.paused);
  option=await click('Frontier Expanse · 160×160');await p.waitForTimeout(200);await p.mouse.click(option.x+option.w/2,option.y+option.h+3+26*.5);await p.waitForFunction(()=>window.frontierState.buttons.some(b=>b.text==='Meridian Riverlands · 96×96'));
  await click('Start');await p.waitForFunction(()=>window.frontierState.started&&window.frontierState.map_id==='riverlands');
  assert.deepEqual(errors,[]);console.log(`Godot visible map selector and new game passed ${viewport.width}x${viewport.height}`);await p.close();
 }
}finally{await browser.close();}
