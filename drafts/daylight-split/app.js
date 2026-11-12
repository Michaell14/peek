// Blink, "Daylight Split" draft.
// The story is a column of short steps that scroll like any page. The screen
// beside them stays put, and whichever step reaches the middle of the window
// plays on it, on a clock. Some steps have a control that drives the screen.
// Hold Space (or press a key on the page) at any point to open Blink yourself.
(() => {
  'use strict';

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));
  const clamp = (v, a, b) => Math.min(Math.max(v, a), b);
  const seg = (t, a, b) => clamp((t - a) / (b - a), 0, 1);
  const lerp = (a, b, p) => a + (b - a) * p;
  const easeInOut = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
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
  // The story, as one timeline T (the same one Daylight scrubs by scroll).
  // Here each step plays a stretch of it on a clock: keys are
  // [milliseconds since the step started, T], straight lines between.
  // ---------------------------------------------------------------------

  const STEPS = [
    { id: 'open', keys: [[0, -0.62], [1900, 0.42], [2300, 0.9]] },
    { id: 'detour', keys: [[0, 0.9], [300, 1.0], [4700, 2.0], [5100, 2.08]] },
    { id: 'hold', keys: [[0, 2.08], [260, 2.12], [720, 2.42], [2700, 3.06], [2900, 3.14], [3300, 3.2], [4100, 3.4], [4400, 3.5]] },
    { id: 'websites', keys: [[0, 3.5], [450, 4.04], [700, 4.12], [1700, 4.38], [3100, 4.74], [3300, 4.78], [4500, 4.97]] },
    { id: 'widgets', keys: [[0, 4.97], [800, 5.2], [1700, 5.42], [3300, 5.8]] },
    { id: 'files', keys: [[0, 5.8], [700, 6.0], [1500, 6.4], [2300, 6.6], [2500, 6.64], [3700, 6.85]] },
    { id: 'tap', keys: [[0, 6.85], [450, 7.0], [800, 7.11], [900, 7.17], [1200, 7.27], [1900, 7.42], [2200, 7.5], [2700, 7.62], [4300, 7.98], [4500, 8.0]] },
    { id: 'arrange', keys: [[0, 8.0], [600, 8.09], [1000, 8.16], [1300, 8.2], [1900, 8.31], [2300, 8.37], [2900, 8.48], [3300, 8.54], [3900, 8.65], [4300, 8.71], [4700, 8.77], [4900, 8.79], [5600, 8.93], [5800, 8.95]] },
    { id: 'full-screen', keys: [[0, 8.95], [350, 9.08], [600, 9.12], [1700, 9.42], [2300, 9.55], [2450, 9.62], [3700, 9.88], [3900, 9.93], [4400, 10]] },
  ];
  // Short replays that a control starts.
  const MINI = {
    reload: [[0, 4.6], [900, 4.74], [1100, 4.78], [2300, 4.97]],
    save: [[0, 6.5], [600, 6.6], [700, 6.64], [1600, 6.85]],
  };

  const OVERLAY = [[-2, 0], [2.12, 0], [2.4, 1], [3.06, 1], [3.12, 0], [4.04, 0], [4.1, 1], [6.94, 1], [7.0, 0], [7.12, 0], [7.17, 1], [9.03, 1], [9.08, 0], [9.56, 0], [9.62, 1], [9.88, 1], [9.93, 0]];
  const KEY_DOWN = [[2.1, 3.06], [4.03, 6.94], [7.11, 7.15], [9.02, 9.05], [9.55, 9.88]];
  const STRIP = [[7.17, 0], [7.23, 1], [9.03, 1], [9.07, 0]];

  const TEXT_A = 'Since the new page went live, we are at';
  const TEXT_B = ' 368.';
  const TYPE_A = [[-0.62, 0], [0.42, TEXT_A.length]];
  const TYPE_B = [[3.2, 0], [3.4, TEXT_B.length]];

  // Clicking around to check things: which window comes forward, and when.
  const FRONT = [[1.18, 'cal'], [1.43, 'mail'], [1.67, 'web'], [1.92, 'writer']];
  const APP_NAME = { writer: 'Writer', cal: 'Calendar', mail: 'Mail', web: 'Browser' };
  const DOCK_X = { files: 495, writer: 553, cal: 611, mail: 669, web: 727, settings: 785 };
  const DOCK_Y = 761;

  // Camera: [zoom, x, y] where (x, y) is the point of the screen to centre on.
  const CAMERA = [[4.12, [1, 640, 400]], [4.38, [1.42, 628, 330]], [4.92, [1.42, 628, 330]], [5.12, [1, 640, 400]]];

  // Tile frames on the board, [x, y, w, h], in screen pixels.
  // Arranging: in Freeform, resize the page, move the file, move the clock.
  // Back in Flow, the tiles are packed into columns read off where they now
  // are, as the app does (packFlow below gives the same result).
  const FRAMES = {
    clock: [[8.54, [0, 0, 330, 212]], [8.64, [902, 394, 330, 212]], [8.79, [902, 394, 330, 212]], [8.93, [878, 474, 354, 256]]],
    reminders: [[8.79, [0, 226, 330, 504]], [8.93, [0, 0, 330, 730]]],
    web: [[8.2, [344, 0, 520, 730]], [8.3, [344, 0, 520, 380]]],
    calendar: [[6.1, [878, 0, 354, 730]], [6.36, [878, 0, 354, 380]], [8.79, [878, 0, 354, 380]], [8.93, [878, 0, 354, 460]]],
    pdf: [[6.14, [878, 780, 354, 336]], [6.4, [878, 394, 354, 336]], [8.37, [878, 394, 354, 336]], [8.47, [344, 394, 354, 336]], [8.79, [344, 394, 354, 336]], [8.93, [344, 394, 520, 336]]],
  };
  const BOARD_W = 1232;
  const BOARD_H = 730;
  const GAP = 14;
  const HELD = { web: [8.2, 8.31], pdf: [8.37, 8.48], clock: [8.54, 8.65] };
  const TILE_ORDER = ['clock', 'reminders', 'web', 'calendar', 'pdf'];

  // The pointer, in two acts. Points that depend on layout are measured.
  const P = {};
  let POINTER = [];
  const POINTER_SHOWN = [[0.98, 0], [1.02, 1], [2.0, 1], [2.06, 0], [7.22, 0], [7.27, 1], [8.88, 1], [8.94, 0]];
  const CLICKS = [1.18, 1.43, 1.67, 1.92, 7.45, 8.09, 8.16, 8.71, 8.77];

  function buildPointerPath() {
    POINTER = [
      [1.0, [560, 470]],
      [1.15, [DOCK_X.cal, DOCK_Y]], [1.21, [DOCK_X.cal, DOCK_Y]],
      [1.4, [DOCK_X.mail, DOCK_Y]], [1.46, [DOCK_X.mail, DOCK_Y]],
      [1.64, [DOCK_X.web, DOCK_Y]], [1.7, [DOCK_X.web, DOCK_Y]],
      [1.8, [800, 352]], [1.84, [800, 352]],
      [1.9, [DOCK_X.writer, DOCK_Y]], [1.94, [DOCK_X.writer, DOCK_Y]],
      [2.04, [620, 500]],
      [7.22, P.boardMid], [7.42, P.room], [7.5, P.room],
      [7.62, P.webMid], [7.98, P.webMid],
      [8.07, P.free], [8.1, P.free],
      [8.14, P.edit], [8.17, P.edit],
      [8.19, P.webEdge], [8.2, P.webEdge], [8.3, [P.webEdge[0], 46 + 380]], [8.31, [P.webEdge[0], 46 + 380]],
      [8.36, P.pdf], [8.37, P.pdf], [8.47, [P.pdf[0] - 534, P.pdf[1]]], [8.48, [P.pdf[0] - 534, P.pdf[1]]],
      [8.53, P.clock], [8.54, P.clock], [8.64, [P.clock[0] + 902, P.clock[1] + 394]], [8.65, [P.clock[0] + 902, P.clock[1] + 394]],
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
  // Each "Reload now" brings slightly newer numbers.
  function webValues(n) {
    if (n <= 0) return WEB_VALUES.before;
    if (n === 1) return WEB_VALUES.after;
    const extra = n - 1;
    return {
      ...WEB_VALUES.after,
      visitors: (12536 + extra * 21 + (extra % 3) * 4).toLocaleString('en-US'),
      signups: String(371 + extra),
      visit: `2m ${44 + (extra % 3)}s`,
    };
  }

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
      screen: q('.screen'),
      desk: q('.desk'),
      cam: display.closest('.cam'),
      wins: {},
      dockIcons: {},
      appName: q('[data-app-name]'),
      mbBlink: q('[data-mb-blink]'),
      menubar: q('.menubar'),
      dock: q('.dock'),
      typedA: $$('[data-typed="a"]', display),
      typedB: $$('[data-typed="b"]', display),
      full: q('[data-full]'),
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
    scenes.push(scene);
    return scene;
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
  // visitor; `pinned` means they tapped and it stays. `script` (0 to 1) lets
  // the story's own Blink step aside once the visitor has taken over;
  // `reloads` counts "Reload now"; `layout` is a board the visitor arranged.
  function render(scene, T, { user = 0, pinned = false, still = false, script = 1, reloads = 0, layout = null } = {}) {
    const custom = layout && T >= 7.99 ? layout : null;
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

    // Full screen.
    const fullP = track([[9.12, 0], [9.42, 1]], T);
    const fullO = track([[9.12, 0], [9.2, 1]], T, linear);
    css(scene, scene.full, 'visibility', fullO > 0 ? 'visible' : 'hidden');
    css(scene, scene.full, 'opacity', fullO.toFixed(3));
    const inset = [62, 410, 126, 170].map((v) => lerp(v, 0, fullP));
    css(scene, scene.full, 'clip-path', `inset(${inset.map(px).join(' ')} round ${px(lerp(12, 0, fullP))})`);
    const chrome = track([[9.12, 0], [9.26, 1]], T);
    css(scene, scene.menubar, 'transform', `translateY(${px(-30 * chrome)})`);
    css(scene, scene.dock, 'transform', `translateX(-50%) translateY(${px(90 * chrome)})`);

    // Blink.
    const sceneOverlay = track(OVERLAY, T, linear) * script;
    const overlay = Math.max(sceneOverlay, user);
    css(scene, scene.ov, 'opacity', overlay.toFixed(3));
    css(scene, scene.ov, 'visibility', overlay > 0.001 ? 'visible' : 'hidden');
    flag(scene.ov, 'is-live', pinned);
    flag(scene.mbBlink, 'is-on', overlay > 0.5);
    if (still) flag(scene.desk, 'is-blurred', overlay > 0.5);
    const bloom = T > 2 && T < 2.6 ? track([[2.12, 0.965], [2.42, 1]], T) : 0.985 + 0.015 * overlay;
    css(scene, scene.board, 'transform', `scale(${(user > sceneOverlay ? 0.985 + 0.015 * user : bloom).toFixed(4)})`);
    css(scene, scene.strip, 'opacity', Math.max(track(STRIP, T, linear) * script, pinned ? 1 : 0).toFixed(3));

    // Arranging.
    const freeform = custom ? custom.mode === 'free' : T >= 8.09 && T < 8.77;
    const editing = custom ? custom.mode === 'free' && custom.editing : T >= 8.16 && T < 8.71;
    flag(scene.segFlow, 'is-on', !freeform);
    flag(scene.segFree, 'is-on', freeform);
    flag(scene.board, 'is-editing', editing);
    flag(scene.edit, 'is-on', editing);
    text(scene.edit, editing ? 'Done' : 'Edit');
    text(scene.stripHint, editing ? (custom ? 'Drag a tile to move it' : 'Drag a tile to move it, or its edge to resize') : 'fn or esc to close');
    flag(scene.ov, 'is-arranging', !!(custom && editing && overlay > 0.5));

    // Tiles.
    TILE_ORDER.forEach((kind, index) => {
      const element = scene.tiles[kind];
      if (!element) return;
      const [x, y, w, h] = custom ? custom.frames[kind] : track(FRAMES[kind], T);
      let opacity = 1;
      let lift = 0;
      if (T > 2.05 && T < 2.5 && user <= sceneOverlay) {
        const o = seg(T, 2.14 + index * 0.035, 2.28 + index * 0.035);
        opacity = o;
        lift = (1 - o) * 12;
      }
      if (kind === 'pdf') opacity = track([[6.14, 0], [6.24, 1]], T, linear);
      css(scene, element, 'transform', `translate(${px(x)}, ${px(y + lift)})`);
      css(scene, element, 'width', px(w));
      css(scene, element, 'height', px(h));
      css(scene, element, 'opacity', opacity.toFixed(3));
      css(scene, element, 'visibility', opacity > 0.001 ? 'visible' : 'hidden');
      const held = HELD[kind];
      flag(element, 'is-held', custom ? custom.held === kind : !!held && T >= held[0] && T < held[1]);
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
    const values = webValues(refreshed ? reloads + 1 : reloads);
    for (const [key, element] of Object.entries(scene.values)) {
      text(element, values[key]);
      if (element.tagName === 'B') flag(element, 'is-new', refreshed && T < 4.96);
    }
    css(scene, scene.lastBar, 'transform', `scaleY(${track([[4.76, 0.9], [4.86, 1]], T).toFixed(3)})`);
    const scroll = track([[7.66, 0], [7.78, -120], [7.86, -120], [7.98, 0]], T);
    css(scene, scene.webBody, 'transform', `translateY(${px(scroll)})`);

    // The file that changes on disk.
    flag(scene.pdf, 'is-updated', T >= 6.62);

    // Now, on the calendar.
    if (scene.calNow) {
      const pulse = T > 5.45 && T < 6 ? ((T - 5.45) / 0.18) % 1 : 1;
      css(scene, scene.calNow, '--pulse-s', (0.4 + pulse * 1.6).toFixed(3));
      css(scene, scene.calNow, '--pulse-o', (T > 5.45 && T < 6 ? 0.9 * (1 - pulse) : 0).toFixed(3));
    }

    // The pointer.
    if (POINTER.length) {
      const shown = track(POINTER_SHOWN, T, linear) * (still && !(T > 1 && T < 2.05) && !(T > 7.2 && T < 9) ? 0 : 1) * (custom ? 0 : script);
      const [x, y] = track(POINTER, T);
      const click = CLICKS.some((t) => Math.abs(T - t) < 0.012) || Object.values(HELD).some(([a, b]) => T >= a && T < b);
      css(scene, scene.pointer, 'opacity', shown.toFixed(3));
      css(scene, scene.pointer, 'transform', `translate(${px(x)}, ${px(y)}) scale(${click ? 0.86 : 1})`);
    }

    // The camera.
    const [zoom, cx, cy] = track(CAMERA, T);
    const dx = -(cx - 640) * scene.fit * zoom;
    const dy = -(cy - 400) * scene.fit * zoom;
    css(scene, scene.cam, 'transform', zoom === 1 ? 'none' : `translate(${px(dx)}, ${px(dy)}) scale(${zoom.toFixed(4)})`);
  }

  // ---------------------------------------------------------------------
  // The page.
  // ---------------------------------------------------------------------

  const root = document.documentElement;
  const bar = $('#bar');
  const openMark = $('.open__mark');
  const lens = $('#lens');
  const cam = $('#cam');
  const display = $('#display');
  const blocks = $$('#story .block');
  const footKey = $('.foot .fnkey');
  const getKey = $('.get .fnkey');
  const calm = window.matchMedia('(prefers-reduced-motion: reduce)');
  const stepIndex = (id) => STEPS.findIndex((step) => step.id === id);
  const TAP = stepIndex('tap');
  const ARRANGE = stepIndex('arrange');

  // Build the board in the picture, then the scene that drives it.
  $('[data-board]', display).innerHTML = TILE_ORDER.map(tileHTML).join('');
  $('[data-slot="web"]', display).innerHTML = RENDER.web()
    .replace(/<div class="w-hover"[\s\S]*?<\/span>\s*<\/div>/, '')
    .replace(/ data-[a-z-]+(="[^"]*")?/g, '');
  const stageScene = makeScene(display);

  let T = STEPS[0].keys[0][1];
  let active = -1;
  let scriptOv = 1;          // 0 once the visitor has the tapped-open Blink
  let reloads = 0;
  let layoutState = null;    // { mode: 'free' | 'flow', editing, frames, held }
  let needCut = false;
  const state = { vh: window.innerHeight, phone: false, stickyBottom: 0 };

  // ---- Size ------------------------------------------------------------------

  function layout() {
    const vw = root.clientWidth;
    const vh = window.innerHeight;
    const barH = 60;
    state.vh = vh;
    state.phone = vw < 900;
    let dw;
    if (!state.phone) {
      const gutter = vw >= 1200 ? 40 : 28;
      const wrap = Math.min(vw - 2 * gutter, 1720);
      const colgap = clamp(vw * 0.046, 40, 80);
      const foot = 64;
      dw = Math.min(Math.round(vw * 0.6), wrap - colgap - 340, 1180, (vh - barH - 40 - foot) * 1300 / 820);
      const dh = dw * 820 / 1300;
      root.style.setProperty('--colgap', `${Math.round(colgap)}px`);
      root.style.setProperty('--st', `${Math.round(barH + Math.max(16, (vh - barH - dh - foot) / 2))}px`);
      root.style.removeProperty('--bh');
    } else {
      dw = vw - 32;
      const dh = dw * 820 / 1300;
      state.stickyBottom = barH + 4 + dh;
      root.style.removeProperty('--colgap');
      root.style.removeProperty('--st');
      root.style.setProperty('--bh', `${Math.round(Math.max(300, (vh - state.stickyBottom) * 0.8))}px`);
    }
    dw = Math.floor(dw);
    root.style.setProperty('--dw', `${dw}px`);
    root.style.setProperty('--dh', `${Math.round(dw * 820 / 1300)}px`);
    root.style.setProperty('--f', (dw / 1300).toFixed(5));
    stageScene.fit = dw / 1300;
  }

  // The line a step has to cross to become the one that plays.
  function lineY() {
    if (!state.phone) return state.vh * 0.5;
    return state.stickyBottom + (state.vh - state.stickyBottom) * 0.45;
  }

  function stepAtLine() {
    const line = lineY();
    for (let i = blocks.length - 1; i > 0; i -= 1) {
      if (blocks[i].getBoundingClientRect().top <= line) return i;
    }
    return 0;
  }

  // ---- Playing ---------------------------------------------------------------

  const player = { keys: null, step: -1, start: 0, total: 0, playing: false, mini: false };
  let loopFrame = 0;
  const kick = () => { if (!loopFrame) loopFrame = requestAnimationFrame(loop); };

  function setProgress(k, p) {
    const fill = blocks[k] && $('.block__line i', blocks[k]);
    if (fill) fill.style.transform = `scaleX(${p.toFixed(4)})`;
  }

  function playKeys(keys, { step = active, mini = false } = {}) {
    player.keys = keys;
    player.step = step;
    player.mini = mini;
    player.total = keys[keys.length - 1][0];
    player.start = performance.now();
    if (calm.matches) {
      T = keys[keys.length - 1][1];
      player.playing = false;
      finished();
      renderStage();
      return;
    }
    T = keys[0][1];
    player.playing = true;
    if (!mini) setProgress(step, 0);
    kick();
  }

  function stopPlaying() {
    if (!player.playing) return;
    player.playing = false;
    if (!player.mini) setProgress(player.step, 1);
  }

  function finished() {
    if (!player.mini) setProgress(player.step, 1);
    if (player.step === TAP && active === TAP && !player.mini) handOver();
  }

  // Flow packing, tweened.
  const pack = { from: null, to: null, start: 0, on: false };

  function loop(now) {
    loopFrame = 0;
    let again = false;
    if (player.playing) {
      const elapsed = now - player.start;
      T = track(player.keys, elapsed, linear);
      if (!player.mini) setProgress(player.step, clamp(elapsed / player.total, 0, 1));
      if (elapsed >= player.total) {
        player.playing = false;
        finished();
      } else {
        again = true;
      }
    }
    if (pack.on && layoutState) {
      const p = clamp((now - pack.start) / 520, 0, 1);
      const e = easeInOut(p);
      for (const kind of TILE_ORDER) layoutState.frames[kind] = mix(pack.from[kind], pack.to[kind], e);
      if (p >= 1) pack.on = false; else again = true;
    }
    renderStage();
    if (again) kick();
  }

  // A soft cut when the screen jumps to a different moment.
  function cut() {
    if (calm.matches || !cam.animate) return;
    cam.animate([{ filter: 'blur(10px)', opacity: 0.55 }, { filter: 'blur(0px)', opacity: 1 }], { duration: 420, easing: 'cubic-bezier(0.2, 0.7, 0.2, 1)' });
  }

  // Leaving a step tidies up what the visitor did in it.
  function leave(k) {
    if (k < 0) return;
    if (peek.where === 'stage' && peek.state === 'pinned') {
      peek.state = 'hidden';
      hideOverlay();
    }
    if (k === TAP && scriptOv === 0) {
      if (userOverlay.u < 0.5) needCut = true;
      scriptOv = 1;
    }
    if (k === ARRANGE && layoutState) layoutState.editing = false;
  }

  // Play step k from its start.
  function startStep(k) {
    const keys = STEPS[k].keys;
    if (k === TAP) {
      scriptOv = 1;
      if (peek.where === 'stage' && peek.state === 'pinned') { peek.state = 'hidden'; hideOverlay(true); }
    }
    if (k === ARRANGE && layoutState) { layoutState = null; needCut = true; }
    if (needCut || Math.abs(T - keys[0][1]) > 0.02) cut();
    needCut = false;
    playKeys(keys, { step: k });
  }

  // Show step k as it ends, at once.
  function showEnd(k) {
    const keys = STEPS[k].keys;
    const to = keys[keys.length - 1][1];
    player.playing = false;
    if (needCut || Math.abs(T - to) > 0.02) cut();
    needCut = false;
    T = to;
    player.step = k;
    player.mini = false;
    finished();
    renderStage();
  }

  let pendingPlay = 0;
  function activate(k, how) {
    if (k !== active) {
      const previous = active;
      active = k;
      blocks.forEach((block, i) => {
        flag(block, 'is-on', i === k);
        if (i !== k) setProgress(i, 0);
      });
      leave(previous);
    }
    clearTimeout(pendingPlay);
    if (how === 'play') startStep(k);
    else if (how === 'end') showEnd(k);
    else if (how === 'soon') pendingPlay = setTimeout(() => startStep(k), calm.matches ? 0 : 140);
    renderStage();
  }

  // ---- Scrolling ---------------------------------------------------------------

  let lockUntil = 0;
  function scrollToStep(k, force = false) {
    if (!force && stepAtLine() === k) return;
    const rect = blocks[k].getBoundingClientRect();
    const top = k === 0 ? 0 : window.scrollY + rect.top + rect.height / 2 - lineY();
    lockUntil = performance.now() + 1200;
    window.scrollTo({ top: Math.max(0, top), behavior: calm.matches ? 'auto' : 'smooth' });
  }
  function goTo(k, how, force = false) {
    scrollToStep(k, force);
    activate(k, how);
  }
  window.addEventListener('scrollend', () => { lockUntil = 0; requestFrame(); });

  function onFrame() {
    frame = 0;
    const scrolled = window.scrollY;
    flag(bar, 'is-past', scrolled > openMark.offsetTop + openMark.offsetHeight * 0.7 - 60);
    if (performance.now() > lockUntil) {
      const k = stepAtLine();
      if (k !== active) activate(k, 'soon');
    }
    if (peek.state === 'pinned' && peek.where === 'stage' && stageVisibility() < 0.4) dismiss();
  }
  let frame = 0;
  const requestFrame = () => { if (!frame) frame = requestAnimationFrame(onFrame); };
  window.addEventListener('scroll', requestFrame, { passive: true });

  // ---- Drawing the screen and the controls -------------------------------------

  const tapLabel = $('[data-tap-label]');
  const tapNote = $('[data-tap-note]');
  const dragNote = $('[data-drag-note]');
  const flowButton = $('[data-ctl="flow"]');
  const freeButton = $('[data-ctl="free"]');

  function renderStage() {
    render(stageScene, T, {
      user: userOverlay.u,
      pinned: peek.state === 'pinned' && peek.where === 'stage',
      script: scriptOv,
      reloads,
      layout: layoutState,
    });
    paintControls();
  }

  function setPressed(button, on) {
    const value = String(on);
    if (button.getAttribute('aria-pressed') !== value) button.setAttribute('aria-pressed', value);
  }

  function paintControls() {
    // Keys go down when the story holds fn, and when the visitor does.
    const ghost = scriptOv > 0 && within(T, KEY_DOWN) && peek.state === 'hidden';
    flag(footKey, 'is-down', ghost || keyHeld);
    $$('.block [data-key]').forEach((key) => {
      const mine = blocks[active] && blocks[active].contains(key);
      flag(key, 'is-down', pressedKey === key || (mine && (ghost || (keyHeld && !pressedKey))));
    });
    flag(getKey, 'is-down', pressedKey === getKey || (keyHeld && !pressedKey && peek.where === 'page'));

    // Tap: says what a tap would do now.
    const open = active === TAP && (scriptOv === 0
      ? peek.where === 'stage' && peek.state !== 'hidden'
      : track(OVERLAY, T, linear) > 0.5);
    text(tapLabel, open ? 'Tap to close' : 'Tap to keep it open');
    flag(tapNote, 'is-shown', open && scriptOv === 0 && peek.state === 'pinned');

    // Flow or Freeform: follows the screen.
    const free = layoutState ? layoutState.mode === 'free' : T >= 8.09 && T < 8.77;
    setPressed(flowButton, !free);
    setPressed(freeButton, free);
    flag(dragNote, 'is-shown', !!(layoutState && layoutState.mode === 'free' && layoutState.editing && active === ARRANGE));
  }

  // ---- Tap: once the story has tapped Blink open, it is the visitor's --------

  function handOver() {
    scriptOv = 0;
    if (peek.state === 'hidden') {
      peek.state = 'pinned';
      peek.where = 'stage';
      userOverlay.u = 1;
      userOverlay.target = 1;
    }
    renderStage();
  }
  // If the visitor reaches for fn while the tap step is still playing.
  function takeOverTap() {
    if (active !== TAP || scriptOv === 0 || stageVisibility() <= 0.5) return;
    const open = track(OVERLAY, T, linear) > 0.5;
    stopPlaying();
    scriptOv = 0;
    if (open && peek.state === 'hidden') {
      peek.state = 'pinned';
      peek.where = 'stage';
      userOverlay.u = 1;
      userOverlay.target = 1;
    }
  }

  // ---- Arrange: Freeform lets you drag the tiles on the screen ---------------

  function framesAt(t) {
    const frames = {};
    TILE_ORDER.forEach((kind) => { frames[kind] = track(FRAMES[kind], t).slice(); });
    return frames;
  }

  // Columns read off where the tiles are, then packed to full height.
  function packFlow(frames) {
    const items = TILE_ORDER.map((kind) => ({ kind, f: frames[kind] }))
      .sort((a, b) => (a.f[0] + a.f[2] / 2) - (b.f[0] + b.f[2] / 2));
    const columns = [];
    items.forEach((item) => {
      const cx = item.f[0] + item.f[2] / 2;
      const column = columns.find((c) => cx >= c.x && cx <= c.x + c.w);
      if (column) {
        column.items.push(item);
        column.w = Math.max(column.w, item.f[2]);
      } else {
        columns.push({ x: item.f[0], w: item.f[2], items: [item] });
      }
    });
    columns.sort((a, b) => a.x - b.x);
    const widths = columns.map((c) => Math.max(...c.items.map((item) => item.f[2])));
    const room = BOARD_W - GAP * (columns.length - 1);
    const scale = Math.min(1, room / widths.reduce((a, b) => a + b, 0));
    const out = {};
    let x = 0;
    columns.forEach((column, c) => {
      const w = widths[c] * scale;
      column.items.sort((a, b) => a.f[1] - b.f[1]);
      const total = column.items.reduce((s, item) => s + item.f[3], 0);
      const free = BOARD_H - GAP * (column.items.length - 1);
      let y = 0;
      column.items.forEach((item, j) => {
        const h = j === column.items.length - 1 ? BOARD_H - y : Math.round(free * item.f[3] / total);
        out[item.kind] = [Math.round(x), Math.round(y), Math.round(w), Math.round(h)];
        y += h + GAP;
      });
      x += w + GAP;
    });
    return out;
  }

  function snap(value, size, limit, others) {
    const candidates = [0, limit - size];
    others.forEach(([start, length]) => candidates.push(start, start + length + GAP, start - GAP - size, start + length - size));
    let best = value;
    let distance = 16;
    candidates.forEach((c) => {
      const d = Math.abs(c - value);
      if (d < distance) { distance = d; best = c; }
    });
    return clamp(best, 0, limit - size);
  }

  function toFreeform() {
    if (layoutState && layoutState.mode === 'free') { layoutState.editing = true; renderStage(); return; }
    stopPlaying();
    // Switching keeps every tile where it is.
    const frames = layoutState ? layoutState.frames : framesAt(T);
    layoutState = { mode: 'free', editing: true, frames, held: null };
    renderStage();
  }

  function toFlow() {
    if (!layoutState) {
      if (player.playing) { player.playing = false; showEnd(ARRANGE); }
      return;
    }
    if (layoutState.mode === 'flow') return;
    const target = packFlow(layoutState.frames);
    layoutState.mode = 'flow';
    layoutState.editing = false;
    layoutState.held = null;
    if (calm.matches) {
      layoutState.frames = target;
      renderStage();
      return;
    }
    pack.from = {};
    TILE_ORDER.forEach((kind) => { pack.from[kind] = layoutState.frames[kind].slice(); });
    pack.to = target;
    pack.start = performance.now();
    pack.on = true;
    kick();
  }

  const drag = { kind: null, id: 0, x: 0, y: 0, frame: null, k: 1 };
  stageScene.board.addEventListener('pointerdown', (event) => {
    if (!layoutState || layoutState.mode !== 'free' || !layoutState.editing) return;
    const tile = event.target.closest('.tile');
    if (!tile || event.button !== 0) return;
    event.preventDefault();
    tile.setPointerCapture(event.pointerId);
    drag.kind = tile.dataset.tile;
    drag.id = event.pointerId;
    drag.x = event.clientX;
    drag.y = event.clientY;
    drag.frame = layoutState.frames[drag.kind].slice();
    drag.k = stageScene.screen.getBoundingClientRect().width / 1280 || 1;
    layoutState.held = drag.kind;
    renderStage();
  });
  stageScene.board.addEventListener('pointermove', (event) => {
    if (!drag.kind || event.pointerId !== drag.id || !layoutState) return;
    const [x0, y0, w, h] = drag.frame;
    const others = TILE_ORDER.filter((kind) => kind !== drag.kind).map((kind) => layoutState.frames[kind]);
    const x = snap(x0 + (event.clientX - drag.x) / drag.k, w, BOARD_W, others.map((f) => [f[0], f[2]]));
    const y = snap(y0 + (event.clientY - drag.y) / drag.k, h, BOARD_H, others.map((f) => [f[1], f[3]]));
    layoutState.frames[drag.kind] = [x, y, w, h];
    kick();
  });
  ['pointerup', 'pointercancel'].forEach((type) => stageScene.board.addEventListener(type, (event) => {
    if (!drag.kind || event.pointerId !== drag.id) return;
    drag.kind = null;
    if (layoutState) layoutState.held = null;
    renderStage();
  }));

  // ---- The other controls -------------------------------------------------------

  const REM_ORDER = ['invoice', 'room', 'sam', 'plants', 'dentist'];
  function tickOne() {
    const rem = stageScene.rem;
    const next = REM_ORDER.find((key) => !rem[key].classList.contains('is-done'));
    REM_ORDER.forEach((key) => { rem[key].dataset.user = '1'; });
    if (next) rem[next].classList.add('is-done');
    else REM_ORDER.forEach((key) => rem[key].classList.remove('is-done'));
    renderStage();
  }

  // A control in a step that is not playing yet brings that step in first.
  function own(block) {
    const k = blocks.indexOf(block);
    if (k !== active) {
      scrollToStep(k);
      activate(k, 'end');
    }
    return k;
  }

  const ACTIONS = {
    reload() { stopPlaying(); reloads += 1; playKeys(MINI.reload, { mini: true }); },
    save() { stopPlaying(); playKeys(MINI.save, { mini: true }); },
    tick() { if (player.playing) showEnd(active); tickOne(); },
    free() { toFreeform(); },
    flow() { toFlow(); },
  };
  $$('[data-ctl]').forEach((control) => {
    const action = ACTIONS[control.dataset.ctl];
    if (!action) return;
    control.addEventListener('click', () => {
      own(control.closest('.block'));
      action();
    });
  });

  blocks.forEach((block, k) => {
    $('.replay', block)?.addEventListener('click', () => goTo(k, 'play'));
    if (k === 0) return;
    block.addEventListener('click', (event) => {
      if (event.target.closest('button, a, .switch')) return;
      if (String(window.getSelection && window.getSelection())) return;
      if (k === active && player.playing && player.step === k) return;
      goTo(k, 'play');
    });
  });

  // Tabbing into a step plays it, as scrolling to it would.
  let lastPointer = 0;
  document.addEventListener('pointerdown', () => { lastPointer = performance.now(); }, true);
  blocks.forEach((block, k) => block.addEventListener('focusin', () => {
    if (performance.now() - lastPointer < 800 || k === active) return;
    goTo(k, 'play', true);
  }));

  // ---- Measuring points the pointer goes to --------------------------------

  function measure() {
    const scene = stageScene;
    render(scene, 7.5);
    const screenRect = scene.screen.getBoundingClientRect();
    const k = screenRect.width / 1280;
    if (!k) return;
    const centre = (element) => {
      const r = element.getBoundingClientRect();
      return [(r.left + r.width / 2 - screenRect.left) / k, (r.top + r.height / 2 - screenRect.top) / k];
    };
    P.room = centre($('i', scene.rem.room));
    P.free = centre(scene.segFree);
    P.flow = centre(scene.segFlow);
    P.edit = centre(scene.edit);
    P.boardMid = [700, 600];
    P.webMid = [24 + 344 + 300, 46 + 420];
    P.webEdge = [24 + 344 + 260, 46 + 730];
    P.pdf = [24 + 878 + 177, 46 + 394 + 150];
    P.clock = [24 + 190, 46 + 120];
    buildPointerPath();
    renderStage();
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
  let pressedKey = null;
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
    renderStage();
  }

  function stageVisibility() {
    const r = lens.getBoundingClientRect();
    const visible = Math.min(r.bottom, state.vh) - Math.max(r.top, 0);
    return clamp(visible / Math.max(r.height, 1), 0, 1);
  }

  function shortcutDown() {
    takeOverTap();
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
    renderStage();
  }

  function dismiss() {
    if (peek.state === 'pinned') { peek.state = 'hidden'; hideOverlay(); }
    else if (peek.state === 'holding') { peek.state = 'releasing'; hideOverlay(); }
  }

  function tweenUser(target, instant = false) {
    userOverlay.target = target;
    if (calm.matches || instant) {
      userOverlay.u = target;
      cancelAnimationFrame(userOverlay.raf);
      userOverlay.raf = 0;
      renderStage();
      return;
    }
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
    if (peek.where === 'stage') {
      tweenUser(1);
    } else {
      layoutPov();
      pov.classList.add('is-open');
      pov.setAttribute('aria-hidden', 'false');
    }
  }

  function hideOverlay(instant = false) {
    setPinned(false);
    tweenUser(0, instant);
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
    if (event.key === 'Escape' && (peek.state !== 'hidden' || (active === TAP && scriptOv > 0 && track(OVERLAY, T, linear) > 0.5))) {
      event.preventDefault();
      takeOverTap();
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
  keys.forEach((key) => {
    key.addEventListener('pointerdown', (event) => {
      if (event.button !== 0 || pressedKey) return;
      event.preventDefault();
      const block = key.closest('.block');
      if (block && blocks.indexOf(block) !== active) {
        const k = own(block);
        // The tap step ends with Blink already open, which is what this asked for.
        if (k === TAP) return;
      }
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
    if (peek.state !== 'pinned' || peek.where !== 'stage') return;
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
    layout();
    measure();
    onFrame();
  }

  updateClocks();
  updateCalendar();
  layout();
  measure();
  activate(stepAtLine(), 'play');
  onFrame();
  setInterval(updateClocks, 1000);
  setInterval(updateCalendar, 60000);

  if (document.fonts && document.fonts.ready) document.fonts.ready.then(refresh);

  let resizeTimer = 0;
  window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => { refresh(); if (pov.classList.contains('is-open')) layoutPov(); }, 80);
  });
  calm.addEventListener('change', () => { refresh(); showEnd(active); });

  // For checking the page by script.
  window.__split = {
    peek,
    get T() { return T; },
    get active() { return active; },
    get playing() { return player.playing; },
    get layout() { return layoutState; },
    goTo,
    stepScrollTop(k) {
      const rect = blocks[k].getBoundingClientRect();
      return k === 0 ? 0 : window.scrollY + rect.top + rect.height / 2 - lineY();
    },
  };
})();
