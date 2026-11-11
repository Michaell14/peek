// Exercises the website in docs/ in a real browser: the hold-to-blink demo,
// arranging tiles, and the smaller interactive pieces.
//
//   node Tests/Browser/site.test.mjs
//
// Needs Playwright (`npm install --no-save playwright`). BROWSER=webkit runs
// the engine Safari uses.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const playwright = createRequire(import.meta.url)('playwright');
const engine = playwright[process.env.BROWSER || 'chromium'];
const root = join(fileURLToPath(new URL('.', import.meta.url)), '..', '..', 'docs');

const types = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.png': 'image/png', '.jpg': 'image/jpeg', '.woff2': 'font/woff2' };
const server = createServer(async (request, response) => {
  const path = normalize(decodeURIComponent(new URL(request.url, 'http://x').pathname));
  try {
    const body = await readFile(join(root, path === '/' ? 'index.html' : path));
    response.writeHead(200, { 'content-type': types[extname(path)] || types['.html'] });
    response.end(body);
  } catch {
    response.writeHead(404).end();
  }
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}/`;

const browser = await engine.launch();
let passed = 0;

async function test(name, body, viewport = { width: 1280, height: 800 }, options = {}) {
  const context = await browser.newContext({ viewport, ...options });
  const page = await context.newPage();
  const errors = [];
  page.requests = [];
  page.on('request', (request) => page.requests.push(request.url()));
  page.on('pageerror', (error) => errors.push(String(error)));
  page.on('console', (message) => { if (message.type() === 'error') errors.push(message.text()); });
  try {
    await page.goto(origin);
    await body(page);
    assert.deepEqual(errors, [], 'the page logged errors');
    passed += 1;
    console.log(`ok   ${name}`);
  } catch (error) {
    console.log(`FAIL ${name}\n${error.stack}`);
    process.exitCode = 1;
  } finally {
    await context.close();
  }
}

const state = (page) => page.evaluate(() => window.__blink.peek.state);
const isOpen = (page) => page.evaluate(() => document.getElementById('overlay').classList.contains('is-open'));
const order = (page) => page.evaluate(() => window.__blink.board.tiles.map((tile) => tile.kind));
const frames = (page) => page.evaluate(() => Object.fromEntries(window.__blink.board.tiles.map((tile) => [tile.kind, tile.frame])));

async function tap(page, key = 'Space') {
  await page.keyboard.down(key);
  await page.waitForTimeout(40);
  await page.keyboard.up(key);
  await page.waitForTimeout(350);
}

// Jump straight there: the page scrolls smoothly otherwise.
async function scrollTo(page, y) {
  await page.evaluate((top) => window.scrollTo({ top, behavior: 'instant' }), y);
  await page.waitForTimeout(150);
}

const storyUnit = (page) => page.evaluate(() => (document.getElementById('story').offsetHeight - window.innerHeight) / 5.6);
const pictureStep = (page) => page.evaluate(() => Number(document.getElementById('screen').dataset.step));
const opacity = (page, selector) => page.locator(selector).evaluate((el) => getComputedStyle(el).opacity);

async function centre(page, selector) {
  const box = await page.locator(selector).boundingBox();
  return [box.x + box.width / 2, box.y + box.height / 2];
}

await test('holding the key shows the overlay only while it is down', async (page) => {
  assert.equal(await isOpen(page), false);
  await page.keyboard.down('Space');
  await page.waitForTimeout(500);
  assert.equal(await isOpen(page), true);
  assert.equal(await state(page), 'holding');
  assert.equal(await page.evaluate(() => document.getElementById('overlay').classList.contains('is-pinned')), false);
  await page.keyboard.up('Space');
  await page.waitForTimeout(300);
  assert.equal(await isOpen(page), false);
  assert.equal(await state(page), 'hidden');
  assert.match(await page.textContent('#meter-readout'), /a hold/);
});

await test('holding does not scroll the page or repeat', async (page) => {
  await page.keyboard.down('Space');
  for (let i = 0; i < 5; i += 1) { await page.keyboard.down('Space'); } // auto-repeat
  await page.waitForTimeout(400);
  assert.equal(await page.evaluate(() => window.scrollY), 0);
  assert.equal(await state(page), 'holding');
  await page.keyboard.up('Space');
});

await test('a tap keeps it open; a second tap or esc closes it', async (page) => {
  await tap(page);
  assert.equal(await state(page), 'pinned');
  assert.match(await page.textContent('#meter-readout'), /a tap/);
  assert.equal(await page.evaluate(() => document.querySelector('main').inert), true, 'the page behind is out of reach');
  await tap(page);
  assert.equal(await state(page), 'hidden');
  assert.equal(await page.evaluate(() => document.querySelector('main').inert), false);

  await tap(page);
  await page.keyboard.press('Escape');
  await page.waitForTimeout(250);
  assert.equal(await state(page), 'hidden');
});

await test('the key in the hero works with a pointer: hold and tap', async (page) => {
  const [x, y] = await centre(page, '#hero-key');
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.waitForTimeout(500);
  assert.equal(await isOpen(page), true);
  await page.mouse.up();
  await page.waitForTimeout(300);
  assert.equal(await isOpen(page), false);

  await page.mouse.down();
  await page.waitForTimeout(40);
  await page.mouse.up();
  await page.waitForTimeout(350);
  assert.equal(await state(page), 'pinned');
});

await test('tiles are laid out in columns that fill the board without overlapping', async (page) => {
  await tap(page);
  const layout = await frames(page);
  const size = await page.evaluate(() => window.__blink.board.size());
  assert.deepEqual(Object.keys(layout), ['clock', 'reminders', 'web', 'calendar']);
  assert.equal(layout.clock.x, layout.reminders.x, 'short tiles stack in one column');
  assert.equal(layout.reminders.y + layout.reminders.h, size.height, 'the last tile in a column reaches the bottom');
  assert.equal(layout.web.h, size.height);
  const list = Object.values(layout);
  for (let i = 0; i < list.length; i += 1) {
    for (let j = i + 1; j < list.length; j += 1) {
      const a = list[i], b = list[j];
      const overlap = a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
      assert.equal(overlap, false, 'tiles overlap');
    }
  }
});

await test('escape leaves arranging before it closes the overlay', async (page) => {
  await tap(page);
  await page.click('#board-edit');
  assert.equal(await page.textContent('#board-edit'), 'Done');
  await page.keyboard.press('Escape');
  assert.equal(await page.textContent('#board-edit'), 'Edit');
  assert.equal(await state(page), 'pinned');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(250);
  assert.equal(await state(page), 'hidden');
});

await test('dragging a tile past the others reorders the board', async (page) => {
  await tap(page);
  await page.click('#board-edit');
  const before = await frames(page);
  const bounds = await page.locator('#board').boundingBox();
  const from = [bounds.x + before.clock.x + before.clock.w / 2, bounds.y + before.clock.y + before.clock.h / 2];
  const to = [bounds.x + before.calendar.x + before.calendar.w - 20, bounds.y + before.calendar.y + before.calendar.h / 2];
  await page.mouse.move(...from);
  await page.mouse.down();
  await page.mouse.move((from[0] + to[0]) / 2, (from[1] + to[1]) / 2, { steps: 6 });
  await page.mouse.move(...to, { steps: 6 });
  await page.mouse.up();
  await page.waitForTimeout(400);
  assert.deepEqual(await order(page), ['reminders', 'web', 'calendar', 'clock']);
});

await test('freeform starts from the flow arrangement and lets tiles go anywhere', async (page) => {
  await tap(page);
  const flow = await frames(page);
  await page.click('[data-board-mode="freeform"]');
  await page.waitForTimeout(400);
  assert.deepEqual(await frames(page), flow, 'switching mode moves nothing');

  await page.click('#board-edit');
  const bounds = await page.locator('#board').boundingBox();
  const start = [bounds.x + flow.clock.x + flow.clock.w / 2, bounds.y + flow.clock.y + flow.clock.h / 2];
  await page.mouse.move(...start);
  await page.mouse.down();
  await page.mouse.move(start[0] + 120, start[1] + 90, { steps: 8 });
  await page.mouse.up();
  const moved = (await frames(page)).clock;
  assert.equal(moved.x, flow.clock.x + 120);
  assert.equal(moved.y, flow.clock.y + 90);
  assert.equal(moved.w, flow.clock.w);
});

await test('tiles can be removed and added back from the palette', async (page) => {
  await tap(page);
  await page.click('#board-edit');
  await page.click('[aria-label="Remove Clock"]');
  await page.waitForTimeout(350);
  assert.deepEqual(await order(page), ['reminders', 'web', 'calendar']);

  await page.click('#board-add');
  const offered = await page.locator('#palette-list button').allTextContents();
  assert.equal(offered.length, 2, 'the palette offers what is not on the board');
  await page.keyboard.press('ArrowDown');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(350);
  assert.deepEqual(await order(page), ['reminders', 'web', 'calendar', 'notes']);
  assert.equal(await page.locator('#palette').isHidden(), true);
});

await test('widgets are alive: clocks tick, reminders tick off, new ones can be added', async (page) => {
  await tap(page);
  const time = await page.textContent('#board [data-zone-row="0"] .w-clock__time');
  assert.match(time, /^\d{1,2}:\d{2}/);
  assert.equal(await page.locator('#board .w-clock__glyph svg').count(), 3);

  assert.equal(await page.textContent('#board .w-rem__count'), '3');
  await page.click('#board .w-rem__item >> nth=0');
  assert.equal(await page.textContent('#board .w-rem__count'), '2');
  await page.fill('#board .w-rem__new input', 'Tell a friend');
  await page.keyboard.press('Enter');
  assert.equal(await page.textContent('#board .w-rem__count'), '3');
  assert.equal(await state(page), 'pinned', 'typing in a field does not trigger the shortcut');

  assert.ok(await page.locator('#board .w-cal__event').count() >= 3);
  assert.equal(await page.locator('#board .w-cal__now').count(), 1);
});

await test('typing a space in a field does not close the overlay', async (page) => {
  await tap(page);
  await page.click('#board .w-rem__new input');
  await page.keyboard.type('a b c');
  assert.equal(await page.inputValue('#board .w-rem__new input'), 'a b c');
  assert.equal(await state(page), 'pinned');
});

await test('less noise: switches remove the junk, clicking removes anything, reset restores', async (page) => {
  await page.locator('#q-page').scrollIntoViewIfNeeded();
  const height = () => page.evaluate(() => document.querySelector('.browser__body').getBoundingClientRect().height);
  const checked = () => page.locator('.switch').evaluateAll((els) => els.map((el) => el.getAttribute('aria-checked')));
  const original = await height();
  assert.match(await page.textContent('#q-count'), /as it arrives/);

  await page.click('#q-ads');
  await page.click('#q-cookies');
  await page.waitForTimeout(700);
  assert.deepEqual(await checked(), ['true', 'true', 'false']);
  assert.ok(await height() < original - 80, 'the page got shorter');
  assert.equal(await opacity(page, '.junk--bar'), '0');
  assert.match(await page.textContent('#q-count'), /4 things gone/);

  await page.click('#q-pick');
  assert.match(await page.textContent('#q-count'), /Click anything in the page/);
  await page.click('.junk--letter');
  await page.waitForTimeout(700);
  assert.equal(await page.locator('.junk--letter').evaluate((el) => el.classList.contains('is-hidden')), true);
  assert.equal(await opacity(page, '.page-figure'), '1', 'the number is untouched');
  assert.match(await page.textContent('#q-count'), /5 things gone/);

  // A switch turned off puts its things back; what was picked out by hand stays out.
  await page.click('#q-ads');
  await page.waitForTimeout(700);
  assert.equal(await opacity(page, '.junk--strip >> nth=0'), '1');
  assert.match(await page.textContent('#q-count'), /2 things gone/);

  await page.click('#q-reset');
  await page.waitForTimeout(700);
  assert.ok(Math.abs(await height() - original) < 2, 'everything is back');
  assert.deepEqual(await checked(), ['false', 'false', 'false']);
  assert.match(await page.textContent('#q-count'), /as it arrives/);
});

await test('the switches work from the keyboard, and stay put while the page under them changes', async (page) => {
  await page.locator('#q-page').scrollIntoViewIfNeeded();
  const top = () => page.locator('#q-ads').evaluate((el) => Math.round(el.getBoundingClientRect().top));
  const before = await top();
  await page.focus('#q-ads');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(700);
  assert.equal(await page.getAttribute('#q-ads', 'aria-checked'), 'true');
  assert.equal(await opacity(page, '.junk--strip >> nth=0'), '0');
  assert.equal(await top(), before, 'the switch moved from under the pointer');
  await page.keyboard.press('Enter');
  assert.equal(await page.getAttribute('#q-ads', 'aria-checked'), 'false');
  assert.equal(await state(page), 'hidden');
});

await test('the switches work with a finger', async (page) => {
  await page.locator('#q-page').scrollIntoViewIfNeeded();
  await page.tap('#q-cookies');
  await page.tap('#q-pick');
  await page.tap('.page-nav');
  await page.waitForTimeout(700);
  assert.equal(await opacity(page, '.junk--bar'), '0');
  assert.equal(await page.locator('.page-nav').evaluate((el) => el.classList.contains('is-hidden')), true);
  assert.match(await page.textContent('#q-count'), /2 things gone/);
}, { width: 390, height: 780 }, { hasTouch: true, isMobile: true });

await test('clicking the mock page does nothing unless click-to-hide is on', async (page) => {
  await page.locator('#quiet').scrollIntoViewIfNeeded();
  await page.click('.page-figure');
  assert.equal(await page.locator('.browser .is-hidden').count(), 0);
});

await test('space with another key held is some other shortcut', async (page) => {
  for (const modifier of ['Shift', 'Alt', 'Control', 'Meta']) {
    await page.keyboard.down(modifier);
    await page.keyboard.down('Space');
    await page.waitForTimeout(150);
    assert.equal(await isOpen(page), false, `${modifier} + Space opened it`);
    await page.keyboard.up('Space');
    await page.keyboard.up(modifier);
  }
  assert.equal(await state(page), 'hidden');
  assert.equal(await page.locator('#recorder').count(), 0);
});

await test('copy buttons, layout switch and questions respond', async (page) => {
  await page.locator('#layout-stage').scrollIntoViewIfNeeded();
  await page.click('[data-layout="freeform"]');
  assert.equal(await page.getAttribute('#layout-stage', 'data-mode'), 'freeform');

  await page.locator('#get').scrollIntoViewIfNeeded();
  await page.click('.copy >> nth=0');
  assert.equal(await page.textContent('.copy >> nth=0'), 'Copied');

  await page.locator('#faq').scrollIntoViewIfNeeded();
  await page.click('.faq summary >> nth=0');
  assert.equal(await page.locator('.faq details >> nth=0').getAttribute('open'), '');
});

await test('the story: scrolling steps through it, and the picture follows', async (page) => {
  const said = () => page.locator('.step.is-on').innerText();
  assert.equal(await pictureStep(page), 0);
  assert.match(await said(), /brings them to you/);

  const unit = await storyUnit(page);
  const lines = [/middle of something/, /quick look/, /find your way back/, /hold one key/, /never left/];
  for (let step = 1; step <= 5; step += 1) {
    await scrollTo(page, unit * (step - 0.1));
    assert.equal(await pictureStep(page), step);
    assert.equal(await page.locator('.step.is-on').count(), 1);
    assert.match(await said(), lines[step - 1]);
  }

  // The windows pile up, then one key clears them.
  await scrollTo(page, unit * 2.9);
  await page.waitForTimeout(900);
  assert.equal(await opacity(page, '.win--mail'), '1');
  assert.equal(await opacity(page, '.scr-overlay'), '0');
  await scrollTo(page, unit * 3.9);
  await page.waitForTimeout(1000);
  assert.equal(await opacity(page, '.win--mail'), '0');
  assert.equal(await opacity(page, '.scr-overlay'), '1');
  assert.equal(await page.locator('#hero-key').evaluate((el) => el.classList.contains('is-ghost')), true, 'the key goes down with it');
  await scrollTo(page, unit * 4.9);
  await page.waitForTimeout(500);
  assert.equal(await opacity(page, '.scr-overlay'), '0');
  assert.equal(await page.locator('#hero-key').evaluate((el) => el.classList.contains('is-ghost')), false);

  // And back up again.
  await scrollTo(page, 0);
  assert.equal(await pictureStep(page), 0);
  assert.match(await said(), /brings them to you/);
});

await test('the picture fits its place, and its tiles fill it without overlapping', async (page) => {
  const box = await page.locator('#display-wrap').boundingBox();
  const display = await page.locator('.display').boundingBox();
  assert.ok(Math.abs(display.width - box.width) < 2 && Math.abs(display.height - box.height) < 2, 'the picture is not scaled to its place');
  assert.ok(box.x + box.width <= 1280 && box.y + box.height <= 800, 'the picture runs off the screen');

  const tiles = await page.locator('#screen-board .tile').evaluateAll((els) => els.map((el) => ({ x: el.offsetLeft, y: el.offsetTop, w: el.offsetWidth, h: el.offsetHeight })));
  assert.equal(tiles.length, 4);
  for (let i = 0; i < tiles.length; i += 1) {
    for (let j = i + 1; j < tiles.length; j += 1) {
      const a = tiles[i], b = tiles[j];
      assert.equal(a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h, false, 'tiles overlap');
    }
  }
  assert.ok(Math.max(...tiles.map((t) => t.x + t.w)) > 1180, 'the tiles leave the canvas half empty');
  assert.equal(await page.locator('.display').evaluate((el) => el.inert), true, 'the picture is not something to tab into');
});

await test('the cover shows itself off until someone tries it', async (page) => {
  const attract = () => page.evaluate(() => document.getElementById('screen').dataset.attract);
  const ghost = () => page.locator('#hero-key').evaluate((el) => el.classList.contains('is-ghost'));
  assert.equal(await attract(), 'on');
  assert.equal(await ghost(), true);
  await page.waitForFunction(() => document.getElementById('screen').dataset.attract === 'off', null, { timeout: 6000 });
  assert.equal(await ghost(), false);
  await page.waitForFunction(() => document.getElementById('screen').dataset.attract === 'on', null, { timeout: 4000 });

  await tap(page);
  await tap(page);
  assert.equal(await state(page), 'hidden');
  assert.equal(await ghost(), false);
  await page.waitForTimeout(4200);
  assert.equal(await attract(), 'on', 'it stops once the real thing has been used');
  assert.equal(await ghost(), false);
});

await test('with reduced motion the cover stays still', async (page) => {
  await page.waitForTimeout(4200);
  assert.equal(await page.evaluate(() => document.getElementById('screen').dataset.attract), 'on');
  assert.equal(await page.locator('#hero-key').evaluate((el) => el.classList.contains('is-ghost')), false);
  await tap(page);
  assert.equal(await state(page), 'pinned');
}, { width: 1280, height: 800 }, { reducedMotion: 'reduce' });

await test('past the story: the bar names the section, and the second key works', async (page) => {
  assert.equal(await page.locator('#top-bar').evaluate((el) => el.classList.contains('is-past')), false);
  await page.locator('#try-key').scrollIntoViewIfNeeded();
  await scrollTo(page, await page.evaluate(() => document.getElementById('how').offsetTop));
  assert.equal(await page.locator('#top-bar').evaluate((el) => el.classList.contains('is-past')), true);
  assert.equal(await page.textContent('#running'), '02 — Two gestures');
  assert.equal(await page.locator('#hint').evaluate((el) => el.classList.contains('is-on')), true);

  const [x, y] = await centre(page, '#try-key');
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.waitForTimeout(500);
  assert.equal(await isOpen(page), true);
  assert.equal(await page.locator('#hero-key').evaluate((el) => el.classList.contains('is-down')), true, 'both keys go down together');
  await page.mouse.up();
  await page.waitForTimeout(300);
  assert.equal(await isOpen(page), false);
  assert.match(await page.textContent('#meter-readout'), /a hold/);

  await scrollTo(page, await page.evaluate(() => document.getElementById('faq').offsetTop));
  assert.equal(await page.textContent('#running'), '08 — Questions');
});

await test('the page loads nothing from anywhere else, and its typefaces arrive', async (page) => {
  await page.evaluate(() => document.fonts.ready);
  for (const url of page.requests) {
    assert.ok(url.startsWith(origin) || url.startsWith('data:'), `the page asked for ${url}`);
  }
  assert.equal(await page.evaluate(() => document.fonts.check('40px Fraunces') && document.fonts.check('16px Archivo')), true);
  assert.equal(await page.getAttribute('h1', 'aria-label'), 'Blink');
  const picture = await page.evaluate(() => new Promise((resolve) => {
    const image = new Image();
    image.onload = () => resolve(image.naturalWidth);
    image.onerror = () => resolve(0);
    image.src = 'desk.jpg';
  }));
  assert.ok(picture > 1000, 'the desktop picture is missing');
});

await test('every link on the page goes somewhere real', async (page) => {
  const links = await page.locator('a[href]').evaluateAll((anchors) => anchors.map((a) => a.getAttribute('href')));
  for (const href of links) {
    if (href.startsWith('#')) {
      assert.equal(await page.locator(href).count(), 1, `no element for ${href}`);
    } else {
      assert.match(href, /^https:\/\/github\.com\/Michaell14\/peek/, `unexpected link ${href}`);
    }
  }
});

await test('on a phone: no sideways scrolling, and the overlay becomes a list', async (page) => {
  const widths = await page.evaluate(() => [document.documentElement.scrollWidth, window.innerWidth]);
  assert.equal(widths[0], widths[1], 'the page is wider than the screen');

  // No keyboard on a phone: press and hold the key on the page.
  const [x, y] = await centre(page, '#hero-key');
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.waitForTimeout(40);
  await page.mouse.up();
  await page.waitForTimeout(350);
  assert.equal(await state(page), 'pinned');
  assert.equal(await page.locator('#board').evaluate((el) => el.classList.contains('is-stacked')), true);
  const tiles = await page.locator('#board .tile').evaluateAll((els) => els.map((el) => el.getBoundingClientRect()).map((r) => [r.left, r.right, r.width]));
  for (const [left, right, width] of tiles) {
    assert.ok(left >= 0 && right <= 390 && width > 300, 'a tile does not fit the screen');
  }
}, { width: 390, height: 780 });

await browser.close();
server.close();
console.log(`\n${passed} passed${process.exitCode ? ', some FAILED' : ''}`);
