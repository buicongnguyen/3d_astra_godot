import { chromium } from 'playwright';
import assert from 'node:assert/strict';
const base = process.env.TEST_URL || 'http://127.0.0.1:4176/3d_astra_godot/';
const browser = await chromium.launch({headless:true,
  executablePath:process.platform === 'win32' ? 'C:/Program Files/Google/Chrome/Application/chrome.exe' : undefined,
  args:['--enable-unsafe-swiftshader']});
try {
  for (const mobile of [false,true]) {
    const page = await browser.newPage({viewport: mobile ? {width:390,height:844} : {width:1280,height:800},isMobile:mobile,hasTouch:mobile});
    const errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    page.on('console',m=>{if(m.type()==='error') errors.push(m.text());});
    const cmd = async o => {
      await page.evaluate(o=>window.frontierCommand(JSON.stringify(o)),o);
      await page.waitForTimeout(200);
    };
    await page.goto(base+'?test=1');
    await page.waitForFunction(()=>window.frontierState?.ready,null,{timeout:90000});
    await cmd({action:'start',manual_clock:true});
    const start=await page.evaluate(()=>window.frontierState);
    const ids=start.entities.filter(e=>e.type==='worker'&&e.team===0).map(e=>e.id);
    const deposit=start.entities.find(e=>e.type==='alloy');
    await cmd({action:'select',ids});
    await cmd({action:'camera',x:deposit.x,z:deposit.z,zoom:32});
    const point=await page.evaluate(id=>window.frontierState.entities.find(e=>e.id===id).screen,deposit.id);
    if(mobile) await page.touchscreen.tap(...point);
    else await page.mouse.click(...point,{button:'right'});
    await page.waitForFunction(ids=>ids.every(id=>window.frontierState.entities.find(e=>e.id===id).orders[0]==='gather'),ids);
    await cmd({action:'step',seconds:300});
    const before=await page.evaluate(()=>window.frontierState);
    assert.ok(before.alloy>700,'sustained income');
    assert.ok(ids.every(id=>['gather','deliver'].includes(before.entities.find(e=>e.id===id).orders[0])));
    await cmd({action:'harvest_deplete',id:deposit.id});
    await cmd({action:'step',seconds:45});
    const after=await page.evaluate(()=>window.frontierState);
    assert.ok(after.alloy>before.alloy,'income resumes after depletion');
    assert.ok(ids.every(id=>{
      const w=after.entities.find(e=>e.id===id);
      return ['gather','deliver'].includes(w.orders[0]) && w.resource!==deposit.id;
    }),'every worker switches deposit');
    assert.deepEqual(errors,[]);
    console.log(`Godot ${mobile?'touch':'desktop'}: gathering input, sustained income and depletion recovery passed`);
    await page.close();
  }
} finally { await browser.close(); }
