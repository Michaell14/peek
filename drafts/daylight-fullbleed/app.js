// Blink, "Daylight, full bleed" draft.
// The browser window is the Mac. Its screen fills the window while the page
// scrolls, and the distance scrolled plays Blink's story on it; at the end
// the screen steps back onto the page. Hold Space (or press the fn key) at
// any point to open Blink yourself.
(() => {
  'use strict';

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));
  const clamp = (v, a, b) => Math.min(Math.max(v, a), b);
  const seg = (t, a, b) => clamp((t - a) / (b - a), 0, 1);
  const lerp = (a, b, p) => a + (b - a) * p;
  const easeInOut = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
  const easeOut = (x) => 1 - Math.pow(1 - x, 3);
  const linear = (x) => x;
  const mix = (a, b, p) => (Array.isArray(a) ? a.map((v, i) => lerp(v, b[i], p)) : lerp(a, b, p));

  // A keyframe track: [[t, value], ...]; holds its ends, eases between keys.
  function track(keys, T, ease = easeInOut) {
    if (T <= keys[0][0]) return keys[0][1];
    for (let i = 1; i < keys.length; i += 1) {
      const [t1, v1] = keys[i];
      if (T <= t1) {
        const [t0, v0] = keys[i - 1];
        return mix(v0, v1, t1 === t0 ? 1 : ease((T - t0) / (t1 - t0)));
      }
    }
    return keys[keys.length - 1][1];
  }
  const within = (T, ranges) => ranges.some(([a, b]) => T >= a && T < b);

  // ---------------------------------------------------------------------
  // The story, as a timeline. T runs from -1 at the top of the page to 11.
  //   -1 to 0    the desktop with the headline; then the writer's windows arrive
  //    0 to 10   ten beats; beat k runs from T = k - 1 to T = k
  //   10 to 11   the screen steps back onto the page
  // ---------------------------------------------------------------------

  // How far you scroll through each part, in viewport heights.
  const LENGTHS = [0.9, 0.8, 1.1, 0.95, 0.85, 1.15, 1.0, 1.0, 1.0, 1.4, 1.15, 1.2];
  // Where each beat's still sits, for phones and reduced motion.
  const STILLS = [0.92, 1.82, 2.75, 3.8, 4.9, 5.74, 6.85, 7.56, 8.74, 9.75];
  // When each beat's caption fills, as a fraction of its beat.
  const FILL = [null, [0.02, 0.36], [0.03, 0.45], [0.02, 0.36], [0.02, 0.42], [0.03, 0.5], [0.03, 0.62], [0.03, 0.5], [0.02, 0.42], [0.03, 0.5], [0.03, 0.45]];

  const OVERLAY = [[-2, 0], [2.12, 0], [2.4, 1], [3.06, 1], [3.12, 0], [4.04, 0], [4.1, 1], [6.94, 1], [7.0, 0], [7.12, 0], [7.17, 1], [9.03, 1], [9.08, 0], [9.56, 0], [9.62, 1], [9.88, 1], [9.93, 0]];
  const KEY_DOWN = [[2.1, 3.06], [4.03, 6.94], [7.11, 7.15], [9.02, 9.05], [9.55, 9.88]];
  const STRIP = [[7.17, 0], [7.23, 1], [9.03, 1], [9.07, 0]];

  // The opening: the headline leaves, the windows arrive one by one.
  const HERO_OUT = [[-0.86, 0], [-0.52, 1]];
  const WIN_IN = { web: [-0.7, -0.44], cal: [-0.62, -0.36], mail: [-0.54, -0.28], writer: [-0.44, -0.12] };
  const MENUS_IN = [-0.16, -0.04];

  const TEXT_A = 'Since the new page went live, we are at';
  const TEXT_B = ' 368.';
  const TYPE_A = [[-0.08, 0], [0.6, TEXT_A.length]];
  const TYPE_B = [[3.2, 0], [3.4, TEXT_B.length]];

  // Clicking around to check things: which window comes forward, and when.
  const FRONT = [[1.18, 'cal'], [1.43, 'mail'], [1.67, 'web'], [1.92, 'writer']];
  const APP_NAME = { writer: 'Writer', cal: 'Calendar', mail: 'Mail', web: 'Browser' };
  // The Dock hides until the pointer goes to the bottom of the screen.
  const DOCK_ORDER = ['files', 'writer', 'cal', 'mail', 'web', 'settings'];
  const DOCK_SHOWN = [[1.03, 0], [1.11, 1], [1.97, 1], [2.07, 0], [10.14, 0], [10.34, 1]];

  // Full screen, and back out of it before the screen steps back.
  // The page goes white at the window, grows to fill the screen, then the
  // text appears at its new size; and the same backwards.
  const FULL = [[9.14, 0], [9.38, 1], [10.03, 1], [10.16, 0]];
  const FULL_SHOWN = [[9.12, 0], [9.16, 1], [10.14, 1], [10.18, 0]];
  const FULL_TEXT = [[9.35, 0], [9.42, 1], [10.0, 1], [10.04, 0]];
  const CHROME_GONE = [[9.12, 0], [9.26, 1], [10.02, 1], [10.16, 0]];

  // When the hint above the key shows (until the visitor has tried it).
  const TIP = [[0.12, 0.95], [3.14, 3.95]];

  // Stepping back: the screen becomes a display on the page.
  const PULL = [10.12, 10.86];

  // Tile frames on the board, [x, y, w, h], in screen pixels, for a board of
  // any size. Flow packs three columns; arranging (beat 9) resizes the page,
  // moves the file, moves the clock, then goes back to Flow.
  function boardLayout(W, H) {
    const gap = 14;
    const room = W - 2 * gap;
    const w1 = Math.round(room * 330 / 1204);
    const w2 = Math.round(room * 520 / 1204);
    const w3 = room - w1 - w2;
    const x2 = w1 + gap;
    const x3 = x2 + w2 + gap;
    const ch = Math.round(H * 0.52);
    return { W, H, gap, x1: 0, x2, x3, w1, w2, w3, ch, lh: H - ch - gap };
  }
  function framesFor(L) {
    const { W, H, gap, x1, x2, x3, w1, w2, w3, ch, lh } = L;
    const clockAway = [W - w1, ch + gap, w1, 212];
    return {
      clock: [[8.54, [x1, 0, w1, 212]], [8.64, clockAway], [8.79, clockAway], [8.93, [x1, 0, w1, 212]]],
      reminders: [[0, [x1, 226, w1, H - 226]]],
      web: [[8.2, [x2, 0, w2, H]], [8.3, [x2, 0, w2, ch]], [8.79, [x2, 0, w2, ch]], [8.93, [x2, 0, w2, H]]],
      calendar: [[6.1, [x3, 0, w3, H]], [6.36, [x3, 0, w3, ch]]],
      pdf: [[6.14, [x3, H + 50, w3, lh]], [6.4, [x3, ch + gap, w3, lh]], [8.37, [x3, ch + gap, w3, lh]], [8.47, [x2, ch + gap, w3, lh]], [8.79, [x2, ch + gap, w3, lh]], [8.93, [x3, ch + gap, w3, lh]]],
    };
  }
  const HELD = { web: [8.2, 8.31], pdf: [8.37, 8.48], clock: [8.54, 8.65] };
  const TILE_ORDER = ['clock', 'reminders', 'web', 'calendar', 'pdf'];
  const BOARD_LEFT = 24;
  const BOARD_TOP = 74; // under the menu bar and Blink's strip

  // The pointer, in two acts. Points that depend on layout are measured.
  const POINTER_SHOWN = [[0.98, 0], [1.02, 1], [2.0, 1], [2.06, 0], [7.22, 0], [7.27, 1], [8.94, 1], [9.0, 0]];
  const CLICKS = [1.18, 1.43, 1.67, 1.92, 7.45, 8.09, 8.16, 8.71, 8.77];

  function buildPointerPath(scene, P) {
    const { ox, oy, L } = scene;
    const dock = (app) => [scene.SW / 2 - 145 + 58 * DOCK_ORDER.indexOf(app), scene.SH - 39];
    const desk = (x, y) => [x + ox, y + oy];
    const edgeTo = [P.webEdge[0], BOARD_TOP + L.ch];
    const pdfTo = [P.pdf[0] - (L.x3 - L.x2), P.pdf[1]];
    const clockTo = [P.clock[0] + (L.W - L.w1 - L.x1), P.clock[1] + L.ch + L.gap];
    scene.path = [
      [1.0, desk(560, 470)],
      [1.15, dock('cal')], [1.21, dock('cal')],
      [1.4, dock('mail')], [1.46, dock('mail')],
      [1.64, dock('web')], [1.7, dock('web')],
      [1.8, desk(800, 352)], [1.84, desk(800, 352)],
      [1.9, dock('writer')], [1.94, dock('writer')],
      [2.04, desk(620, 500)],
      [7.22, P.boardMid], [7.42, P.room], [7.5, P.room],
      [7.62, P.webMid], [7.98, P.webMid],
      [8.07, P.free], [8.1, P.free],
      [8.14, P.edit], [8.17, P.edit],
      [8.19, P.webEdge], [8.2, P.webEdge], [8.3, edgeTo], [8.31, edgeTo],
      [8.36, P.pdf], [8.37, P.pdf], [8.47, pdfTo], [8.48, pdfTo],
      [8.53, P.clock], [8.54, P.clock], [8.64, clockTo], [8.65, clockTo],
      [8.7, P.edit], [8.72, P.edit],
      [8.76, P.flow], [8.9, P.flow],
    ];
  }

  // ---------------------------------------------------------------------
  // Tiles. The same renderers fill the screen in the picture and the
  // overlay over the page.
  // ---------------------------------------------------------------------

  const icon = (paths) => `<svg viewBox="0 0 16 16" aria-hidden="true">${paths}</svg>`;
  const ICONS = {
    clock: icon('<circle cx="8" cy="8" r="6"/><path d="M8 4.6V8l2.3 1.5"/>'),
    reminders: icon('<circle cx="3.6" cy="4.5" r="1.4"/><circle cx="3.6" cy="11.5" r="1.4"/><path d="M7.4 4.5h6M7.4 11.5h6"/>'),
    web: icon('<circle cx="8" cy="8" r="6"/><path d="M2 8h12M8 2c2 2 2 10 0 12M8 2c-2 2-2 10 0 12"/>'),
    calendar: icon('<rect x="2.2" y="3" width="11.6" height="10.8" rx="2"/><path d="M2.2 6.6h11.6M5.4 1.8v2.4M10.6 1.8v2.4"/>'),
    pdf: icon('<path d="M4 1.8h5.4L12.6 5v8.2a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V2.8a1 1 0 0 1 1-1z"/><path d="M9.2 1.8V5h3.4M5.4 8.4h5.2M5.4 11h3.4"/>'),
    sun: '<svg viewBox="0 0 16 16" width="13" height="13" aria-hidden="true"><circle cx="8" cy="8" r="3.1" fill="currentColor"/><path stroke="currentColor" stroke-width="1.4" stroke-linecap="round" d="M8 1.3v1.5M8 13.2v1.5M1.3 8h1.5M13.2 8h1.5M3.3 3.3l1 1M11.7 11.7l1 1M3.3 12.7l1-1M11.7 4.3l1-1"/></svg>',
    moon: '<svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true"><path fill="currentColor" d="M13.4 10A5.7 5.7 0 0 1 6 2.6a5.7 5.7 0 1 0 7.4 7.4z"/></svg>',
  };
  const TITLES = { clock: 'Clock', reminders: 'Reminders', web: 'Example dashboard', calendar: 'Calendar', pdf: 'agenda.pdf' };

  const ZONES = [
    { zone: 'America/New_York', name: 'New York' },
    { zone: 'Europe/London', name: 'London' },
    { zone: 'Asia/Tokyo', name: 'Tokyo' },
  ];

  const WEB_VALUES = {
    before: { visitors: '12,480', signups: '368', bounce: '38%', visit: '2m 41s', 'visitors-e': '▲ 8.2%', 'signups-e': '▲ 7.6%', 'bounce-e': '▼ 1.4%', 'visit-e': '▲ 12s' },
    after: { visitors: '12,536', signups: '371', bounce: '37%', visit: '2m 44s', 'visitors-e': '▲ 8.7%', 'signups-e': '▲ 8.5%', 'bounce-e': '▼ 2.6%', 'visit-e': '▲ 15s' },
  };
  const BARS = [52, 49, 58, 55, 61, 84, 90];

  const RENDER = {
    clock: () => `<div class="w-clock">${ZONES.map((entry, index) => `
        <div class="w-clock__row" data-zone-row="${index}">
          <span class="w-clock__glyph"></span>
          <span class="w-clock__place"><b>${entry.name}</b><span></span></span>
          <span class="w-clock__time"></span>
        </div>`).join('')}</div>`,

    reminders: () => `
      <div class="w-rem">
        <div class="w-rem__head"><span class="seg"><i class="is-on">Today</i><i>Scheduled</i><i>All</i></span><span class="w-rem__count" data-rem-count>5</span></div>
        <div class="w-rem__list">
          <p class="w-label">Overdue</p>
          <button type="button" tabindex="-1" class="w-rem__item" data-rem="invoice"><i></i><span><b>Send the invoice</b><small class="is-late">Yesterday</small></span></button>
          <p class="w-label">Today</p>
          <button type="button" tabindex="-1" class="w-rem__item" data-rem="room"><i></i><span><b>Book a room for Thursday</b><small>10:00 AM</small></span></button>
          <button type="button" tabindex="-1" class="w-rem__item" data-rem="sam"><i></i><span><b>Reply to Sam</b><small>Today</small></span></button>
          <button type="button" tabindex="-1" class="w-rem__item" data-rem="plants"><i></i><span><b>Water the plants</b><small>Today</small></span></button>
          <button type="button" tabindex="-1" class="w-rem__item" data-rem="dentist"><i></i><span><b>Call the dentist</b><small>Today, 5:30 PM</small></span></button>
        </div>
        <div class="w-rem__new"><b>+</b>New Reminder</div>
      </div>`,

    web: () => `
      <div class="w-web">
        <div class="w-hover" data-hover>
          <i>${icon('<path d="M9.8 3.5 5.3 8l4.5 4.5"/>')}</i>
          <i>${icon('<path d="M6.2 3.5 10.7 8l-4.5 4.5"/>')}</i>
          <i class="ring" data-ring>${icon('<path d="M12.6 8a4.6 4.6 0 1 1-1.4-3.3M12.8 2.8v2.6h-2.6"/>')}<svg class="r" viewBox="0 0 26 24" aria-hidden="true"><circle cx="13" cy="12" r="10"/></svg></i>
          <span data-refresh>Refresh in 5:00</span>
        </div>
        <div class="w-web__body" data-web-body>
          <h5>Example dashboard</h5>
          <p class="w-web__sub">Last 7 days</p>
          <div class="w-web__stats">
            <div class="w-web__card"><small>Visitors</small><b data-v="visitors">12,480</b><em class="up" data-v="visitors-e">▲ 8.2%</em></div>
            <div class="w-web__card"><small>Sign-ups per day</small><b data-v="signups">368</b><em class="up" data-v="signups-e">▲ 7.6%</em></div>
            <div class="w-web__card"><small>Bounce rate</small><b data-v="bounce">38%</b><em class="down" data-v="bounce-e">▼ 1.4%</em></div>
            <div class="w-web__card"><small>Avg. visit</small><b data-v="visit">2m 41s</b><em class="up" data-v="visit-e">▲ 12s</em></div>
          </div>
          <div class="w-web__card" style="margin-top:10px"><small>Sign-ups per day</small>
            <div class="w-web__chart">${BARS.map((h) => `<i style="height:${h}%"></i>`).join('')}</div>
          </div>
          <div class="w-web__card" style="margin-top:10px"><small>Top pages</small>
            <div class="w-web__rows"><div><span>/</span><span>5,210</span></div><div><span>/signup</span><span>2,577</span></div><div><span>/pricing</span><span>2,034</span></div><div><span>/docs/getting-started</span><span>1,377</span></div><div><span>/blog/new-page</span><span>962</span></div></div>
          </div>
        </div>
        <div class="w-web__flash" data-flash></div>
      </div>`,

    calendar: () => `
      <div class="w-cal">
        <div class="w-cal__head">
          <span class="w-cal__day"></span>
          <span class="w-cal__date"><b></b><span></span></span>
          <span class="seg"><i class="is-on">Day</i><i>7 Days</i></span>
        </div>
        <div class="w-cal__grid"></div>
      </div>`,

    pdf: () => `
      <div class="w-pdf" data-pdf>
        <div class="w-pdf__page">
          <h6>Agenda</h6>
          <h4>Thursday review</h4>
          <ol>
            <li>The new sign-up page, first week</li>
            <li>Pricing page copy</li>
            <li>Hiring a second designer</li>
            <li class="is-new">Sign-ups: 342 a day before, 368 now</li>
          </ol>
          <p>Room 2, 2:00 PM. Sam to bring the numbers.</p>
        </div>
        <span class="w-pdf__tag">agenda.pdf changed, reloaded</span>
      </div>`,
  };

  function tileHTML(kind) {
    return `<section class="tile" data-tile="${kind}" aria-label="${TITLES[kind]}">${RENDER[kind]()}
      <div class="tile__dim"></div>
      <div class="tile__cover" aria-hidden="true"><span class="tile__x"><svg viewBox="0 0 10 10"><path d="M2 2l6 6M8 2l-6 6"/></svg></span>${ICONS[kind]}<span>${TITLES[kind]}</span></div>
    </section>`;
  }

  // ---- Live contents ---------------------------------------------------------

  function hourIn(zone, date) {
    return Number(new Intl.DateTimeFormat('en-GB', { hour: 'numeric', hourCycle: 'h23', timeZone: zone }).format(date));
  }
  function dayDifference(zone, date) {
    const format = (timeZone) => new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
    return Math.round((Date.parse(format(zone)) - Date.parse(format(undefined))) / 86400000);
  }
  function offsetHours(zone, date) {
    const local = new Date(date.toLocaleString('en-US'));
    const remote = new Date(date.toLocaleString('en-US', { timeZone: zone }));
    return Math.round((remote - local) / 360000) / 10;
  }

  function updateClocks() {
    const now = new Date();
    const time = now.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' }).replace(/\s?[AP]M/i, '');
    const date = now.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' }).replace(',', '');
    $$('[data-live-time]').forEach((element) => { if (element.textContent !== time) element.textContent = time; });
    $$('[data-live-date]').forEach((element) => { if (element.textContent !== date) element.textContent = date; });

    const rows = ZONES.map((entry) => {
      const parts = new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit', timeZone: entry.zone }).formatToParts(now);
      const digits = parts.filter((part) => ['hour', 'literal', 'minute'].includes(part.type)).map((part) => part.value).join('').trim();
      const period = (parts.find((part) => part.type === 'dayPeriod') || {}).value || '';
      const hour = hourIn(entry.zone, now);
      const difference = dayDifference(entry.zone, now);
      const offset = offsetHours(entry.zone, now);
      const dayName = difference > 0 ? 'Tomorrow' : difference < 0 ? 'Yesterday' : 'Today';
      const detail = offset === 0 ? dayName : `${dayName}, ${offset > 0 ? '+' : '−'}${Math.abs(offset)} ${Math.abs(offset) === 1 ? 'hr' : 'hrs'}`;
      return { html: `${digits}<small>${period}</small>`, day: hour >= 6 && hour < 18, detail };
    });
    $$('[data-zone-row]').forEach((row) => {
      const data = rows[Number(row.dataset.zoneRow)];
      const glyph = $('.w-clock__glyph', row);
      const glyphClass = `w-clock__glyph ${data.day ? 'is-day' : 'is-night'}`;
      if (glyph.className !== glyphClass) { glyph.className = glyphClass; glyph.innerHTML = data.day ? ICONS.sun : ICONS.moon; }
      const timeElement = $('.w-clock__time', row);
      if (timeElement.innerHTML !== data.html) timeElement.innerHTML = data.html;
      const place = $('.w-clock__place span', row);
      if (place.textContent !== data.detail) place.textContent = data.detail;
    });
  }

  // A day that always has something going on around now.
  function updateCalendar() {
    const now = new Date();
    const anchor = Math.min(Math.max(now.getHours(), 2), 19);
    const first = anchor - 2;
    const hours = 9;
    const scale = 100 / hours;
    const position = (hour) => (hour - first) * scale;
    const label = (hour) => new Date(2000, 0, 1, Math.floor(hour), (hour % 1) * 60).toLocaleTimeString('en-US', { hour: 'numeric', minute: hour % 1 ? '2-digit' : undefined });
    const events = [
      { title: 'Design review', start: anchor - 1.5, end: anchor - 0.5, color: '#5fd0c2', column: 0, of: 1 },
      { title: 'Thursday review', start: anchor + 0.25, end: anchor + 1.25, color: '#5b9dff', column: 0, of: 2 },
      { title: 'Sam, 1:1', start: anchor + 0.75, end: anchor + 1.75, color: '#b98cff', column: 1, of: 2 },
      { title: 'Lunch', start: anchor + 2.5, end: anchor + 3.25, color: '#ffc761', column: 0, of: 1 },
      { title: 'Ship it', start: anchor + 4.5, end: anchor + 5.5, color: '#ff8a7a', column: 0, of: 1 },
    ];
    let html = '';
    for (let i = 1; i < hours; i += 1) html += `<div class="w-cal__hour" style="top:${i * scale}%"><span>${label(first + i)}</span></div>`;
    for (const event of events) {
      const width = `calc((100% - 54px) / ${event.of} - 3px)`;
      const left = `calc(44px + (100% - 54px) / ${event.of} * ${event.column})`;
      html += `<div class="w-cal__event" style="--c:${event.color};background:${event.color}38;top:calc(${position(event.start)}% + 1px);height:calc(${(event.end - event.start) * scale}% - 3px);left:${left};width:${width}"><b>${event.title}</b><span>${label(event.start)}</span></div>`;
    }
    const nowHour = now.getHours() + now.getMinutes() / 60;
    if (nowHour >= first && nowHour <= first + hours) html += `<div class="w-cal__now" data-now style="top:${position(nowHour)}%"></div>`;

    $$('.w-cal').forEach((root) => {
      $('.w-cal__day', root).textContent = now.getDate();
      $('.w-cal__date b', root).textContent = now.toLocaleDateString('en-US', { weekday: 'long' });
      $('.w-cal__date span', root).textContent = now.toLocaleDateString('en-US', { month: 'long' });
      $('.w-cal__grid', root).innerHTML = html;
    });
    scenes.forEach((scene) => { scene.calNow = $('[data-now]', scene.display); });
    if (stills.length) renderStills();
  }
  // ---------------------------------------------------------------------
  // A scene: one copy of the screen, and how to draw it at any moment T.
  // ---------------------------------------------------------------------

  const scenes = [];

  function makeScene(display) {
    const q = (selector) => $(selector, display);
    const webTile = $('[data-tile="web"]', display);
    const w = (selector) => $(selector, webTile);
    const scene = {
      display,
      cache: new WeakMap(),
      fit: 1,
      SW: 1280,
      SH: 800,
      ox: 0,
      oy: 0,
      path: [],
      camera: [[0, [1, 640, 400]]],
      screen: q('.screen'),
      desk: q('.desk'),
      cam: display.closest('.cam'),
      hero: q('[data-hero]'),
      wins: {},
      dockIcons: {},
      appName: q('[data-app-name]'),
      menus: q('[data-menus]'),
      mbBlink: q('[data-mb-blink]'),
      menubar: q('.menubar'),
      dock: q('.dock'),
      typedA: $$('[data-typed="a"]', display),
      typedB: $$('[data-typed="b"]', display),
      full: q('[data-full]'),
      fullDoc: q('.doc--full'),
      ov: q('[data-ov]'),
      strip: q('[data-strip]'),
      stripHint: q('[data-strip-hint]'),
      segFlow: q('[data-seg-flow]'),
      segFree: q('[data-seg-free]'),
      edit: q('[data-edit]'),
      board: q('[data-board]'),
      tiles: {},
      rem: {},
      remCount: q('[data-rem-count]'),
      hover: w('[data-hover]'),
      ring: w('[data-ring]'),
      refresh: w('[data-refresh]'),
      flash: w('[data-flash]'),
      webBody: w('[data-web-body]'),
      webDim: w('.tile__dim'),
      values: {},
      lastBar: null,
      pdf: q('[data-pdf]'),
      calNow: q('[data-now]'),
      pointer: q('[data-pointer]'),
    };
    $$('[data-win]', display).forEach((element) => { scene.wins[element.dataset.win] = element; });
    $$('.dock [data-app]', display).forEach((element) => { scene.dockIcons[element.dataset.app] = element; });
    $$('[data-tile]', display).forEach((element) => { scene.tiles[element.dataset.tile] = element; });
    $$('[data-rem]', display).forEach((element) => { scene.rem[element.dataset.rem] = element; });
    $$('[data-v]', webTile).forEach((element) => { scene.values[element.dataset.v] = element; });
    scene.lastBar = $$('.w-web__chart i', webTile).pop();
    setGeometry(scene, 1280, 800, 1, 24);
    scenes.push(scene);
    return scene;
  }

  // The screen's size in screen pixels, how much it is scaled, and how much
  // room the board leaves at the bottom (for the caption pill).
  function setGeometry(scene, SW, SH, fit, reserve) {
    const L = boardLayout(Math.round(SW - 2 * BOARD_LEFT), Math.round(SH - BOARD_TOP - reserve));
    Object.assign(scene, { SW, SH, fit, ox: (SW - 1280) / 2, oy: (SH - 800) / 2, L, frames: framesFor(L) });
    const style = scene.display.style;
    style.setProperty('--sw', px(SW));
    style.setProperty('--sh', px(SH));
    style.setProperty('--f', fit.toFixed(5));
    style.setProperty('--ox', px(scene.ox));
    style.setProperty('--oy', px(scene.oy));
    style.setProperty('--bw', `${L.W}px`);
    style.setProperty('--bh', `${L.H}px`);
    // The camera leans in on the web page's refresh timer in beat 5.
    const home = [1, SW / 2, SH / 2];
    const look = [1.42, BOARD_LEFT + L.x2 + L.w2 / 2, BOARD_TOP + L.H * 0.39];
    scene.camera = [[4.12, home], [4.38, look], [4.92, look], [5.12, home]];
  }

  // Writes a style only when it changed since last time.
  function css(scene, element, property, value) {
    if (!element) return;
    let memo = scene.cache.get(element);
    if (!memo) scene.cache.set(element, (memo = {}));
    if (memo[property] === value) return;
    memo[property] = value;
    element.style.setProperty(property, value);
  }
  function flag(element, name, on) {
    if (element && element.classList.contains(name) !== on) element.classList.toggle(name, on);
  }
  function text(element, value) {
    if (element && element.textContent !== value) element.textContent = value;
  }
  const px = (v) => `${Math.round(v * 10) / 10}px`;

  function frontAt(T) {
    const order = ['web', 'cal', 'mail', 'writer'];
    for (const [t, app] of FRONT) {
      if (T < t) break;
      order.splice(order.indexOf(app), 1);
      order.push(app);
    }
    return order;
  }

  // Draw the scene at moment T. `user` (0 to 1) is Blink opened by the
  // visitor; `pinned` means they tapped and it stays. Returns what the page
  // around the screen needs to know.
  function render(scene, T, { user = 0, pinned = false, still = false } = {}) {
    const { SW, SH, ox, oy } = scene;

    // The opening: the headline leaves and the windows arrive.
    if (scene.hero) {
      const gone = track(HERO_OUT, T);
      css(scene, scene.hero, 'opacity', (1 - gone).toFixed(3));
      css(scene, scene.hero, 'visibility', gone > 0.999 ? 'hidden' : 'visible');
      css(scene, scene.hero, 'transform', gone > 0 ? `translateY(${px(-40 * gone)})` : 'none');
      css(scene, scene.hero, 'filter', gone > 0.002 && gone < 0.998 ? `blur(${(gone * 9).toFixed(1)}px)` : 'none');
    }
    for (const [app, [a, b]] of Object.entries(WIN_IN)) {
      const p = easeOut(seg(T, a, b));
      const element = scene.wins[app];
      css(scene, element, 'opacity', seg(T, a, a + (b - a) * 0.4).toFixed(3));
      css(scene, element, 'visibility', p > 0.001 ? 'visible' : 'hidden');
      css(scene, element, 'transform', p > 0.999 ? 'none' : `translateY(${px(28 * (1 - p))}) scale(${(0.95 + 0.05 * p).toFixed(4)})`);
    }
    css(scene, scene.menus, 'opacity', seg(T, MENUS_IN[0], MENUS_IN[1]).toFixed(3));

    // Windows: stacking order, and which one is in front.
    const order = frontAt(T);
    const front = order[order.length - 1];
    order.forEach((app, index) => {
      css(scene, scene.wins[app], 'z-index', String(index + 1));
      flag(scene.wins[app], 'is-key', app === front);
    });
    text(scene.appName, APP_NAME[front]);
    for (const [app, element] of Object.entries(scene.dockIcons)) {
      const t = { cal: 1.18, mail: 1.43, web: 1.67, writer: 1.92 }[app];
      flag(element, 'is-click', t != null && Math.abs(T - t) < 0.012);
    }

    // The sentence being written.
    const a = Math.round(track(TYPE_A, T, linear));
    const b = Math.round(track(TYPE_B, T, linear));
    scene.typedA.forEach((element) => text(element, TEXT_A.slice(0, a)));
    scene.typedB.forEach((element) => text(element, TEXT_B.slice(0, b)));

    // Full screen, and back.
    const fullP = track(FULL, T);
    const fullO = track(FULL_SHOWN, T, linear);
    css(scene, scene.full, 'visibility', fullO > 0 ? 'visible' : 'hidden');
    css(scene, scene.full, 'opacity', fullO.toFixed(3));
    css(scene, scene.fullDoc, 'opacity', track(FULL_TEXT, T, linear).toFixed(3));
    const inset = [62 + oy, SW - 870 - ox, SH - 674 - oy, 170 + ox].map((v) => lerp(v, 0, fullP));
    css(scene, scene.full, 'clip-path', `inset(${inset.map(px).join(' ')} round ${px(lerp(12, 0, fullP))})`);
    const chrome = track(CHROME_GONE, T);
    css(scene, scene.menubar, 'transform', chrome > 0 ? `translateY(${px(-30 * chrome)})` : 'none');

    // The Dock, which hides until it is wanted.
    const dockHidden = Math.max(1 - track(DOCK_SHOWN, T), chrome);
    css(scene, scene.dock, 'transform', `translateX(-50%) translateY(${px(96 * dockHidden)})`);

    // Blink.
    const sceneOverlay = track(OVERLAY, T, linear);
    const overlay = Math.max(sceneOverlay, user);
    css(scene, scene.ov, 'opacity', overlay.toFixed(3));
    css(scene, scene.ov, 'visibility', overlay > 0.001 ? 'visible' : 'hidden');
    flag(scene.ov, 'is-live', pinned);
    flag(scene.mbBlink, 'is-on', overlay > 0.5);
    flag(scene.menubar, 'is-dark', overlay > 0.5);
    if (still) flag(scene.desk, 'is-blurred', overlay > 0.5);
    const bloom = T > 2 && T < 2.6 ? track([[2.12, 0.965], [2.42, 1]], T) : 0.985 + 0.015 * overlay;
    const lift = chrome > 0 ? `translateY(${px(-28 * chrome)}) ` : '';
    css(scene, scene.board, 'transform', `${lift}scale(${(user > sceneOverlay ? 0.985 + 0.015 * user : bloom).toFixed(4)})`);
    css(scene, scene.strip, 'opacity', Math.max(track(STRIP, T, linear), pinned ? 1 : 0).toFixed(3));
    css(scene, scene.strip, 'transform', chrome > 0 ? `translateY(${px(-28 * chrome)})` : 'none');

    // Arranging.
    const freeform = T >= 8.09 && T < 8.77;
    const editing = T >= 8.16 && T < 8.71;
    flag(scene.segFlow, 'is-on', !freeform);
    flag(scene.segFree, 'is-on', freeform);
    flag(scene.board, 'is-editing', editing);
    flag(scene.edit, 'is-on', editing);
    text(scene.edit, editing ? 'Done' : 'Edit');
    text(scene.stripHint, editing ? 'Drag a tile to move it, or its edge to resize' : 'fn or esc to close');

    // Tiles.
    TILE_ORDER.forEach((kind, index) => {
      const element = scene.tiles[kind];
      if (!element) return;
      const [x, y, w, h] = track(scene.frames[kind], T);
      let opacity = 1;
      let rise = 0;
      if (T > 2.05 && T < 2.5 && user <= sceneOverlay) {
        const o = seg(T, 2.14 + index * 0.035, 2.28 + index * 0.035);
        opacity = o;
        rise = (1 - o) * 12;
      }
      if (kind === 'pdf') opacity = track([[6.14, 0], [6.24, 1]], T, linear);
      css(scene, element, 'transform', `translate(${px(x)}, ${px(y + rise)})`);
      css(scene, element, 'width', px(w));
      css(scene, element, 'height', px(h));
      css(scene, element, 'opacity', opacity.toFixed(3));
      css(scene, element, 'visibility', opacity > 0.001 ? 'visible' : 'hidden');
      const held = HELD[kind];
      flag(element, 'is-held', !!held && T >= held[0] && T < held[1]);
    });
    // While the widgets have their turn, the page steps back.
    css(scene, scene.webDim, 'opacity', track([[5.08, 0], [5.2, 1], [5.86, 1], [5.98, 0]], T, linear).toFixed(3));

    // Reminders that get done.
    const done = { plants: T >= 5.42, room: T >= 7.45 };
    for (const [key, element] of Object.entries(scene.rem)) {
      if (key in done && !element.dataset.user) flag(element, 'is-done', done[key]);
    }
    if (scene.remCount) text(scene.remCount, String(Object.values(scene.rem).filter((element) => !element.classList.contains('is-done')).length));

    // The web page: hover bar, refresh timer, and the numbers after.
    css(scene, scene.hover, 'opacity', track([[4.34, 0], [4.4, 1], [5.0, 1], [5.06, 0]], T, linear).toFixed(3));
    const refreshed = T >= 4.76;
    const ring = refreshed ? track([[4.76, 0], [5.1, 0.12]], T, linear) : track([[4.4, 0], [4.74, 1]], T, linear);
    css(scene, scene.ring, '--ring', ring.toFixed(3));
    const left = Math.round((1 - ring) * 300);
    text(scene.refresh, ring >= 0.999 ? 'Refreshing' : `Refresh in ${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')}`);
    css(scene, scene.flash, 'opacity', track([[4.74, 0], [4.76, 0.75], [4.84, 0]], T, linear).toFixed(3));
    const values = refreshed ? WEB_VALUES.after : WEB_VALUES.before;
    for (const [key, element] of Object.entries(scene.values)) {
      text(element, values[key]);
      if (element.tagName === 'B') flag(element, 'is-new', refreshed && T < 4.96);
    }
    css(scene, scene.lastBar, 'transform', `scaleY(${track([[4.76, 0.9], [4.86, 1]], T).toFixed(3)})`);
    const scroll = track([[7.66, 0], [7.78, -120], [7.86, -120], [7.98, 0]], T);
    css(scene, scene.webBody, 'transform', scroll ? `translateY(${px(scroll)})` : 'none');

    // The file that changes on disk.
    flag(scene.pdf, 'is-updated', T >= 6.62);

    // Now, on the calendar.
    if (scene.calNow) {
      const pulse = T > 5.45 && T < 6 ? ((T - 5.45) / 0.18) % 1 : 1;
      css(scene, scene.calNow, '--pulse-s', (0.4 + pulse * 1.6).toFixed(3));
      css(scene, scene.calNow, '--pulse-o', (T > 5.45 && T < 6 ? 0.9 * (1 - pulse) : 0).toFixed(3));
    }

    // The pointer.
    if (scene.path.length) {
      const shown = track(POINTER_SHOWN, T, linear) * (still && !(T > 1 && T < 2.05) && !(T > 7.2 && T < 9) ? 0 : 1);
      const [x, y] = track(scene.path, T);
      const click = CLICKS.some((t) => Math.abs(T - t) < 0.012) || Object.values(HELD).some(([a0, b0]) => T >= a0 && T < b0);
      css(scene, scene.pointer, 'opacity', shown.toFixed(3));
      css(scene, scene.pointer, 'transform', `translate(${px(x)}, ${px(y)}) scale(${click ? 0.86 : 1})`);
    }

    // The camera.
    const [zoom, cx, cy] = track(scene.camera, T);
    const dx = -(cx - SW / 2) * scene.fit * zoom;
    const dy = -(cy - SH / 2) * scene.fit * zoom;
    css(scene, scene.cam, 'transform', zoom === 1 ? 'none' : `translate(${px(dx)}, ${px(dy)}) scale(${zoom.toFixed(4)})`);

    return { overlay, dock: 1 - dockHidden };
  }

  // ---------------------------------------------------------------------
  // The page.
  // ---------------------------------------------------------------------

  const root = document.documentElement;
  const bar = $('#bar');
  const take = $('#take');
  const lens = $('#lens');
  const display = $('#display');
  const foot = $('#foot');
  const stack = $('#stack');
  const caps = $$('#caps .cap');
  const stageKey = $('.foot .fnkey');
  const floatBox = $('#float');
  const calm = window.matchMedia('(prefers-reduced-motion: reduce)');

  // Build the board in the picture, then the scene that drives it.
  $('[data-board]', display).innerHTML = TILE_ORDER.map(tileHTML).join('');
  $('[data-slot="web"]', display).innerHTML = RENDER.web()
    .replace(/<div class="w-hover"[\s\S]*?<\/span>\s*<\/div>/, '')
    .replace(/ data-[a-z-]+(="[^"]*")?/g, '');
  const stageScene = makeScene(display);
  const sceneNav = Array.from(display.querySelectorAll('.mb-link, .mb-get'));

  // Captions: one span per word, so they can fill in as you read. The
  // opening line is not filled; it is already there.
  function splitWords(element) {
    const words = element.textContent.trim().split(/\s+/);
    element.innerHTML = words.map((word) => `<span class="w">${word}</span>`).join(' ');
    return $$('.w', element);
  }
  const capWords = caps.map((cap, k) => (k === 0 ? [] : splitWords(cap)));
  function paintWords(words, fill, cache) {
    const n = words.length;
    words.forEach((word, i) => {
      const key = Math.round(clamp(fill * n - i, 0, 1) * 40);
      if (cache[i] === key) return;
      cache[i] = key;
      word.style.setProperty('--w', (key / 40).toFixed(3));
    });
  }
  const capCache = caps.map(() => []);

  let mode = '';
  let T = -1;
  let tried = false;
  const state = { vw: 0, vh: window.innerHeight, lengthsPx: [], target: { x: 0, y: 0, w: 1 }, pull: -1, footLift: 0, dockLift: 0 };

  function isTakeMode() {
    return window.innerWidth >= 900 && window.innerHeight >= 560 && !calm.matches;
  }

  // The screen fills the window. It is drawn at 1280 x 800 or larger and
  // scaled, never more than 1.3 times, so text stays sharp and in proportion.
  function layout() {
    const vw = document.documentElement.clientWidth;
    const vh = window.innerHeight;
    state.vw = vw;
    state.vh = vh;
    if (mode === 'take') {
      const fit = Math.min(vw / 1280, vh / 800, 1.3);
      // The pill and key grow a little on large screens, and the board leaves room for them.
      state.u = clamp(fit / 1.125, 1, 1.18);
      foot.style.setProperty('--u', state.u.toFixed(4));
      const reserve = Math.max(24, (22 + 62 * state.u + 14) / fit);
      setGeometry(stageScene, vw / fit, vh / fit, fit, reserve);
      state.lengthsPx = LENGTHS.map((l) => l * vh);
      take.style.height = `${vh + state.lengthsPx.reduce((s, v) => s + v, 0)}px`;
      // Where the screen ends up once it has stepped back.
      // It sits under the page's menu bar, with room below for its shadow.
      const above = 34 + Math.max(36, vh * 0.05);
      const below = Math.max(72, vh * 0.1);
      const w = Math.round(Math.min(vw - 2 * Math.max(48, vw * 0.1), 1240, (vh - above - below) * vw / vh));
      const h = w * vh / vw;
      state.target = { w, x: (vw - w) / 2, y: above + (vh - above - below - h) / 2 };
      root.style.setProperty('--dw', `${w}px`);
      state.pull = -1;
      state.dockLift = 70 * fit + 12 - 22;
    } else {
      root.style.removeProperty('--dw');
      take.style.height = '';
      lens.style.transform = '';
      const width = stack.clientWidth || vw;
      const cf = width / 1280;
      stack.style.setProperty('--cf', cf.toFixed(5));
      const reserve = vw >= 900 ? Math.max(24, (36 + 66 + 12) / cf) : 24;
      stills.forEach((still) => setGeometry(still.scene, 1280, 800, cf, reserve));
      stills.forEach((still) => measure(still.scene));
      renderStills();
    }
  }

  function setMode() {
    const next = isTakeMode() ? 'take' : 'stack';
    if (next === mode) return;
    mode = next;
    root.classList.toggle('is-take', mode === 'take');
    root.classList.toggle('is-stack', mode === 'stack');
    stack.hidden = mode !== 'stack';
    if (mode === 'stack') buildStills();
  }

  // T from where the page is scrolled.
  function readT() {
    let rest = -take.getBoundingClientRect().top;
    if (rest <= 0) return -1;
    for (let k = 0; k < state.lengthsPx.length; k += 1) {
      const length = state.lengthsPx[k];
      if (rest < length) return k - 1 + rest / length;
      rest -= length;
    }
    return LENGTHS.length - 1;
  }

  // Scroll position for a given T.
  function scrollForT(target) {
    let y = take.getBoundingClientRect().top + window.scrollY;
    for (let k = 0; k < state.lengthsPx.length; k += 1) {
      if (target < k) return y + (target - (k - 1)) * state.lengthsPx[k];
      y += state.lengthsPx[k];
    }
    return y;
  }

  // The pill hugs the caption it is showing. Each caption's widest line is
  // measured once at full width; the pill then eases between them.
  const pill = $('.pill');
  let pillWidths = [];
  let pillFor = -1;
  function measureCaptions() {
    pill.style.removeProperty('--pill');
    pillFor = -1;
    const range = document.createRange();
    pillWidths = caps.map((cap) => {
      range.selectNodeContents(cap);
      const rects = Array.from(range.getClientRects());
      if (!rects.length) return 0;
      const left = Math.min(...rects.map((r) => r.left));
      const right = Math.max(...rects.map((r) => r.right));
      return Math.ceil((right - left) / (state.u || 1));
    });
  }

  function renderCaptions() {
    const active = clamp(Math.floor(T) + 1, 0, 10);
    if (active !== pillFor && pillWidths[active]) {
      pillFor = active;
      pill.style.setProperty('--pill', `${pillWidths[active] + 64}px`);
    }
    caps.forEach((cap, k) => {
      if (Math.abs(k - active) > 1) {
        if (cap.style.opacity !== '0') cap.style.opacity = '0';
        return;
      }
      const t = T - (k - 1);
      const on = k === 0 ? 1 : seg(t, 0, 0.06);
      const off = k === 10 ? 1 : 1 - seg(t, 0.93, 1);
      const opacity = on * off;
      cap.style.opacity = opacity.toFixed(3);
      cap.style.transform = `translateY(${((1 - on) * 8 - (1 - off) * 8).toFixed(1)}px)`;
      cap.style.filter = opacity > 0.98 ? 'none' : `blur(${((1 - on) * 5 + (1 - off) * 5).toFixed(1)}px)`;
      if (k > 0) paintWords(capWords[k], seg(t, FILL[k][0], FILL[k][1]), capCache[k]);
    });
  }

  // The screen steps back onto the page: it shrinks into a display with a
  // thin bezel, and the page's own menu bar comes down.
  function renderPullback() {
    const p = easeInOut(seg(T, PULL[0], PULL[1]));
    if (p === state.pull) return;
    state.pull = p;
    const screen = stageScene.screen;
    if (p === 0) {
      lens.style.transform = 'none';
      screen.style.borderRadius = '';
      screen.style.boxShadow = '';
      return;
    }
    const { target, vw } = state;
    const s = lerp(1, target.w / vw, p);
    lens.style.transform = `translate(${(target.x * p).toFixed(2)}px, ${(target.y * p).toFixed(2)}px) scale(${s.toFixed(5)})`;
    const k = stageScene.fit * s; // screen pixels to page pixels
    const bezel = (9 * p) / k;
    screen.style.borderRadius = `${((13 * p) / k).toFixed(2)}px`;
    screen.style.boxShadow = [
      `0 0 0 ${bezel.toFixed(2)}px #0e0f12`,
      `0 0 0 ${(bezel + 1 / k).toFixed(2)}px rgba(10, 12, 16, ${(0.4 * p).toFixed(3)})`,
      `0 ${(30 / k).toFixed(1)}px ${(64 / k).toFixed(1)}px ${(-30 / k).toFixed(1)}px rgba(28, 38, 58, ${(0.5 * p).toFixed(3)})`,
      `0 ${(12 / k).toFixed(1)}px ${(26 / k).toFixed(1)}px ${(-14 / k).toFixed(1)}px rgba(28, 38, 58, ${(0.28 * p).toFixed(3)})`,
    ].join(', ');
  }

  let stageOverlay = 0;
  function renderStage() {
    const info = render(stageScene, T, { user: userOverlay.u, pinned: peek.state === 'pinned' && peek.where === 'stage' });
    stageOverlay = info.overlay;
    if (mode !== 'take') return;
    const ghost = within(T, KEY_DOWN);
    flag(stageKey, 'is-down', ghost || keyHeld);
    // The pill makes way for the Dock, turns dark over Blink, and leaves with the screen.
    const lift = -state.dockLift * info.dock * (1 - userOverlay.u);
    if (lift !== state.footLift) { state.footLift = lift; foot.style.setProperty('--lift', `${lift.toFixed(1)}px`); }
    flag(foot, 'is-dark', info.overlay > 0.5);
    const footShown = 1 - seg(T, 10.0, 10.16);
    foot.style.opacity = footShown.toFixed(3);
    foot.style.visibility = footShown > 0 ? 'visible' : 'hidden';
    flag(foot, 'has-tip', !tried && within(T, TIP));
    // Source and Download leave the picture as the page's own menu bar arrives.
    const nav = (1 - seg(T, 10.3, 10.5)).toFixed(3);
    if (nav !== state.nav) { state.nav = nav; sceneNav.forEach((link) => { link.style.opacity = nav; }); }
  }

  function onFrame() {
    frame = 0;
    if (mode === 'take') {
      T = readT();
      renderCaptions();
      renderStage();
      renderPullback();
      const back = T >= 10.5;
      flag(bar, 'is-shown', back);
      if (stageScene.menubar.inert !== T >= 10.3) stageScene.menubar.inert = T >= 10.3;
      if (peek.state === 'pinned' && peek.where === 'stage' && stageVisibility() < 0.4) dismiss();
    } else {
      renderStillCaptions();
      const stackRect = stack.getBoundingClientRect();
      flag(floatBox, 'is-shown', stackRect.top < state.vh * 0.6 && stackRect.bottom > state.vh * 0.5);
    }
  }
  let frame = 0;
  const requestFrame = () => { if (!frame) frame = requestAnimationFrame(onFrame); };
  window.addEventListener('scroll', requestFrame, { passive: true });

  // ---- Stills -------------------------------------------------------------

  const stills = [];
  function buildStills() {
    if (stills.length) return;
    const template = display.cloneNode(true);
    template.removeAttribute('id');
    template.removeAttribute('style');
    $$('[data-hero], [id]', template).forEach((element) => {
      if (element.matches('[data-hero]')) element.remove();
      else element.removeAttribute('id');
    });
    stack.innerHTML = '';
    STILLS.forEach((t, index) => {
      const item = document.createElement('li');
      item.className = 'still';
      const view = document.createElement('div');
      view.className = 'still__view';
      view.setAttribute('aria-hidden', 'true');
      view.inert = true;
      const cam = document.createElement('div');
      cam.className = 'cam';
      const copy = template.cloneNode(true);
      cam.append(copy);
      view.append(cam);
      const cap = document.createElement('p');
      cap.className = 'still__cap';
      cap.textContent = caps[index + 1].textContent;
      item.append(view, cap);
      stack.append(item);
      const scene = makeScene(copy);
      stills.push({ index, scene, cap, words: splitWords(cap), cache: [] });
    });
    updateClocks();
    updateCalendar();
  }

  function renderStills() {
    stills.forEach((still) => render(still.scene, STILLS[still.index], { still: true }));
  }

  function renderStillCaptions() {
    const vh = state.vh;
    const wide = state.vw >= 900;
    const tops = stills.map((still) => still.cap.getBoundingClientRect().top);
    stills.forEach((still, i) => {
      const fill = calm.matches || wide ? 1 : seg(vh * 0.92 - tops[i], 0, vh * 0.42);
      paintWords(still.words, fill, still.cache);
    });
  }

  // ---- Measuring points the pointer goes to --------------------------------

  function measure(scene) {
    if (!scene) return;
    render(scene, 7.5);
    const screenRect = scene.screen.getBoundingClientRect();
    const k = screenRect.width / scene.SW;
    if (!k) return;
    const centre = (element) => {
      const r = element.getBoundingClientRect();
      return [(r.left + r.width / 2 - screenRect.left) / k, (r.top + r.height / 2 - screenRect.top) / k];
    };
    const L = scene.L;
    const x0 = BOARD_LEFT;
    const y0 = BOARD_TOP;
    buildPointerPath(scene, {
      room: centre($('i', scene.rem.room)),
      free: centre(scene.segFree),
      flow: centre(scene.segFlow),
      edit: centre(scene.edit),
      boardMid: [x0 + L.x2 + 0.64 * L.w2, y0 + 0.76 * L.H],
      webMid: [x0 + L.x2 + 0.58 * L.w2, y0 + 0.575 * L.H],
      webEdge: [x0 + L.x2 + 0.5 * L.w2, y0 + L.H],
      pdf: [x0 + L.x3 + L.w3 / 2, y0 + L.ch + L.gap + Math.min(150, L.lh * 0.45)],
      clock: [x0 + L.x1 + 0.576 * L.w1, y0 + 120],
    });
  }

  // ---------------------------------------------------------------------
  // Hold or tap. The same small state machine the app uses.
  // ---------------------------------------------------------------------

  const TAP_THRESHOLD = 300;
  const SHORTCUT = 'Space';
  const keys = $$('[data-key]');
  const pov = $('#pov');
  const povBoard = $('#pov-board');
  const peek = { state: 'hidden', since: 0, where: 'stage' };
  let shortcutHeld = false;
  let keyHeld = false;
  const userOverlay = { u: 0, target: 0, raf: 0, last: 0 };

  function isShortcut(event) {
    return event.code === SHORTCUT && !event.ctrlKey && !event.altKey && !event.shiftKey && !event.metaKey;
  }
  function isTyping(target) {
    return target instanceof HTMLElement
      && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName));
  }

  function setKeysDown(down) {
    keyHeld = down;
    keys.forEach((key) => { if (key !== stageKey) flag(key, 'is-down', down); });
    renderStage();
  }

  function stageVisibility() {
    if (mode !== 'take') return 0;
    const r = stageScene.screen.getBoundingClientRect();
    const visible = Math.min(r.bottom, state.vh) - Math.max(r.top, 0);
    return clamp(visible / Math.max(r.height, 1), 0, 1);
  }

  function shortcutDown() {
    setKeysDown(true);
    if (peek.state === 'hidden' || peek.state === 'releasing') {
      peek.state = 'holding';
      peek.since = performance.now();
      peek.where = stageVisibility() > 0.5 ? 'stage' : 'page';
      showOverlay();
    } else if (peek.state === 'pinned') {
      peek.state = 'releasing';
      hideOverlay();
    }
  }

  function shortcutUp() {
    setKeysDown(false);
    if (peek.state === 'holding') {
      if (performance.now() - peek.since <= TAP_THRESHOLD) {
        peek.state = 'pinned';
        setPinned(true);
      } else {
        peek.state = 'hidden';
        hideOverlay();
      }
    } else if (peek.state === 'releasing') {
      peek.state = 'hidden';
    }
  }

  function dismiss() {
    if (peek.state === 'pinned') { peek.state = 'hidden'; hideOverlay(); }
    else if (peek.state === 'holding') { peek.state = 'releasing'; hideOverlay(); }
  }

  function tweenUser(target) {
    userOverlay.target = target;
    if (calm.matches) { userOverlay.u = target; renderStage(); return; }
    if (userOverlay.raf) return;
    userOverlay.last = performance.now();
    const step = (now) => {
      const d = (now - userOverlay.last) / 140;
      userOverlay.last = now;
      userOverlay.u = userOverlay.target > userOverlay.u ? Math.min(userOverlay.target, userOverlay.u + d) : Math.max(userOverlay.target, userOverlay.u - d);
      renderStage();
      userOverlay.raf = userOverlay.u === userOverlay.target ? 0 : requestAnimationFrame(step);
    };
    userOverlay.raf = requestAnimationFrame(step);
  }

  function showOverlay() {
    floatBox.classList.add('is-used');
    tried = true;
    flag(foot, 'has-tip', false);
    if (peek.where === 'stage') {
      tweenUser(1);
    } else {
      layoutPov();
      pov.classList.add('is-open');
      pov.setAttribute('aria-hidden', 'false');
    }
  }

  function hideOverlay() {
    setPinned(false);
    tweenUser(0);
    pov.classList.remove('is-open');
    pov.setAttribute('aria-hidden', 'true');
  }

  let restoreFocus = null;
  function setPinned(pinned) {
    if (peek.where === 'page') {
      pov.classList.toggle('is-pinned', pinned);
      $$('main, .bar, .footer').forEach((element) => { element.inert = pinned; });
      if (pinned) {
        restoreFocus = document.activeElement;
        pov.focus({ preventScroll: true });
      } else if (restoreFocus && document.contains(restoreFocus)) {
        restoreFocus.focus({ preventScroll: true });
        restoreFocus = null;
      }
    }
    renderStage();
  }

  window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && peek.state !== 'hidden') {
      event.preventDefault();
      dismiss();
      return;
    }
    if (isTyping(event.target)) return;
    if (isShortcut(event)) {
      event.preventDefault(); // Space would otherwise scroll the page
      if (!event.repeat && !shortcutHeld) { shortcutHeld = true; shortcutDown(); }
    }
  }, true);

  window.addEventListener('keyup', (event) => {
    if (!shortcutHeld || event.code !== SHORTCUT) return;
    event.preventDefault(); // or a focused button would be pressed
    shortcutHeld = false;
    shortcutUp();
  }, true);

  // A key-up never arrives if the window loses focus while the key is down.
  window.addEventListener('blur', () => {
    if (!shortcutHeld) return;
    shortcutHeld = false;
    if (peek.state === 'holding') peek.since = -Infinity;
    shortcutUp();
  });

  // The keys on the page work with a mouse or a finger too.
  let pressedKey = null;
  keys.forEach((key) => {
    key.addEventListener('pointerdown', (event) => {
      if (event.button !== 0 || pressedKey) return;
      event.preventDefault();
      key.setPointerCapture(event.pointerId);
      pressedKey = key;
      shortcutDown();
    });
    ['pointerup', 'pointercancel'].forEach((type) => key.addEventListener(type, () => {
      if (pressedKey !== key) return;
      pressedKey = null;
      shortcutUp();
    }));
    key.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') { event.preventDefault(); shortcutDown(); shortcutUp(); }
    });
    key.addEventListener('click', (event) => event.preventDefault());
    key.addEventListener('contextmenu', (event) => event.preventDefault());
  });

  // While Blink is pinned on the screen, its reminders can be ticked and a
  // click outside the tiles closes it.
  stageScene.ov.addEventListener('click', (event) => {
    if (peek.state !== 'pinned') return;
    const item = event.target.closest('.w-rem__item');
    if (item) {
      item.dataset.user = '1';
      item.classList.toggle('is-done');
      renderStage();
      return;
    }
    if (!event.target.closest('.tile, .toolbar')) dismiss();
  });

  // ---- Blink over the page --------------------------------------------------

  povBoard.innerHTML = TILE_ORDER.map(tileHTML).join('');
  if (window.matchMedia('(hover: none)').matches) $('#pov-hint').textContent = 'Tap fn again to close';
  const povTiles = $$('.tile', povBoard);
  povBoard.addEventListener('click', (event) => {
    const item = event.target.closest('.w-rem__item');
    if (!item) return;
    item.classList.toggle('is-done');
    const count = $('[data-rem-count]', povBoard);
    count.textContent = $$('.w-rem__item:not(.is-done)', povBoard).length;
  });
  $$('.w-rem__item', povBoard).forEach((item) => { item.tabIndex = 0; });
  pov.addEventListener('pointerdown', (event) => {
    if (event.target === pov || event.target === povBoard) dismiss();
  });
  $('#pov-close').addEventListener('click', dismiss);

  function layoutPov() {
    const width = povBoard.clientWidth || window.innerWidth - 48;
    const height = povBoard.clientHeight || window.innerHeight - 76;
    const list = window.innerWidth < 760;
    povBoard.classList.toggle('is-list', list);
    if (list) {
      const heights = { clock: 212, reminders: 370, web: 560, calendar: 420, pdf: 420 };
      povTiles.forEach((tile) => { tile.style.height = `${heights[tile.dataset.tile]}px`; tile.style.width = ''; tile.style.transform = ''; });
      return;
    }
    // Flow, as in the app: tiles packed in order into full-height columns.
    const gap = 14;
    const columns = [['clock', 'reminders'], ['web'], ['calendar', 'pdf']];
    const natural = [330, 520, 354];
    const room = width - gap * 2;
    const total = natural.reduce((a, b) => a + b, 0);
    const widths = total > room ? natural.map((w) => w * room / total) : natural;
    let x = Math.max(0, (width - widths.reduce((a, b) => a + b, 0) - gap * 2) / 2);
    const tops = { clock: 212, calendar: Math.min(420, height * 0.52) };
    columns.forEach((column, c) => {
      let y = 0;
      column.forEach((kind, row) => {
        const last = row === column.length - 1;
        const h = last ? height - y : tops[kind];
        const tile = povTiles.find((element) => element.dataset.tile === kind);
        Object.assign(tile.style, { transform: `translate(${Math.round(x)}px, ${Math.round(y)}px)`, width: `${Math.round(widths[c])}px`, height: `${Math.round(h)}px` });
        y += h + gap;
      });
      x += widths[c] + gap;
    });
  }

  // ---------------------------------------------------------------------
  // Start.
  // ---------------------------------------------------------------------

  function refresh() {
    setMode();
    layout();
    if (mode === 'take') { measure(stageScene); measureCaptions(); }
    onFrame();
  }

  updateClocks();
  updateCalendar();
  refresh();
  setInterval(updateClocks, 1000);
  setInterval(updateCalendar, 60000);

  if (document.fonts && document.fonts.ready) document.fonts.ready.then(refresh);

  let resizeTimer = 0;
  window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => { refresh(); if (pov.classList.contains('is-open')) layoutPov(); }, 80);
  });
  calm.addEventListener('change', refresh);

  // For checking the page by script.
  window.__daylight = { peek, scrollForT, get T() { return T; }, get mode() { return mode; }, render: () => onFrame() };
})();
