import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';
// Ambient life in the exported game: every map builds its families with compiling shaders, the
// clock moves during play, and the frame-time governor calms, then stills, the tiny things.
const browser=await chromium.launch({headless:true,executablePath:process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined,args:['--enable-unsafe-swiftshader']});
fs.mkdirSync('test-results',{recursive:true});
const expected={riverlands:['birds','bird-shadows','butterflies','dragonflies','fish','motes'],classic:['birds','bird-shadows','motes'],basin:['birds','bird-shadows','butterflies','motes'],
  expanse:['birds','bird-shadows','butterflies','dragonflies','fish','motes'],dunes:['birds','bird-shadows','motes'],woodlands:['birds','bird-shadows','butterflies','dragonflies','fish','motes'],highlands:['birds','bird-shadows','motes']};
try{
  const page=await browser.newPage({viewport:{width:1280,height:800}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error'||/SHADER ERROR/i.test(m.text()))errors.push(m.text().slice(0,300));});
  const state=()=>page.evaluate(()=>window.frontierState);
  const cmd=async c=>{await page.evaluate(c=>window.frontierCommand(JSON.stringify(c)),c);await page.waitForTimeout(180);};
  await page.goto((process.env.TEST_URL||'http://127.0.0.1:4176/3d_astra_godot/')+'?test=1');
  await page.waitForFunction(()=>window.frontierState?.ready,null,{timeout:90000});
  const ids=['riverlands','classic','basin','expanse','dunes','woodlands','highlands'];
  for(const [index,id] of ids.entries()){
    if(index)await cmd({action:'restart'});
    await cmd({action:'stage',index});await cmd({action:'start',manual_clock:true});await cmd({action:'visual_fog',hidden:false});
    let s=await state();assert.equal(s.map_id,id);
    assert.deepEqual(s.life.families,expected[id],`${id} ambient families`);
    const clock=s.life.clock;await page.waitForTimeout(600);s=await state();
    assert.ok(s.life.clock>clock,`${id} life moves during play`);
    await cmd({action:'camera',x:0,z:6,zoom:30});await page.waitForTimeout(250);
    await page.screenshot({path:`test-results/life-${id}.png`});
  }
  // Governor (synthetic frame timings): two slow seconds calm the motion, two more still it.
  await cmd({action:'governor',reset:true,seconds:4,ms:16});
  await cmd({action:'governor',seconds:2.1,ms:45});assert.equal((await state()).life.level,1,'slow frames calm ambient life');
  await cmd({action:'governor',seconds:2.1,ms:45});let s=await state();assert.equal(s.life.level,0,'more slow frames hold it still');
  const held=s.life.clock;await page.waitForTimeout(500);assert.equal((await state()).life.clock,held,'still life does not move');
  assert.equal(s.life.share,0.5,'still hides half the creatures');
  await cmd({action:'governor',seconds:2.1,ms:45});assert.equal((await state()).life.share,0,'rescue hides them all');
  await cmd({action:'governor',seconds:40,ms:16});s=await state();assert.equal(s.life.level,2,'smooth frames restore full motion');
  assert.equal(s.life.share,1,'and every creature');
  assert.deepEqual(errors,[]);
  console.log('Godot ambient life passed: 7 maps, moving clock, governor full -> calm -> still -> full.');
}finally{await browser.close();}
