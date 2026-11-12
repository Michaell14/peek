// Blink, "Through the Day" draft. A variation of Daylight.
// One screen stays pinned while the page scrolls, and the distance scrolled
// plays one working day on it, from eight in the morning to half past six.
// The clock, the light, the calendar and the reminders follow the hour.
// Hold Space (or press the fn key on screen) at any point to open Blink yourself.
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
  // The day. Beat k runs from T = k - 1 to T = k; before the screen pins,
  // T runs from -1 up to 0. Times are minutes after midnight.
  // ---------------------------------------------------------------------

  // How far you scroll through each beat, in viewport heights.
  const LENGTHS = [0.62, 1.1, 0.95, 0.85, 1.2, 1.1, 1.05, 1.0, 1.45, 1.2];
  // When each caption fills, as a fraction of its beat.
  const FILL = [[-0.3, 0.35], [0.03, 0.45], [0.02, 0.36], [0.02, 0.42], [0.03, 0.5], [0.03, 0.55], [0.03, 0.5], [0.02, 0.42], [0.03, 0.5], [0.03, 0.45]];

  // The clock. It runs slowly inside a beat and hurries between them, while
  // the caption changes: 8:40, 8:45, 8:52, then 10:15, 12:30, 15:00, 15:40, 17:45, 18:30.
  const TIME = [[-1, 480], [0, 517], [0.95, 522], [1.06, 523], [1.94, 531], [2.06, 532], [3.0, 532.6], [3.9, 533.4], [4.06, 612], [4.95, 618], [5.06, 744], [5.95, 756], [6.06, 896], [6.6, 900], [6.95, 904], [7.06, 936], [7.95, 946], [8.06, 1060], [8.95, 1070], [9.06, 1104], [10, 1116]];
  const minutesAt = (T) => track(TIME, T, linear);

  // The moments the day stops at, for the list beside the screen and the stills.
  const MOMENTS = [
    { T: 0.92, m: 520 }, { T: 1.82, m: 525 }, { T: 2.75, m: 532 }, { T: 3.8, m: 533 }, { T: 4.8, m: 615 },
    { T: 5.74, m: 750 }, { T: 6.85, m: 900 }, { T: 7.56, m: 940 }, { T: 8.5, m: 1065 }, { T: 9.75, m: 1110 },
  ];

  const clockText = (m) => {
    const t = Math.floor(((m % 1440) + 1440) % 1440);
    return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`;
  };
  function dayPart(m) {
    if (m < 540) return 'early morning';
    if (m < 720) return 'morning';
    if (m < 810) return 'midday';
    if (m < 990) return 'afternoon';
    if (m < 1080) return 'late afternoon';
    return 'evening';
  }

  // The wallpaper's light through the day: sky (top, middle, horizon), the
  // sun's glow and where it sits, five ranges of hills, and stars.
  const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
  const palette = (p) => [...hex(p.s1), ...hex(p.s2), ...hex(p.s3), ...p.sun, p.sx, p.sy, ...hex(p.h1), ...hex(p.h2), ...hex(p.h3), ...hex(p.h4), ...hex(p.h5), p.stars];
  const WALL = [
    [480, palette({ s1: '#8d9fc2', s2: '#cdd0e0', s3: '#f3d7c8', sun: [255, 222, 196, 0.9], sx: 230, sy: 470, h1: '#cfcfdc', h2: '#b3b5ca', h3: '#959bb5', h4: '#77809e', h5: '#5d6787', stars: 0 })],
    [615, palette({ s1: '#92b4dc', s2: '#d3e1ef', s3: '#edf1f5', sun: [255, 255, 255, 0.9], sx: 430, sy: 230, h1: '#cbd6e2', h2: '#adbfd2', h3: '#8ea6bf', h4: '#6f8baa', h5: '#55718f', stars: 0 })],
    [750, palette({ s1: '#7eaee0', s2: '#cde2f5', s3: '#f0f5f8', sun: [255, 255, 255, 0.95], sx: 690, sy: 90, h1: '#cddbe2', h2: '#abc3cd', h3: '#88a7b5', h4: '#67899c', h5: '#4c6d82', stars: 0 })],
    [900, palette({ s1: '#8eb0d8', s2: '#d9e2ea', s3: '#f4ede2', sun: [255, 248, 230, 0.9], sx: 930, sy: 210, h1: '#d5dadc', h2: '#b9c1c6', h3: '#98a4ad', h4: '#788697', h5: '#5d6b81', stars: 0 })],
    [1065, palette({ s1: '#8796bb', s2: '#e4c5b0', s3: '#f7c792', sun: [255, 204, 140, 0.95], sx: 1060, sy: 420, h1: '#dcc0b1', h2: '#be9e93', h3: '#9a7e80', h4: '#77626f', h5: '#56495b', stars: 0 })],
    [1110, palette({ s1: '#2c3658', s2: '#6a6385', s3: '#dc9f8a', sun: [255, 160, 120, 0.5], sx: 1150, sy: 520, h1: '#6c6886', h2: '#55536e', h3: '#43425b', h4: '#323249', h5: '#242539', stars: 0.85 })],
  ];

  // The page's own light: three washes over dawn, as in the stylesheet.
  const GROUND = { dawn: hex('#e5eaf2'), noon: hex('#f4f5f6'), late: hex('#f4ece0'), dusk: hex('#dddce6') };
  const groundMix = (m) => ({ noon: seg(m, 525, 720), late: seg(m, 880, 1040), dusk: seg(m, 1072, 1108) });
  function groundColor(m) {
    const p = groundMix(m);
    let c = GROUND.dawn;
    c = mix(c, GROUND.noon, p.noon);
    c = mix(c, GROUND.late, p.late);
    c = mix(c, GROUND.dusk, p.dusk);
    return `rgb(${c.map(Math.round).join(',')})`;
  }

  // ---------------------------------------------------------------------
  // What happens on the screen, beat by beat.
  // ---------------------------------------------------------------------

  // Blink in the picture: held at 8:52, then a glance at each moment of the
  // day, tapped open at 15:40 and 17:45, and held over the film at 18:30.
  const OVERLAY = [[-2, 0], [2.12, 0], [2.4, 1], [3.06, 1], [3.12, 0], [4.1, 0], [4.16, 1], [4.9, 1], [4.96, 0], [5.08, 0], [5.14, 1], [5.9, 1], [5.96, 0], [6.06, 0], [6.12, 1], [6.94, 1], [7.0, 0], [7.12, 0], [7.17, 1], [7.93, 1], [7.98, 0], [8.09, 0], [8.14, 1], [9.03, 1], [9.08, 0], [9.58, 0], [9.64, 1], [9.88, 1], [9.93, 0]];
  const KEY_DOWN = [[2.1, 3.06], [4.08, 4.9], [5.06, 5.9], [6.04, 6.94], [7.11, 7.15], [7.9, 7.93], [8.07, 8.1], [9.0, 9.03], [9.57, 9.88]];
  const STRIP = [[7.17, 0], [7.23, 1], [7.93, 1], [7.97, 0], [8.14, 0], [8.19, 1], [9.03, 1], [9.07, 0]];

  const TEXT_A = 'Since the new page went live, we are at';
  const TEXT_B = ' 368.';
  const TYPE_A = [[-0.62, 0], [0.42, TEXT_A.length]];
  const TYPE_B = [[3.2, 0], [3.4, TEXT_B.length]];

  // Clicking around to check things: which window comes forward, and when.
  const FRONT = [[1.18, 'cal'], [1.43, 'mail'], [1.67, 'web'], [1.92, 'writer']];
  const APP_NAME = { writer: 'Writer', cal: 'Calendar', mail: 'Mail', web: 'Browser' };
  const DOCK_CLICK = { cal: 1.18, mail: 1.43, web: 1.67, writer: 1.92, player: 9.12 };

  // Camera: [zoom, x, y] where (x, y) is the point of the screen to centre on.
  const CAMERA = [[4.14, [1, 640, 400]], [4.36, [1.42, 628, 330]], [4.84, [1.42, 628, 330]], [4.98, [1, 640, 400]]];

  // Tile frames on the board, [x, y, w, h], in screen pixels.
  // Tidying up (beat 9): resize the page, move the file, move the clock, then
  // back to Flow, which packs everything into columns again.
  const FRAMES = {
    clock: [[8.62, [0, 0, 330, 212]], [8.72, [902, 394, 330, 212]], [8.87, [902, 394, 330, 212]], [9.01, [0, 0, 330, 212]]],
    reminders: [[0, [0, 226, 330, 504]]],
    web: [[8.28, [344, 0, 520, 730]], [8.38, [344, 0, 520, 380]], [8.87, [344, 0, 520, 380]], [9.01, [344, 0, 520, 730]]],
    calendar: [[6.1, [878, 0, 354, 730]], [6.36, [878, 0, 354, 380]]],
    pdf: [[6.14, [878, 780, 354, 336]], [6.4, [878, 394, 354, 336]], [8.45, [878, 394, 354, 336]], [8.55, [344, 394, 354, 336]], [8.87, [344, 394, 354, 336]], [9.01, [878, 394, 354, 336]]],
  };
  const HELD = { web: [8.28, 8.39], pdf: [8.45, 8.56], clock: [8.62, 8.73] };
  const TILE_ORDER = ['clock', 'reminders', 'web', 'calendar', 'pdf'];

  // The pointer, in three acts. Points that depend on layout are measured.
  const P = { dock: {} };
  let POINTER = [];
  const POINTER_SHOWN = [[0.98, 0], [1.02, 1], [2.0, 1], [2.06, 0], [7.22, 0], [7.27, 1], [9.15, 1], [9.2, 0]];
  const CLICKS = [1.18, 1.43, 1.67, 1.92, 7.45, 8.17, 8.24, 8.79, 8.85, 9.12];

  function buildPointerPath() {
    const d = P.dock;
    POINTER = [
      [1.0, [560, 470]],
      [1.15, d.cal], [1.21, d.cal],
      [1.4, d.mail], [1.46, d.mail],
      [1.64, d.web], [1.7, d.web],
      [1.8, [800, 352]], [1.84, [800, 352]],
      [1.9, d.writer], [1.94, d.writer],
      [2.04, [620, 500]],
      [7.22, P.boardMid], [7.4, P.sam], [7.47, P.sam],
      [7.58, P.webMid], [7.9, P.webMid],
      [8.14, P.free], [8.18, P.free],
      [8.22, P.edit], [8.25, P.edit],
      [8.27, P.webEdge], [8.28, P.webEdge], [8.38, [P.webEdge[0], 46 + 380]], [8.39, [P.webEdge[0], 46 + 380]],
      [8.44, P.pdf], [8.45, P.pdf], [8.55, [P.pdf[0] - 534, P.pdf[1]]], [8.56, [P.pdf[0] - 534, P.pdf[1]]],
      [8.61, P.clock], [8.62, P.clock], [8.72, [P.clock[0] + 902, P.clock[1] + 394]], [8.73, [P.clock[0] + 902, P.clock[1] + 394]],
      [8.78, P.edit], [8.8, P.edit],
      [8.84, P.flow], [8.98, P.flow],
      [9.1, d.player], [9.2, d.player],
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

  // In the picture the cities keep fixed offsets from the day's clock; over
  // the page they show the real time.
  const ZONES = [
    { zone: 'America/Los_Angeles', name: 'San Francisco', offset: -8 },
    { zone: 'America/New_York', name: 'New York', offset: -5 },
    { zone: 'Asia/Tokyo', name: 'Tokyo', offset: 9 },
  ];

  const WEB_VALUES = {
    before: { visitors: '12,480', signups: '368', bounce: '38%', visit: '2m 41s', 'visitors-e': '▲ 8.2%', 'signups-e': '▲ 7.6%', 'bounce-e': '▼ 1.4%', 'visit-e': '▲ 12s' },
    after: { visitors: '13,105', signups: '371', bounce: '37%', visit: '2m 44s', 'visitors-e': '▲ 9.1%', 'signups-e': '▲ 8.5%', 'bounce-e': '▼ 2.6%', 'visit-e': '▲ 15s' },
  };
  const BARS = [52, 49, 58, 55, 61, 84, 90];

  // Reminders, with the minute each one falls due.
  const REMINDERS = [
    { key: 'room', title: 'Book a room for the review', due: 600 },
    { key: 'plants', title: 'Water the plants', due: 720 },
    { key: 'sam', title: 'Reply to Sam', label: 'Today' },
    { key: 'dentist', title: 'Call the dentist', due: 1050 },
  ];

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
          ${REMINDERS.map((r) => `<button type="button" tabindex="-1" class="w-rem__item" data-rem="${r.key}"${r.due ? ` data-due="${r.due}"` : ''}><i></i><span><b>${r.title}</b><small>${r.due ? clockText(r.due) : r.label}</small></span></button>`).join('')}
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
            <li class="is-new">Sign-ups: 342 a day last week, 371 now</li>
          </ol>
          <p>Room 2, 16:00. Sam to bring the numbers.</p>
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

  function paintClockRow(row, { digits, day, detail }) {
    const glyph = $('.w-clock__glyph', row);
    const glyphClass = `w-clock__glyph ${day ? 'is-day' : 'is-night'}`;
    if (glyph.className !== glyphClass) { glyph.className = glyphClass; glyph.innerHTML = day ? ICONS.sun : ICONS.moon; }
    const timeElement = $('.w-clock__time', row);
    if (timeElement.textContent !== digits) timeElement.textContent = digits;
    const place = $('.w-clock__place span', row);
    if (place.textContent !== detail) place.textContent = detail;
  }
  const offsetText = (dayDiff, offset) => {
    const dayName = dayDiff > 0 ? 'Tomorrow' : dayDiff < 0 ? 'Yesterday' : 'Today';
    return offset === 0 ? dayName : `${dayName}, ${offset > 0 ? '+' : '−'}${Math.abs(offset)} ${Math.abs(offset) === 1 ? 'hr' : 'hrs'}`;
  };

  // ---- The calendar tile in the picture: one fixed Thursday ------------------

  const CAL_FIRST = 7;
  const CAL_HOURS = 14;
  const HOUR_PX = 54;
  const SCENE_EVENTS = [
    { title: 'Standup', start: 9.5, end: 10, color: '#5b9dff' },
    { title: 'Design review', start: 11, end: 12, color: '#5fd0c2' },
    { title: 'Lunch with Lena', start: 12.5, end: 13.25, color: '#ffc761' },
    { title: 'Sam, 1:1', start: 14, end: 14.5, color: '#b98cff' },
    { title: 'Thursday review', start: 16, end: 17, color: '#5b9dff' },
    { title: 'Send the weekly notes', start: 17.5, end: 18, color: '#ff8a7a' },
  ];
  const hourLabel = (h) => `${Math.floor(h)}:${String(Math.round((h % 1) * 60)).padStart(2, '0')}`;

  function fillSceneCalendar(root) {
    $('.w-cal__day', root).textContent = '12';
    $('.w-cal__date b', root).textContent = 'Thursday';
    $('.w-cal__date span', root).textContent = 'November';
    let html = '<div class="w-cal__track" data-cal-track>';
    for (let i = 1; i < CAL_HOURS; i += 1) html += `<div class="w-cal__hour" style="top:${i * HOUR_PX}px"><span>${CAL_FIRST + i}:00</span></div>`;
    for (const event of SCENE_EVENTS) {
      html += `<div class="w-cal__event${event.end - event.start < 0.75 ? ' is-short' : ''}" style="--c:${event.color};background:${event.color}38;top:${(event.start - CAL_FIRST) * HOUR_PX + 1}px;height:${(event.end - event.start) * HOUR_PX - 3}px;left:44px;right:10px"><b>${event.title}</b><span>${hourLabel(event.start)}</span></div>`;
    }
    html += '<div class="w-cal__now" data-now></div></div>';
    $('.w-cal__grid', root).innerHTML = html;
  }

  // ---- Over the page: the real time ------------------------------------------

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
    $$('[data-zone-row]', povBoard).forEach((row) => {
      const entry = ZONES[Number(row.dataset.zoneRow)];
      const hour = hourIn(entry.zone, now);
      const minute = Number(new Intl.DateTimeFormat('en-GB', { minute: 'numeric', timeZone: entry.zone }).format(now));
      paintClockRow(row, {
        digits: `${hour}:${String(minute).padStart(2, '0')}`,
        day: hour >= 6 && hour < 18,
        detail: offsetText(dayDifference(entry.zone, now), offsetHours(entry.zone, now)),
      });
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
    const events = [
      { title: 'Design review', start: anchor - 1.5, end: anchor - 0.5, color: '#5fd0c2', column: 0, of: 1 },
      { title: 'Thursday review', start: anchor + 0.25, end: anchor + 1.25, color: '#5b9dff', column: 0, of: 2 },
      { title: 'Sam, 1:1', start: anchor + 0.75, end: anchor + 1.75, color: '#b98cff', column: 1, of: 2 },
      { title: 'Lunch', start: anchor + 2.5, end: anchor + 3.25, color: '#ffc761', column: 0, of: 1 },
      { title: 'Ship it', start: anchor + 4.5, end: anchor + 5.5, color: '#ff8a7a', column: 0, of: 1 },
    ];
    let html = '';
    for (let i = 1; i < hours; i += 1) html += `<div class="w-cal__hour" style="top:${i * scale}%"><span>${hourLabel(first + i)}</span></div>`;
    for (const event of events) {
      const width = `calc((100% - 54px) / ${event.of} - 3px)`;
      const left = `calc(44px + (100% - 54px) / ${event.of} * ${event.column})`;
      html += `<div class="w-cal__event" style="--c:${event.color};background:${event.color}38;top:calc(${position(event.start)}% + 1px);height:calc(${(event.end - event.start) * scale}% - 3px);left:${left};width:${width}"><b>${event.title}</b><span>${hourLabel(event.start)}</span></div>`;
    }
    const nowHour = now.getHours() + now.getMinutes() / 60;
    if (nowHour >= first && nowHour <= first + hours) html += `<div class="w-cal__now" style="top:${position(nowHour)}%"></div>`;

    $$('.w-cal', povBoard).forEach((root) => {
      $('.w-cal__day', root).textContent = now.getDate();
      $('.w-cal__date b', root).textContent = now.toLocaleDateString('en-US', { weekday: 'long' });
      $('.w-cal__date span', root).textContent = now.toLocaleDateString('en-US', { month: 'long' });
      $('.w-cal__grid', root).innerHTML = html;
    });
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
      minute: null,
      screen: q('.screen'),
      desk: q('.desk'),
      cam: display.closest('.cam'),
      wall: q('[data-wall]'),
      sun: q('[data-sun]'),
      stars: q('[data-stars]'),
      sceneTime: q('[data-scene-time]'),
      calWinNow: q('[data-cal-now]'),
      wins: {},
      dockIcons: {},
      appName: q('[data-app-name]'),
      mbBlink: q('[data-mb-blink]'),
      menubar: q('.menubar'),
      dock: q('.dock'),
      typedA: $$('[data-typed="a"]', display),
      typedB: $$('[data-typed="b"]', display),
      full: q('[data-full]'),
      film: q('[data-film]'),
      filmUi: q('[data-film-ui]'),
      filmAt: q('[data-film-at]'),
      filmHead: q('[data-film-head]'),
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
      zoneRows: $$('[data-zone-row]', display),
      hover: w('[data-hover]'),
      ring: w('[data-ring]'),
      refresh: w('[data-refresh]'),
      flash: w('[data-flash]'),
      webBody: w('[data-web-body]'),
      webDim: w('.tile__dim'),
      values: {},
      lastBar: null,
      pdf: q('[data-pdf]'),
      calTrack: q('[data-cal-track]'),
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
  const rgb = (a, i) => `rgb(${Math.round(a[i])},${Math.round(a[i + 1])},${Math.round(a[i + 2])})`;

  function frontAt(T) {
    const order = ['web', 'cal', 'mail', 'writer'];
    for (const [t, app] of FRONT) {
      if (T < t) break;
      order.splice(order.indexOf(app), 1);
      order.push(app);
    }
    return order;
  }

  // Everything on the screen that only depends on the hour: the menu bar
  // clock, the wallpaper's light, the world clocks and the calendar's now.
  function paintHour(scene, m) {
    text(scene.sceneTime, clockText(m));
    const p = track(WALL, m, linear);
    ['--s1', '--s2', '--s3'].forEach((name, i) => css(scene, scene.wall, name, rgb(p, i * 3)));
    css(scene, scene.wall, '--sun', `rgba(${Math.round(p[9])},${Math.round(p[10])},${Math.round(p[11])},${p[12].toFixed(2)})`);
    css(scene, scene.sun, 'transform', `translate(${px(p[13])}, ${px(p[14])})`);
    ['--h1', '--h2', '--h3', '--h4', '--h5'].forEach((name, i) => css(scene, scene.wall, name, rgb(p, 15 + i * 3)));
    css(scene, scene.stars, 'opacity', p[30].toFixed(2));

    scene.zoneRows.forEach((row) => {
      const entry = ZONES[Number(row.dataset.zoneRow)];
      const local = m + entry.offset * 60;
      const hour = Math.floor((((local % 1440) + 1440) % 1440) / 60);
      paintClockRow(row, { digits: clockText(local), day: hour >= 6 && hour < 18, detail: offsetText(Math.floor(local / 1440), entry.offset) });
    });

    const hours = m / 60;
    css(scene, scene.calWinNow, 'transform', `translateY(${px(((hours - 8) / 11) * 356)})`);
    css(scene, scene.calWinNow, 'opacity', hours >= 8 && hours <= 19 ? '1' : '0');
  }

  // Draw the scene at moment T. `user` (0 to 1) is Blink opened by the
  // visitor; `pinned` means they tapped and it stays; `minutes` overrides the hour.
  function render(scene, T, { user = 0, pinned = false, still = false, minutes = null } = {}) {
    const m = minutes == null ? minutesAt(T) : minutes;
    const minute = Math.floor(m);
    if (scene.minute !== minute) { scene.minute = minute; paintHour(scene, minute); }

    // Windows: stacking order, and which one is in front.
    const order = frontAt(T);
    const front = order[order.length - 1];
    order.forEach((app, index) => {
      css(scene, scene.wins[app], 'z-index', String(index + 1));
      flag(scene.wins[app], 'is-key', app === front);
    });
    text(scene.appName, APP_NAME[front]);
    for (const [app, element] of Object.entries(scene.dockIcons)) {
      const t = DOCK_CLICK[app];
      flag(element, 'is-click', t != null && Math.abs(T - t) < 0.012);
    }

    // The sentence being written.
    const a = Math.round(track(TYPE_A, T, linear));
    const b = Math.round(track(TYPE_B, T, linear));
    scene.typedA.forEach((element) => text(element, TEXT_A.slice(0, a)));
    scene.typedB.forEach((element) => text(element, TEXT_B.slice(0, b)));

    // Evening: the film opens in a window, then goes full screen.
    const fullP = track([[9.16, 0], [9.44, 1]], T);
    const fullO = track([[9.11, 0], [9.125, 1]], T, linear);
    css(scene, scene.full, 'visibility', fullO > 0 ? 'visible' : 'hidden');
    css(scene, scene.full, 'opacity', fullO.toFixed(3));
    if (fullO > 0) {
      const inset = [190, 300, 230, 300].map((v) => lerp(v, 0, fullP));
      css(scene, scene.full, 'clip-path', `inset(${inset.map(px).join(' ')} round ${px(lerp(12, 0, fullP))})`);
      const play = seg(T, 9.12, 10);
      css(scene, scene.film, 'transform', `translateX(${px(-80 * play)})`);
      css(scene, scene.filmUi, 'opacity', track([[9.4, 0], [9.44, 1], [9.52, 1], [9.58, 0]], T, linear).toFixed(3));
      const seconds = Math.round(41 * 60 + 12 + play * 58);
      text(scene.filmAt, `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`);
      css(scene, scene.filmHead, 'transform', `scaleX(${(seconds / 6480).toFixed(4)})`);
    }
    const chrome = track([[9.16, 0], [9.3, 1]], T);
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

    // Tidying up.
    const freeform = T >= 8.17 && T < 8.85;
    const editing = T >= 8.24 && T < 8.79;
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
    css(scene, scene.webDim, 'opacity', track([[5.14, 0], [5.24, 1], [5.86, 1], [5.92, 0]], T, linear).toFixed(3));

    // Reminders that fall due, and the ones that get done.
    const done = { room: T >= 5.3, plants: T >= 5.42, sam: T >= 7.45 };
    for (const [key, element] of Object.entries(scene.rem)) {
      if (key in done && !element.dataset.user) flag(element, 'is-done', done[key]);
      if (element.dataset.due) flag($('small', element), 'is-late', m >= Number(element.dataset.due));
    }
    if (scene.remCount) text(scene.remCount, String(Object.values(scene.rem).filter((element) => !element.classList.contains('is-done')).length));

    // The web page: hover bar, refresh timer, and the numbers after.
    css(scene, scene.hover, 'opacity', track([[4.3, 0], [4.36, 1], [4.86, 1], [4.9, 0]], T, linear).toFixed(3));
    const refreshed = T >= 4.74;
    const ring = refreshed ? track([[4.74, 0], [5.0, 0.12]], T, linear) : track([[4.38, 0], [4.72, 1]], T, linear);
    css(scene, scene.ring, '--ring', ring.toFixed(3));
    const left = Math.round((1 - ring) * 300);
    text(scene.refresh, ring >= 0.999 ? 'Refreshing' : `Refresh in ${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')}`);
    css(scene, scene.flash, 'opacity', track([[4.72, 0], [4.74, 0.75], [4.82, 0]], T, linear).toFixed(3));
    const values = refreshed ? WEB_VALUES.after : WEB_VALUES.before;
    for (const [key, element] of Object.entries(scene.values)) {
      text(element, values[key]);
      if (element.tagName === 'B') flag(element, 'is-new', refreshed && T < 4.94);
    }
    css(scene, scene.lastBar, 'transform', `scaleY(${track([[4.74, 0.9], [4.84, 1]], T).toFixed(3)})`);
    const scroll = track([[7.6, 0], [7.72, -120], [7.8, -120], [7.9, 0]], T);
    css(scene, scene.webBody, 'transform', `translateY(${px(scroll)})`);

    // The file that changes on disk, at three.
    flag(scene.pdf, 'is-updated', T >= 6.6);

    // Now, on the calendar: the day scrolls so that now stays in view.
    if (scene.calTrack) {
      const visible = track(FRAMES.calendar, T)[3] - 54;
      const nowY = (m / 60 - CAL_FIRST) * HOUR_PX;
      const offset = clamp(nowY - visible * 0.34, 0, CAL_HOURS * HOUR_PX - visible);
      css(scene, scene.calTrack, 'transform', `translateY(${px(-offset)})`);
      css(scene, scene.calNow, 'transform', `translateY(${px(nowY)})`);
      const pulse = T > 5.45 && T < 5.95 ? ((T - 5.45) / 0.18) % 1 : 1;
      css(scene, scene.calNow, '--pulse-s', (0.4 + pulse * 1.6).toFixed(3));
      css(scene, scene.calNow, '--pulse-o', (T > 5.45 && T < 5.95 ? 0.9 * (1 - pulse) : 0).toFixed(3));
    }

    // The pointer.
    if (POINTER.length) {
      const shown = track(POINTER_SHOWN, T, linear) * (still && !(T > 1 && T < 2.05) && !(T > 7.2 && T < 9) ? 0 : 1);
      const [x, y] = track(POINTER, T);
      const click = CLICKS.some((t) => Math.abs(T - t) < 0.012) || Object.values(HELD).some(([a0, b0]) => T >= a0 && T < b0);
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
  const display = $('#display');
  const stack = $('#stack');
  const caps = $$('#caps .cap');
  const index = $('#index');
  const indexLinks = $$('a', index);
  const indexNow = $('#index-now');
  const dayTime = $('[data-daytime]');
  const dayPartEl = $('[data-daypart]');
  const stageKey = $('.day .fnkey');
  const floatBox = $('#float');
  const groundLayers = { noon: $('.ground__noon'), late: $('.ground__late'), dusk: $('.ground__dusk') };
  const calm = window.matchMedia('(prefers-reduced-motion: reduce)');

  // Build the board in the picture, then the scene that drives it.
  $('[data-board]', display).innerHTML = TILE_ORDER.map(tileHTML).join('');
  fillSceneCalendar($('.w-cal', display));
  $('[data-slot="web"]', display).innerHTML = RENDER.web()
    .replace(/<div class="w-hover"[\s\S]*?<\/span>\s*<\/div>/, '')
    .replace(/ data-[a-z-]+(="[^"]*")?/g, '');
  const stageScene = makeScene(display);

  // Captions: one span per word, so they can fill in as you read.
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
      word.style.color = `rgba(12,13,16,${(0.2 + 0.8 * key / 40).toFixed(3)})`;
    });
  }
  const capCache = caps.map(() => []);

  // The big clock beside the screen. It is left-aligned, so only the
  // minutes move as they change.
  const paintDayTime = (m) => text(dayTime, clockText(m));
  let lastPart = '';
  function paintDayPart(m) {
    const part = dayPart(m);
    if (part === lastPart) return;
    lastPart = part;
    dayPartEl.innerHTML = `<b>Thursday</b><span>${part}</span>`;
  }

  // The page's light: three washes faded over dawn.
  const groundMemo = {};
  function paintGround(m) {
    const p = groundMix(m);
    for (const [key, layer] of Object.entries(groundLayers)) {
      const value = p[key].toFixed(3);
      if (groundMemo[key] !== value) { groundMemo[key] = value; layer.style.opacity = value; }
    }
  }

  let mode = '';
  let T = -1;
  const state = { vh: window.innerHeight, preDistance: 1, lengthsPx: [], indexTop: 0, indexRow: 26 };

  function isTakeMode() {
    return window.innerWidth >= 900 && window.innerHeight >= 560 && !calm.matches;
  }

  // Size the screen to the viewport. The screen keeps the left of the
  // content column, the day takes the right edge, and the captions get two
  // headline-sized lines below the screen.
  function layout() {
    const vw = document.documentElement.clientWidth;
    const vh = window.innerHeight;
    state.vh = vh;
    if (mode === 'take') {
      const side = vw >= 1360 ? 56 : vw >= 1100 ? 40 : 28;
      const rw = Math.round(clamp(vw * 0.165, 180, 270));
      const gap = Math.round(clamp(vw * 0.03, 26, 52));
      let cap = Math.round(clamp(Math.min(vw * 0.037, vh * 0.062), 32, 62));
      let fit = null;
      for (let attempt = 0; attempt < 6; attempt += 1) {
        const capGap = Math.round(cap * 0.42);
        const capH = cap * 1.04 * 2 + 4;
        const bottom = Math.max(24, vh * 0.035);
        let dh = vh - 70 - capGap - capH - bottom;
        let dw = Math.min(dh * 1300 / 820, vw - 2 * side - gap - rw, 1300);
        dw = Math.round(dw);
        dh = Math.round(dw * 820 / 1300);
        const cw = dw + gap + rw;
        const block = dh + capGap + capH;
        const top = Math.round(60 + Math.max(10, (vh - 60 - block - bottom) / 2));
        fit = { dw, dh, cw, rw, gap, cap, capGap, top, dayH: Math.round(block - 4) };
        root.style.setProperty('--dw', `${dw}px`);
        root.style.setProperty('--dh', `${dh}px`);
        root.style.setProperty('--cw', `${cw}px`);
        root.style.setProperty('--rw', `${rw}px`);
        root.style.setProperty('--gap', `${gap}px`);
        root.style.setProperty('--cap', `${cap}px`);
        root.style.setProperty('--capgap', `${capGap}px`);
        root.style.setProperty('--top', `${top}px`);
        root.style.setProperty('--day-h', `${fit.dayH}px`);
        root.style.setProperty('--f', (dw / 1300).toFixed(5));
        // Two lines at most: if a caption wraps to three, set them all smaller.
        const tallest = Math.max(...caps.map((cap0) => cap0.offsetHeight));
        if (tallest <= capH + 2 || cap <= 30) break;
        cap = Math.round(cap * 0.94);
      }
      stageScene.fit = fit.dw / 1300;
      state.lengthsPx = LENGTHS.map((l) => l * vh);
      take.style.height = `${vh + state.lengthsPx.reduce((s, v) => s + v, 0)}px`;
      state.preDistance = Math.max(take.offsetTop, 1);
      const rows = $$('li', index);
      if (rows.length && rows[0].offsetHeight) {
        state.indexTop = rows[0].offsetTop;
        state.indexRow = rows[0].offsetHeight;
      }
    } else {
      ['--dw', '--dh', '--cw', '--rw', '--gap', '--cap', '--capgap', '--top', '--day-h', '--f'].forEach((name) => root.style.removeProperty(name));
      take.style.height = '';
      const inner = $('.still__in', stack);
      const width = (inner && inner.clientWidth) || (document.documentElement.clientWidth - 32);
      const viewWidth = window.innerWidth >= 900 ? (width - 40) * 1.7 / 2.7 : width;
      stack.style.setProperty('--cf', (viewWidth / 1300).toFixed(5));
      stills.forEach((still) => { still.scene.fit = viewWidth / 1300; });
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

  // Scroll position for a given T (used by the list of moments).
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
      cap.style.transform = `translateY(${((1 - on) * 14 - (1 - off) * 14).toFixed(1)}px)`;
      cap.style.filter = opacity > 0.98 ? 'none' : `blur(${((1 - on) * 8 + (1 - off) * 8).toFixed(1)}px)`;
      const [a, b] = FILL[i];
      paintWords(capWords[i], seg(t, a, b), capCache[i]);
    });
    indexLinks.forEach((link) => flag(link, 'is-on', Number(link.dataset.go) === active && T > -0.05));
  }

  // The day beside the screen: the clock, the part of the day, and the
  // marker that walks down the list of moments.
  function renderDay() {
    const m = minutesAt(T);
    paintDayTime(m);
    paintDayPart(m);
    paintGround(m);
    const y = state.indexTop + clamp(T, 0, 10) * state.indexRow;
    indexNow.style.transform = `translateY(${y.toFixed(1)}px)`;
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
      renderDay();
      if (peek.state === 'pinned' && peek.where === 'stage' && stageVisibility() < 0.4) dismiss();
    } else {
      renderStillCaptions();
      const stackRect = stack.getBoundingClientRect();
      flag(floatBox, 'is-shown', stackRect.top < state.vh * 0.6 && stackRect.bottom > state.vh * 0.5);
      paintGround(lerp(480, 1110, seg(state.vh * 0.5, stackRect.top, stackRect.bottom)));
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
    stack.innerHTML = '';
    MOMENTS.forEach((moment, index) => {
      const item = document.createElement('li');
      item.className = 'still';
      // Each still sits on the light of its hour; neighbours meet halfway.
      const before = index === 0 ? 480 : (MOMENTS[index - 1].m + moment.m) / 2;
      const after = index === MOMENTS.length - 1 ? 1116 : (moment.m + MOMENTS[index + 1].m) / 2;
      item.style.background = `linear-gradient(${groundColor(before)}, ${groundColor(after)})`;
      const inner = document.createElement('div');
      inner.className = 'still__in';
      const time = document.createElement('p');
      time.className = 'still__time';
      time.innerHTML = `<b>${clockText(moment.m)}</b><span><strong>Thursday</strong> ${dayPart(moment.m)}</span>`;
      const view = document.createElement('div');
      view.className = 'still__view';
      view.setAttribute('aria-hidden', 'true');
      const cam = document.createElement('div');
      cam.className = 'cam';
      const copy = template.cloneNode(true);
      cam.append(copy);
      view.append(cam);
      const cap = document.createElement('p');
      cap.className = 'still__cap';
      cap.textContent = caps[index].textContent;
      inner.append(time, view, cap);
      item.append(inner);
      stack.append(item);
      const scene = makeScene(copy);
      stills.push({ index, scene, cap, words: splitWords(cap), cache: [] });
    });
  }

  function renderStills() {
    stills.forEach((still) => render(still.scene, MOMENTS[still.index].T, { still: true, minutes: MOMENTS[still.index].m }));
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
    const scene = mode === 'take' ? stageScene : (stills[7] && stills[7].scene);
    if (!scene) return;
    render(scene, 7.5);
    const screenRect = scene.screen.getBoundingClientRect();
    const k = screenRect.width / 1280;
    if (!k) return;
    const centre = (element) => {
      const r = element.getBoundingClientRect();
      return [(r.left + r.width / 2 - screenRect.left) / k, (r.top + r.height / 2 - screenRect.top) / k];
    };
    for (const [app, element] of Object.entries(scene.dockIcons)) P.dock[app] = centre(element);
    P.sam = centre($('i', scene.rem.sam));
    P.free = centre(scene.segFree);
    P.flow = centre(scene.segFlow);
    P.edit = centre(scene.edit);
    P.boardMid = [700, 600];
    P.webMid = [24 + 344 + 300, 46 + 420];
    P.webEdge = [24 + 344 + 260, 46 + 730];
    P.pdf = [24 + 878 + 177, 46 + 394 + 150];
    P.clock = [24 + 190, 46 + 120];
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
  $('[data-rem-count]', povBoard).textContent = $$('.w-rem__item', povBoard).length;
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

  // ---- The list of moments ------------------------------------------------------

  indexLinks.forEach((link) => link.addEventListener('click', (event) => {
    event.preventDefault();
    const k = Number(link.dataset.go);
    const target = k === 1 ? 0.3 : MOMENTS[k - 1].T - 0.04;
    window.scrollTo({ top: scrollForT(target), behavior: calm.matches ? 'auto' : 'smooth' });
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
  setInterval(updateClocks, 1000);
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
  window.__day = { peek, scrollForT, minutesAt, get T() { return T; }, get mode() { return mode; }, render: () => onFrame() };
})();
