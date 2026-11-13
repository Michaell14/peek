// Blink's website.
// The opening scrolls like any page, and the screen rises into place. From
// there the story plays on it one step per scroll: each scroll gesture plays
// the next step through and rests there, and the page scrolls freely again
// after the last one. Hold Space (or press the ⌥`
// keys on screen) at any point to open Blink yourself.
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

  const DMG = 'https://github.com/Michaell14/peek/releases/latest/download/Blink.dmg';
  void DMG;

  // ---------------------------------------------------------------------
  // The story, as a timeline. Beat k runs from T = k - 1 to T = k.
  // Before the screen pins, T runs from -1 up to 0.
  // ---------------------------------------------------------------------

  // How far you scroll through each beat, in viewport heights.
  const LENGTHS = [0.62, 1.1, 0.95, 0.85, 1.15, 1.0, 1.0, 1.0, 1.4, 1.15];
  // Where each beat's still sits, for phones and reduced motion.
  const STILLS = [0.92, 1.82, 2.75, 3.8, 4.9, 5.74, 6.85, 7.56, 8.74, 9.75];
  // When each caption fills, as a fraction of its beat.
  const FILL = [[-0.3, 0.35], [0.03, 0.45], [0.02, 0.36], [0.02, 0.42], [0.03, 0.5], [0.03, 0.62], [0.03, 0.5], [0.02, 0.42], [0.03, 0.5], [0.03, 0.45]];

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
  // Arranging (beat 9), in columns as the app does it: pull the page's edge
  // in (the row stays centred, so every column shifts), then lift the PDF
  // above the calendar in its column.
  const FRAMES = {
    clock: [[8.2, [0, 0, 330, 212]], [8.3, [50, 0, 330, 212]]],
    reminders: [[8.2, [0, 226, 330, 504]], [8.3, [50, 226, 330, 504]]],
    web: [[8.2, [344, 0, 520, 730]], [8.3, [394, 0, 420, 730]]],
    calendar: [[6.1, [878, 0, 354, 730]], [6.36, [878, 0, 354, 380]], [8.2, [878, 0, 354, 380]], [8.3, [828, 0, 354, 380]], [8.41, [828, 0, 354, 380]], [8.48, [828, 350, 354, 380]]],
    pdf: [[6.14, [878, 780, 354, 336]], [6.4, [878, 394, 354, 336]], [8.2, [878, 394, 354, 336]], [8.3, [828, 394, 354, 336]], [8.37, [828, 394, 354, 336]], [8.47, [828, 0, 354, 336]]],
  };
  const HELD = { web: [8.2, 8.31], pdf: [8.37, 8.48] };
  const TILE_ORDER = ['clock', 'reminders', 'web', 'calendar', 'pdf'];

  // The pointer, in two acts. Points that depend on layout are measured.
  const P = {};
  let POINTER = [];
  const POINTER_SHOWN = [[0.98, 0], [1.02, 1], [2.0, 1], [2.06, 0], [7.22, 0], [7.27, 1], [8.94, 1], [9.0, 0]];
  const CLICKS = [1.18, 1.43, 1.67, 1.92, 7.45, 8.12, 8.71];

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
      [8.09, P.edit], [8.14, P.edit],
      [8.19, P.webEdge], [8.2, P.webEdge], [8.3, [P.webEdge[0] - 50, P.webEdge[1]]], [8.31, [P.webEdge[0] - 50, P.webEdge[1]]],
      [8.36, P.pdf], [8.37, P.pdf], [8.47, [P.pdf[0], P.pdf[1] - 394]], [8.48, [P.pdf[0], P.pdf[1] - 394]],
      [8.66, P.edit], [8.72, P.edit], [8.9, P.edit],
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
  // visitor; `pinned` means they tapped and it stays.
  function render(scene, T, { user = 0, pinned = false, still = false } = {}) {
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
    const sceneOverlay = track(OVERLAY, T, linear);
    const overlay = Math.max(sceneOverlay, user);
    css(scene, scene.ov, 'opacity', overlay.toFixed(3));
    css(scene, scene.ov, 'visibility', overlay > 0.001 ? 'visible' : 'hidden');
    flag(scene.ov, 'is-live', pinned);
    flag(scene.mbBlink, 'is-on', overlay > 0.5);
    if (still) flag(scene.desk, 'is-blurred', overlay > 0.5);
    const bloom = T > 2 && T < 2.6 ? track([[2.12, 0.965], [2.42, 1]], T) : 0.985 + 0.015 * overlay;
    css(scene, scene.board, 'transform', `scale(${(user > sceneOverlay ? 0.985 + 0.015 * user : bloom).toFixed(4)})`);
    css(scene, scene.strip, 'opacity', Math.max(track(STRIP, T, linear), pinned ? 1 : 0).toFixed(3));

    // Arranging.
    const editing = T >= 8.13 && T < 8.71;
    flag(scene.board, 'is-editing', editing);
    flag(scene.edit, 'is-on', editing);
    text(scene.edit, editing ? 'Done' : 'Edit');
    text(scene.stripHint, editing ? 'Drag a tile to move it, or its edge to resize' : '⌥` or esc to close');

    // Tiles.
    TILE_ORDER.forEach((kind, index) => {
      const element = scene.tiles[kind];
      if (!element) return;
      const [x, y, w, h] = track(FRAMES[kind], T);
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
      const shown = track(POINTER_SHOWN, T, linear) * (still && !(T > 1 && T < 2.05) && !(T > 7.2 && T < 9) ? 0 : 1);
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
  const heroMark = $('.hero__mark');
  const take = $('#take');
  const stage = $('#stage');
  const display = $('#display');
  const stack = $('#stack');
  const caps = $$('#caps .cap');
  const index = $('#index');
  const indexLinks = $$('a', index);
  const stageKey = $('.foot .fnkey');
  const floatBox = $('#float');
  const calm = window.matchMedia('(prefers-reduced-motion: reduce)');

  // Build the board in the picture, then the scene that drives it.
  $('[data-board]', display).innerHTML = TILE_ORDER.map(tileHTML).join('');
  $('[data-slot="web"]', display).innerHTML = RENDER.web()
    .replace(/<div class="w-hover"[\s\S]*?<\/span>\s*<\/div>/, '')
    .replace(/ data-[a-z-]+(="[^"]*")?/g, '');
  const stageScene = makeScene(display);

  // Captions: one span per word, so they can fill in as you read.
  const ink4 = [195, 199, 206];
  const ink = [12, 13, 16];
  function splitWords(element) {
    const words = element.textContent.trim().split(/\s+/);
    element.innerHTML = words.map((word) => `<span class="w">${word}</span>`).join(' ');
    return $$('.w', element);
  }
  const capWords = caps.map(splitWords);
  function paintWords(words, fill, cache) {
    const n = words.length;
    words.forEach((word, i) => {
      const w = clamp(fill * n - i, 0, 1);
      const key = Math.round(w * 40);
      if (cache[i] === key) return;
      cache[i] = key;
      const c = ink4.map((v, k) => Math.round(lerp(v, ink[k], key / 40)));
      word.style.color = `rgb(${c.join(',')})`;
    });
  }
  const capCache = caps.map(() => []);

  let mode = '';
  let T = -1;
  const state = { vh: window.innerHeight, preDistance: 1, lengthsPx: [] };

  function isTakeMode() {
    return window.innerWidth >= 900 && window.innerHeight >= 560 && !calm.matches;
  }

  // Size the screen to the viewport: as large as fits above the captions.
  function layout() {
    const vw = document.documentElement.clientWidth;
    const vh = window.innerHeight;
    state.vh = vh;
    const side = vw >= 1240 ? 168 : 40;
    let dw = 0;
    let dh = vh - 60 - 14 - 24 - 40 - 2.3 * 30;
    for (let i = 0; i < 3; i += 1) {
      dw = Math.min(dh * 1300 / 820, vw - 2 * side, 1240);
      dh = dw * 820 / 1300;
      const cap = clamp(dw * 0.03, 24, 36);
      const room = vh - 60 - 14 - 24 - 34 - 2.24 * cap;
      if (dh > room) dh = room;
    }
    dw = Math.round(dh * 1300 / 820);
    dh = Math.round(dw * 820 / 1300);
    if (mode === 'take') {
      root.style.setProperty('--dw', `${dw}px`);
      root.style.setProperty('--dh', `${dh}px`);
      root.style.setProperty('--f', (dw / 1300).toFixed(5));
      stageScene.fit = dw / 1300;
      state.lengthsPx = LENGTHS.map((l) => l * vh);
      take.style.height = `${vh + state.lengthsPx.reduce((s, v) => s + v, 0)}px`;
      state.preDistance = Math.max(take.offsetTop, 1);
    } else {
      root.style.removeProperty('--dw');
      root.style.removeProperty('--dh');
      root.style.removeProperty('--f');
      take.style.height = '';
      const width = stack.clientWidth || (vw - 32);
      const viewWidth = window.innerWidth >= 900 ? (width - 40) * 1.7 / 2.7 : width;
      stack.style.setProperty('--cf', (viewWidth / 1300).toFixed(5));
      stillFit = viewWidth / 1300;
      stills.forEach((still) => { if (still.scene) still.scene.fit = stillFit; });
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
    measure();
  }

  // T from where the page is scrolled.
  function readT() {
    const top = take.getBoundingClientRect().top;
    if (top > 0) return clamp(-top / state.preDistance, -1, 0);
    let rest = -top;
    for (let k = 0; k < state.lengthsPx.length; k += 1) {
      const length = state.lengthsPx[k];
      if (rest < length) return k + rest / length;
      rest -= length;
    }
    return 10;
  }

  // Scroll position for a given T (used by the step list).
  function scrollForT(target) {
    const base = take.getBoundingClientRect().top + window.scrollY;
    if (target <= 0) return base + target * state.preDistance;
    let y = base;
    for (let k = 0; k < state.lengthsPx.length; k += 1) {
      if (target < k + 1) return y + (target - k) * state.lengthsPx[k];
      y += state.lengthsPx[k];
    }
    return y;
  }

  function renderCaptions() {
    const active = clamp(Math.floor(T) + 1, 1, 10);
    caps.forEach((cap, i) => {
      const k = i + 1;
      if (Math.abs(k - active) > 1) {
        if (cap.style.opacity !== '0') cap.style.opacity = '0';
        return;
      }
      const t = T - (k - 1);
      const on = k === 1 ? 1 : seg(t, 0, 0.06);
      const off = k === 10 ? 1 : 1 - seg(t, 0.93, 1);
      const opacity = on * off;
      cap.style.opacity = opacity.toFixed(3);
      cap.style.transform = `translateY(${((1 - on) * 10 - (1 - off) * 10).toFixed(1)}px)`;
      cap.style.filter = opacity > 0.98 ? 'none' : `blur(${((1 - on) * 6 + (1 - off) * 6).toFixed(1)}px)`;
      const [a, b] = FILL[i];
      paintWords(capWords[i], seg(t, a, b), capCache[i]);
    });
    indexLinks.forEach((link) => flag(link, 'is-on', Number(link.dataset.go) === active));
    // The step list joins once the screen has settled, and steps aside for close-ups.
    const zoom = track(CAMERA, T)[0];
    const shown = seg(T, -0.2, -0.02) * (1 - seg(zoom, 1, 1.06));
    index.style.opacity = shown.toFixed(3);
    index.style.visibility = shown > 0.01 ? 'visible' : 'hidden';
  }

  function renderStage() {
    render(stageScene, T, { user: userOverlay.u, pinned: peek.state === 'pinned' && peek.where === 'stage' });
    const ghost = mode === 'take' && within(T, KEY_DOWN);
    flag(stageKey, 'is-down', ghost || keyHeld);
  }

  function onFrame() {
    frame = 0;
    const scrolled = window.scrollY;
    flag(bar, 'is-past', scrolled > heroMark.offsetTop + heroMark.offsetHeight * 0.7 - 60);
    if (mode === 'take') {
      T = readT();
      renderCaptions();
      renderStage();
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

  // Each still is a full copy of the screen, so they are built only as they
  // come near the screen, not all at once when the page opens.
  const stills = [];
  let stillTemplate = null;
  let stillFit = 0.3;
  let stillWatcher = null;
  function buildStills() {
    if (stills.length) return;
    stillTemplate = display.cloneNode(true);
    stillTemplate.removeAttribute('id');
    stack.innerHTML = '';
    STILLS.forEach((t, index) => {
      const item = document.createElement('li');
      item.className = 'still';
      const view = document.createElement('div');
      view.className = 'still__view';
      view.setAttribute('aria-hidden', 'true');
      view.dataset.still = index;
      const cap = document.createElement('p');
      cap.className = 'still__cap';
      cap.textContent = caps[index].textContent;
      item.append(view, cap);
      stack.append(item);
      stills.push({ index, scene: null, view, cap, words: splitWords(cap), cache: [] });
    });
    // The ones about to come into view are built straight away; the rest are
    // built in spare moments, one at a time, so they are ready before anyone
    // scrolls to them and the page never stops for long to make them.
    stillWatcher = new IntersectionObserver((entries) => {
      entries.forEach((entry) => { if (entry.isIntersecting) fillStill(stills[Number(entry.target.dataset.still)]); });
    }, { rootMargin: '50% 0px' });
    stills.forEach((still) => stillWatcher.observe(still.view));
    buildAhead();
  }

  const whenIdle = window.requestIdleCallback
    ? (callback) => requestIdleCallback(callback, { timeout: 2000 })
    : (callback) => setTimeout(callback, 150);
  function buildAhead() {
    whenIdle(() => {
      const next = stills.find((still) => !still.scene);
      if (!next || mode !== 'stack') return;
      fillStill(next);
      buildAhead();
    });
  }

  function fillStill(still) {
    if (still.scene) return;
    stillWatcher.unobserve(still.view);
    const cam = document.createElement('div');
    cam.className = 'cam';
    const copy = stillTemplate.cloneNode(true);
    cam.append(copy);
    still.view.append(cam);
    still.scene = makeScene(copy);
    still.scene.fit = stillFit;
    if (!POINTER.length) measure();
    updateClocks();
    render(still.scene, STILLS[still.index], { still: true });
  }

  function renderStills() {
    stills.forEach((still) => { if (still.scene) render(still.scene, STILLS[still.index], { still: true }); });
  }

  function renderStillCaptions() {
    const vh = state.vh;
    const tops = stills.map((still) => still.cap.getBoundingClientRect().top);
    stills.forEach((still, i) => {
      const fill = calm.matches ? 1 : seg(vh * 0.92 - tops[i], 0, vh * 0.42);
      paintWords(still.words, fill, still.cache);
    });
  }

  // ---- Measuring points the pointer goes to --------------------------------

  function measure() {
    // Any copy of the screen will do: the points are the same in all of them.
    const built = stills.find((still) => still.scene);
    const scene = mode === 'take' ? stageScene : built && built.scene;
    if (!scene) return;
    render(scene, 7.5);
    const screenRect = scene.screen.getBoundingClientRect();
    const k = screenRect.width / 1280;
    if (!k) return;
    const centre = (element) => {
      const r = element.getBoundingClientRect();
      return [(r.left + r.width / 2 - screenRect.left) / k, (r.top + r.height / 2 - screenRect.top) / k];
    };
    const box = $('i', scene.rem.room);
    P.room = centre(box);
    P.edit = centre(scene.edit);
    P.boardMid = [700, 600];
    P.webMid = [24 + 344 + 300, 46 + 420];
    P.webEdge = [24 + 344 + 520, 46 + 365];
    P.pdf = [24 + 828 + 177, 46 + 394 + 168];
    buildPointerPath();
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
    const r = display.getBoundingClientRect();
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
  if (window.matchMedia('(hover: none)').matches) $('#pov-hint').textContent = 'Tap the keys again to close';
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

  // ---- One step per scroll ----------------------------------------------------
  // The opening scrolls normally. Once the screen is in place, a scroll
  // gesture does not scrub the story. It plays the next step through at that
  // step's own pace, and the page waits there. Further scrolling is held back
  // until the step has finished and the gesture has ended. After the last
  // step the page scrolls freely again.

  // Where the story comes to rest: the end of each step.
  const REST = [0.9, 1.93, 2.9, 3.9, 4.9, 5.9, 6.9, 7.9, 8.93, 9.97];
  // How long one whole unit of T takes to play, in ms: the opening, then each step.
  const PACE = [1300, 1700, 2600, 1500, 1700, 2400, 2000, 2000, 2600, 3600, 2800];
  const BACK = 0.5; // stepping back plays at twice the speed
  const JUMP = 1100; // a jump across several steps takes at most this long
  const GAP = 160; // ms without scrolling that ends a gesture

  const lock = { raf: 0, from: 0, to: 0, start: 0, total: 0, parts: [], armed: true, lastAt: 0, lastSize: 0, touchY: null };

  const inStory = () => mode === 'take';
  const nextRest = (now, direction) => (direction > 0
    ? REST.find((r) => r > now + 0.005)
    : [...REST].reverse().find((r) => r < now - 0.005));

  // The pieces of T between two points, each with how long it takes to play.
  function parts(from, to) {
    const lo = Math.min(from, to);
    const hi = Math.max(from, to);
    const list = [];
    for (let k = -1; k < 10; k += 1) {
      const a = Math.max(lo, k);
      const b = Math.min(hi, k + 1);
      if (b > a) list.push({ a, b, ms: (b - a) * PACE[k + 1] });
    }
    if (from > to) list.reverse().forEach((part) => { [part.a, part.b] = [part.b, part.a]; });
    return list;
  }

  const settle = (x) => 0.6 * x + 0.4 * x * x * (3 - 2 * x);

  function playTo(target, { fast = false } = {}) {
    cancelAnimationFrame(lock.raf);
    lock.from = readT();
    lock.to = target;
    lock.parts = parts(lock.from, target);
    let total = lock.parts.reduce((sum, part) => sum + part.ms, 0);
    if (target < lock.from) total *= BACK;
    if (fast) total = Math.min(total, JUMP);
    const scale = total / Math.max(lock.parts.reduce((sum, part) => sum + part.ms, 0), 1);
    lock.parts.forEach((part) => { part.span = part.ms * scale; });
    lock.total = Math.max(total, 1);
    lock.start = performance.now();
    lock.raf = requestAnimationFrame(playFrame);
  }

  function playFrame(now) {
    const p = settle(clamp((now - lock.start) / lock.total, 0, 1));
    let left = p * lock.total;
    let at = lock.to;
    for (const part of lock.parts) {
      if (left <= part.span) { at = part.a + (part.b - part.a) * (part.span ? left / part.span : 1); break; }
      left -= part.span;
    }
    window.scrollTo(0, scrollForT(at));
    onFrame();
    lock.raf = p < 1 ? requestAnimationFrame(playFrame) : 0;
  }

  const playing = () => lock.raf !== 0;

  // Moves one step in a direction. Returns false when the page should scroll
  // on its own instead: before the story, after it, or outside it.
  function step(direction) {
    if (!inStory()) return false;
    const now = readT();
    if (direction < 0 && window.scrollY > scrollForT(10) + 2) return false; // below the story
    if (direction > 0 && now >= 10) return false;
    const target = nextRest(now, direction);
    if (target === undefined) return false;
    playTo(target);
    return true;
  }

  // Scrolling down through the opening: if this much more would bring the
  // screen into place, the story takes over from here and plays its first
  // step, instead of letting the page run on past it.
  function arrives(distance) {
    if (!inStory() || playing() || distance <= 0) return false;
    if (readT() >= 0) return false;
    if (window.scrollY + distance < scrollForT(0) - 2) return false;
    playTo(REST[0]);
    return true;
  }
  const pixels = (event) => event.deltaY * (event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? state.vh : 1);

  // Would a gesture in this direction be the story's, rather than the page's?
  function owns(direction) {
    if (!inStory()) return false;
    if (playing()) return true;
    const now = readT();
    if (now < 0) return false; // the opening scrolls normally
    if (direction < 0 && window.scrollY > scrollForT(10) + 2) return false;
    if (direction > 0 && now >= 10) return false;
    return nextRest(now, direction) !== undefined;
  }

  window.addEventListener('wheel', (event) => {
    if (event.ctrlKey || Math.abs(event.deltaX) > Math.abs(event.deltaY) || !event.deltaY) return;
    const direction = Math.sign(event.deltaY);
    const now = performance.now();
    if (arrives(pixels(event))) {
      event.preventDefault();
      lock.lastAt = now;
      lock.lastSize = Math.abs(event.deltaY);
      return;
    }
    if (!owns(direction)) return;
    event.preventDefault();
    const size = Math.abs(event.deltaY);
    // A new gesture: after a pause, or a fresh push while momentum is fading.
    const fresh = now - lock.lastAt > GAP || (size > lock.lastSize * 1.6 && size > 12);
    lock.lastAt = now;
    lock.lastSize = size;
    if (playing() || !fresh) return;
    step(direction);
  }, { passive: false });

  window.addEventListener('keydown', (event) => {
    if (event.altKey || event.ctrlKey || event.metaKey || isTyping(event.target)) return;
    const direction = { ArrowDown: 1, PageDown: 1, ArrowUp: -1, PageUp: -1 }[event.key];
    if (!direction) return;
    if (!event.repeat && arrives(event.key === 'PageDown' ? state.vh * 0.85 : 40)) { event.preventDefault(); return; }
    if (!owns(direction)) return;
    event.preventDefault();
    if (!playing() && !event.repeat) step(direction);
  });

  // Large touch screens get the same steps: one swipe, one step.
  window.addEventListener('touchstart', (event) => {
    lock.touchY = event.touches.length === 1 ? event.touches[0].clientY : null;
    lock.armed = !playing();
  }, { passive: true });
  window.addEventListener('touchmove', (event) => {
    if (lock.touchY === null) return;
    const dy = lock.touchY - event.touches[0].clientY;
    const direction = Math.sign(dy);
    if (!direction || !owns(direction)) return;
    event.preventDefault();
    if (lock.armed && !playing() && Math.abs(dy) > 30) {
      lock.armed = false;
      step(direction);
    }
  }, { passive: false });

  // ---- The step list ----------------------------------------------------------

  indexLinks.forEach((link) => link.addEventListener('click', (event) => {
    event.preventDefault();
    const k = Number(link.dataset.go);
    const target = REST[k - 1];
    const far = Math.abs(target - readT()) > 1.2;
    playTo(target, { fast: far });
  }));

  // ---------------------------------------------------------------------
  // Start.
  // ---------------------------------------------------------------------

  function refresh() {
    setMode();
    layout();
    onFrame();
  }

  updateClocks();
  updateCalendar();
  setMode();
  layout();
  measure();
  refresh();
  // The clocks show minutes: update them as each minute turns, not every second.
  (function nextMinute() {
    setTimeout(() => { updateClocks(); nextMinute(); }, 60000 - (Date.now() % 60000) + 40);
  }());
  setInterval(updateCalendar, 60000);

  const afterFonts = () => { layout(); measure(); refresh(); };
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(afterFonts);

  let resizeTimer = 0;
  window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => { refresh(); if (pov.classList.contains('is-open')) layoutPov(); }, 80);
  });
  calm.addEventListener('change', refresh);

  // For checking the page by script.
  window.__blink = { peek, scrollForT, REST, get playing() { return playing(); }, get user() { return userOverlay.u; }, get T() { return T; }, get mode() { return mode; }, render: () => onFrame() };
})();
