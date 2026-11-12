// Exercises the website in docs/ in a real browser: the walkthrough that
// scrolling plays on the pinned screen, the hold-to-blink demo, and the rest
// of the page.
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

const types = {
  '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.woff2': 'font/woff2',
};
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
    await page.evaluate(() => document.fonts.ready);
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

const blink = (page, key) => page.evaluate((name) => window.__blink[name], key);
const state = (page) => page.evaluate(() => window.__blink.peek.state);
const pageOverlayOpen = (page) => page.evaluate(() => document.getElementById('pov').classList.contains('is-open'));

async function tap(page, key = 'Space') {
  await page.keyboard.down(key);
  await page.waitForTimeout(40);
  await page.keyboard.up(key);
  await page.waitForTimeout(350);
}

// Jump straight to a point in the walkthrough (T runs from 0 to 10).
async function goToBeat(page, T) {
  const y = await page.evaluate((target) => window.__blink.scrollForT(target), T);
  await page.evaluate((top) => window.scrollTo({ top, behavior: 'instant' }), y);
  // Draw from the new position now rather than wait for the scroll event,
  // which a slow machine can deliver late.
  await page.evaluate(() => window.__blink.render());
  await page.waitForTimeout(250);
}

async function centre(page, selector) {
  const box = await page.locator(selector).boundingBox();
  return [box.x + box.width / 2, box.y + box.height / 2];
}

// The caption that is showing, by its beat number.
const shownCaption = (page) => page.evaluate(() => {
  const caps = [...document.querySelectorAll('#caps .cap')];
  const shown = caps.filter((cap) => Number(getComputedStyle(cap).opacity) > 0.9);
  return shown.map((cap) => Number(cap.dataset.beat));
});

await test('scrolling plays the walkthrough on the pinned screen', async (page) => {
  assert.equal(await blink(page, 'mode'), 'take');
  const before = await page.locator('#display').boundingBox();
  for (const beat of [1, 3, 5, 9]) {
    await goToBeat(page, beat - 0.5);
    const T = await blink(page, 'T');
    assert.ok(Math.abs(T - (beat - 0.5)) < 0.05, `expected T near ${beat - 0.5}, got ${T}`);
    assert.deepEqual(await shownCaption(page), [beat]);
  }
  // The screen stays where it is while the story plays.
  await goToBeat(page, 1.5);
  const a = await page.locator('#display').boundingBox();
  await goToBeat(page, 2.5);
  const b = await page.locator('#display').boundingBox();
  assert.equal(Math.round(a.y), Math.round(b.y), 'the screen moved while pinned');
  assert.ok(before.y > a.y, 'the screen should rise into place from the opening');

  // Holding fn in the story brings Blink up over the writer.
  await goToBeat(page, 2.6);
  const shown = await page.locator('[data-ov]').evaluate((el) => Number(getComputedStyle(el).opacity));
  assert.ok(shown > 0.9, 'Blink is not showing during the hold beat');
});

await test('the step list jumps to a beat', async (page) => {
  await goToBeat(page, 1.5);
  await page.click('#index a[data-go="7"]');
  await page.waitForFunction(() => Math.abs(window.__blink.T - 6.5) < 0.1, null, { timeout: 4000 });
  await page.waitForTimeout(200);
  assert.deepEqual(await shownCaption(page), [7]);
});

await test('holding Space over the screen opens Blink on it, only while held', async (page) => {
  await goToBeat(page, 0.4);
  await page.keyboard.down('Space');
  await page.waitForTimeout(400);
  assert.equal(await state(page), 'holding');
  assert.equal(await page.evaluate(() => window.__blink.peek.where), 'stage');
  assert.equal(await blink(page, 'user'), 1);
  assert.equal(await pageOverlayOpen(page), false, 'it opened over the page instead');
  await page.keyboard.up('Space');
  await page.waitForTimeout(400);
  assert.equal(await state(page), 'hidden');
  assert.equal(await blink(page, 'user'), 0);
});

await test('holding does not scroll the page or repeat', async (page) => {
  await goToBeat(page, 0.4);
  const before = await page.evaluate(() => window.scrollY);
  await page.keyboard.down('Space');
  for (let i = 0; i < 5; i += 1) { await page.keyboard.down('Space'); } // auto-repeat
  await page.waitForTimeout(400);
  assert.equal(await page.evaluate(() => window.scrollY), before);
  assert.equal(await state(page), 'holding');
  await page.keyboard.up('Space');
});

await test('a tap keeps it open; a second tap or esc closes it; reminders can be ticked', async (page) => {
  await goToBeat(page, 0.4);
  await tap(page);
  assert.equal(await state(page), 'pinned');
  const reminder = page.locator('#display [data-rem="plants"]');
  await reminder.click();
  assert.equal(await reminder.evaluate((el) => el.classList.contains('is-done')), true);
  await tap(page);
  assert.equal(await state(page), 'hidden');

  await tap(page);
  await page.keyboard.press('Escape');
  await page.waitForTimeout(300);
  assert.equal(await state(page), 'hidden');
});

await test('below the walkthrough, Space opens Blink over the page itself', async (page) => {
  await page.locator('#faq').scrollIntoViewIfNeeded();
  await page.waitForTimeout(200);
  await page.keyboard.down('Space');
  await page.waitForTimeout(300);
  assert.equal(await pageOverlayOpen(page), true);
  await page.keyboard.up('Space');
  await page.waitForTimeout(300);
  assert.equal(await pageOverlayOpen(page), false);

  await tap(page);
  assert.equal(await state(page), 'pinned');
  assert.equal(await page.evaluate(() => document.querySelector('main').inert), true, 'the page behind is out of reach');
  const item = page.locator('#pov-board .w-rem__item >> nth=0');
  await item.click();
  assert.equal(await item.evaluate((el) => el.classList.contains('is-done')), true);
  await page.keyboard.press('Escape');
  await page.waitForTimeout(300);
  assert.equal(await state(page), 'hidden');
  assert.equal(await page.evaluate(() => document.querySelector('main').inert), false);
});

await test('the fn key on the page works with a pointer: hold and tap', async (page) => {
  await goToBeat(page, 0.4);
  const [x, y] = await centre(page, '.foot .fnkey');
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.waitForTimeout(450);
  assert.equal(await state(page), 'holding');
  await page.mouse.up();
  await page.waitForTimeout(350);
  assert.equal(await state(page), 'hidden');

  await page.mouse.down();
  await page.waitForTimeout(40);
  await page.mouse.up();
  await page.waitForTimeout(350);
  assert.equal(await state(page), 'pinned');
});

await test('space with another key held is some other shortcut', async (page) => {
  await goToBeat(page, 0.4);
  for (const modifier of ['Shift', 'Alt', 'Control', 'Meta']) {
    await page.keyboard.down(modifier);
    await page.keyboard.down('Space');
    await page.waitForTimeout(150);
    assert.equal(await state(page), 'hidden', `${modifier} + Space opened it`);
    await page.keyboard.up('Space');
    await page.keyboard.up(modifier);
  }
});

await test('the questions respond, and say what the app does by default', async (page) => {
  await page.locator('#faq').scrollIntoViewIfNeeded();
  await page.click('.faq summary >> nth=0');
  assert.equal(await page.locator('.faq details >> nth=0').getAttribute('open'), '');
  const answers = await page.locator('.faq').textContent(); // closed answers included
  assert.match(answers, /fn/);
  assert.match(answers, /Input Monitoring/);
  assert.match(answers, /Open Anyway/);
});

await test('the page loads nothing from anywhere else, and its typefaces and wallpaper arrive', async (page) => {
  for (const url of page.requests) {
    assert.ok(url.startsWith(origin) || url.startsWith('data:'), `the page asked for ${url}`);
  }
  assert.equal(await page.evaluate(() => document.fonts.check('40px Fraunces') && document.fonts.check('16px "Schibsted Grotesk"')), true);
  const wallpaper = await page.evaluate(() => new Promise((resolve) => {
    const image = new Image();
    image.onload = () => resolve(image.naturalWidth);
    image.onerror = () => resolve(0);
    image.src = 'wall.svg';
  }));
  assert.ok(wallpaper > 0, 'the wallpaper is missing');
});

await test('the download links ask for the file the release workflow publishes', async (page) => {
  const links = await page.locator('a', { hasText: /Download/ }).evaluateAll((anchors) => anchors.map((a) => a.href));
  assert.equal(links.length, 3, 'top bar, opening and closing');
  for (const href of links) {
    assert.equal(href, 'https://github.com/Michaell14/peek/releases/latest/download/Blink.dmg');
  }
  const workflow = await readFile(join(root, '..', '.github', 'workflows', 'release.yml'), 'utf8');
  const packaging = await readFile(join(root, '..', 'Scripts', 'package.sh'), 'utf8');
  assert.match(packaging, /Blink\.dmg/, 'the packaging script no longer makes Blink.dmg');
  assert.match(workflow, /Scripts\/package\.sh/, 'the release workflow no longer packages the app');
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

await test('with reduced motion the walkthrough is a list of stills', async (page) => {
  assert.equal(await blink(page, 'mode'), 'stack');
  assert.equal(await page.locator('#stack').isVisible(), true);
  assert.equal(await page.locator('#stack .still').count(), 10);
  const caption = await page.locator('#stack .still__cap >> nth=2').textContent();
  assert.match(caption, /Hold fn/);
}, { width: 1280, height: 800 }, { reducedMotion: 'reduce' });

await test('on a phone: stills, no sideways scrolling, and the key opens Blink as a list', async (page) => {
  assert.equal(await blink(page, 'mode'), 'stack');
  const widths = await page.evaluate(() => [document.documentElement.scrollWidth, window.innerWidth]);
  assert.equal(widths[0], widths[1], 'the page is wider than the screen');
  assert.equal(await page.locator('#stack .still').count(), 10);

  // No keyboard on a phone: the floating key appears by the stills.
  await page.locator('#stack .still >> nth=3').scrollIntoViewIfNeeded();
  await page.waitForTimeout(300);
  await page.locator('#float-key').tap();
  await page.waitForTimeout(350);
  assert.equal(await state(page), 'pinned');
  assert.equal(await page.locator('#pov-board').evaluate((el) => el.classList.contains('is-list')), true);
  const tiles = await page.locator('#pov-board .tile').evaluateAll((els) => els.map((el) => el.getBoundingClientRect()).map((r) => [r.left, r.right]));
  for (const [left, right] of tiles) {
    assert.ok(left >= 0 && right <= 390, 'a tile does not fit the screen');
  }
}, { width: 390, height: 780 }, { hasTouch: true, isMobile: true });

await browser.close();
server.close();
console.log(`\n${passed} passed${process.exitCode ? ', some FAILED' : ''}`);
