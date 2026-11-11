// Runs the scripts Gander injects into web pages in a real browser.
//
//   swift run gander-scripts > /tmp/gander-scripts.json
//   node Tests/Browser/picker.test.mjs /tmp/gander-scripts.json
//
// Needs Playwright with a Chromium build (`npm i playwright`).
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';

// `require` also finds a globally installed Playwright (via NODE_PATH).
const { chromium } = createRequire(import.meta.url)('playwright');

const scripts = JSON.parse(readFileSync(process.argv[2], 'utf8'));

const PAGE = `<!doctype html>
<html><head><style>
  body { margin: 0; font: 14px sans-serif; }
  #sidebar { position: absolute; left: 0; top: 0; width: 200px; height: 300px; background: #ddd; }
  main { margin-left: 220px; }
  .card { height: 60px; margin: 10px 0; background: #cdf; }
  .promo p { height: 30px; margin: 4px 0; background: #fdc; }
  #css-1a2b3c4d { height: 40px; background: #dfd; }
  .tall { height: 2000px; }
</style></head>
<body>
  <div id="sidebar"><a id="nav-link" href="https://example.com/elsewhere">link</a></div>
  <main>
    <div class="card">one</div>
    <div class="card">two</div>
    <div class="card featured">three</div>
    <div class="promo"><p>a</p><p id="second">b</p><p>c</p></div>
    <section><div id="css-1a2b3c4d" class="sc-8f3a91bc x12345"><span id="deep">generated</span></div></section>
    <ul><li>1</li><li><button id="btn" onclick="window.clicked = true">press</button></li></ul>
    <div class="tall"></div>
  </main>
</body></html>`;

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 900, height: 600 } });
await context.route('**/*', (route) => route.fulfill({ contentType: 'text/html', body: PAGE }));

let passed = 0;
async function test(name, body) {
  const page = await context.newPage();
  try {
    await body(page);
    passed += 1;
    console.log(`ok   ${name}`);
  } catch (error) {
    console.log(`FAIL ${name}\n${error.stack}`);
    process.exitCode = 1;
  } finally {
    await page.close();
  }
}

const log = (page) => page.evaluate(() => window.__ganderPickerLog || []);
const displayOf = (page, selector) => page.evaluate((s) => getComputedStyle(document.querySelector(s)).display, selector);

async function centre(page, selector) {
  const box = await page.locator(selector).boundingBox();
  return [box.x + box.width / 2, box.y + box.height / 2];
}

/** Hover an element, click it, and return the message the picker posted. */
async function pick(page, selector) {
  const before = (await log(page)).length;
  const [x, y] = await centre(page, selector);
  await page.mouse.move(x, y);
  await page.mouse.click(x, y);
  const messages = await log(page);
  assert.equal(messages.length, before + 1, 'exactly one message per click');
  return messages.at(-1);
}

/** The picked selector must match the clicked element and nothing else. */
async function assertIdentifies(page, message, expectedSelector) {
  const result = await page.evaluate(
    ([picked, expected]) => {
      const matches = document.querySelectorAll(picked);
      return { count: matches.length, same: matches[0] === document.querySelector(expected) };
    },
    [message.selector, expectedSelector],
  );
  assert.deepEqual(result, { count: 1, same: true }, `selector "${message.selector}"`);
}

await test('click hides the element and reports a unique selector', async (page) => {
  await page.goto('https://example.com/');
  await page.evaluate(scripts.picker);
  const message = await pick(page, '#sidebar');
  assert.equal(message.type, 'hide');
  assert.equal(message.host, 'example.com');
  assert.equal(message.selector, 'div#sidebar');
  assert.equal(await displayOf(page, '#sidebar'), 'none');
});

await test('siblings with the same classes are told apart', async (page) => {
  await page.goto('https://example.com/');
  await page.evaluate(scripts.picker);
  const message = await pick(page, '.card:nth-of-type(2)');
  await assertIdentifies(page, message, '.card:nth-of-type(2)');
  assert.equal(await displayOf(page, '.card:nth-of-type(1)'), 'block');
  assert.equal(await displayOf(page, '.card:nth-of-type(3)'), 'block');
});

await test('a distinguishing class is enough on its own', async (page) => {
  await page.goto('https://example.com/');
  await page.evaluate(scripts.picker);
  const message = await pick(page, '.featured');
  await assertIdentifies(page, message, '.featured');
  assert.match(message.selector, /featured/);
});

await test('machine-generated ids and classes are not relied on', async (page) => {
  await page.goto('https://example.com/');
  await page.evaluate(scripts.picker);
  await page.evaluate(() => { document.getElementById('deep').removeAttribute('id'); });
  const message = await pick(page, '#css-1a2b3c4d > span');
  assert.doesNotMatch(message.selector, /1a2b3c4d|8f3a91bc|x12345/);
  await assertIdentifies(page, message, '#css-1a2b3c4d > span');
});

await test('clicks do not reach the page while picking', async (page) => {
  await page.goto('https://example.com/');
  await page.evaluate(scripts.picker);
  await pick(page, '#btn');
  assert.equal(await page.evaluate(() => window.clicked), undefined);
  await pick(page, '.card:nth-of-type(1)');
  assert.equal(page.url(), 'https://example.com/');
});

await test('links are not followed while picking', async (page) => {
  await page.goto('https://example.com/');
  await page.evaluate(scripts.picker);
  const message = await pick(page, '#nav-link');
  assert.equal(page.url(), 'https://example.com/');
  await assertIdentifies(page, message, '#nav-link');
});

await test('arrow keys widen and narrow the selection', async (page) => {
  await page.goto('https://example.com/');
  await page.evaluate(scripts.picker);
  const [x, y] = await centre(page, '#second');
  await page.mouse.move(x, y);
  await page.keyboard.press('ArrowUp');
  await page.mouse.click(x, y);
  let messages = await log(page);
  await assertIdentifies(page, messages.at(-1), '.promo');
  assert.equal(await displayOf(page, '.promo'), 'none');

  // Up then down returns to the element under the pointer.
  const [bx, by] = await centre(page, '#btn');
  await page.mouse.move(bx, by);
  await page.keyboard.press('ArrowUp');
  await page.keyboard.press('ArrowUp');
  await page.keyboard.press('ArrowDown');
  await page.keyboard.press('ArrowDown');
  await page.mouse.click(bx, by);
  messages = await log(page);
  await assertIdentifies(page, messages.at(-1), '#btn');
});

await test('the page itself can never be hidden', async (page) => {
  await page.goto('https://example.com/');
  await page.evaluate(scripts.picker);
  const [x, y] = await centre(page, '#second');
  await page.mouse.move(x, y);
  for (let i = 0; i < 20; i += 1) { await page.keyboard.press('ArrowUp'); }
  await page.mouse.click(x, y);
  assert.equal(await displayOf(page, 'body'), 'block');
  assert.equal(await displayOf(page, 'html'), 'block');
  const messages = await log(page);
  assert.notEqual(messages.at(-1).selector, 'body');
});

await test('escape ends picking and restores normal clicks', async (page) => {
  await page.goto('https://example.com/');
  await page.evaluate(scripts.picker);
  await page.mouse.move(400, 30);
  await page.keyboard.press('Escape');
  assert.deepEqual(await log(page), [{ type: 'done' }]);
  assert.equal(await page.evaluate(() => window.__ganderPicker), undefined);
  await page.click('#btn');
  assert.equal(await page.evaluate(() => window.clicked), true);
  assert.equal(await displayOf(page, '#btn'), 'inline-block');
});

await test('stopping from outside removes the outline', async (page) => {
  await page.goto('https://example.com/');
  const before = await page.evaluate(() => document.documentElement.children.length);
  await page.evaluate(scripts.picker);
  await page.evaluate(scripts.picker); // starting twice must not stack up
  assert.equal(await page.evaluate(() => document.documentElement.children.length), before + 1);
  await page.evaluate(scripts.stopPicker);
  await page.evaluate(scripts.stopPicker); // stopping twice is harmless
  assert.equal(await page.evaluate(() => document.documentElement.children.length), before);
  await page.click('#btn');
  assert.equal(await page.evaluate(() => window.clicked), true);
});

await test('the outline follows the element when the page scrolls', async (page) => {
  await page.goto('https://example.com/');
  await page.evaluate(scripts.picker);
  const [x, y] = await centre(page, '.featured');
  await page.mouse.move(x, y);
  await page.evaluate(() => window.scrollBy(0, 40));
  await page.waitForFunction(() => {
    const outline = document.documentElement.lastElementChild.getBoundingClientRect();
    const target = document.querySelector('.featured').getBoundingClientRect();
    return Math.abs(outline.top - target.top) < 1 && Math.abs(outline.height - target.height) < 1;
  });
});

await test('saved elements are hidden on the matching site only', async (page) => {
  await page.goto('https://example.com/');
  await page.evaluate(scripts.hide);
  assert.equal(await displayOf(page, '#sidebar'), 'none');
  assert.equal(await displayOf(page, '#second'), 'none', 'rules saved for www. apply to the bare host');
  assert.equal(await displayOf(page, 'main'), 'block', 'another site\'s rule must not apply');
  assert.equal(await displayOf(page, '.promo p:nth-of-type(1)'), 'block');

  await page.goto('https://sub.other.org/');
  await page.evaluate(scripts.hide);
  assert.equal(await displayOf(page, 'main'), 'none', 'rules apply to subdomains');
  assert.equal(await displayOf(page, '#sidebar'), 'block');

  await page.goto('https://notexample.com/');
  await page.evaluate(scripts.hide);
  assert.equal(await displayOf(page, '#sidebar'), 'block', 'suffix match must respect the dot');
});

await test('re-running the hide script replaces rather than piles up', async (page) => {
  await page.goto('https://example.com/');
  await page.evaluate(scripts.hide);
  await page.evaluate(scripts.hide);
  assert.equal(await page.evaluate(() => document.querySelectorAll('#gander-hidden-elements').length), 1);
  await page.evaluate(scripts.hideNothing);
  assert.equal(await page.evaluate(() => document.querySelectorAll('#gander-hidden-elements').length), 0);
  assert.equal(await displayOf(page, '#sidebar'), 'block', 'clearing the rules brings elements back');
});

await test('scroll lock left by a consent dialog is undone', async (page) => {
  await page.goto('https://example.com/');
  await page.addStyleTag({ content: 'html.sp-message-open { overflow: hidden !important; }' });
  await page.evaluate(() => document.documentElement.classList.add('sp-message-open'));
  assert.equal(await page.evaluate(() => getComputedStyle(document.documentElement).overflowY), 'hidden');
  await page.evaluate(scripts.scrollUnlock);
  assert.equal(await page.evaluate(() => getComputedStyle(document.documentElement).overflowY), 'auto');
});

await browser.close();
console.log(`\n${passed} passed${process.exitCode ? ', some FAILED' : ''}`);
