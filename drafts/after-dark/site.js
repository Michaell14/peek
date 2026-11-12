// Blink, "After Dark" draft. The page is its own demo: hold Space (or the key
// drawn on the page) and the overlay appears, as fn does in the app.
(() => {
  'use strict';

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));
  const clamp = (value, low = 0, high = 1) => Math.min(Math.max(value, low), high);
  const seg = (p, a, b) => clamp((p - a) / (b - a)); // how far p is between a and b
  const lerp = (a, b, t) => a + (b - a) * t;
  const ease = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
  const easeOut = (t) => 1 - Math.pow(1 - t, 3);
  const calm = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const narrowQuery = window.matchMedia('(max-width: 860px)');
  const coarse = window.matchMedia('(hover: none) and (pointer: coarse)').matches;
  let narrow = narrowQuery.matches;
  const TAP_THRESHOLD = 300; // ms: shorter than this is a tap, longer is a hold

  function make(tag, className, html) {
    const element = document.createElement(tag);
    if (className) element.className = className;
    if (html != null) element.innerHTML = html;
    return element;
  }

  // Position of an element inside an ancestor, ignoring transforms.
  function offsetIn(element, ancestor) {
    let x = 0;
    let y = 0;
    let node = element;
    while (node && node !== ancestor) {
      x += node.offsetLeft;
      y += node.offsetTop;
      node = node.offsetParent;
    }
    return { x, y, w: element.offsetWidth, h: element.offsetHeight };
  }

  // ---------------------------------------------------------------------
  // Small line icons, drawn here so the page needs no icon font.
  // ---------------------------------------------------------------------

  const icon = (paths) => `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths}</svg>`;
  const ICONS = {
    clock: icon('<circle cx="8" cy="8" r="6"/><path d="M8 4.6V8l2.3 1.5"/>'),
    reminders: icon('<circle cx="3.6" cy="4.5" r="1.4"/><circle cx="3.6" cy="11.5" r="1.4"/><path d="M7.4 4.5h6M7.4 11.5h6"/>'),
    web: icon('<circle cx="8" cy="8" r="6"/><path d="M2 8h12M8 2c2 2 2 10 0 12M8 2c-2 2-2 10 0 12"/>'),
    calendar: icon('<rect x="2.2" y="3" width="11.6" height="10.8" rx="2"/><path d="M2.2 6.6h11.6M5.4 1.8v2.4M10.6 1.8v2.4"/>'),
    notes: icon('<rect x="2.6" y="2.2" width="10.8" height="11.6" rx="2"/><path d="M5.2 5.6h5.6M5.2 8h5.6M5.2 10.4h3.2"/>'),
    back: icon('<path d="M10 3.5 5.5 8l4.5 4.5"/>'),
    forward: icon('<path d="M6 3.5 10.5 8 6 12.5"/>'),
    reload: icon('<path d="M13 8a5 5 0 1 1-1.6-3.7M13 2.8v3h-3"/>'),
    more: icon('<circle cx="4" cy="8" r=".6"/><circle cx="8" cy="8" r=".6"/><circle cx="12" cy="8" r=".6"/>'),
    sun: '<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="3.1" fill="currentColor"/><path stroke="currentColor" stroke-width="1.4" stroke-linecap="round" d="M8 1.3v1.5M8 13.2v1.5M1.3 8h1.5M13.2 8h1.5M3.3 3.3l1 1M11.7 11.7l1 1M3.3 12.7l1-1M11.7 4.3l1-1"/></svg>',
    moon: '<svg viewBox="0 0 16 16" aria-hidden="true"><path fill="currentColor" d="M13.4 10A5.7 5.7 0 0 1 6 2.6a5.7 5.7 0 1 0 7.4 7.4z"/></svg>',
  };

  // ---------------------------------------------------------------------
  // What goes in a tile. Each renderer returns a fresh element; sizes in
  // the CSS are in em, so a tile can be drawn at any scale.
  // ---------------------------------------------------------------------

  const ZONES3 = [{ name: 'Local' }, { name: 'London', zone: 'Europe/London' }, { name: 'Tokyo', zone: 'Asia/Tokyo' }];
  const ZONES4 = [{ name: 'Local' }, { name: 'London', zone: 'Europe/London' }, { name: 'New York', zone: 'America/New_York' }, { name: 'Tokyo', zone: 'Asia/Tokyo' }];

  const REMINDERS = [
    { label: 'Overdue' },
    { title: 'Send the invoice', when: 'Yesterday', late: true },
    { label: 'Today' },
    { title: 'Water the plants', when: 'Today' },
    { title: 'Call the dentist', when: 'Today, 11:30' },
    { title: 'Book the room for Thursday', when: 'Today' },
  ];

  const RENDER = {
    clock: () => renderClock(ZONES3),
    clock4: () => renderClock(ZONES4),
    reminders: () => renderReminders(REMINDERS),
    calendar: () => renderCalendar(),
    web: () => renderDashboard(),
    mail: () => renderMail(),
    pdf: () => renderPDF(),
    notes: () => renderNotes(),
    site: () => renderSite(),
  };

  function renderClock(zones) {
    const root = make('div', 'w-clock');
    root.innerHTML = zones.map((entry) => `
      <div class="w-clock__row" data-zone="${entry.zone || ''}">
        <span class="w-clock__glyph"></span>
        <span class="w-clock__place"><b>${entry.name}</b><span></span></span>
        <span class="w-clock__time"></span>
      </div>`).join('') + '<p class="w-clock__add">+ Add City</p>';
    return root;
  }

  function renderReminders(items) {
    const root = make('div', 'w-rem');
    const rows = items.map((item) => (item.label
      ? `<p class="w-label">${item.label}</p>`
      : `<button type="button" class="w-rem__item"><i></i><span><b>${item.title}</b><small${item.late ? ' class="is-late"' : ''}>${item.when}</small></span></button>`)).join('');
    root.innerHTML = `
      <div class="w-rem__head">
        <div class="segmented" aria-hidden="true"><span class="is-on">Today</span><span>Scheduled</span><span>All</span></div>
        <span class="w-rem__count"></span>
      </div>
      <div class="w-rem__list">${rows}</div>
      <label class="w-rem__new"><span aria-hidden="true">+</span><input type="text" placeholder="New Reminder" aria-label="New reminder"></label>`;
    const list = $('.w-rem__list', root);
    const count = $('.w-rem__count', root);
    const recount = () => { count.textContent = $$('.w-rem__item:not(.is-done)', list).length; };
    list.addEventListener('click', (event) => {
      const item = event.target.closest('.w-rem__item');
      if (!item) return;
      item.classList.toggle('is-done');
      item.setAttribute('aria-pressed', item.classList.contains('is-done'));
      recount();
    });
    $('input', root).addEventListener('keydown', (event) => {
      const input = event.currentTarget;
      if (event.key !== 'Enter' || !input.value.trim()) return;
      const item = make('button', 'w-rem__item', '<i></i><span><b></b><small>Today</small></span>');
      item.type = 'button';
      $('b', item).textContent = input.value.trim();
      list.append(item);
      input.value = '';
      recount();
      list.scrollTop = list.scrollHeight;
    });
    recount();
    return root;
  }

  function renderCalendar() {
    const root = make('div', 'w-cal');
    root.innerHTML = `
      <div class="w-cal__head">
        <span class="w-cal__day"></span>
        <span class="w-cal__date"><b></b><span></span></span>
        <span class="segmented" aria-hidden="true"><span class="is-on">Day</span><span>7 Days</span></span>
      </div>
      <div class="w-cal__grid"></div>`;
    paintCalendar(root, new Date());
    return root;
  }

  function renderDashboard() {
    const root = make('div', 'w-web');
    root.innerHTML = `
      <div class="w-web__body">
        <h5>Example dashboard</h5>
        <p class="w-web__sub">Last 7 days</p>
        <div class="w-web__stats">
          <div class="w-web__card"><small>Visitors</small><b>12,480</b><em class="up">▲ 8.2%</em></div>
          <div class="w-web__card"><small>Sign-ups</small><b>342</b><em class="up">▲ 3.1%</em></div>
          <div class="w-web__card"><small>Bounce rate</small><b>38%</b><em class="down">▼ 1.4%</em></div>
          <div class="w-web__card"><small>Avg. visit</small><b>2m 41s</b><em class="up">▲ 12s</em></div>
        </div>
        <div class="w-web__card w-web__wide"><small>Visitors per day</small>
          <div class="w-web__chart"><i style="height:46%"></i><i style="height:58%"></i><i style="height:52%"></i><i style="height:71%"></i><i style="height:88%"></i><i style="height:64%"></i><i style="height:97%"></i></div>
        </div>
        <div class="w-web__card w-web__wide"><small>Top pages</small>
          <div class="w-web__rows"><div><span>/</span><span>5,210</span></div><div><span>/pricing</span><span>2,034</span></div><div><span>/docs/getting-started</span><span>1,377</span></div><div><span>/blog/launch</span><span>962</span></div></div>
        </div>
      </div>`;
    return root;
  }

  function renderMail() {
    const root = make('div', 'w-mail');
    root.innerHTML = `
      <div class="w-mail__top"><b>Inbox</b><span>12 unread</span></div>
      <ul>
        <li class="is-new"><b>Sam Okafor</b><time>9:38</time><span>Thursday works. Shall we say two?</span></li>
        <li class="is-new"><b>Build bot</b><time>9:31</time><span>main is green again after 4 attempts</span></li>
        <li class="is-new"><b>Priya N.</b><time>9:12</time><span>Review requested: tidy the importer</span></li>
        <li><b>Accounts</b><time>8:50</time><span>Invoice 0042 is due on Friday</span></li>
        <li><b>Lena Fischer</b><time>Mon</time><span>Notes from yesterday, and one question</span></li>
        <li><b>Harbour Ferries</b><time>Mon</time><span>Your timetable for November</span></li>
      </ul>`;
    return root;
  }

  function renderPDF() {
    const root = make('div', 'w-pdf');
    const rows = (list) => list.map(([a, b, c]) => `<tr><td>${a}</td><td>${b}</td><td>${c}</td></tr>`).join('');
    root.innerHTML = `
      <div class="w-pdf__page">
        <h6>Harbour line</h6>
        <p>Weekday timetable, from 2 November</p>
        <table>
          <thead><tr><th>Departs</th><th>From</th><th>Arrives</th></tr></thead>
          <tbody>${rows([['07:10', 'West Pier', '07:32'], ['07:40', 'West Pier', '08:02'], ['08:15', 'Old Quay', '08:41'], ['08:45', 'West Pier', '09:07'], ['09:30', 'Old Quay', '09:56'], ['12:10', 'West Pier', '12:32'], ['15:40', 'Old Quay', '16:06'], ['17:05', 'West Pier', '17:27'], ['17:35', 'West Pier', '17:57'], ['18:20', 'Old Quay', '18:46'], ['19:15', 'West Pier', '19:37']])}</tbody>
        </table>
      </div>`;
    return root;
  }

  function renderNotes() {
    const area = make('textarea', 'w-notes');
    area.placeholder = 'Type something. It will still be here next time you look.';
    area.setAttribute('aria-label', 'Notes');
    area.spellcheck = false;
    try { area.value = localStorage.getItem('blink-after-dark-note') || 'Door code for the studio: 4471\nAsk Sam: Thursday at two?\n'; } catch (error) { area.value = 'Door code for the studio: 4471\nAsk Sam: Thursday at two?\n'; }
    area.addEventListener('input', () => {
      try { localStorage.setItem('blink-after-dark-note', area.value); } catch (error) { /* private window */ }
    });
    return area;
  }

  // A website with its controls showing, set to refresh every 30 seconds.
  function renderSite() {
    const root = make('div', 'w-site');
    const bars = [32, 48, 41, 66, 58, 72, 61, 80, 74, 88, 70, 22];
    root.innerHTML = `
      <div class="tilebar">
        <span class="tilebar__btn" aria-hidden="true">${ICONS.back}</span>
        <span class="tilebar__btn" aria-hidden="true">${ICONS.forward}</span>
        <button type="button" class="tilebar__btn" data-reload aria-label="Reload">${ICONS.reload}</button>
        <span class="tilebar__url">shop.example.com/today</span>
        <span class="tilebar__refresh" title="Auto-Refresh: 30 seconds">
          <svg viewBox="0 0 20 20" aria-hidden="true"><circle class="track" cx="10" cy="10" r="8"/><circle class="left" cx="10" cy="10" r="8" stroke-dasharray="50.27" stroke-dashoffset="0"/></svg>
          <span data-count>0:30</span>
        </span>
        <span class="tilebar__btn" aria-hidden="true">${ICONS.more}</span>
      </div>
      <div class="w-site__page">
        <i class="w-site__load"></i>
        <div class="w-site__inner">
          <div class="w-site__top"><h5>Orders today</h5><span data-updated></span></div>
          <div class="w-site__big"><b data-orders>46</b><em data-delta></em></div>
          <div class="w-site__bars">${bars.map((h) => `<i style="height:${h}%"></i>`).join('')}</div>
          <div class="w-site__list" data-list>
            <p><span>#1046</span><span>Tide chart print, A3</span><span>£24</span></p>
            <p><span>#1045</span><span>Lighthouse mug</span><span>£12</span></p>
            <p><span>#1044</span><span>Harbour map, framed</span><span>£58</span></p>
            <p><span>#1043</span><span>Postcards, set of 6</span><span>£9</span></p>
            <p><span>#1042</span><span>Tide chart print, A2</span><span>£32</span></p>
          </div>
        </div>
      </div>`;

    const PERIOD = 30;
    const count = $('[data-count]', root);
    const ring = $('.left', root);
    const load = $('.w-site__load', root);
    const inner = $('.w-site__inner', root);
    const updated = $('[data-updated]', root);
    const orders = $('[data-orders]', root);
    const delta = $('[data-delta]', root);
    const list = $('[data-list]', root);
    const lastBar = $$('.w-site__bars i', root).pop();
    const items = ['Lighthouse mug', 'Tide chart print, A3', 'Postcards, set of 6', 'Sea glass earrings', 'Harbour map, framed', 'Fog horn whistle'];
    const prices = ['£12', '£24', '£9', '£18', '£58', '£6'];
    let left = PERIOD;
    let number = 46;
    let order = 1046;
    let barHeight = 22;
    const stamp = () => { updated.textContent = `Updated ${new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' })}`; };

    function refresh() {
      left = PERIOD;
      load.classList.remove('is-on');
      void load.offsetWidth;
      load.classList.add('is-on');
      inner.classList.add('is-dim');
      setTimeout(() => {
        const added = 1 + Math.floor(Math.random() * 3);
        number += added;
        barHeight = Math.min(barHeight + added * 6, 96);
        orders.textContent = number;
        delta.textContent = `+${added} since the last look`;
        lastBar.style.height = `${barHeight}%`;
        for (let i = 0; i < added; i += 1) {
          order += 1;
          const pick = Math.floor(Math.random() * items.length);
          const row = make('p', 'is-fresh', `<span>#${order}</span><span>${items[pick]}</span><span>${prices[pick]}</span>`);
          list.prepend(row);
        }
        while (list.children.length > 5) list.lastElementChild.remove();
        stamp();
        inner.classList.remove('is-dim');
        load.classList.remove('is-on');
      }, 650);
    }

    function tick() {
      left -= 1;
      if (left <= 0) refresh();
      count.textContent = `0:${String(left).padStart(2, '0')}`;
      ring.style.strokeDashoffset = (50.27 * (1 - left / PERIOD)).toFixed(2);
    }
    $('[data-reload]', root).addEventListener('click', refresh);
    stamp();
    setInterval(tick, 1000);
    return root;
  }

  // ---- Keeping the live tiles live ---------------------------------------

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

  const localPlace = (Intl.DateTimeFormat().resolvedOptions().timeZone || 'Here').split('/').pop().replace(/_/g, ' ');

  function updateClocks() {
    const now = new Date();
    const time = now.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
    $$('[data-live-time]').forEach((element) => { element.textContent = time.replace(/\s?[AP]M/i, ''); });
    const date = now.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' }).replace(',', '');
    $$('[data-live-date]').forEach((element) => { element.textContent = date; });
    $$('[data-live-day]').forEach((element) => { element.textContent = now.getDate(); });
    const month = now.toLocaleDateString('en-GB', { month: 'short' }).toUpperCase();
    $$('[data-live-mon]').forEach((element) => { element.textContent = month; });

    $$('.w-clock__row').forEach((row) => {
      const zone = row.dataset.zone || undefined;
      const parts = new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit', timeZone: zone }).formatToParts(now);
      const digits = parts.filter((part) => ['hour', 'literal', 'minute'].includes(part.type)).map((part) => part.value).join('').trim();
      const period = (parts.find((part) => part.type === 'dayPeriod') || {}).value || '';
      const hour = hourIn(zone, now);
      const day = hour >= 6 && hour < 18;
      const glyph = $('.w-clock__glyph', row);
      const glyphClass = `w-clock__glyph ${day ? 'is-day' : 'is-night'}`;
      if (glyph.className !== glyphClass) {
        glyph.className = glyphClass;
        glyph.innerHTML = day ? ICONS.sun : ICONS.moon;
      }
      const html = `${digits}<small>${period}</small>`;
      const timeElement = $('.w-clock__time', row);
      if (timeElement.innerHTML !== html) timeElement.innerHTML = html;
      let detail = localPlace;
      if (zone) {
        const difference = dayDifference(zone, now);
        const offset = offsetHours(zone, now);
        const dayName = difference > 0 ? 'Tomorrow' : difference < 0 ? 'Yesterday' : 'Today';
        detail = offset === 0 ? dayName : `${dayName}, ${offset > 0 ? '+' : '−'}${Math.abs(offset)} ${Math.abs(offset) === 1 ? 'hr' : 'hrs'}`;
      }
      const place = $('.w-clock__place span', row);
      if (place.textContent !== detail) place.textContent = detail;
    });
  }

  // A day that always has something going on around now.
  function paintCalendar(root, now) {
    $('.w-cal__day', root).textContent = now.getDate();
    $('.w-cal__date b', root).textContent = now.toLocaleDateString([], { weekday: 'long' });
    $('.w-cal__date span', root).textContent = now.toLocaleDateString([], { month: 'long' });
    const grid = $('.w-cal__grid', root);
    const anchor = Math.min(Math.max(now.getHours(), 2), 18);
    const first = anchor - 2;
    const hours = 9;
    const scale = 100 / hours;
    const position = (hour) => (hour - first) * scale;
    const events = [
      { title: 'Standup', start: anchor - 1.5, end: anchor - 1.1, color: '#5fd0c2', column: 0, of: 1 },
      { title: 'Design review', start: anchor, end: anchor + 1, color: '#5b9dff', column: 0, of: 2 },
      { title: '1:1 with Sam', start: anchor + 0.5, end: anchor + 1.5, color: '#b98cff', column: 1, of: 2 },
      { title: 'Lunch', start: anchor + 2, end: anchor + 2.75, color: '#5fd0c2', column: 0, of: 1 },
      { title: 'Ship it', start: anchor + 3.5, end: anchor + 4.5, color: '#ffc761', column: 0, of: 1 },
      { title: 'Call with Lena', start: anchor + 5.25, end: anchor + 6, color: '#ff8a7a', column: 0, of: 1 },
    ];
    const label = (hour) => new Date(2000, 0, 1, Math.floor(hour), Math.round((hour % 1) * 60))
      .toLocaleTimeString([], { hour: 'numeric', minute: hour % 1 ? '2-digit' : undefined });
    let html = '';
    for (let i = 1; i < hours; i += 1) {
      html += `<div class="w-cal__hour" style="top:${(i * scale).toFixed(3)}%"><span>${label(first + i)}</span></div>`;
    }
    for (const event of events) {
      const width = `calc((100% - 4.1em) / ${event.of} - 3px)`;
      const left = `calc(3.6em + (100% - 4.1em) / ${event.of} * ${event.column})`;
      html += `<div class="w-cal__event" style="--c:${event.color};background:${event.color}38;top:calc(${position(event.start).toFixed(3)}% + 1px);height:calc(${((event.end - event.start) * scale).toFixed(3)}% - 3px);left:${left};width:${width}"><b>${event.title}</b><span>${label(event.start)}</span></div>`;
    }
    html += '<div class="w-cal__now"><span></span></div>';
    grid.innerHTML = html;
    grid.dataset.first = first;
    moveNowLine(root, now);
  }

  function moveNowLine(root, now) {
    const grid = $('.w-cal__grid', root);
    const line = $('.w-cal__now', grid);
    if (!line) return;
    const first = Number(grid.dataset.first);
    const hour = now.getHours() + now.getMinutes() / 60 + now.getSeconds() / 3600;
    line.style.top = `${((hour - first) * 100 / 9).toFixed(3)}%`;
    line.firstChild.textContent = now.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }).replace(/\s?[AP]M/i, '');
  }

  let calendarHour = new Date().getHours();
  function updateCalendars() {
    const now = new Date();
    if (now.getHours() !== calendarHour) {
      calendarHour = now.getHours();
      $$('.w-cal').forEach((root) => paintCalendar(root, now));
    } else {
      $$('.w-cal').forEach((root) => moveNowLine(root, now));
    }
  }

  // Fill every static tile placeholder on the page.
  function fillTiles(root = document) {
    $$('[data-render]', root).forEach((holder) => {
      if (holder.firstChild) return;
      holder.append(RENDER[holder.dataset.render]());
    });
  }

  // ---------------------------------------------------------------------
  // Boards: tiles, the two layout modes, and arranging. One class serves
  // the overlay and the arrange scene.
  // ---------------------------------------------------------------------

  const GAP = 14;

  // Flow layout, as in the app: tiles are packed in order into full-height
  // columns; short tiles stack and the last one in a column stretches.
  function flowColumns(items, height) {
    const columns = [];
    let used = 0;
    let fills = false;
    for (const item of items) {
      if (item.h == null) {
        columns.push([item]); fills = true; used = height;
        continue;
      }
      const h = Math.min(Math.max(item.h, 80), height);
      if (columns.length && !fills && used + GAP + h <= height + 0.5) {
        columns[columns.length - 1].push(item); used += GAP + h;
      } else {
        columns.push([item]); fills = false; used = h;
      }
    }
    return columns;
  }

  function flowLayout(items, width, height) {
    const frames = new Map();
    if (!items.length) return frames;
    const columns = flowColumns(items, height);
    let widths = columns.map((column) => Math.max(...column.map((item) => item.w)));
    const gaps = GAP * (columns.length - 1);
    const natural = widths.reduce((a, b) => a + b, 0);
    const room = Math.max(width - gaps, 1);
    if (natural > room) widths = widths.map((w) => w * room / natural);
    const total = widths.reduce((a, b) => a + b, 0) + gaps;
    let x = Math.max(0, (width - total) / 2);
    columns.forEach((column, index) => {
      let y = 0;
      column.forEach((item, row) => {
        const last = row === column.length - 1;
        const h = last ? Math.max(height - y, 0) : Math.min(Math.max(item.h ?? height, 80), height);
        frames.set(item.id, { x: Math.round(x), y: Math.round(y), w: Math.round(widths[index]), h: Math.round(h) });
        y += h + GAP;
      });
      x += widths[index] + GAP;
    });
    return frames;
  }

  // Where a dragged tile would land: an index into the list without it.
  function insertionIndex(point, movingID, items, width, height) {
    const others = items.filter((item) => item.id !== movingID);
    if (!others.length) return 0;
    const frames = flowLayout(others, width, height);
    const columns = flowColumns(others, height);
    let best = 0;
    let bestDistance = Infinity;
    others.forEach((item, index) => {
      const f = frames.get(item.id);
      const dx = Math.max(f.x - point.x, 0, point.x - (f.x + f.w));
      const dy = Math.max(f.y - point.y, 0, point.y - (f.y + f.h));
      const distance = Math.hypot(dx, dy);
      if (distance < bestDistance) { bestDistance = distance; best = index; }
    });
    const f = frames.get(others[best].id);
    const stacked = columns.find((column) => column.includes(others[best])).length > 1;
    const after = stacked ? point.y > f.y + f.h / 2 : point.x > f.x + f.w / 2;
    return best + (after ? 1 : 0);
  }

  const CATALOG = {
    clock: { title: 'Clock', w: 290, h: 232 },
    reminders: { title: 'Reminders', w: 300, h: null },
    web: { title: 'Example dashboard', w: 420, h: null },
    calendar: { title: 'Calendar', w: 300, h: null },
    notes: { title: 'Notes', w: 290, h: 220 },
  };

  class Board {
    constructor(element, options = {}) {
      this.el = element;
      this.arrange = !!options.arrange;
      this.scale = options.scale || (() => 1);
      this.stackBelow = options.stackBelow || 0;
      this.onMode = options.onMode || (() => {});
      this.mode = 'flow';
      this.isEditing = this.arrange;
      this.tiles = [];
      if (this.arrange) {
        this.guideX = make('i', 'board__guide board__guide--x');
        this.guideY = make('i', 'board__guide board__guide--y');
        this.el.append(this.guideX, this.guideY);
      }
    }

    add(kind) {
      const spec = CATALOG[kind];
      const element = make('section', 'tile');
      element.setAttribute('aria-label', spec.title);
      element.append(RENDER[kind]());
      const cover = make('div', 'tile__cover');
      if (this.arrange) {
        cover.innerHTML = '<span class="tile__grip"></span><span class="tile__size"></span>';
        $$('button, input, textarea', element).forEach((control) => { control.tabIndex = -1; });
      } else {
        cover.innerHTML = `${ICONS[kind]}<span>${spec.title}</span>`;
      }
      element.append(cover);
      const tile = { id: kind, kind, w: spec.w, h: spec.h, frame: null, el: element };
      cover.addEventListener('pointerdown', (event) => {
        if (event.target.classList.contains('tile__size')) this.beginResize(tile, event);
        else this.beginDrag(tile, event);
      });
      this.tiles.push(tile);
      this.el.append(element);
      return tile;
    }

    size() { return { width: this.el.clientWidth, height: this.el.clientHeight }; }

    get isStacked() { return this.stackBelow > 0 && window.innerWidth < this.stackBelow; }

    layout(animated, skip = null) {
      this.el.classList.toggle('is-stacked', this.isStacked);
      if (this.isStacked) {
        const heights = { clock: 220, reminders: 320, web: 520, calendar: 440, notes: 200 };
        this.tiles.forEach((tile) => { tile.el.style.height = `${heights[tile.kind]}px`; });
        return;
      }
      const { width, height } = this.size();
      if (!width || !height) return;
      const frames = this.mode === 'flow' ? flowLayout(this.tiles, width, height) : null;
      for (const tile of this.tiles) {
        if (frames) tile.frame = frames.get(tile.id);
        if (!tile.frame || tile === skip) continue;
        const f = tile.frame;
        tile.el.style.transitionDuration = animated ? '' : '0s';
        Object.assign(tile.el.style, { left: `${f.x}px`, top: `${f.y}px`, width: `${f.w}px`, height: `${f.h}px` });
      }
      if (!animated) {
        void this.el.offsetWidth; // apply without animating, then restore
        this.tiles.forEach((tile) => { tile.el.style.transitionDuration = ''; });
      }
    }

    setMode(mode) {
      if (mode === this.mode) return;
      if (mode === 'flow') {
        // Read the canvas left to right, then top to bottom.
        this.tiles.sort((a, b) => (a.frame.x - b.frame.x) || (a.frame.y - b.frame.y));
      }
      this.mode = mode; // freeform simply starts from where flow left things
      this.el.classList.toggle('is-free', mode === 'freeform');
      this.layout(true);
      this.onMode(mode);
    }

    setEditing(editing) {
      if (this.arrange) return;
      this.isEditing = editing;
      this.el.classList.toggle('is-editing', editing);
    }

    point(event) {
      const bounds = this.el.getBoundingClientRect();
      const s = this.scale();
      return { x: (event.clientX - bounds.left) / s, y: (event.clientY - bounds.top) / s };
    }

    // Freeform: snap to the canvas edges and to the other tiles.
    snap(tile, x, y, w, h, edges = 'move') {
      const { width, height } = this.size();
      const threshold = 10;
      const xs = [];
      const ys = [];
      if (edges === 'move') {
        xs.push({ v: 0, line: 0 }, { v: width - w, line: width });
        ys.push({ v: 0, line: 0 }, { v: height - h, line: height });
      } else {
        xs.push({ v: width, line: width });
        ys.push({ v: height, line: height });
      }
      for (const other of this.tiles) {
        if (other === tile || !other.frame) continue;
        const o = other.frame;
        if (edges === 'move') {
          xs.push({ v: o.x, line: o.x }, { v: o.x + o.w - w, line: o.x + o.w }, { v: o.x + o.w + GAP, line: o.x + o.w + GAP / 2 }, { v: o.x - w - GAP, line: o.x - GAP / 2 });
          ys.push({ v: o.y, line: o.y }, { v: o.y + o.h - h, line: o.y + o.h }, { v: o.y + o.h + GAP, line: o.y + o.h + GAP / 2 }, { v: o.y - h - GAP, line: o.y - GAP / 2 });
        } else {
          xs.push({ v: o.x + o.w, line: o.x + o.w }, { v: o.x - GAP, line: o.x - GAP / 2 });
          ys.push({ v: o.y + o.h, line: o.y + o.h }, { v: o.y - GAP, line: o.y - GAP / 2 });
        }
      }
      const valueX = edges === 'move' ? x : x + w;
      const valueY = edges === 'move' ? y : y + h;
      const pick = (list, value) => list.reduce((best, c) => (Math.abs(c.v - value) < threshold && (!best || Math.abs(c.v - value) < Math.abs(best.v - value)) ? c : best), null);
      const sx = pick(xs, valueX);
      const sy = pick(ys, valueY);
      this.showGuides(sx && sx.line, sy && sy.line);
      return { x: sx ? sx.v : valueX, y: sy ? sy.v : valueY };
    }

    showGuides(x, y) {
      if (!this.guideX) return;
      this.guideX.classList.toggle('is-on', x != null);
      this.guideY.classList.toggle('is-on', y != null);
      if (x != null) this.guideX.style.left = `${x}px`;
      if (y != null) this.guideY.style.top = `${y}px`;
    }

    beginDrag(tile, event) {
      if (!this.isEditing || this.isStacked || event.button !== 0) return;
      // On a touch screen the board is drawn too small to drag, so the page scrolls instead.
      if (event.pointerType === 'touch' && this.arrange) return;
      event.preventDefault();
      const handle = event.currentTarget;
      handle.setPointerCapture(event.pointerId);
      const start = this.point(event);
      const origin = { ...tile.frame };
      tile.el.classList.add('is-dragging');
      tile.el.style.transitionProperty = 'box-shadow';

      const move = (moveEvent) => {
        const { width, height } = this.size();
        const now = this.point(moveEvent);
        let x = origin.x + now.x - start.x;
        let y = origin.y + now.y - start.y;
        if (this.mode === 'freeform') {
          x = clamp(x, 0, width - origin.w);
          y = clamp(y, 0, height - origin.h);
          const snapped = this.snap(tile, x, y, origin.w, origin.h);
          x = snapped.x;
          y = snapped.y;
          tile.frame = { ...origin, x, y };
        }
        tile.el.style.left = `${x}px`;
        tile.el.style.top = `${y}px`;
        if (this.mode === 'freeform') return;
        const index = insertionIndex(now, tile.id, this.tiles, width, height);
        const others = this.tiles.filter((other) => other !== tile);
        others.splice(index, 0, tile);
        if (others.some((other, i) => other !== this.tiles[i])) {
          this.tiles = others;
          this.layout(true, tile); // the others make room; this one follows the pointer
        }
      };
      const end = () => {
        handle.removeEventListener('pointermove', move);
        handle.removeEventListener('pointerup', end);
        handle.removeEventListener('pointercancel', end);
        tile.el.classList.remove('is-dragging');
        tile.el.style.transitionProperty = '';
        this.showGuides(null, null);
        this.layout(true);
      };
      handle.addEventListener('pointermove', move);
      handle.addEventListener('pointerup', end);
      handle.addEventListener('pointercancel', end);
    }

    beginResize(tile, event) {
      if (this.mode !== 'freeform' || event.button !== 0 || event.pointerType === 'touch') return;
      event.preventDefault();
      event.stopPropagation();
      const handle = event.target;
      handle.setPointerCapture(event.pointerId);
      const start = this.point(event);
      const origin = { ...tile.frame };
      tile.el.classList.add('is-dragging');
      tile.el.style.transitionProperty = 'box-shadow';
      const move = (moveEvent) => {
        const { width, height } = this.size();
        const now = this.point(moveEvent);
        let w = clamp(origin.w + now.x - start.x, 170, width - origin.x);
        let h = clamp(origin.h + now.y - start.y, 120, height - origin.y);
        const snapped = this.snap(tile, origin.x, origin.y, w, h, 'resize');
        w = clamp(snapped.x - origin.x, 170, width - origin.x);
        h = clamp(snapped.y - origin.y, 120, height - origin.y);
        tile.frame = { ...origin, w, h };
        tile.el.style.width = `${w}px`;
        tile.el.style.height = `${h}px`;
      };
      const end = () => {
        handle.removeEventListener('pointermove', move);
        handle.removeEventListener('pointerup', end);
        handle.removeEventListener('pointercancel', end);
        tile.el.classList.remove('is-dragging');
        tile.el.style.transitionProperty = '';
        this.showGuides(null, null);
      };
      handle.addEventListener('pointermove', move);
      handle.addEventListener('pointerup', end);
      handle.addEventListener('pointercancel', end);
    }
  }

  // ---------------------------------------------------------------------
  // The shortcut. In the app it is yours to choose; on this page it is Space.
  // ---------------------------------------------------------------------

  const SHORTCUT = 'Space';
  let shortcutHeld = false;

  function isShortcut(event) {
    return event.code === SHORTCUT && !event.ctrlKey && !event.altKey && !event.shiftKey && !event.metaKey;
  }

  function isTyping(target) {
    return target instanceof HTMLElement
      && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName))
      && target.type !== 'checkbox';
  }

  // ---------------------------------------------------------------------
  // Hold or tap. The same small state machine the app uses.
  // ---------------------------------------------------------------------

  const overlay = $('#overlay');
  const keys = $$('[data-blink-key]');
  const peek = { state: 'hidden', since: 0, uses: 0 };
  const board = new Board($('#board'), { stackBelow: 760 });

  function setKeysDown(down) {
    keys.forEach((key) => key.classList.toggle('is-down', down));
  }

  function shortcutDown() {
    const now = performance.now();
    setKeysDown(true);
    keys.forEach((key) => key.classList.add('is-used'));
    if (peek.state === 'hidden' || peek.state === 'releasing') {
      peek.state = 'holding';
      peek.since = now;
      showOverlay();
    } else if (peek.state === 'pinned') {
      peek.state = 'releasing';
      hideOverlay();
    }
  }

  function shortcutUp() {
    const now = performance.now();
    setKeysDown(false);
    if (peek.state === 'holding') {
      if (now - peek.since <= TAP_THRESHOLD) {
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
    if (peek.state === 'pinned') {
      peek.state = 'hidden';
      hideOverlay();
    } else if (peek.state === 'holding') {
      peek.state = 'releasing';
      hideOverlay();
    }
  }

  function showOverlay() {
    peek.uses += 1;
    board.layout(false);
    overlay.classList.add('is-open');
    overlay.setAttribute('aria-hidden', 'false');
    document.body.classList.add('is-peeking');
    requestFrame();
  }

  function hideOverlay() {
    setPinned(false);
    overlay.classList.remove('is-open');
    overlay.setAttribute('aria-hidden', 'true');
    document.body.classList.remove('is-peeking');
    requestFrame();
  }

  let restoreFocus = null;

  function setPinned(pinned) {
    overlay.classList.toggle('is-pinned', pinned);
    keys.forEach((key) => key.classList.toggle('is-pinned', pinned));
    // While Blink is open the page behind it is out of reach, as your desktop would be.
    $$('main, .bar, .foot').forEach((element) => { element.inert = pinned; });
    if (pinned) {
      restoreFocus = document.activeElement;
      overlay.focus({ preventScroll: true });
    } else {
      board.setEditing(false);
      editButton.textContent = 'Edit';
      editButton.classList.remove('is-on');
      $('#overlay-hint').textContent = 'Space or esc to close';
      if (restoreFocus && document.contains(restoreFocus)) restoreFocus.focus({ preventScroll: true });
      restoreFocus = null;
    }
  }

  window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && peek.state !== 'hidden') {
      event.preventDefault();
      if (board.isEditing) { board.setEditing(false); editButton.textContent = 'Edit'; editButton.classList.remove('is-on'); } else dismiss();
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
    event.preventDefault(); // or a focused button would be "clicked"
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

  // The key on the page works with a mouse or a finger too.
  let pressedKey = null;
  keys.forEach((key) => {
    key.addEventListener('pointerdown', (event) => {
      if (event.button !== 0 || pressedKey) return;
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

  overlay.addEventListener('pointerdown', (event) => {
    if (event.target === overlay || event.target === board.el) {
      if (!board.isEditing) dismiss();
    }
  });
  $('#board-close').addEventListener('click', dismiss);
  const editButton = $('#board-edit');
  editButton.addEventListener('click', () => {
    board.setEditing(!board.isEditing);
    editButton.textContent = board.isEditing ? 'Done' : 'Edit';
    editButton.classList.toggle('is-on', board.isEditing);
    $('#overlay-hint').textContent = board.isEditing ? 'Drag a tile to move it' : 'Space or esc to close';
  });
  $$('[data-board-mode]').forEach((button) => {
    button.addEventListener('click', () => board.setMode(button.dataset.boardMode));
  });
  board.onMode = (mode) => $$('[data-board-mode]').forEach((button) => button.classList.toggle('is-on', button.dataset.boardMode === mode));

  // ---------------------------------------------------------------------
  // Scenes. Each tall section reports how far through it the page has
  // scrolled (0 to 1), and one rAF-throttled handler updates them all.
  // ---------------------------------------------------------------------

  let vw = window.innerWidth;
  let vh = window.innerHeight;

  // ---- 1 + 2: the stage ----------------------------------------------------

  const stage = {
    el: $('#stage'),
    pin: $('#stage-pin'),
    hero: $('#hero'),
    beatA: $('#beat-a'),
    beatB: $('#beat-b'),
    dock: $('#dock'),
    writer: $('#writer'),
    notice: $('#notice'),
    glass: $('#desk-glass'),
    lifts: $$('.lift').map((element) => ({
      kind: element.dataset.lift,
      el: element,
      body: $('.lift__body', element),
      icon: $(`[data-dock="${element.dataset.lift}"]`),
    })),
    natural: { mail: 300, calendar: 270, web: 380, reminders: 270, pdf: 290 },

    setup() {
      this.lifts.forEach((lift) => {
        const tint = make('div', 'lift__tint');
        lift.el.prepend(tint);
        lift.tint = tint;
        const face = lift.icon.cloneNode(true);
        $$('.badge', face).forEach((badge) => badge.remove());
        face.removeAttribute('data-dock');
        face.classList.add('lift-face');
        $('#desk').append(face);
        lift.face = face;
      });
    },

    measure() {
      const w = this.pin.clientWidth;
      const h = this.pin.clientHeight;
      const bar = 44;
      let frames;
      if (!narrow) {
        const textRight = this.beatB.offsetLeft + this.beatB.offsetWidth + Math.max(36, w * 0.03);
        const r = { x: textRight, y: bar + 24, w: w - textRight - 24, h: h - bar - 24 - 100 }; // the corner below is the key's
        const colW = [0.31, 0.38, 0.31].map((f) => (r.w - 2 * GAP) * f);
        const x1 = r.x + colW[0] + GAP;
        const x2 = x1 + colW[1] + GAP;
        const half = (r.h - GAP) / 2;
        const calH = (r.h - GAP) * 0.56;
        frames = {
          mail: { x: r.x, y: r.y, w: colW[0], h: half },
          reminders: { x: r.x, y: r.y + half + GAP, w: colW[0], h: half },
          web: { x: x1, y: r.y, w: colW[1], h: r.h },
          calendar: { x: x2, y: r.y, w: colW[2], h: calH },
          pdf: { x: x2, y: r.y + calH + GAP, w: colW[2], h: r.h - calH - GAP },
        };
      } else {
        const top = this.beatB.offsetTop + this.beatB.offsetHeight + 22;
        const r = { x: 14, y: top, w: w - 28, h: Math.max(h - top - 84, 200) }; // the corner below is the key's
        const half = (r.w - GAP) / 2;
        const rows = [0.36, 0.28, 0.36].map((f) => (r.h - 2 * GAP) * f);
        const y1 = r.y + rows[0] + GAP;
        const y2 = y1 + rows[1] + GAP;
        frames = {
          mail: { x: r.x, y: r.y, w: half, h: rows[0] },
          calendar: { x: r.x + half + GAP, y: r.y, w: half, h: rows[0] },
          web: { x: r.x, y: y1, w: r.w, h: rows[1] },
          reminders: { x: r.x, y: y2, w: half, h: rows[2] },
          pdf: { x: r.x + half + GAP, y: y2, w: half, h: rows[2] },
        };
      }
      this.lifts.forEach((lift) => {
        const f = frames[lift.kind];
        Object.keys(f).forEach((k) => { f[k] = Math.round(f[k]); });
        lift.frame = f;
        lift.from = offsetIn(lift.icon, this.pin);
        lift.radius = parseFloat(getComputedStyle(lift.icon).borderTopLeftRadius) || 12;
        Object.assign(lift.el.style, { left: `${f.x}px`, top: `${f.y}px`, width: `${f.w}px`, height: `${f.h}px` });
        lift.body.style.fontSize = `${clamp(13 * f.w / this.natural[lift.kind], 7, 13.5).toFixed(2)}px`;
        Object.assign(lift.face.style, { left: `${lift.from.x}px`, top: `${lift.from.y}px` });
      });
      this.dockShift = this.dock.offsetHeight + 24;
    },

    update(rawP) {
      // With reduced motion, show three resting states and nothing in between.
      const p = calm ? (rawP < 0.2 ? 0 : rawP < 0.5 ? 0.27 : 1) : rawP;

      const heroOut = seg(p, 0, 0.07);
      this.hero.style.opacity = (1 - heroOut).toFixed(3);
      this.hero.style.transform = heroOut ? `translate3d(0, ${(-heroOut * 34).toFixed(1)}px, 0)` : '';
      this.hero.style.filter = heroOut > 0 && heroOut < 1 ? `blur(${(heroOut * 8).toFixed(1)}px)` : '';
      this.hero.style.visibility = heroOut >= 1 ? 'hidden' : ''; // and out of the tab order

      const dockIn = easeOut(seg(p, 0.07, 0.15));
      this.dock.style.transform = `translate3d(0, ${((1 - dockIn) * this.dockShift).toFixed(1)}px, 0)`;
      this.dock.classList.toggle('has-badges', p > 0.16 && p < 0.42);

      const writerIn = easeOut(seg(p, 0.09, 0.17));
      this.writer.style.opacity = writerIn.toFixed(3);
      this.writer.style.transform = `translate3d(0, ${((1 - writerIn) * 36).toFixed(1)}px, 0) scale(${(0.97 + 0.03 * writerIn).toFixed(4)})`;

      const noticeIn = seg(p, 0.19, 0.24);
      this.notice.style.opacity = (noticeIn * (1 - seg(p, 0.35, 0.39))).toFixed(3);
      this.notice.style.transform = `translate3d(${((1 - easeOut(noticeIn)) * 40).toFixed(1)}px, 0, 0)`;

      fadeBeat(this.beatA, seg(p, 0.12, 0.19), seg(p, 0.33, 0.39));
      this.glass.style.opacity = seg(p, 0.35, 0.47).toFixed(3);

      const arc = narrow ? 40 : 90;
      this.lifts.forEach((lift, index) => {
        const start = 0.39 + index * 0.075;
        const e = ease(seg(p, start, start + 0.16));
        const flying = e > 0;
        if (flying !== lift.flying) {
          lift.flying = flying;
          lift.el.classList.toggle('is-flying', flying);
          lift.face.classList.toggle('is-flying', flying);
          lift.icon.classList.toggle('is-gone', flying);
        }
        if (!flying) return;
        const f = lift.frame;
        const r = lift.from;
        const sx = lerp(r.w / f.w, 1, e);
        const sy = lerp(r.h / f.h, 1, e);
        const x = lerp(r.x, f.x, e);
        const y = lerp(r.y, f.y, e) - Math.sin(Math.PI * e) * arc;
        lift.el.style.transform = `translate3d(${(x - f.x).toFixed(2)}px, ${(y - f.y).toFixed(2)}px, 0) scale(${sx.toFixed(4)}, ${sy.toFixed(4)})`;
        const radius = lerp(lift.radius, narrow ? 12 : 18, e);
        lift.el.style.borderRadius = `${(radius / sx).toFixed(2)}px / ${(radius / sy).toFixed(2)}px`;
        lift.tint.style.opacity = (1 - seg(e, 0.12, 0.6)).toFixed(3);
        const content = lift.body.firstElementChild;
        if (content) content.style.opacity = seg(e, 0.55, 0.95).toFixed(3);
        const cx = x + (f.w * sx) / 2 - (r.x + r.w / 2);
        const cy = y + (f.h * sy) / 2 - (r.y + r.h / 2);
        lift.face.style.transform = `translate3d(${cx.toFixed(2)}px, ${cy.toFixed(2)}px, 0) scale(${lerp(1, 1.8, e).toFixed(3)})`;
        lift.face.style.opacity = (1 - seg(e, 0.1, 0.45)).toFixed(3);
      });

      fadeBeat(this.beatB, seg(p, 0.79, 0.87), 0);
    },
  };

  // Words come in sharp and leave soft.
  function fadeBeat(element, inT, outT) {
    const shown = easeOut(inT) * (1 - outT);
    element.style.opacity = shown.toFixed(3);
    const y = (1 - easeOut(inT)) * 26 - outT * 20;
    element.style.transform = `translate3d(0, ${y.toFixed(1)}px, 0)`;
    element.style.filter = outT > 0 && outT < 1 ? `blur(${(outT * 10).toFixed(1)}px)` : '';
  }

  // ---- 3: hold, let go, tap --------------------------------------------------

  const modes = {
    el: $('#modes'),
    screen: $('#modes-screen'),
    key: $('#modes-key'),
    label: $('#modes-state'),
    typed: $('#modes-typed'),
    pointer: $('#modes-pointer'),
    notes: $$('[data-note]'),
    words: [],
    lineOf: [],
    lit: -1,
    state: null,
    timers: [],

    setup() {
      $$('.scrub__line').forEach((line, index) => {
        const words = line.textContent.trim().split(/\s+/);
        line.innerHTML = words.map((word) => `<span class="w">${word}</span>`).join(' ');
        $$('.w', line).forEach((word) => { this.words.push(word); this.lineOf.push(index); });
      });
      // The overlay in the picture: the same four tiles, laid out the same way.
      const canvas = $('#modes-board');
      const widths = { clock: 320, reminders: 320, web: 524, calendar: 352 };
      const items = Object.keys(widths).map((kind) => ({ id: kind, w: widths[kind], h: CATALOG[kind].h }));
      const frames = flowLayout(items, 1280 - 56, 800 - 80);
      for (const item of items) {
        const f = frames.get(item.id);
        const tile = make('div', 'tile');
        tile.append(RENDER[item.id]());
        Object.assign(tile.style, { left: `${f.x}px`, top: `${f.y}px`, width: `${f.w}px`, height: `${f.h}px` });
        canvas.append(tile);
      }
    },

    update(p) {
      const lit = calm ? this.words.length : Math.round(seg(p, 0.03, 0.8) * this.words.length);
      if (lit !== this.lit) {
        this.lit = lit;
        this.words.forEach((word, index) => word.classList.toggle('is-lit', index < lit));
      }
      let beat = lit === 0 ? -1 : this.lineOf[lit - 1];
      if (calm) beat = p < 0.5 ? 0 : 2;
      this.setState(beat);
    },

    later(fn, ms) { this.timers.push(setTimeout(fn, ms)); },

    setState(beat) {
      const names = ['hold', 'letgo', 'tap'];
      const state = names[beat] || 'idle';
      if (state === this.state) return;
      this.state = state;
      this.timers.forEach(clearTimeout);
      this.timers = [];
      this.screen.dataset.state = state;
      this.notes.forEach((note) => note.classList.toggle('is-on', Number(note.dataset.note) === beat));
      this.key.classList.remove('is-down', 'is-lit');
      const say = (text) => { this.label.textContent = text; };
      if (state === 'idle') say('Scroll to try each one');
      if (state === 'hold') { this.key.classList.add('is-down'); say('Holding fn: Blink is open'); }
      if (state === 'letgo') {
        say('Let go: back in the document');
        if (!this.typed.textContent) this.type(', which is gone the moment you leave it.');
      }
      if (state === 'tap') {
        say('Tapped fn: Blink stays open');
        this.key.classList.add('is-down');
        this.later(() => { this.key.classList.remove('is-down'); this.key.classList.add('is-lit'); }, 150);
        this.pointer.style.setProperty('--px', '900px');
        this.pointer.style.setProperty('--py', '700px');
        this.later(() => {
          const item = $('.w-rem__item', this.screen);
          if (!item) return;
          const spot = offsetIn($('i', item), this.screen);
          this.pointer.style.setProperty('--px', `${spot.x + 4}px`);
          this.pointer.style.setProperty('--py', `${spot.y + 4}px`);
          this.later(() => {
            item.classList.add('is-done');
            $('.w-rem__count', this.screen).textContent = $$('.w-rem__item:not(.is-done)', this.screen).length;
          }, calm ? 0 : 950);
        }, calm ? 0 : 450);
      }
    },

    type(text) {
      if (calm) { this.typed.textContent = text; return; }
      let index = 0;
      const step = () => {
        index += 1;
        this.typed.textContent = text.slice(0, index);
        if (index < text.length) this.later(step, 45 + Math.random() * 60);
      };
      this.later(step, 400);
    },
  };

  // ---- 4: the gallery, which moves sideways ------------------------------------

  const gallery = {
    el: $('#holds'),
    track: $('#gallery-track'),
    rail: $('#gallery-rail'),
    span: 0,
    size() {
      if (narrow || calm) {
        this.el.style.height = '';
        this.track.style.transform = '';
        this.span = 0;
        return;
      }
      this.span = Math.max(this.track.scrollWidth - window.innerWidth, 0);
      this.el.style.height = `${Math.round(vh + this.span)}px`;
    },
    update(p) {
      if (!this.span) return;
      const e = clamp((p - 0.05) / 0.9);
      this.track.style.transform = `translate3d(${(-e * this.span).toFixed(1)}px, 0, 0)`;
      this.rail.style.setProperty('--g', e.toFixed(4));
    },
  };

  // ---- 6: less noise -------------------------------------------------------------

  const noise = {
    el: $('#noise'),
    news: $('#news'),
    flow: $('#news-flow'),
    rest: $('#news-rest'),
    picker: $('#news-picker'),
    pointer: $('#news-pointer'),
    steps: $$('.noise__steps li'),
    parts: Object.fromEntries($$('[data-nz]').map((element) => [element.dataset.nz, element])),
    measure() {
      const area = $('.news', this.news);
      this.leaderH = this.parts.leader.offsetHeight;
      this.sideH = this.parts.side.offsetHeight + 18;
      this.letter = offsetIn(this.parts.letter, area);
      this.areaW = area.offsetWidth;
      this.areaH = area.offsetHeight;
    },
    dissolve(element, t, drop = 10) {
      element.style.opacity = (1 - t).toFixed(3);
      element.style.transform = t ? `translate3d(0, ${(t * drop).toFixed(1)}px, 0) scale(${(1 - t * 0.04).toFixed(4)})` : '';
      element.style.filter = t > 0 && t < 1 ? `blur(${(t * 7).toFixed(1)}px)` : '';
      element.style.visibility = t >= 1 ? 'hidden' : '';
    },
    update(rawP) {
      const p = calm ? (rawP < 0.5 ? 0 : 1) : rawP;
      this.dissolve(this.parts.cookie, seg(p, 0.1, 0.24), 60);
      const leader = seg(p, 0.32, 0.44);
      this.dissolve(this.parts.leader, leader);
      const shiftA = -this.leaderH * ease(seg(p, 0.36, 0.48));
      this.flow.style.transform = `translate3d(0, ${shiftA.toFixed(1)}px, 0)`;
      this.dissolve(this.parts.side, seg(p, 0.38, 0.5));
      const shiftB = -this.sideH * ease(seg(p, 0.42, 0.54));
      this.rest.style.transform = `translate3d(0, ${shiftB.toFixed(1)}px, 0)`;
      this.dissolve(this.parts.video, seg(p, 0.46, 0.58), 30);

      // Then the pointer picks the sign-up box, and it is gone for good.
      const l = this.letter;
      const box = { x: l.x, y: l.y + shiftA + shiftB, w: l.w, h: l.h };
      const travel = ease(seg(p, 0.62, 0.72));
      const px = lerp(this.areaW * 0.42, box.x + box.w * 0.55, travel);
      const py = lerp(this.areaH * 0.92, box.y + box.h * 0.5, travel);
      const pointerOn = seg(p, 0.6, 0.63) * (1 - seg(p, 0.9, 0.94));
      this.pointer.style.opacity = pointerOn.toFixed(3);
      this.pointer.style.transform = `translate3d(${px.toFixed(1)}px, ${py.toFixed(1)}px, 0) scale(1.25)`;
      const gone = seg(p, 0.8, 0.9);
      this.picker.style.opacity = (seg(p, 0.72, 0.75) * (1 - gone)).toFixed(3);
      this.picker.style.transform = `translate3d(${box.x - 4}px, ${(box.y - 4).toFixed(1)}px, 0)`;
      this.picker.style.width = `${box.w + 8}px`;
      this.picker.style.height = `${box.h + 8}px`;
      this.dissolve(this.parts.letter, gone);

      const lit = calm ? [p >= 1, p >= 1, p >= 1] : [p > 0.14, p > 0.4, p > 0.74];
      this.steps.forEach((step, index) => step.classList.toggle('is-on', lit[index]));
    },
  };

  const scenes = [stage, modes, gallery, noise];

  // ---- The key: large in the hero, then docked in the corner -------------------

  const keyEl = $('#key');
  const keySlot = $('#key-slot');
  const keyHint = $('#key-hint');
  const bar = $('#bar');
  let keyBase = 164;
  let slot = { x: 0, y: 0 };
  let lastKeyTransform = '';

  function measureKey() {
    keyBase = keyEl.offsetWidth || 164;
    slot = offsetIn(keySlot, stage.pin);
  }

  function placeKey(t) {
    const dockSize = narrow ? 52 : 60;
    const margin = narrow ? 18 : 26;
    const toX = vw - margin - dockSize;
    const toY = vh - margin - dockSize;
    const e = calm ? (t < 0.5 ? 0 : 1) : ease(t);
    const x = lerp(slot.x, toX, e);
    const y = lerp(slot.y, toY, e);
    const s = lerp(1, dockSize / keyBase, e);
    const transform = `translate3d(${x.toFixed(1)}px, ${y.toFixed(1)}px, 0) scale(${s.toFixed(4)})`;
    if (transform !== lastKeyTransform) { keyEl.style.transform = transform; lastKeyTransform = transform; }
    return e;
  }

  // ---- The loop -------------------------------------------------------------------

  function measureAll() {
    vw = window.innerWidth;
    vh = window.innerHeight;
    narrow = narrowQuery.matches;
    fitScreens();
    gallery.size();
    for (const scene of scenes) {
      scene.top = scene.el.getBoundingClientRect().top + window.scrollY;
      scene.height = scene.el.offsetHeight;
      if (scene.measure) scene.measure();
    }
    measureKey();
    arrangeBoard.layout(false);
    if (overlay.classList.contains('is-open')) board.layout(false);
    frame(true);
  }

  function frame(force = false) {
    const y = window.scrollY;
    for (const scene of scenes) {
      const span = Math.max(scene.height - vh, 1);
      const p = clamp((y - scene.top) / span);
      if (force || p !== scene.p) {
        scene.p = p;
        scene.update(p);
      }
    }
    const docked = placeKey(seg(stage.p, 0, 0.085));
    const past = stage.p > 0.07 || y > stage.top + stage.height;
    bar.classList.toggle('is-past', past);
    const page = document.documentElement;
    const atEnd = y + vh > page.scrollHeight - 700;
    const early = y < gallery.top - vh * 0.3; // a reminder while the first scenes play, then it gets out of the way
    keyHint.classList.toggle('is-on', docked >= 1 && early && !atEnd && peek.uses < 2 && peek.state === 'hidden');
  }

  let frameRequest = 0;
  function requestFrame() {
    if (frameRequest) return;
    frameRequest = requestAnimationFrame(() => { frameRequest = 0; frame(); });
  }
  window.addEventListener('scroll', requestFrame, { passive: true });

  let measureRequest = 0;
  function requestMeasure() {
    if (measureRequest) return;
    measureRequest = requestAnimationFrame(() => { measureRequest = 0; measureAll(); });
  }
  window.addEventListener('resize', () => {
    if (board.mode === 'freeform') {
      const { width, height } = board.size();
      board.tiles.forEach((tile) => {
        if (!tile.frame) return;
        tile.frame.x = Math.max(0, Math.min(tile.frame.x, width - tile.frame.w));
        tile.frame.y = Math.max(0, Math.min(tile.frame.y, height - tile.frame.h));
      });
    }
    requestMeasure();
  });

  // Pictures of screens are drawn at one size and scaled to fit their frame.
  function fitScreens() {
    $$('.screen-fit').forEach((fit) => {
      const design = fit.classList.contains('screen-fit--news') ? 1000 : 1280;
      fit.style.setProperty('--s', (fit.clientWidth / design).toFixed(5));
    });
  }

  // ---- 5: arrange ------------------------------------------------------------------

  const arrangeFit = $('#arrange-fit');
  const arrangeBoard = new Board($('#arrange-board'), {
    arrange: true,
    scale: () => Number(getComputedStyle(arrangeFit).getPropertyValue('--s')) || 0.5,
  });
  const arrangeSwitch = $('.switch');
  arrangeBoard.onMode = (mode) => {
    $$('[data-arrange-mode]').forEach((button) => {
      const on = button.dataset.arrangeMode === mode;
      if (button.hasAttribute('aria-pressed')) button.setAttribute('aria-pressed', on);
      button.classList.toggle('is-on', on);
    });
    arrangeSwitch.classList.toggle('is-free', mode === 'freeform');
    $('#arrange-hint').textContent = mode === 'freeform' ? 'Drag anywhere. Drag a corner to resize.' : 'Drag a tile to reorder';
  };
  $$('[data-arrange-mode]').forEach((button) => {
    button.addEventListener('click', () => arrangeBoard.setMode(button.dataset.arrangeMode));
  });

  // ---------------------------------------------------------------------
  // Start.
  // ---------------------------------------------------------------------

  fillTiles();
  ['clock', 'reminders', 'web', 'calendar'].forEach((kind) => board.add(kind));
  ['clock', 'reminders', 'web', 'calendar', 'notes'].forEach((kind) => arrangeBoard.add(kind));
  stage.setup();
  modes.setup();
  updateClocks();
  updateCalendars();
  measureAll();
  setInterval(updateClocks, 1000);
  setInterval(updateCalendars, 15000);
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(requestMeasure);
  window.addEventListener('load', requestMeasure);
  if ('ResizeObserver' in window) {
    const observer = new ResizeObserver(requestMeasure);
    [arrangeFit, $('#modes-fit'), $('#news-fit')].forEach((element) => observer.observe(element));
  }

  // For the checks.
  window.__blink = { peek, board, arrangeBoard, stage, modes, gallery, noise, shortcutDown, shortcutUp };
})();
