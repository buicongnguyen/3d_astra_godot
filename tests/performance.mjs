import {chromium} from 'playwright';import fs from 'node:fs';
const browser=await chromium.launch({headless:true,executablePath:process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined,args:['--enable-unsafe-swiftshader']});
try{
 const page=await browser.newPage({viewport:{width:1280,height:800}});const errors=[];page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
 await page.goto((process.env.TEST_URL||'http://127.0.0.1:4176/3d_astra_godot/')+'?test=1');await page.waitForFunction(()=>window.frontierState?.ready,null,{timeout:90000});
 await page.evaluate(()=>frontierCommand(JSON.stringify({action:'start'})));await page.evaluate(()=>frontierCommand(JSON.stringify({action:'benchmark'})));
 await page.waitForTimeout(1500);
 const result=await page.evaluate(async()=>{const samples=[];let prev=performance.now();for(let i=0;i<120;i++){let next=await new Promise(requestAnimationFrame);samples.push(next-prev);prev=next;}samples.sort((a,b)=>a-b);return {viewport:[innerWidth,innerHeight],userAgent:navigator.userAgent,units:frontierState.entities.filter(e=>e.team===0&&['worker','ranger','vanguard','breaker'].includes(e.type)).length,medianMs:samples[60],p95Ms:samples[114],drawCalls:frontierState.draw_calls,nodes:frontierState.nodes};});
 result.errors=errors;fs.writeFileSync('test-results/performance.json',JSON.stringify(result,null,2));console.log(result);await page.screenshot({path:'test-results/100-units.png'});
}finally{await browser.close();}
