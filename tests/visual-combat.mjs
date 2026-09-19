import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const browser=await chromium.launch({headless:true,executablePath:process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined,args:['--enable-unsafe-swiftshader']});
fs.mkdirSync('test-results',{recursive:true});
try{
  const page=await browser.newPage({viewport:{width:1280,height:800}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  const state=()=>page.evaluate(()=>window.frontierState);
  const cmd=async c=>{await page.evaluate(c=>window.frontierCommand(JSON.stringify(c)),c);await page.waitForTimeout(180);};
  await page.goto((process.env.TEST_URL||'http://127.0.0.1:4176/3d_astra_godot/')+'?test=1');
  await page.waitForFunction(()=>window.frontierState?.ready,null,{timeout:90000});
  await cmd({action:'start',manual_clock:true});await cmd({action:'visual_setup'});
  await cmd({action:'visual_shots',count:200});let s=await state();assert.equal(s.visual.shots,64);assert.ok(s.visual.barrels>0);
  const lives=s.visual.lives;await page.waitForTimeout(300);assert.deepEqual((await state()).visual.lives,lives,'frozen visual clock preserves lifetimes');
  await cmd({action:'visual_advance',seconds:2});assert.equal((await state()).visual.shots,0);
  await cmd({action:'visual_fog',hidden:true});await cmd({action:'visual_shots'});assert.equal((await state()).visual.shots,0,'hidden shooters produce no trails');
  await cmd({action:'visual_fog',hidden:false});await cmd({action:'visual_settings',motion:true});s=await state();assert.ok(s.visual.combat_motion&&!s.visual.water_motion);
  await cmd({action:'visual_settings',motion:false});assert.equal((await state()).visual.combat_motion,false);await cmd({action:'visual_settings',motion:true});
  await cmd({action:'visual_shots'});await cmd({action:'visual_advance',seconds:.035});
  for(const viewport of [{width:1280,height:800},{width:390,height:844},{width:844,height:390}]){
    await page.setViewportSize(viewport);await page.waitForTimeout(250);
    await page.screenshot({path:`test-results/visual-weapons-${viewport.width}.png`});
    assert.ok((await state()).visual.shots<=64);
  }
  const palettes=new Set();
  await page.setViewportSize({width:1280,height:800});
  for(let index=0;index<4;index++){
    await cmd({action:'restart'});assert.equal((await state()).visual.shots,0);
    await cmd({action:'stage',index});await cmd({action:'start',manual_clock:true});
    s=await state();palettes.add(s.visual.theme.sky);
    if(index>=0){await cmd({action:'camera',x:-s.map_size/2+12,z:20,zoom:68});await page.screenshot({path:`test-results/visual-map-${s.map_id}.png`});}
  }
  assert.equal(palettes.size,4);assert.deepEqual(errors,[]);
  console.log('Godot visual combat passed: weapon feedback, pool cap, frozen clock, fog, independent motion, four biome palettes and restart cleanup.');
}finally{await browser.close();}
