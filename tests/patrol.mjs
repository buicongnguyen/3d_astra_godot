import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';
fs.mkdirSync('test-results', {recursive: true});
const browser = await chromium.launch({headless: true, executablePath: process.platform === 'win32' ? 'C:/Program Files/Google/Chrome/Application/chrome.exe' : undefined, args: ['--enable-unsafe-swiftshader']});
try {
  for (const mobile of [false, true]) {
    const layouts = mobile ? [{width: 320, height: 568}, {width: 390, height: 844}, {width: 667, height: 375}, {width: 844, height: 390}, {width: 768, height: 1024}] : [{width: 1280, height: 800}];
    const page = await browser.newPage({viewport: layouts[0], hasTouch: mobile, isMobile: mobile, deviceScaleFactor: mobile ? 3 : 1});
    const errors = []; page.on('pageerror', e => errors.push(e.message)); page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
    const state = () => page.evaluate(() => window.frontierState);
    const cmd = async c => { await page.evaluate(c => window.frontierCommand(JSON.stringify(c)), c); await page.waitForTimeout(250); };
    const rawClick = async b => {
      const s = await state(); assert.ok(b.x >= 0 && b.y >= 0 && b.x + b.w <= s.viewport[0] + 1 && b.y + b.h <= s.viewport[1] + 1, `${b.text} fits screen`);
      if (mobile) await page.touchscreen.tap(b.x + b.w / 2, b.y + b.h / 2); else await page.mouse.click(b.x + b.w / 2, b.y + b.h / 2);
      await page.waitForFunction(n => window.frontierState.ui_action_serial > n, s.ui_action_serial);
    };
    const click = async text => {
      for (let i = 0; i < 12; i++) {
        const s = await state(), b = s.buttons.find(b => b.text === text);
        if (b) { await rawClick(b); return; }
        const next = s.buttons.find(b => b.text === 'More actions' && !b.disabled);
        assert.ok(next, `${text} reachable through action pages`); await rawClick(next);
      }
      assert.fail(`Missing ${text}`);
    };
    const world = async id => {
      const s = await state(), target = s.entities.find(e => e.id === id);
      // Pan the intended target into the unobscured field before using real input.
      const offset = mobile && s.viewport[0] > s.viewport[1] ? 150 * 42 / s.viewport[1] : 0;
      await cmd({action: 'camera', x: target.x + offset, z: target.z, zoom: 42});
      const e = (await state()).entities.find(e => e.id === id);
      if (mobile) await page.touchscreen.tap(...e.screen); else await page.mouse.click(...e.screen);
      await page.waitForTimeout(250);
    };
    const orders = async id => (await state()).entities.find(e => e.id === id).orders;
    await page.goto((process.env.TEST_URL || 'http://127.0.0.1:4176/3d_astra_godot/') + '?test=1');
    await page.waitForFunction(() => window.frontierState?.ready, null, {timeout: 90000});
    await cmd({action: 'stage', index: 1}); await cmd({action: 'start', manual_clock: true});
    for (const viewport of layouts) {
      await page.setViewportSize(viewport);
      await page.waitForFunction(v => window.frontierState.viewport[0] === v.width && window.frontierState.viewport[1] === v.height, viewport);
      await cmd({action: 'patrol_setup'});
      const s = await state(), own = s.entities.filter(e => e.team === 0), worker = own.find(e => e.type === 'worker'), medic = own.find(e => e.type === 'medic'), enemy = s.entities.find(e => e.type === 'worker' && e.team === 1);
      for (const type of ['ranger', 'tank']) {
        const unit = own.find(e => e.type === type);
        await cmd({action: 'select', ids: [unit.id]});
        if (mobile) await click('Patrol'); else { await page.keyboard.press('p'); await page.waitForTimeout(200); }
        assert.equal((await state()).mode, 'patrol');
        await world(medic.id); assert.deepEqual(await orders(unit.id), ['patrol']);
        // Stop is on a fresh action page after targeting closes.
        await click('Stop'); assert.deepEqual(await orders(unit.id), []);
      }
      await cmd({action: 'select', ids: [worker.id]});
      if (mobile) await click('Attack'); else { await page.keyboard.press('n'); await page.waitForTimeout(200); }
      assert.equal((await state()).mode, 'target_attack');
      await world(worker.id); assert.equal((await state()).mode, 'target_attack', 'friendly target keeps Attack pending');
      await world(enemy.id); assert.deepEqual(await orders(worker.id), ['attack']);
      if (mobile) await click('Move'); else { await page.keyboard.press('m'); await page.waitForTimeout(200); }
      await world(medic.id);
      assert.deepEqual(await orders(worker.id), ['move'], 'Harvester can withdraw');
      await click('Attack'); await click('Stop'); assert.equal((await state()).mode, '');
      await cmd({action: 'select', ids: own.filter(e => ['worker', 'ranger', 'tank', 'medic'].includes(e.type)).map(e => e.id)});
      const seen = new Set();
      for (let i = 0; i < 12; i++) {
        const current = await state();
        for (const b of current.action_buttons) {
          assert.ok(b.x >= 0 && b.y >= 0 && b.x + b.w <= current.viewport[0] + 1 && b.y + b.h <= current.viewport[1] + 1, `${b.text} fits mixed selection`);
          if (mobile) assert.ok(b.w >= 44 && b.h >= 40, `${b.text} touch size`);
          seen.add(b.text);
        }
        const next = current.buttons.find(b => b.text === 'More actions' && !b.disabled);
        if (!next) break; await rawClick(next);
      }
      assert.ok(seen.has('Attack') && seen.has('Patrol'), 'both commands remain accessible for mixed groups');
      await page.screenshot({path: `test-results/patrol-${viewport.width}x${viewport.height}.png`});
      console.log(`Godot Patrol, Harvester Attack, withdrawal and action pages passed: ${viewport.width}x${viewport.height}`);
    }
    assert.deepEqual(errors, []); await page.close();
  }
} finally { await browser.close(); }
