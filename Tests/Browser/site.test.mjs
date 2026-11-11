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

const types = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.png': 'image/png' };
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

async function test(name, body, viewport = { width: 1280, height: 800 }) {
  const context = await browser.newContext({ viewport });
  const page = await context.newPage();
  const errors = [];
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
  const time = await page.textContent('[data-zone-row="0"] .w-clock__time');
  assert.match(time, /^\d{1,2}:\d{2}/);
  assert.equal(await page.locator('.w-clock__glyph svg').count(), 3);

  assert.equal(await page.textContent('.w-rem__count'), '3');
  await page.click('.w-rem__item >> nth=0');
  assert.equal(await page.textContent('.w-rem__count'), '2');
  await page.fill('.w-rem__new input', 'Tell a friend');
  await page.keyboard.press('Enter');
  assert.equal(await page.textContent('.w-rem__count'), '3');
  assert.equal(await state(page), 'pinned', 'typing in a field does not trigger the shortcut');

  assert.ok(await page.locator('.w-cal__event').count() >= 3);
  assert.equal(await page.locator('.w-cal__now').count(), 1);
});

await test('typing a space in a field does not close the overlay', async (page) => {
  await tap(page);
  await page.click('.w-rem__new input');
  await page.keyboard.type('a b c');
  assert.equal(await page.inputValue('.w-rem__new input'), 'a b c');
  assert.equal(await state(page), 'pinned');
});

await test('less noise: switches remove the junk, clicking removes anything, reset restores', async (page) => {
  await page.locator('#quiet').scrollIntoViewIfNeeded();
  const height = () => page.evaluate(() => document.querySelector('.browser__body').getBoundingClientRect().height);
  const original = await height();

  await page.click('label:has(#q-ads)');
  await page.click('label:has(#q-cookies)');
  await page.waitForTimeout(700);
  assert.ok(await height() < original - 80, 'the page got shorter');
  assert.equal(await page.locator('.junk--cookie').evaluate((el) => getComputedStyle(el).opacity), '0');
  assert.match(await page.textContent('#q-count'), /4 things gone/);

  await page.click('label:has(#q-pick)');
  await page.click('.junk--newsletter');
  await page.waitForTimeout(700);
  assert.equal(await page.locator('.junk--newsletter').evaluate((el) => el.classList.contains('is-hidden')), true);
  assert.equal(await page.locator('.page-figure').evaluate((el) => getComputedStyle(el).opacity), '1', 'the number is untouched');
  assert.match(await page.textContent('#q-count'), /5 things gone/);

  await page.click('#q-reset');
  await page.waitForTimeout(700);
  assert.ok(Math.abs(await height() - original) < 2, 'everything is back');
  assert.equal(await page.textContent('#q-count'), '');
});

await test('clicking the mock page does nothing unless click-to-hide is on', async (page) => {
  await page.locator('#quiet').scrollIntoViewIfNeeded();
  await page.click('.page-figure');
  assert.equal(await page.locator('.browser .is-hidden').count(), 0);
});

await test('recording a combination changes what the page listens for', async (page) => {
  await page.locator('#shortcut').scrollIntoViewIfNeeded();
  await page.click('#recorder');
  await page.keyboard.down('Alt');
  await page.keyboard.down('Backquote');
  await page.keyboard.up('Backquote');
  await page.keyboard.up('Alt');
  const shortcut = await page.evaluate(() => window.__blink.getShortcut());
  assert.equal(shortcut.code, 'Backquote');
  assert.equal(shortcut.alt, true);
  assert.equal(await state(page), 'hidden', 'recording does not trigger the overlay');
  assert.equal(await page.locator('#recorder-keys kbd').count(), 2);

  await tap(page, 'Space');
  assert.equal(await state(page), 'hidden', 'the old shortcut no longer works');
  await page.keyboard.down('Alt');
  await tap(page, 'Backquote');
  await page.keyboard.up('Alt');
  assert.equal(await state(page), 'pinned', 'the new one does');
  assert.match(await page.textContent('#overlay-hint'), /`/);
});

await test('a single modifier works as a shortcut, and another key cancels it', async (page) => {
  await page.locator('#shortcut').scrollIntoViewIfNeeded();
  await page.click('[data-preset="AltRight"]');
  assert.deepEqual(await page.evaluate(() => window.__blink.getShortcut()), { modifier: 'AltRight' });

  await page.keyboard.down('AltRight');
  await page.waitForTimeout(450);
  assert.equal(await state(page), 'holding');
  await page.keyboard.up('AltRight');
  await page.waitForTimeout(250);
  assert.equal(await state(page), 'hidden');

  await page.keyboard.down('AltLeft');
  await page.waitForTimeout(200);
  assert.equal(await state(page), 'hidden', 'the left key is a different key');
  await page.keyboard.up('AltLeft');

  // Right ⌥ then a letter is some other shortcut, not a blink.
  await page.keyboard.down('AltRight');
  await page.keyboard.down('KeyC');
  await page.waitForTimeout(200);
  assert.equal(await isOpen(page), false);
  await page.keyboard.up('KeyC');
  await page.keyboard.up('AltRight');
  assert.equal(await state(page), 'hidden');
});

await test('recording a lone modifier, and cancelling with esc', async (page) => {
  await page.locator('#shortcut').scrollIntoViewIfNeeded();
  await page.click('#recorder');
  await page.keyboard.press('Escape');
  assert.deepEqual(await page.evaluate(() => window.__blink.getShortcut().code), 'Space', 'esc keeps the old shortcut');

  await page.click('#recorder');
  await page.keyboard.down('MetaRight');
  await page.keyboard.up('MetaRight');
  assert.deepEqual(await page.evaluate(() => window.__blink.getShortcut()), { modifier: 'MetaRight' });
});

await test('copy buttons, layout switch and questions respond', async (page) => {
  await page.locator('#inside').scrollIntoViewIfNeeded();
  await page.click('[data-layout="freeform"]');
  assert.equal(await page.getAttribute('#layout-stage', 'data-mode'), 'freeform');

  await page.locator('#get').scrollIntoViewIfNeeded();
  await page.click('.copy >> nth=0');
  assert.equal(await page.textContent('.copy >> nth=0'), 'Copied');

  await page.locator('#faq').scrollIntoViewIfNeeded();
  await page.click('.faq summary >> nth=0');
  assert.equal(await page.locator('.faq details >> nth=0').getAttribute('open'), '');
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
  const tiles = await page.locator('.tile').evaluateAll((els) => els.map((el) => el.getBoundingClientRect()).map((r) => [r.left, r.right, r.width]));
  for (const [left, right, width] of tiles) {
    assert.ok(left >= 0 && right <= 390 && width > 300, 'a tile does not fit the screen');
  }
}, { width: 390, height: 780 });

await browser.close();
server.close();
console.log(`\n${passed} passed${process.exitCode ? ', some FAILED' : ''}`);
