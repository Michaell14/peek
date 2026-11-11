// Blink — site behaviour. The page is its own demo: hold the shortcut anywhere
// and the overlay appears, exactly as the app does it over your desktop.
(() => {
  'use strict';

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));
  const TAP_THRESHOLD = 300; // ms: shorter than this is a tap, longer is a hold

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
  const hint = $('#hint');
  const keys = $$('[data-blink-key]'); // the keys drawn on the page
  const peek = { state: 'hidden', since: 0, uses: 0 };

  function setKeysDown(down) {
    keys.forEach((key) => key.classList.toggle('is-down', down));
  }

  function shortcutDown() {
    const now = performance.now();
    setKeysDown(true);
    retireAttract();
    meterStart(now);
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
      const held = now - peek.since;
      meterStop(held);
      if (held <= TAP_THRESHOLD) {
        peek.state = 'pinned';
        setPinned(true);
      } else {
        peek.state = 'hidden';
        hideOverlay();
      }
    } else if (peek.state === 'releasing') {
      peek.state = 'hidden';
      meterStop(null);
    } else {
      meterStop(null);
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
    hint.classList.remove('is-on');
  }

  function hideOverlay() {
    setPinned(false);
    overlay.classList.remove('is-open');
    overlay.setAttribute('aria-hidden', 'true');
  }

  let restoreFocus = null;

  function setPinned(pinned) {
    overlay.classList.toggle('is-pinned', pinned);
    // While Blink is open the page behind it is out of reach, as your
    // desktop would be.
    $$('main, .top, .footer').forEach((element) => { element.inert = pinned; });
    if (pinned) {
      restoreFocus = document.activeElement;
      overlay.focus({ preventScroll: true });
    } else {
      board.setEditing(false);
      closePalette();
      if (restoreFocus && document.contains(restoreFocus)) restoreFocus.focus({ preventScroll: true });
      restoreFocus = null;
    }
  }

  window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && peek.state !== 'hidden') {
      event.preventDefault();
      if (!$('#palette').hidden) closePalette();
      else if (board.isEditing) board.setEditing(false);
      else dismiss();
      return;
    }
    if (!$('#palette').hidden && handlePaletteKey(event)) return;
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
    if (peek.state === 'holding') { peek.since = -Infinity; }
    shortcutUp();
  });

  // The keys on the page work with a mouse or a finger too.
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
    if (event.target === overlay || event.target === $('#board')) {
      if (!$('#palette').hidden) closePalette();
      else if (!board.isEditing) dismiss();
    }
  });
  $('#board-close').addEventListener('click', dismiss);

  // ---------------------------------------------------------------------
  // The ruler under "Two gestures".
  // ---------------------------------------------------------------------

  const meterFill = $('#meter-fill');
  const meterReadout = $('#meter-readout');
  const METER_SPAN = TAP_THRESHOLD * 4; // the tap zone is the first quarter
  let meterFrame = 0;

  function meterStart(start) {
    cancelAnimationFrame(meterFrame);
    const tick = () => {
      const elapsed = performance.now() - start;
      meterFill.style.width = `${Math.min(elapsed / METER_SPAN, 1) * 100}%`;
      meterFrame = requestAnimationFrame(tick);
    };
    tick();
  }

  function meterStop(held) {
    cancelAnimationFrame(meterFrame);
    if (held === null || !Number.isFinite(held)) return;
    meterFill.style.width = `${Math.min(held / METER_SPAN, 1) * 100}%`;
    const seconds = (held / 1000).toFixed(2);
    meterReadout.innerHTML = held <= TAP_THRESHOLD
      ? `<b>${seconds}s — a tap.</b> Blink stays open until you tap again or press esc.`
      : `<b>${seconds}s — a hold.</b> Blink was there for exactly that long, then got out of the way.`;
  }

  // ---------------------------------------------------------------------
  // The board: tiles, the two layout modes, and arranging.
  // ---------------------------------------------------------------------

  const GAP = 14;
  const boardElement = $('#board');

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

  // Small line icons, drawn here so the page needs no icon font.
  const icon = (paths) => `<svg viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths}</svg>`;
  const ICONS = {
    clock: icon('<circle cx="8" cy="8" r="6"/><path d="M8 4.6V8l2.3 1.5"/>'),
    reminders: icon('<circle cx="3.6" cy="4.5" r="1.4"/><circle cx="3.6" cy="11.5" r="1.4"/><path d="M7.4 4.5h6M7.4 11.5h6"/>'),
    web: icon('<circle cx="8" cy="8" r="6"/><path d="M2 8h12M8 2c2 2 2 10 0 12M8 2c-2 2-2 10 0 12"/>'),
    calendar: icon('<rect x="2.2" y="3" width="11.6" height="10.8" rx="2"/><path d="M2.2 6.6h11.6M5.4 1.8v2.4M10.6 1.8v2.4"/>'),
    notes: icon('<rect x="2.6" y="2.2" width="10.8" height="11.6" rx="2"/><path d="M5.2 5.6h5.6M5.2 8h5.6M5.2 10.4h3.2"/>'),
    sun: '<svg viewBox="0 0 16 16" width="13" height="13" aria-hidden="true"><circle cx="8" cy="8" r="3.1" fill="currentColor"/><path stroke="currentColor" stroke-width="1.4" stroke-linecap="round" d="M8 1.3v1.5M8 13.2v1.5M1.3 8h1.5M13.2 8h1.5M3.3 3.3l1 1M11.7 11.7l1 1M3.3 12.7l1-1M11.7 4.3l1-1"/></svg>',
    moon: '<svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true"><path fill="currentColor" d="M13.4 10A5.7 5.7 0 0 1 6 2.6a5.7 5.7 0 1 0 7.4 7.4z"/></svg>',
  };

  const CATALOG = {
    clock: { title: 'Clock', note: 'The time in the places you care about', w: 290, h: 220 },
    reminders: { title: 'Reminders', note: 'What is due, ready to tick off', w: 300, h: 330 },
    web: { title: 'Example dashboard', note: 'Any website, already loaded', w: 420, h: null },
    calendar: { title: 'Calendar', note: "Today's events", w: 300, h: null },
    notes: { title: 'Notes', note: 'A scratchpad that is always there', w: 280, h: 240 },
  };

  const board = {
    mode: 'flow',
    isEditing: false,
    tiles: [], // { id, kind, w, h, frame, element }

    add(kind) {
      const spec = CATALOG[kind];
      const element = document.createElement('section');
      element.className = 'tile';
      element.setAttribute('aria-label', spec.title);
      element.append(renderers[kind]());

      const cover = document.createElement('div');
      cover.className = 'tile__cover';
      cover.innerHTML = `${ICONS[kind]}<span>${spec.title}</span>`;
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'tile__remove';
      remove.setAttribute('aria-label', `Remove ${spec.title}`);
      remove.innerHTML = '<svg viewBox="0 0 10 10" aria-hidden="true"><path d="M2 2l6 6M8 2l-6 6"/></svg>';
      cover.append(remove);
      element.append(cover);

      const tile = { id: kind, kind, w: spec.w, h: spec.h, frame: null, element };
      remove.addEventListener('pointerdown', (event) => event.stopPropagation());
      remove.addEventListener('click', () => this.remove(tile));
      cover.addEventListener('pointerdown', (event) => this.beginDrag(tile, event));
      this.tiles.push(tile);
      boardElement.append(element);
      return tile;
    },

    remove(tile) {
      tile.element.classList.add('is-leaving');
      this.tiles = this.tiles.filter((other) => other !== tile);
      setTimeout(() => tile.element.remove(), 200);
      this.layout(true);
    },

    size() {
      return { width: boardElement.clientWidth, height: boardElement.clientHeight };
    },

    get isStacked() {
      return window.innerWidth < 760;
    },

    // Positions every tile. Freeform frames are remembered per tile; flow
    // frames are worked out from the order.
    layout(animated, skip = null) {
      boardElement.classList.toggle('is-stacked', this.isStacked);
      if (this.isStacked) {
        // Too narrow for columns: a simple scrolling list.
        const heights = { clock: 190, reminders: 300, web: 520, calendar: 420, notes: 200 };
        this.tiles.forEach((tile) => { tile.element.style.height = `${heights[tile.kind]}px`; });
        return;
      }
      const { width, height } = this.size();
      const frames = this.mode === 'flow' ? flowLayout(this.tiles, width, height) : null;
      for (const tile of this.tiles) {
        if (frames) tile.frame = frames.get(tile.id);
        if (!tile.frame || tile === skip) continue;
        const f = tile.frame;
        tile.element.style.transitionDuration = animated ? '' : '0s';
        Object.assign(tile.element.style, { left: `${f.x}px`, top: `${f.y}px`, width: `${f.w}px`, height: `${f.h}px` });
      }
      if (!animated) {
        void boardElement.offsetWidth; // apply without animating, then restore
        this.tiles.forEach((tile) => { tile.element.style.transitionDuration = ''; });
      }
    },

    setMode(mode) {
      if (mode === this.mode) return;
      if (mode === 'flow') {
        // Read the canvas left to right, then top to bottom.
        this.tiles.sort((a, b) => (a.frame.x - b.frame.x) || (a.frame.y - b.frame.y));
      }
      this.mode = mode; // freeform simply starts from where flow left things
      $$('[data-board-mode]').forEach((button) => button.classList.toggle('is-on', button.dataset.boardMode === mode));
      this.layout(true);
    },

    setEditing(editing) {
      this.isEditing = editing;
      boardElement.classList.toggle('is-editing', editing);
      const button = $('#board-edit');
      button.textContent = editing ? 'Done' : 'Edit';
      button.classList.toggle('is-on', editing);
      $('#overlay-hint').textContent = editing ? 'Drag a tile to move it' : 'Space or esc to close';
    },

    beginDrag(tile, event) {
      if (!this.isEditing || this.isStacked || event.button !== 0) return;
      event.preventDefault();
      const cover = event.currentTarget;
      cover.setPointerCapture(event.pointerId);
      const start = { x: event.clientX, y: event.clientY };
      const origin = { ...tile.frame };
      tile.element.classList.add('is-dragging');

      const move = (moveEvent) => {
        const { width, height } = this.size();
        const dx = moveEvent.clientX - start.x;
        const dy = moveEvent.clientY - start.y;
        const x = this.mode === 'freeform' ? Math.min(Math.max(origin.x + dx, 0), width - origin.w) : origin.x + dx;
        const y = this.mode === 'freeform' ? Math.min(Math.max(origin.y + dy, 0), height - origin.h) : origin.y + dy;
        tile.element.style.left = `${x}px`;
        tile.element.style.top = `${y}px`;
        if (this.mode === 'freeform') {
          tile.frame = { ...origin, x, y };
          return;
        }
        const bounds = boardElement.getBoundingClientRect();
        const point = { x: moveEvent.clientX - bounds.left, y: moveEvent.clientY - bounds.top };
        const index = insertionIndex(point, tile.id, this.tiles, width, height);
        const others = this.tiles.filter((other) => other !== tile);
        others.splice(index, 0, tile);
        if (others.some((other, i) => other !== this.tiles[i])) {
          this.tiles = others;
          this.layout(true, tile); // the others make room; this one follows the pointer
        }
      };
      const end = () => {
        cover.removeEventListener('pointermove', move);
        cover.removeEventListener('pointerup', end);
        cover.removeEventListener('pointercancel', end);
        tile.element.classList.remove('is-dragging');
        this.layout(true);
      };
      cover.addEventListener('pointermove', move);
      cover.addEventListener('pointerup', end);
      cover.addEventListener('pointercancel', end);
    },
  };

  $$('[data-board-mode]').forEach((button) => {
    button.addEventListener('click', () => board.setMode(button.dataset.boardMode));
  });
  $('#board-edit').addEventListener('click', () => board.setEditing(!board.isEditing));
  window.addEventListener('resize', () => {
    if (board.mode === 'freeform') {
      // Keep freeform tiles on the canvas when the window shrinks.
      const { width, height } = board.size();
      board.tiles.forEach((tile) => {
        if (!tile.frame) return;
        tile.frame.x = Math.max(0, Math.min(tile.frame.x, width - tile.frame.w));
        tile.frame.y = Math.max(0, Math.min(tile.frame.y, height - tile.frame.h));
      });
    }
    board.layout(false);
  });

  // ---- Tile contents ----------------------------------------------------

  const ZONES = [
    { zone: undefined, name: 'Local' },
    { zone: 'Europe/London', name: 'London' },
    { zone: 'Asia/Tokyo', name: 'Tokyo' },
  ];

  function hourIn(zone, date) {
    return Number(new Intl.DateTimeFormat('en-GB', { hour: 'numeric', hourCycle: 'h23', timeZone: zone }).format(date));
  }

  function dayDifference(zone, date) {
    const format = (timeZone) => new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
    const there = Date.parse(format(zone));
    const here = Date.parse(format(undefined));
    return Math.round((there - here) / 86400000);
  }

  function offsetHours(zone, date) {
    const local = new Date(date.toLocaleString('en-US'));
    const remote = new Date(date.toLocaleString('en-US', { timeZone: zone }));
    return Math.round((remote - local) / 360000) / 10;
  }

  const renderers = {
    clock() {
      const root = document.createElement('div');
      root.className = 'w-clock';
      root.innerHTML = ZONES.map((entry, index) => `
        <div class="w-clock__row" data-zone-row="${index}">
          <span class="w-clock__glyph"></span>
          <span class="w-clock__place"><b>${entry.name}</b><span></span></span>
          <span class="w-clock__time"></span>
        </div>`).join('');
      return root;
    },

    reminders() {
      const root = document.createElement('div');
      root.className = 'w-rem';
      root.innerHTML = `
        <div class="w-rem__head">
          <div class="segmented segmented--small" aria-hidden="true"><button type="button" class="is-on" tabindex="-1">Today</button><button type="button" tabindex="-1">All</button></div>
          <span class="w-rem__count">3</span>
        </div>
        <div class="w-rem__list">
          <p class="w-label">Overdue</p>
          <button type="button" class="w-rem__item"><i></i><span><b>Send the invoice</b><small class="is-late">Yesterday</small></span></button>
          <p class="w-label">Today</p>
          <button type="button" class="w-rem__item"><i></i><span><b>Water the plants</b><small>Today</small></span></button>
          <button type="button" class="w-rem__item"><i></i><span><b>Try holding the key a little longer</b><small>Today, any time</small></span></button>
        </div>
        <label class="w-rem__new"><span aria-hidden="true">＋</span><input type="text" placeholder="New Reminder" aria-label="New reminder"></label>`;
      const list = $('.w-rem__list', root);
      const count = $('.w-rem__count', root);
      const recount = () => { count.textContent = $$('.w-rem__item:not(.is-done)', list).length; };
      list.addEventListener('click', (event) => {
        const item = event.target.closest('.w-rem__item');
        if (!item) return;
        item.classList.toggle('is-done');
        recount();
      });
      $('input', root).addEventListener('keydown', (event) => {
        const input = event.currentTarget;
        if (event.key !== 'Enter' || !input.value.trim()) return;
        const item = document.createElement('button');
        item.type = 'button';
        item.className = 'w-rem__item';
        item.innerHTML = '<i></i><span><b></b><small>Today</small></span>';
        $('b', item).textContent = input.value.trim();
        list.append(item);
        input.value = '';
        recount();
        list.scrollTop = list.scrollHeight;
      });
      return root;
    },

    web() {
      const root = document.createElement('div');
      root.className = 'w-web';
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
          <div class="w-web__card" style="margin-top:10px"><small>Visitors per day</small>
            <div class="w-web__chart"><i style="height:46%"></i><i style="height:58%"></i><i style="height:52%"></i><i style="height:71%"></i><i style="height:88%"></i><i style="height:64%"></i><i style="height:97%"></i></div>
          </div>
          <div class="w-web__card" style="margin-top:10px"><small>Top pages</small>
            <div class="w-web__rows"><div><span>/</span><span>5,210</span></div><div><span>/pricing</span><span>2,034</span></div><div><span>/docs/getting-started</span><span>1,377</span></div><div><span>/blog/launch</span><span>962</span></div></div>
          </div>
        </div>`;
      return root;
    },

    calendar() {
      const root = document.createElement('div');
      root.className = 'w-cal';
      root.innerHTML = `
        <div class="w-cal__head">
          <span class="w-cal__day"></span>
          <span class="w-cal__date"><b></b><span></span></span>
        </div>
        <div class="w-cal__grid"></div>`;
      return root;
    },

    notes() {
      const area = document.createElement('textarea');
      area.className = 'w-notes';
      area.placeholder = 'Jot something down…';
      area.setAttribute('aria-label', 'Notes');
      return area;
    },
  };

  function updateClocks() {
    const now = new Date();
    const time = now.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
    $$('[data-live-time]').forEach((element) => { element.textContent = time.replace(/\s?[AP]M/i, ''); });
    const date = now.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' }).replace(',', '');
    $$('[data-live-date]').forEach((element) => { element.textContent = date; });

    $$('[data-zone-row]').forEach((row) => {
      const entry = ZONES[Number(row.dataset.zoneRow)];
      const parts = new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit', timeZone: entry.zone }).formatToParts(now);
      const digits = parts.filter((part) => ['hour', 'literal', 'minute'].includes(part.type)).map((part) => part.value).join('').trim();
      const period = (parts.find((part) => part.type === 'dayPeriod') || {}).value || '';
      const hour = hourIn(entry.zone, now);
      const day = hour >= 6 && hour < 18;
      const glyph = $('.w-clock__glyph', row);
      const glyphClass = `w-clock__glyph ${day ? 'is-day' : 'is-night'}`;
      if (glyph.className !== glyphClass) {
        glyph.className = glyphClass;
        glyph.innerHTML = day ? ICONS.sun : ICONS.moon;
      }
      $('.w-clock__time', row).innerHTML = `${digits}<small>${period}</small>`;

      let detail = Intl.DateTimeFormat().resolvedOptions().timeZone.split('/').pop().replace(/_/g, ' ');
      if (entry.zone) {
        const difference = dayDifference(entry.zone, now);
        const offset = offsetHours(entry.zone, now);
        const dayName = difference > 0 ? 'Tomorrow' : difference < 0 ? 'Yesterday' : 'Today';
        detail = offset === 0 ? dayName : `${dayName}, ${offset > 0 ? '+' : '−'}${Math.abs(offset)} ${Math.abs(offset) === 1 ? 'hr' : 'hrs'}`;
      }
      $('.w-clock__place span', row).textContent = detail;
    });
  }

  // A day that always has something going on around now.
  function updateCalendar() {
    const now = new Date();
    $$('.w-cal').forEach((root) => {
      $('.w-cal__day', root).textContent = now.getDate();
      $('.w-cal__date b', root).textContent = now.toLocaleDateString([], { weekday: 'long' });
      $('.w-cal__date span', root).textContent = now.toLocaleDateString([], { month: 'long' });

      const grid = $('.w-cal__grid', root);
      const anchor = Math.min(Math.max(now.getHours(), 2), 19);
      const first = anchor - 2;
      const hours = 9;
      const scale = 100 / hours; // percent per hour
      const position = (hour) => (hour - first) * scale;
      const events = [
        { title: 'Design review', start: anchor, end: anchor + 1, color: '#5b9dff', column: 0, of: 2 },
        { title: '1:1 with Sam', start: anchor + 0.5, end: anchor + 1.5, color: '#b98cff', column: 1, of: 2 },
        { title: 'Lunch', start: anchor + 2, end: anchor + 2.75, color: '#5fd0c2', column: 0, of: 1 },
        { title: 'Ship it', start: anchor + 3.5, end: anchor + 4.5, color: '#ffc761', column: 0, of: 1 },
      ];
      const label = (hour) => new Date(2000, 0, 1, Math.floor(hour), (hour % 1) * 60)
        .toLocaleTimeString([], { hour: 'numeric', minute: hour % 1 ? '2-digit' : undefined });

      let html = '';
      for (let i = 1; i < hours; i += 1) {
        html += `<div class="w-cal__hour" style="top:${i * scale}%"><span>${label(first + i)}</span></div>`;
      }
      for (const event of events) {
        const width = `calc((100% - 54px) / ${event.of} - 3px)`;
        const left = `calc(44px + (100% - 54px) / ${event.of} * ${event.column})`;
        html += `<div class="w-cal__event" style="--c:${event.color};background:${event.color}3d;top:calc(${position(event.start)}% + 1px);height:calc(${(event.end - event.start) * scale}% - 3px);left:${left};width:${width}"><b>${event.title}</b><span>${label(event.start)}</span></div>`;
      }
      const nowHour = now.getHours() + now.getMinutes() / 60;
      if (nowHour >= first && nowHour <= first + hours) {
        html += `<div class="w-cal__now" style="top:${position(nowHour)}%"></div>`;
      }
      grid.innerHTML = html;
    });
  }

  // ---- The "add a tile" palette -----------------------------------------

  const palette = $('#palette');
  const paletteList = $('#palette-list');
  let paletteIndex = 0;

  function openPalette() {
    board.setEditing(false);
    const missing = Object.keys(CATALOG).filter((kind) => !board.tiles.some((tile) => tile.kind === kind));
    paletteIndex = 0;
    paletteList.innerHTML = missing.length
      ? missing.map((kind, index) => `
          <li><button type="button" data-kind="${kind}" class="${index === 0 ? 'is-on' : ''}">
            <i>${ICONS[kind]}</i>
            <span>${CATALOG[kind].title}<small>${CATALOG[kind].note}</small></span>
          </button></li>`).join('')
      : '<li class="palette__empty">Everything is already on the board. In the app, this is where you would type any address.</li>';
    palette.hidden = false;
    const first = $('button', paletteList);
    if (first) first.focus({ preventScroll: true });
  }

  function closePalette() {
    palette.hidden = true;
  }

  function handlePaletteKey(event) {
    const buttons = $$('button', paletteList);
    if (!buttons.length) return false;
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      paletteIndex = (paletteIndex + (event.key === 'ArrowDown' ? 1 : -1) + buttons.length) % buttons.length;
      buttons.forEach((button, index) => button.classList.toggle('is-on', index === paletteIndex));
      buttons[paletteIndex].focus({ preventScroll: true });
      return true;
    }
    return false;
  }

  paletteList.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-kind]');
    if (!button) return;
    const tile = board.add(button.dataset.kind);
    if (board.mode === 'freeform') {
      const { width, height } = board.size();
      const h = tile.h ?? Math.round(height * 0.8);
      tile.frame = { x: Math.round((width - tile.w) / 2), y: Math.round((height - h) / 2), w: tile.w, h };
    }
    closePalette();
    updateClocks();
    updateCalendar();
    board.layout(false);
    $('#board-add').focus({ preventScroll: true });
  });
  $('#board-add').addEventListener('click', () => (palette.hidden ? openPalette() : closePalette()));

  // ---------------------------------------------------------------------
  // "Less noise": three switches over a mock page, and click-to-hide.
  // ---------------------------------------------------------------------

  const quietPage = $('#q-page');
  const quietCount = $('#q-count');
  const quietSwitches = { ads: $('#q-ads'), cookies: $('#q-cookies'), pick: $('#q-pick') };
  const quietCaption = quietCount.textContent;
  const isOn = (button) => button.getAttribute('aria-checked') === 'true';

  // Brings the mock page, and the line under it, in step with the switches.
  function applyQuiet() {
    const ads = isOn(quietSwitches.ads);
    const cookies = isOn(quietSwitches.cookies);
    const picking = isOn(quietSwitches.pick);
    quietPage.classList.toggle('block-ads', ads);
    quietPage.classList.toggle('block-cookies', cookies);
    quietPage.classList.toggle('is-picking', picking);

    const gone = $$('.is-hidden', quietPage).length
      + (ads ? $$('[data-junk="noise"]:not(.is-hidden)', quietPage).length : 0)
      + (cookies ? $$('[data-junk="notice"]:not(.is-hidden)', quietPage).length : 0);
    const lines = [];
    if (gone) lines.push(`${gone} ${gone === 1 ? 'thing' : 'things'} gone. The number is still there.`);
    if (picking) lines.push('Click anything in the page to take it out.');
    quietCount.textContent = lines.join(' ') || quietCaption;
  }

  Object.values(quietSwitches).forEach((button) => {
    button.addEventListener('click', () => {
      button.setAttribute('aria-checked', String(!isOn(button)));
      applyQuiet();
    });
  });
  quietPage.addEventListener('click', (event) => {
    if (!isOn(quietSwitches.pick)) return;
    const target = event.target.closest('[data-pick], [data-junk]');
    if (!target || !quietPage.contains(target)) return;
    target.classList.add('is-hidden');
    applyQuiet();
  });
  $('#q-reset').addEventListener('click', () => {
    $$('.is-hidden', quietPage).forEach((element) => element.classList.remove('is-hidden'));
    Object.values(quietSwitches).forEach((button) => button.setAttribute('aria-checked', 'false'));
    applyQuiet();
  });

  // ---------------------------------------------------------------------
  // Layout modes illustration.
  // ---------------------------------------------------------------------

  $$('[data-layout]').forEach((button) => {
    button.addEventListener('click', () => {
      $('#layout-stage').dataset.mode = button.dataset.layout;
      $$('[data-layout]').forEach((other) => other.classList.toggle('is-on', other === button));
    });
  });

  // ---------------------------------------------------------------------
  // Copy buttons.
  // ---------------------------------------------------------------------

  $$('[data-copy]').forEach((button) => {
    button.addEventListener('click', () => {
      const text = button.dataset.copy;
      const fallback = () => {
        const area = document.createElement('textarea');
        area.value = text;
        document.body.append(area);
        area.select();
        document.execCommand('copy');
        area.remove();
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).catch(fallback);
      } else {
        fallback();
      }
      // Say so straight away rather than after the clipboard answers.
      button.textContent = 'Copied';
      button.classList.add('is-done');
      setTimeout(() => { button.textContent = 'Copy'; button.classList.remove('is-done'); }, 1600);
    });
  });

  // ---------------------------------------------------------------------
  // The story at the top. The section is several screens tall and its
  // contents stay pinned; how far the page has scrolled picks the step.
  // ---------------------------------------------------------------------

  const story = $('#story');
  const screen = $('#screen');
  const steps = $$('.step', story);
  const heroKey = $('#hero-key');
  const topBar = $('#top-bar');
  const running = $('#running');
  const sections = $$('[data-title]');
  const calm = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const tale = { step: 0, attract: true, attractTimer: 0, pressTimer: 0 };

  // The key pressing itself, to show what the picture is showing.
  function setGhost(down) {
    heroKey.classList.toggle('is-ghost', down);
  }

  // Until someone tries it, the picture on the cover holds and lets go by
  // itself every few seconds.
  function startAttract() {
    clearTimeout(tale.attractTimer);
    if (!tale.attract || calm) {
      screen.dataset.attract = 'on';
      return;
    }
    let on = true;
    const turn = () => {
      screen.dataset.attract = on ? 'on' : 'off';
      setGhost(on);
      tale.attractTimer = setTimeout(() => { on = !on; turn(); }, on ? 3600 : 1700);
    };
    turn();
  }

  // Once they have, it stays put.
  function retireAttract() {
    if (!tale.attract) return;
    tale.attract = false;
    clearTimeout(tale.attractTimer);
    screen.dataset.attract = 'on';
    if (tale.step === 0) setGhost(false);
  }

  function setStep(step) {
    if (step === tale.step) return;
    tale.step = step;
    screen.dataset.step = step;
    steps.forEach((element) => {
      const on = Number(element.dataset.step) === step;
      element.classList.toggle('is-on', on);
      if (element.classList.contains('step--intro')) element.inert = !on; // its link should not take focus unseen
    });
    clearTimeout(tale.attractTimer);
    clearTimeout(tale.pressTimer);
    setGhost(false);
    if (step === 0) startAttract();
    // "Or hold one key": the windows clear, then the key goes down.
    if (step === 4) tale.pressTimer = setTimeout(() => setGhost(true), calm ? 0 : 500);
  }

  function readScroll() {
    const bounds = story.getBoundingClientRect();
    const span = Math.max(story.offsetHeight - window.innerHeight, 1);
    const scrolled = Math.min(Math.max(-bounds.top, 0), span);
    const unit = span / (steps.length - 0.4); // the last step gets a full unit to itself
    setStep(Math.min(steps.length - 1, Math.floor(scrolled / unit + 0.4)));

    const past = bounds.bottom < 90;
    topBar.classList.toggle('is-past', past);
    // The running head: the last section to have come up past the middle.
    const line = window.innerHeight * 0.4;
    let current = 0;
    sections.forEach((section, index) => { if (section.getBoundingClientRect().top <= line) current = index; });
    const head = `${String(current + 1).padStart(2, '0')} — ${sections[current].dataset.title}`;
    if (running.textContent !== head) running.textContent = head;
    // Further down, remind people the page is live until they have tried it.
    const page = document.documentElement;
    const atEnd = window.scrollY + window.innerHeight > page.scrollHeight - 240; // leave the footer alone
    hint.classList.toggle('is-on', past && !atEnd && peek.uses < 2 && peek.state === 'hidden');
  }

  let scrollFrame = 0;
  const onScroll = () => {
    if (scrollFrame) return;
    scrollFrame = requestAnimationFrame(() => { scrollFrame = 0; readScroll(); });
  };
  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('resize', onScroll);

  // The picture is drawn at one size and scaled to fit its place.
  const displayWrap = $('#display-wrap');
  const display = $('.display', displayWrap);
  const fitDisplay = () => display.style.setProperty('--s', (displayWrap.clientWidth / 1304).toFixed(4));
  if ('ResizeObserver' in window) new ResizeObserver(fitDisplay).observe(displayWrap);
  window.addEventListener('resize', fitDisplay);

  // Inside it, one of the windows shows the same dashboard as the web tile,
  // and Blink shows the same four tiles as the real demo, laid out the same way.
  function buildScreen() {
    $('#screen-web').append(renderers.web());
    const canvas = $('#screen-board');
    const widths = { clock: 320, reminders: 320, web: 524, calendar: 352 }; // sized to fill this canvas
    const items = Object.keys(widths).map((kind) => ({ id: kind, w: widths[kind], h: CATALOG[kind].h }));
    const frames = flowLayout(items, 1280 - 56, 800 - 78);
    for (const item of items) {
      const f = frames.get(item.id);
      const element = document.createElement('div');
      element.className = 'tile';
      element.append(renderers[item.id]());
      Object.assign(element.style, { left: `${f.x}px`, top: `${f.y}px`, width: `${f.w}px`, height: `${f.h}px` });
      canvas.append(element);
    }
  }

  // ---------------------------------------------------------------------
  // Start.
  // ---------------------------------------------------------------------

  ['clock', 'reminders', 'web', 'calendar'].forEach((kind) => board.add(kind));
  buildScreen();
  fitDisplay();
  updateClocks();
  updateCalendar();
  board.layout(false);
  startAttract();
  readScroll();
  setInterval(updateClocks, 1000);
  setInterval(updateCalendar, 60000);

  // For the tests.
  window.__blink = { peek, board, tale, shortcutDown, shortcutUp };
})();
