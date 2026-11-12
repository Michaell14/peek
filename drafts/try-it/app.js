// Blink, "Try it" draft. The screen on the page is a small Mac with Blink on it.
// A checklist walks through seven things to try. Each one is ticked when the
// visitor does it, and shows itself after a moment if they only watch.
(() => {
  'use strict';

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));
  const calm = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const coarse = window.matchMedia('(hover: none) and (pointer: coarse)').matches;
  const wideQuery = window.matchMedia('(min-width: 960px)');

  const W = 1120; // the screen is drawn at this size and scaled to fit
  const H = 700;
  const BOARD_X = 24; // where the board sits inside the overlay
  const BOARD_Y = 46;
  const TAP_THRESHOLD = 300; // ms: shorter is a tap, longer is a hold

  const screen = $('#screen');
  const viewport = $('#viewport');
  const stage = $('#stage');
  const stageInner = $('#stage-inner');
  const overlay = $('#overlay');
  const boardElement = $('#board');
  const statusElement = $('#status');
  const statusText = $('.deck__text', statusElement);
  const statusGlyph = $('.deck__glyph', statusElement);
  const keySpace = $('#key-space');
  const keyEsc = $('#key-esc');
  const tourElement = $('#tour');
  const card = $('#card');
  const todos = $$('.todo');
  const runway = $('#runway');
  const tab = $('#card-tab');
  const topBar = $('#top-bar');
  const coverMark = $('.wordmark--cover');
  const finder = $('#finder');
  const fmenu = $('#fmenu');
  const fmenuSub = $('#fmenu-sub');
  const paletteElement = $('#palette');
  const paletteInput = $('#palette-input');
  const paletteList = $('#palette-list');
  const menuElement = $('#menu');
  const hotspot = $('#hotspot');
  const caret = $('#caret');

  // ---------------------------------------------------------------------
  // Whose action is it? Things the page does by itself never tick a box,
  // and what a demonstration changes is put back when it ends.
  // ---------------------------------------------------------------------

  let quietDepth = 0;
  let demoDepth = 0;
  const quiet = (fn) => { quietDepth += 1; try { return fn(); } finally { quietDepth -= 1; } };
  const ghostly = (fn) => { quietDepth += 1; demoDepth += 1; try { return fn(); } finally { quietDepth -= 1; demoDepth -= 1; } };
  const byVisitor = () => quietDepth === 0;

  // ---------------------------------------------------------------------
  // The checklist.
  // ---------------------------------------------------------------------

  const NAMES = ['hold', 'tap', 'tick', 'site', 'refresh', 'arrange', 'file'];
  const PARTS = { tap: ['tap', 'close'], arrange: ['flow', 'freeform'] };
  const tried = new Set();
  const parts = { tap: new Set(), arrange: new Set() };
  const count = $('#count');

  function markTried(name) {
    if (!byVisitor() || tried.has(name)) return;
    tried.add(name);
    renderProgress();
    count.classList.remove('is-bump');
    void count.offsetWidth;
    count.classList.add('is-bump');
    if (tour.step === NAMES.indexOf(name) + 1) stopDemo();
    refreshHints();
  }

  function markPart(name, part) {
    if (!byVisitor() || tried.has(name) || parts[name].has(part)) return;
    parts[name].add(part);
    renderProgress();
    if (PARTS[name].every((each) => parts[name].has(each))) markTried(name);
    else refreshHints();
  }

  function renderProgress() {
    count.textContent = tried.size;
    todos.forEach((todo) => {
      const name = todo.dataset.name;
      const done = tried.has(name);
      todo.classList.toggle('is-tried', done);
      $('[data-sr]', todo).textContent = done ? ' (tried)' : '';
      if (PARTS[name]) {
        $$('[data-part]', todo).forEach((span) => span.classList.toggle('is-done', done || parts[name].has(span.dataset.part)));
      }
    });
    const boxes = $('#tally-boxes');
    boxes.innerHTML = NAMES.map((name) => `<i class="${tried.has(name) ? 'is-tried' : ''}"></i>`).join('');
    const n = tried.size;
    $('#tally-text').textContent = n === 0
      ? 'You watched all seven.'
      : n === NAMES.length ? 'You tried all seven.' : `You tried ${n} of the seven.`;
  }

  // ---------------------------------------------------------------------
  // The screen is drawn at one size and scaled to fit. On a phone the view
  // follows what is being used, so it is big enough to touch.
  // ---------------------------------------------------------------------

  const camera = { focus: null, scale: 0.5, x: 0, y: 0 };
  let fitScale = 0.5;
  const followsFocus = () => fitScale < 0.5;

  function localRect(element) {
    const s = screen.getBoundingClientRect();
    const r = element.getBoundingClientRect();
    const k = s.width / W;
    return { x: (r.left - s.left) / k, y: (r.top - s.top) / k, w: r.width / k, h: r.height / k };
  }

  function applyCamera(animate) {
    const w = viewport.clientWidth;
    const h = viewport.clientHeight;
    if (!w) return;
    fitScale = w / W;
    let s = fitScale;
    let x = 0;
    let y = 0;
    const rect = camera.focus && followsFocus() ? camera.focus() : null;
    if (rect) {
      const pad = 10;
      s = Math.max(fitScale, Math.min(1, (w - pad * 2) / rect.w, (h - pad * 2) / rect.h));
      x = w / 2 - (rect.x + rect.w / 2) * s;
      y = h / 2 - (rect.y + rect.h / 2) * s;
      // Taller than the view: start from its top.
      if (rect.h * s > h - pad * 2) y = pad - rect.y * s;
      x = Math.min(0, Math.max(w - W * s, x));
      y = Math.min(0, Math.max(h - H * s, y));
    }
    screen.classList.toggle('is-moving', Boolean(animate) && !calm);
    screen.style.transform = `translate(${x.toFixed(2)}px, ${y.toFixed(2)}px) scale(${s.toFixed(4)})`;
    Object.assign(camera, { scale: s, x, y });
    refreshHints();
  }

  function focusOn(target) {
    camera.focus = target || null;
    if (followsFocus()) applyCamera(true);
  }

  const tileRect = (tile) => ({ x: BOARD_X + tile.frame.x, y: BOARD_Y + tile.frame.y, w: tile.frame.w, h: tile.frame.h });
  // The top of a tile, which is what a small screen can show of it.
  const tileTop = (tile) => ({ ...tileRect(tile), h: Math.min(tile.frame.h, 250) });

  // ---------------------------------------------------------------------
  // Hold or tap. The same small state machine the app uses; Space stands
  // in for fn, which a web page cannot see.
  // ---------------------------------------------------------------------

  const peek = { state: 'hidden', since: 0 };
  let spaceHeld = false;

  function shortcutDown() {
    const now = performance.now();
    if (peek.state === 'hidden' || peek.state === 'releasing') {
      peek.state = 'holding';
      peek.since = now;
      showOverlay();
    } else if (peek.state === 'pinned') {
      peek.state = 'releasing';
      closedByVisitor();
      hideOverlay();
    }
  }

  function shortcutUp() {
    const now = performance.now();
    if (peek.state === 'holding') {
      if (now - peek.since <= TAP_THRESHOLD) {
        peek.state = 'pinned';
        setPinned(true);
        markPart('tap', 'tap');
      } else {
        peek.state = 'hidden';
        hideOverlay();
        markTried('hold');
        flashCaret();
      }
    } else if (peek.state === 'releasing') {
      peek.state = 'hidden';
    }
    refreshHints();
  }

  function dismiss() {
    if (peek.state === 'pinned') {
      peek.state = 'hidden';
      closedByVisitor();
      hideOverlay();
    } else if (peek.state === 'holding') {
      peek.state = 'releasing';
      hideOverlay();
    }
  }

  function closedByVisitor() {
    if (parts.tap.has('tap')) markPart('tap', 'close');
  }

  // Open and in use, as several steps need it. Put back afterwards when a
  // demonstration did it.
  function ensurePinned() {
    if (peek.state === 'pinned') return;
    peek.state = 'pinned';
    showOverlay();
    setPinned(true);
    if (demoDepth) tour.undo.push(forceClose);
  }

  function forceClose() {
    if (peek.state === 'hidden') return;
    peek.state = 'hidden';
    hideOverlay();
  }

  function showOverlay() {
    board.layout(false);
    overlay.classList.add('is-open');
    overlay.setAttribute('aria-hidden', 'false');
    refreshHints();
  }

  function hideOverlay() {
    setPinned(false);
    overlay.classList.remove('is-open');
    overlay.setAttribute('aria-hidden', 'true');
    refreshHints();
  }

  function setPinned(pinned) {
    overlay.classList.toggle('is-pinned', pinned);
    overlay.inert = !pinned;
    if (pinned) {
      if (tour.step === 6) board.setEditing(true);
    } else {
      board.setEditing(false);
      closePalette();
      closeMenu();
    }
    refreshHints();
  }

  function flashCaret() {
    caret.classList.remove('is-flash');
    void caret.offsetWidth;
    caret.classList.add('is-flash');
    clearTimeout(flashCaret.timer);
    flashCaret.timer = setTimeout(() => caret.classList.remove('is-flash'), calm ? 2400 : 2700);
  }

  const isShortcut = (event) => event.code === 'Space' && !event.ctrlKey && !event.altKey && !event.shiftKey && !event.metaKey;
  const isTyping = (target) => target instanceof HTMLElement
    && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName))
    && target.type !== 'checkbox';

  // Space only belongs to the demo while the screen is in view.
  function stageInView() {
    const r = stage.getBoundingClientRect();
    const visible = Math.min(r.bottom, window.innerHeight) - Math.max(r.top, 0);
    return visible > Math.min(r.height, window.innerHeight) * 0.3;
  }

  window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      if (!stageInView()) return;
      keyEsc.classList.add('is-down');
      if (!fmenu.hidden) { event.preventDefault(); userInput(); closeFinderMenu(); return; }
      if (!menuElement.hidden) { event.preventDefault(); userInput(); closeMenu(); return; }
      if (!paletteElement.hidden) { event.preventDefault(); userInput(); closePalette(); return; }
      if (peek.state !== 'hidden' || tour.undo.length) {
        event.preventDefault();
        userInput();
        if (board.isEditing && tour.step !== 6) board.setEditing(false);
        else dismiss();
      }
      return;
    }
    if (!paletteElement.hidden && handlePaletteKey(event)) return;
    if (isTyping(event.target)) return;
    if (isShortcut(event) && stageInView()) {
      event.preventDefault(); // Space would otherwise scroll the page
      if (!event.repeat && !spaceHeld) {
        spaceHeld = true;
        userInput();
        keySpace.classList.add('is-down');
        shortcutDown();
      }
    }
  }, true);

  window.addEventListener('keyup', (event) => {
    if (event.key === 'Escape') keyEsc.classList.remove('is-down');
    if (!spaceHeld || event.code !== 'Space') return;
    event.preventDefault(); // or a focused button would be "clicked"
    spaceHeld = false;
    keySpace.classList.remove('is-down');
    shortcutUp();
  }, true);

  // A key-up never arrives if the window loses focus while the key is down.
  window.addEventListener('blur', () => {
    if (!spaceHeld) return;
    spaceHeld = false;
    keySpace.classList.remove('is-down');
    if (peek.state === 'holding') peek.since = -Infinity;
    shortcutUp();
  });

  // The keys under the screen work with a mouse or a finger too.
  let keyPressed = false;
  keySpace.addEventListener('pointerdown', (event) => {
    if (event.button !== 0 || keyPressed) return;
    keySpace.setPointerCapture(event.pointerId);
    keyPressed = true;
    userInput();
    keySpace.classList.add('is-down');
    shortcutDown();
  });
  ['pointerup', 'pointercancel'].forEach((type) => keySpace.addEventListener(type, () => {
    if (!keyPressed) return;
    keyPressed = false;
    keySpace.classList.remove('is-down');
    shortcutUp();
  }));
  keySpace.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') { event.preventDefault(); userInput(); shortcutDown(); shortcutUp(); }
  });
  keySpace.addEventListener('click', (event) => event.preventDefault());
  keySpace.addEventListener('contextmenu', (event) => event.preventDefault());

  keyEsc.addEventListener('click', () => {
    userInput();
    if (!fmenu.hidden) closeFinderMenu();
    else if (!menuElement.hidden) closeMenu();
    else if (!paletteElement.hidden) closePalette();
    else dismiss();
  });

  // Clicking the glass around the tiles closes Blink, as in the app.
  overlay.addEventListener('pointerdown', (event) => {
    if (!menuElement.hidden && !menuElement.contains(event.target)) closeMenu();
    if (event.target === overlay || event.target === boardElement) {
      if (!paletteElement.hidden) closePalette();
      else if (!board.isEditing) dismiss();
    }
  });
  $('#board-close').addEventListener('click', dismiss);

  // ---------------------------------------------------------------------
  // The board: tiles, Flow and Freeform, and arranging.
  // ---------------------------------------------------------------------

  const GAP = 14;

  // Flow, as in the app: tiles are packed in order into full-height
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

  const icon = (paths, size = 16) => `<svg viewBox="0 0 16 16" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths}</svg>`;
  const ICONS = {
    clock: icon('<circle cx="8" cy="8" r="6"/><path d="M8 4.6V8l2.3 1.5"/>'),
    reminders: icon('<circle cx="3.6" cy="4.5" r="1.4"/><circle cx="3.6" cy="11.5" r="1.4"/><path d="M7.4 4.5h6M7.4 11.5h6"/>'),
    web: icon('<circle cx="8" cy="8" r="6"/><path d="M2 8h12M8 2c2 2 2 10 0 12M8 2c-2 2-2 10 0 12"/>'),
    calendar: icon('<rect x="2.2" y="3" width="11.6" height="10.8" rx="2"/><path d="M2.2 6.6h11.6M5.4 1.8v2.4M10.6 1.8v2.4"/>'),
    notes: icon('<rect x="2.6" y="2.2" width="10.8" height="11.6" rx="2"/><path d="M5.2 5.6h5.6M5.2 8h5.6M5.2 10.4h3.2"/>'),
    file: icon('<path d="M4 1.8h5.2L12.4 5v9.2H4z"/><path d="M9 1.8V5h3.4"/>'),
    search: icon('<circle cx="7" cy="7" r="4.6"/><path d="m10.4 10.4 3.4 3.4"/>'),
    sun: '<svg viewBox="0 0 16 16" width="13" height="13" aria-hidden="true"><circle cx="8" cy="8" r="3.1" fill="currentColor"/><path stroke="currentColor" stroke-width="1.4" stroke-linecap="round" d="M8 1.3v1.5M8 13.2v1.5M1.3 8h1.5M13.2 8h1.5M3.3 3.3l1 1M11.7 11.7l1 1M3.3 12.7l1-1M11.7 4.3l1-1"/></svg>',
    moon: '<svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true"><path fill="currentColor" d="M13.4 10A5.7 5.7 0 0 1 6 2.6a5.7 5.7 0 1 0 7.4 7.4z"/></svg>',
    back: icon('<path d="M9.8 3.5 5.3 8l4.5 4.5"/>', 12),
    forward: icon('<path d="M6.2 3.5 10.7 8l-4.5 4.5"/>', 12),
    reload: icon('<path d="M12.6 8.2a4.6 4.6 0 1 1-1.4-3.4"/><path d="M12.4 2.6v2.6H9.8"/>', 12),
    more: '<svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true"><circle cx="3.4" cy="8" r="1.35"/><circle cx="8" cy="8" r="1.35"/><circle cx="12.6" cy="8" r="1.35"/></svg>',
  };

  const WIDGETS = {
    clock: { title: 'Clock', note: 'The time in the places you care about', w: 270, h: 196 },
    reminders: { title: 'Reminders', note: 'What is due, ready to tick off', w: 270, h: 330 },
    calendar: { title: 'Calendar', note: "Today's events", w: 290, h: null },
    notes: { title: 'Notes', note: 'A scratchpad that is always there', w: 260, h: 220 },
  };
  const SITES = {
    metrics: { title: 'Example dashboard', host: 'metrics.example', w: 340, h: null },
    weather: { title: 'Weather', host: 'weather.example', w: 330, h: 300 },
    status: { title: 'Status page', host: 'status.example', w: 330, h: 300 },
  };
  const FILES = {
    trains: { title: 'Train times.pdf', w: 330, h: 300 },
    plan: { title: 'Floor plan.pdf', w: 330, h: 300 },
    notes: { title: 'Handbook.html', w: 330, h: 300 },
  };

  let serial = 0;

  const board = {
    mode: 'flow',
    isEditing: false,
    tiles: [],
    drag: null,

    has(kind, key) { return this.tiles.some((tile) => tile.kind === kind && tile.key === key); },

    // spec: { kind: 'widget' | 'web' | 'file', key, title, w, h, host?, query? }
    add(spec) {
      serial += 1;
      const tile = { ...spec, id: `${spec.kind}-${spec.key}-${serial}`, frame: null, refresh: 0, nextAt: 0, loads: 0, demo: false };
      const element = document.createElement('section');
      element.className = 'tile';
      element.setAttribute('aria-label', spec.title);
      const content = render(tile);
      if (!tile.update) tile.update = () => {};
      element.append(content);

      if (spec.kind !== 'widget') {
        const load = document.createElement('i');
        load.className = 'tile__load';
        element.append(load);
        const bar = document.createElement('div');
        bar.className = 'tbar';
        bar.innerHTML = (spec.kind === 'web'
          ? `<button type="button" aria-label="Back" tabindex="-1">${ICONS.back}</button><button type="button" aria-label="Forward" tabindex="-1">${ICONS.forward}</button><button type="button" class="reload" aria-label="Reload">${ICONS.reload}</button>`
          : '') + `<button type="button" class="more" aria-label="More for ${spec.title}" aria-haspopup="menu">${ICONS.more}</button>`;
        element.append(bar);
        const reload = $('.reload', bar);
        if (reload) reload.addEventListener('click', () => reloadTile(tile));
        $('.more', bar).addEventListener('click', (event) => {
          event.stopPropagation();
          if (!menuElement.hidden && menu.tile === tile) closeMenu();
          else openTileMenu(tile);
        });
      }

      const cover = document.createElement('div');
      cover.className = 'tile__cover';
      cover.innerHTML = `${ICONS[spec.kind === 'widget' ? spec.key : spec.kind === 'web' ? 'web' : 'file']}<span>${spec.title}</span>`;
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'tile__remove';
      remove.setAttribute('aria-label', `Remove ${spec.title}`);
      remove.innerHTML = '<svg viewBox="0 0 10 10" aria-hidden="true"><path d="M2 2l6 6M8 2l-6 6"/></svg>';
      cover.append(remove);
      element.append(cover);
      remove.addEventListener('pointerdown', (event) => event.stopPropagation());
      remove.addEventListener('click', () => this.remove(tile));
      cover.addEventListener('pointerdown', (event) => beginPointerDrag(tile, event));

      tile.element = element;
      this.tiles.push(tile);
      boardElement.append(element);
      if (demoDepth) {
        tile.demo = true;
        tour.undo.push(() => this.remove(tile, true));
      }
      return tile;
    },

    remove(tile, instantly) {
      if (!this.tiles.includes(tile)) return;
      this.tiles = this.tiles.filter((other) => other !== tile);
      if (menu.tile === tile) closeMenu();
      if (instantly || calm) tile.element.remove();
      else {
        tile.element.classList.add('is-leaving');
        setTimeout(() => tile.element.remove(), 260);
      }
      this.layout(true);
      refreshHints();
    },

    size() { return { width: boardElement.clientWidth, height: boardElement.clientHeight }; },

    layout(animated, skip = null) {
      const { width, height } = this.size();
      if (!width) return;
      const frames = this.mode === 'flow' ? flowLayout(this.tiles, width, height) : null;
      for (const tile of this.tiles) {
        if (frames) tile.frame = frames.get(tile.id);
        if (!tile.frame) {
          // New in Freeform: the middle of the board.
          const h = tile.h ?? Math.round(height * 0.8);
          tile.frame = { x: Math.round((width - tile.w) / 2), y: Math.round((height - h) / 2), w: tile.w, h };
        }
        if (tile === skip) continue;
        const f = tile.frame;
        tile.element.style.transitionDuration = animated && !calm ? '' : '0s';
        Object.assign(tile.element.style, { left: `${f.x}px`, top: `${f.y}px`, width: `${f.w}px`, height: `${f.h}px` });
      }
      if (!animated || calm) {
        void boardElement.offsetWidth;
        this.tiles.forEach((tile) => { tile.element.style.transitionDuration = ''; });
      }
      refreshHints();
    },

    setMode(mode) {
      if (mode === this.mode) return;
      if (mode === 'flow') {
        this.tiles.sort((a, b) => (a.frame.x - b.frame.x) || (a.frame.y - b.frame.y));
      }
      this.mode = mode;
      $$('[data-board-mode]').forEach((button) => {
        const on = button.dataset.boardMode === mode;
        button.classList.toggle('is-on', on);
        button.setAttribute('aria-pressed', String(on));
      });
      this.layout(true);
    },

    setEditing(editing) {
      this.isEditing = editing;
      overlay.classList.toggle('is-editing', editing);
      const button = $('#board-edit');
      button.textContent = editing ? 'Done' : 'Edit';
      button.classList.toggle('is-on', editing);
      $('#ov-hint').textContent = editing ? 'Drag a tile to move it' : 'Space or esc to close';
      if (editing) closeMenu();
      refreshHints();
    },

    snapshot() {
      return { mode: this.mode, order: this.tiles.slice(), frames: new Map(this.tiles.map((tile) => [tile, { ...tile.frame }])) };
    },

    restore(snap) {
      this.mode = snap.mode;
      $$('[data-board-mode]').forEach((button) => button.classList.toggle('is-on', button.dataset.boardMode === snap.mode));
      const alive = new Set(this.tiles);
      this.tiles = snap.order.filter((tile) => alive.has(tile)).concat(this.tiles.filter((tile) => !snap.order.includes(tile)));
      this.tiles.forEach((tile) => { if (snap.frames.has(tile)) tile.frame = { ...snap.frames.get(tile) }; });
      this.layout(true);
    },

    dragStart(tile) {
      this.drag = { tile, origin: { ...tile.frame }, order: this.tiles.map((each) => each.id).join() };
      tile.element.classList.add('is-dragging');
      closeMenu();
    },

    dragMove(dx, dy, point) {
      if (!this.drag) return;
      const { tile, origin } = this.drag;
      const { width, height } = this.size();
      if (this.mode === 'freeform') {
        // Snaps to an 8 point grid and to the edges of the board.
        const snap = (value, max) => {
          const v = Math.min(Math.max(value, 0), max);
          if (v < 12) return 0;
          if (max - v < 12) return max;
          return Math.round(v / 8) * 8;
        };
        const x = snap(origin.x + dx, width - origin.w);
        const y = snap(origin.y + dy, height - origin.h);
        tile.frame = { ...origin, x, y };
        tile.element.style.left = `${x}px`;
        tile.element.style.top = `${y}px`;
        return;
      }
      tile.element.style.left = `${origin.x + dx}px`;
      tile.element.style.top = `${origin.y + dy}px`;
      const index = insertionIndex(point, tile.id, this.tiles, width, height);
      const others = this.tiles.filter((other) => other !== tile);
      others.splice(index, 0, tile);
      if (others.some((other, i) => other !== this.tiles[i])) {
        this.tiles = others;
        this.layout(true, tile); // the others make room; this one follows the pointer
      }
    },

    dragEnd() {
      if (!this.drag) return { reordered: false, moved: false };
      const { tile, origin, order } = this.drag;
      this.drag = null;
      tile.element.classList.remove('is-dragging');
      const reordered = this.tiles.map((each) => each.id).join() !== order;
      const moved = Math.hypot(tile.frame.x - origin.x, tile.frame.y - origin.y) > 6;
      this.layout(true);
      return { reordered, moved };
    },

    cancelDrag() {
      if (this.drag) this.dragEnd();
    },
  };

  const screenScale = () => screen.getBoundingClientRect().width / W;

  function beginPointerDrag(tile, event) {
    if (!board.isEditing || event.button !== 0) return;
    event.preventDefault();
    const cover = event.currentTarget;
    cover.setPointerCapture(event.pointerId);
    const start = { x: event.clientX, y: event.clientY };
    board.dragStart(tile);
    const move = (moveEvent) => {
      const k = screenScale();
      const bounds = boardElement.getBoundingClientRect();
      board.dragMove((moveEvent.clientX - start.x) / k, (moveEvent.clientY - start.y) / k, {
        x: (moveEvent.clientX - bounds.left) / k,
        y: (moveEvent.clientY - bounds.top) / k,
      });
    };
    const end = () => {
      cover.removeEventListener('pointermove', move);
      cover.removeEventListener('pointerup', end);
      cover.removeEventListener('pointercancel', end);
      const mode = board.mode;
      const result = board.dragEnd();
      if (mode === 'flow' && result.reordered) markPart('arrange', 'flow');
      if (mode === 'freeform' && result.moved) markPart('arrange', 'freeform');
    };
    cover.addEventListener('pointermove', move);
    cover.addEventListener('pointerup', end);
    cover.addEventListener('pointercancel', end);
  }

  $$('[data-board-mode]').forEach((button) => {
    button.addEventListener('click', () => {
      userInput();
      if (button.closest('.todo')) quiet(ensurePinned);
      board.setMode(button.dataset.boardMode);
    });
  });
  $('#board-edit').addEventListener('click', () => board.setEditing(!board.isEditing));

  // ---------------------------------------------------------------------
  // What the tiles show.
  // ---------------------------------------------------------------------

  const ZONES = [
    { zone: undefined, name: 'Here' },
    { zone: 'Europe/London', name: 'London' },
    { zone: 'Asia/Tokyo', name: 'Tokyo' },
  ];

  const hourIn = (zone, date) => Number(new Intl.DateTimeFormat('en-GB', { hour: 'numeric', hourCycle: 'h23', timeZone: zone }).format(date));

  function dayDifference(zone, date) {
    const format = (timeZone) => new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
    return Math.round((Date.parse(format(zone)) - Date.parse(format(undefined))) / 86400000);
  }

  function offsetHours(zone, date) {
    const local = new Date(date.toLocaleString('en-US'));
    const remote = new Date(date.toLocaleString('en-US', { timeZone: zone }));
    return Math.round((remote - local) / 360000) / 10;
  }

  const clockText = (date) => date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });

  function render(tile) {
    if (tile.kind === 'widget') return widgets[tile.key](tile);
    if (tile.kind === 'file') return files[tile.key](tile);
    return (pages[tile.key] || pages.generic)(tile);
  }

  const widgets = {
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
        <div class="w-rem__head"><b>Today</b><span class="w-rem__count">4</span></div>
        <div class="w-rem__list">
          <p class="w-label">Overdue</p>
          <button type="button" class="w-rem__item"><i></i><span><b>Send the invoice</b><small class="is-late">Yesterday</small></span></button>
          <p class="w-label">Today</p>
          <button type="button" class="w-rem__item" data-demo><i></i><span><b>Water the plants</b><small>Today</small></span></button>
          <button type="button" class="w-rem__item"><i></i><span><b>Check the new train times</b><small>10:30</small></span></button>
          <button type="button" class="w-rem__item"><i></i><span><b>Book the room for Thursday</b><small>Today</small></span></button>
        </div>
        <label class="w-rem__new"><span aria-hidden="true">＋</span><input type="text" placeholder="New Reminder" aria-label="New reminder"></label>`;
      const list = $('.w-rem__list', root);
      list.addEventListener('click', (event) => {
        const item = event.target.closest('.w-rem__item');
        if (!item) return;
        toggleReminder(item);
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
        recountReminders();
        list.scrollTop = list.scrollHeight;
        markTried('tick');
      });
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

  function toggleReminder(item) {
    const done = !item.classList.contains('is-done');
    item.classList.toggle('is-done', done);
    recountReminders();
    if (done) markTried('tick');
    if (demoDepth && done) tour.undo.push(() => { item.classList.remove('is-done'); recountReminders(); });
    refreshHints();
  }

  function recountReminders() {
    $$('.w-rem').forEach((root) => {
      $('.w-rem__count', root).textContent = $$('.w-rem__item:not(.is-done)', root).length;
    });
  }

  // Stand-in web pages. Each can be "reloaded", and its numbers move on.
  const wobble = (n, seed, spread) => Math.round(Math.sin(n * 1.7 + seed) * spread);
  const pageClock = (tile) => {
    const t = new Date(tile.born + tile.loads * (tile.refresh || 300) * 1000);
    return clockText(t);
  };

  function pageShell(tile, title, sub, body) {
    const root = document.createElement('div');
    root.className = 'pg';
    root.innerHTML = `
      <div class="pg__bar"><b>${title}</b><span>${sub}</span></div>
      <div class="pg__body">${body}</div>
      <p class="pg__foot"><span>Updated <b data-v="updated"></b></span><em>Stand-in page</em></p>`;
    return root;
  }

  function setValue(root, key, value) {
    const element = $(`[data-v="${key}"]`, root);
    if (!element || element.textContent === String(value)) return;
    element.textContent = value;
    if (root.dataset.ready) {
      element.classList.remove('is-changed');
      void element.offsetWidth;
      element.classList.add('is-changed');
    }
  }

  const pages = {
    metrics(tile) {
      const root = pageShell(tile, 'Example dashboard', 'Last 7 days', `
        <div class="w-web__stats">
          <div class="w-web__card"><small>Visitors</small><b data-v="visitors">12,480</b><em class="up">▲ 8.2%</em></div>
          <div class="w-web__card"><small>Sign-ups</small><b data-v="signups">342</b><em class="up">▲ 3.1%</em></div>
        </div>
        <div class="w-web__card" style="margin-top:8px"><small>Visitors per day</small>
          <div class="w-web__chart"><i style="height:46%"></i><i style="height:58%"></i><i style="height:52%"></i><i style="height:71%"></i><i style="height:88%"></i><i style="height:64%"></i><i style="height:97%"></i></div>
        </div>
        <div class="w-web__card" style="margin-top:8px"><small>Top pages</small>
          <div class="w-web__rows"><div><span>/</span><span>5,210</span></div><div><span>/pricing</span><span>2,034</span></div><div><span>/docs</span><span>1,377</span></div><div><span>/blog/launch</span><span>962</span></div></div>
        </div>`);
      tile.update = () => {
        setValue(root, 'visitors', (12480 + tile.loads * 37 + wobble(tile.loads, 1, 12)).toLocaleString('en-US'));
        setValue(root, 'signups', 342 + tile.loads * 2);
        setValue(root, 'updated', pageClock(tile));
      };
      return root;
    },

    weather(tile) {
      const hours = ['Now', '+1', '+2', '+3', '+4', '+5'];
      const root = pageShell(tile, 'Weather', 'Harbourside', `
        <div class="wx__now">
          <span class="wx__temp"><span data-v="temp">14</span>°</span>
          <span class="wx__sky"><b data-v="sky">Showers, clearing later</b><small>Feels like <span data-v="feels">12</span>°</small></span>
        </div>
        <div class="wx__hours">${hours.map((label, i) => `<div><small data-h="${i}">${label}</small><i class="wx__g" data-g="${i}"></i><b data-v="h${i}">14°</b><em data-v="r${i}">40%</em></div>`).join('')}</div>
        <div class="wx__rows"><div><small>Wind</small><b data-v="wind">18 km/h</b></div><div><small>Rain today</small><b data-v="rain">4 mm</b></div></div>`);
      tile.update = () => {
        const n = tile.loads;
        const base = 14 + Math.min(n, 4) * 0.5;
        setValue(root, 'temp', Math.round(base + wobble(n, 0.3, 1)));
        setValue(root, 'feels', Math.round(base - 2 + wobble(n, 2, 1)));
        setValue(root, 'sky', n < 2 ? 'Showers, clearing later' : n < 4 ? 'Clearing from the west' : 'Bright spells');
        setValue(root, 'wind', `${18 - Math.min(n, 6) + wobble(n, 4, 1)} km/h`);
        setValue(root, 'rain', `${Math.max(0, 4 - n)} mm`);
        const now = new Date(tile.born + n * (tile.refresh || 300) * 1000);
        for (let i = 0; i < 6; i += 1) {
          const rain = Math.max(0, 60 - (n + i) * 12 + wobble(i, n, 6));
          setValue(root, `h${i}`, `${Math.round(base + i * 0.6 + wobble(i + n, 1, 1))}°`);
          setValue(root, `r${i}`, `${rain}%`);
          $(`[data-g="${i}"]`, root).className = `wx__g wx__g--${rain > 35 ? 'rain' : rain > 12 ? 'cloud' : 'sun'}`;
          if (i) $(`[data-h="${i}"]`, root).textContent = new Date(now.getTime() + i * 3600000).toLocaleTimeString([], { hour: 'numeric' }).replace(/\s?[AP]M/i, (m) => m.trim().toLowerCase());
        }
        setValue(root, 'updated', pageClock(tile));
      };
      return root;
    },

    status(tile) {
      const strip = (warn) => Array.from({ length: 30 }, (_, i) => `<i class="${i === warn ? 'is-warn' : ''}"></i>`).join('');
      const root = pageShell(tile, 'Status', 'status.example', `
        <p class="st__ok"><i></i><span data-v="ok">Everything is working</span></p>
        <div class="st__rows">
          <div class="st__row"><b>Website</b><span data-v="u1">99.98%</span><span class="st__bars">${strip(-1)}</span></div>
          <div class="st__row"><b>Sign-in</b><span data-v="u2">100%</span><span class="st__bars">${strip(-1)}</span></div>
          <div class="st__row"><b>Payments</b><span data-v="u3">99.91%</span><span class="st__bars">${strip(22)}</span></div>
        </div>
        <div class="st__nums"><div><small>Jobs waiting</small><b data-v="queue">12</b></div><div><small>Response time</small><b data-v="resp">184 ms</b></div></div>`);
      tile.update = () => {
        const n = tile.loads;
        setValue(root, 'queue', Math.max(0, 12 + wobble(n, 0.5, 7)));
        setValue(root, 'resp', `${184 + wobble(n, 2.2, 26)} ms`);
        setValue(root, 'u3', n > 2 ? '99.92%' : '99.91%');
        setValue(root, 'updated', pageClock(tile));
      };
      return root;
    },

    generic(tile) {
      const root = pageShell(tile, tile.title, tile.query ? 'Search results' : 'Stand-in page', tile.query
        ? `<div class="gen"><p>Results for “${escapeHTML(tile.query)}”, as your search engine would show them.</p>
            ${[1, 2, 3].map((i) => `<div class="gen__res"><small>${escapeHTML(slug(tile.query))}${i > 1 ? `-${i}` : ''}.example</small><b>${escapeHTML(tile.query)}${i === 1 ? '' : i === 2 ? ' near you' : ': what to know'}</b><i></i><i class="s"></i></div>`).join('')}</div>`
        : `<div class="gen"><div class="gen__hero"></div><p>In Blink, ${escapeHTML(tile.host)} loads here, signed in and kept up to date in the background.</p><i></i><i></i><i class="s"></i><i></i><i class="s"></i></div>`);
      tile.update = () => setValue(root, 'updated', pageClock(tile));
      return root;
    },
  };

  const files = {
    trains(tile) {
      const root = document.createElement('div');
      root.className = 'doc-tile';
      const rows = [['07:42', '08:09', '2'], ['07:58', '08:25', '1'], ['08:12', '08:39', '2'], ['08:27', '08:54', '1'], ['08:43', '09:10', '2'], ['09:02', '09:29', '1'], ['09:31', '09:58', '2'], ['10:04', '10:31', '1']];
      root.innerHTML = `<div class="doc-tile__page">
        <p class="doc-tile__kicker">Harbour Line</p>
        <h6>Train times</h6>
        <p>Weekdays, from 2 November</p>
        <table><thead><tr><th>Harbour</th><th>Central</th><th>Platform</th></tr></thead>
        <tbody>${rows.map((r, i) => `<tr class="${i === 3 ? 'is-next' : ''}"><td>${r[0]}</td><td>${r[1]}</td><td>${r[2]}</td></tr>`).join('')}</tbody></table>
      </div>`;
      tile.update = () => {};
      return root;
    },
    plan(tile) {
      const root = document.createElement('div');
      root.className = 'doc-tile';
      root.innerHTML = `<div class="doc-tile__page">
        <p class="doc-tile__kicker">Second floor</p>
        <h6>Floor plan</h6>
        <p>Rooms you can book</p>
        <svg viewBox="0 0 240 150" aria-hidden="true" fill="none" stroke="#222" stroke-width="1.6">
          <rect x="2" y="2" width="236" height="146"/><path d="M90 2v70M150 2v70M2 72h80M98 72h44M158 72h80M120 72v76"/>
          <g fill="#555" stroke="none" font-size="9" font-family="Archivo, sans-serif"><text x="12" y="40">Room 1</text><text x="102" y="40">Room 2</text><text x="164" y="40">Kitchen</text><text x="30" y="115">Open desks</text><text x="150" y="115">Room 3</text></g>
          <rect x="96" y="8" width="48" height="58" fill="#fff3d6" stroke="none"/><text x="102" y="40" fill="#555" stroke="none" font-size="9" font-family="Archivo, sans-serif">Room 2</text>
        </svg>
      </div>`;
      tile.update = () => {};
      return root;
    },
    notes(tile) {
      const root = document.createElement('div');
      root.className = 'doc-tile doc-tile--html';
      root.innerHTML = `<div class="doc-tile__page">
        <h6>Handbook</h6><p>Who to ask, and where things are</p>
        <h5>Day to day</h5><ul><li>Rota questions: Ana</li><li>Keys and passes: front desk</li><li>Expenses: the form on the wiki</li></ul>
        <h5>When something breaks</h5><ul><li>Check the status page first</li><li>Then post in the support channel</li></ul>
      </div>`;
      tile.update = () => {};
      return root;
    },
  };

  const escapeHTML = (text) => text.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const slug = (text) => text.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 24) || 'results';

  function updateClocks() {
    const now = new Date();
    const time = clockText(now);
    $$('[data-live-time]').forEach((element) => { element.textContent = time.replace(/\s?[AP]M/i, ''); });
    const date = now.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' }).replace(',', '');
    $$('[data-live-date]').forEach((element) => { element.textContent = date; });

    $$('[data-zone-row]').forEach((row) => {
      const entry = ZONES[Number(row.dataset.zoneRow)];
      const parts2 = new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit', timeZone: entry.zone }).formatToParts(now);
      const digits = parts2.filter((part) => ['hour', 'literal', 'minute'].includes(part.type)).map((part) => part.value).join('').trim();
      const period = (parts2.find((part) => part.type === 'dayPeriod') || {}).value || '';
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
      const scale = 100 / hours;
      const position = (hour) => (hour - first) * scale;
      const events = [
        { title: 'Design review', start: anchor, end: anchor + 1, color: '#5b9dff', column: 0, of: 2 },
        { title: '1:1 with Sam', start: anchor + 0.5, end: anchor + 1.5, color: '#b98cff', column: 1, of: 2 },
        { title: 'Lunch', start: anchor + 2, end: anchor + 2.75, color: '#5fd0c2', column: 0, of: 1 },
        { title: 'Rota planning', start: anchor + 3.5, end: anchor + 4.5, color: '#ffc761', column: 0, of: 1 },
      ];
      const label = (hour) => new Date(2000, 0, 1, Math.floor(hour), (hour % 1) * 60)
        .toLocaleTimeString([], { hour: 'numeric', minute: hour % 1 ? '2-digit' : undefined });
      let html = '';
      for (let i = 1; i < hours; i += 1) html += `<div class="w-cal__hour" style="top:${i * scale}%"><span>${label(first + i)}</span></div>`;
      for (const event of events) {
        const width = `calc((100% - 54px) / ${event.of} - 3px)`;
        const left = `calc(44px + (100% - 54px) / ${event.of} * ${event.column})`;
        html += `<div class="w-cal__event" style="--c:${event.color};background:${event.color}3d;top:calc(${position(event.start)}% + 1px);height:calc(${(event.end - event.start) * scale}% - 3px);left:${left};width:${width}"><b>${event.title}</b><span>${label(event.start)}</span></div>`;
      }
      const nowHour = now.getHours() + now.getMinutes() / 60;
      if (nowHour >= first && nowHour <= first + hours) html += `<div class="w-cal__now" style="top:${position(nowHour)}%"></div>`;
      grid.innerHTML = html;
    });
  }

  // ---------------------------------------------------------------------
  // Adding: websites, widgets and files.
  // ---------------------------------------------------------------------

  function addTile(spec) {
    const tile = board.add(spec);
    tile.born = Date.now();
    tile.update();
    tile.element.querySelector('.pg, .doc-tile, .w-rem, .w-clock, .w-cal, .w-notes')?.setAttribute('data-ready', '1');
    $$('.pg', tile.element).forEach((pg) => { pg.dataset.ready = '1'; });
    if (!calm) tile.element.classList.add('is-new');
    updateClocks();
    updateCalendar();
    board.layout(false);
    return tile;
  }

  function addSite(key) {
    const spec = SITES[key];
    const tile = addTile({ kind: 'web', key, title: spec.title, host: spec.host, w: spec.w, h: spec.h });
    markTried('site');
    focusOn(() => tileTop(tile));
    return tile;
  }

  function addTyped(text) {
    const address = /\./.test(text) && !/\s/.test(text);
    const host = address ? text.replace(/^https?:\/\//, '').replace(/\/.*$/, '') : null;
    const tile = addTile(address
      ? { kind: 'web', key: 'generic', title: host, host, w: 330, h: null }
      : { kind: 'web', key: 'generic', title: `“${text}”`, query: text, host: 'search', w: 330, h: null });
    markTried('site');
    focusOn(() => tileTop(tile));
    return tile;
  }

  function addWidget(key) {
    const spec = WIDGETS[key];
    const tile = addTile({ kind: 'widget', key, title: spec.title, w: spec.w, h: spec.h });
    focusOn(() => tileTop(tile));
    return tile;
  }

  function openFile(key) {
    const spec = FILES[key];
    closeFinderMenu();
    ensurePinned();
    const tile = addTile({ kind: 'file', key, title: spec.title, w: spec.w, h: spec.h });
    markTried('file');
    focusOn(() => tileTop(tile));
    return tile;
  }

  // ---- The palette -------------------------------------------------------

  let paletteItems = [];
  let paletteIndex = 0;

  function catalog() {
    const items = [];
    for (const key of ['weather', 'status']) {
      items.push({ title: SITES[key].title, sub: SITES[key].host, kind: 'Website', icon: 'web', act: () => addSite(key) });
    }
    for (const key of Object.keys(WIDGETS)) {
      if (!board.has('widget', key)) items.push({ title: WIDGETS[key].title, sub: WIDGETS[key].note, kind: 'Widget', icon: key, act: () => addWidget(key) });
    }
    items.push({ title: 'PDF or HTML File…', sub: 'Keep a document within reach', kind: 'File', icon: 'file', act: () => { toast('Blink would ask you to choose a file. Here it picked Train times.pdf.'); openFile('trains'); } });
    return items;
  }

  function paletteResults(query) {
    const all = catalog();
    const text = query.trim();
    if (!text) return all;
    const needle = text.toLowerCase();
    const starts = all.filter((item) => item.title.toLowerCase().startsWith(needle));
    const contains = all.filter((item) => !item.title.toLowerCase().startsWith(needle)
      && (item.title.toLowerCase().includes(needle) || item.sub.toLowerCase().includes(needle)));
    const address = /\./.test(text) && !/\s/.test(text);
    const typed = address
      ? { title: `Open ${text.replace(/^https?:\/\//, '').replace(/\/.*$/, '')}`, sub: `https://${text.replace(/^https?:\/\//, '')}`, kind: 'Website', icon: 'web', act: () => addTyped(text) }
      : { title: `Search for “${text}”`, sub: 'Opens the results as a tile', kind: 'Search', icon: 'search', act: () => addTyped(text) };
    return [...starts, typed, ...contains];
  }

  function renderPalette() {
    paletteItems = paletteResults(paletteInput.value);
    paletteIndex = Math.min(paletteIndex, Math.max(paletteItems.length - 1, 0));
    paletteList.innerHTML = paletteItems.map((item, index) => `
      <li><button type="button" role="option" data-index="${index}" class="${index === paletteIndex ? 'is-on' : ''}" aria-selected="${index === paletteIndex}" tabindex="-1">
        <i>${ICONS[item.icon] || ICONS.web}</i>
        <span>${escapeHTML(item.title)}<small>${escapeHTML(item.sub)}</small></span>
        <em>${item.kind}</em>
      </button></li>`).join('');
  }

  function openPalette() {
    closeMenu();
    if (board.isEditing && tour.step !== 6) board.setEditing(false);
    paletteElement.classList.toggle('is-right', followsFocus());
    paletteElement.hidden = false;
    paletteInput.value = '';
    paletteIndex = 0;
    renderPalette();
    if (demoDepth) tour.undo.push(closePalette);
    if (byVisitor() && !coarse) paletteInput.focus({ preventScroll: true });
    focusOn(() => localRect(paletteElement));
    refreshHints();
  }

  function closePalette() {
    if (paletteElement.hidden) return;
    paletteElement.hidden = true;
    if (document.activeElement === paletteInput) $('#board-add').focus({ preventScroll: true });
    focusOn(defaultFocus(tour.step));
    refreshHints();
  }

  function setPaletteQuery(text) {
    paletteInput.value = text;
    paletteIndex = 0;
    renderPalette();
  }

  function choosePaletteItem(index) {
    const item = paletteItems[index];
    if (!item) return;
    paletteElement.hidden = true;
    item.act();
    if (document.activeElement === paletteInput) $('#board-add').focus({ preventScroll: true });
    refreshHints();
  }

  function handlePaletteKey(event) {
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      userInput();
      paletteIndex = (paletteIndex + (event.key === 'ArrowDown' ? 1 : -1) + paletteItems.length) % paletteItems.length;
      renderPalette();
      return true;
    }
    if (event.key === 'Enter') {
      event.preventDefault();
      userInput();
      choosePaletteItem(paletteIndex);
      return true;
    }
    return false;
  }

  paletteInput.addEventListener('input', () => { paletteIndex = 0; renderPalette(); });
  paletteList.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-index]');
    if (button) choosePaletteItem(Number(button.dataset.index));
  });
  $('#board-add').addEventListener('click', () => (paletteElement.hidden ? openPalette() : closePalette()));

  // ---- A tile's ⋯ menu ---------------------------------------------------

  const PRESETS = [0, 30, 60, 300, 900, 1800, 3600];
  const presetLabel = (seconds) => {
    if (!seconds) return 'Off';
    if (seconds < 60) return `${seconds} seconds`;
    if (seconds < 3600) return seconds === 60 ? '1 minute' : `${seconds / 60} minutes`;
    return '1 hour';
  };
  const menu = { tile: null };

  function openTileMenu(tile) {
    menu.tile = tile;
    const items = tile.kind === 'web'
      ? [['reload', 'Reload'], ['browser', 'Open in Browser'], ['copy', 'Copy Link'], null, ['hide', 'Hide Elements…'], null, ['refresh', 'Auto-Refresh', true], ['mobile', 'Request Mobile Site'], null, ['remove', 'Remove Tile']]
      : [['app', 'Open in Default App'], ['finder', 'Show in Finder'], null, ['remove', 'Remove Tile']];
    menuElement.innerHTML = items.map((item) => (item
      ? `<button type="button" role="menuitem" data-act="${item[0]}" class="${item[2] ? 'has-sub' : ''}">${item[1]}</button>`
      : '<span class="menu__sep"></span>')).join('')
      + `<div class="menu__sub" role="menu" hidden>${PRESETS.map((seconds) => `<button type="button" role="menuitemradio" data-every="${seconds}" class="${tile.refresh === seconds ? 'is-checked' : ''}">${presetLabel(seconds)}</button>`).join('')}</div>`;
    const more = $('.more', tile.element);
    const anchor = localRect(more);
    menuElement.hidden = false;
    const width = menuElement.offsetWidth;
    const height = menuElement.offsetHeight;
    const left = Math.max(8, Math.min(W - width - 8, anchor.x + anchor.w - width));
    const top = Math.min(H - height - 8, anchor.y + anchor.h + 6);
    menuElement.style.left = `${left}px`;
    menuElement.style.top = `${top}px`;
    tile.element.classList.add('show-bar');
    more.classList.add('is-on');
    if (demoDepth) tour.undo.push(closeMenu);
    focusOn(() => menuFocusRect());
    refreshHints();
  }

  function menuFocusRect() {
    const sub = $('.menu__sub', menuElement);
    // With the submenu open, show it and the line it came from.
    const rects = sub && !sub.hidden
      ? [localRect(sub), localRect($('[data-act="refresh"]', menuElement))]
      : [localRect(menuElement), ...(menu.tile ? [localRect($('.tbar', menu.tile.element))] : [])];
    const x = Math.min(...rects.map((r) => r.x));
    const y = Math.min(...rects.map((r) => r.y));
    const right = Math.max(...rects.map((r) => r.x + r.w));
    const bottom = Math.max(...rects.map((r) => r.y + r.h));
    return { x, y, w: right - x, h: bottom - y };
  }

  function openSubmenu() {
    const sub = $('.menu__sub', menuElement);
    const item = $('[data-act="refresh"]', menuElement);
    if (!sub || !item) return;
    sub.hidden = false;
    item.classList.add('is-hot');
    const menuLeft = parseFloat(menuElement.style.left);
    const goesLeft = menuLeft + menuElement.offsetWidth + sub.offsetWidth - 6 > W - 8;
    sub.style.left = goesLeft ? `${-sub.offsetWidth + 4}px` : `${menuElement.offsetWidth - 4}px`;
    sub.style.top = `${item.offsetTop - 5}px`;
    focusOn(() => menuFocusRect());
  }

  function closeMenu() {
    if (menuElement.hidden) return;
    menuElement.hidden = true;
    if (menu.tile) {
      menu.tile.element.classList.remove('show-bar');
      $('.more', menu.tile.element)?.classList.remove('is-on');
    }
    menu.tile = null;
    focusOn(defaultFocus(tour.step));
    refreshHints();
  }

  menuElement.addEventListener('pointerover', (event) => {
    const button = event.target.closest('[data-act]');
    if (!button) return;
    if (button.dataset.act === 'refresh') openSubmenu();
    else {
      const sub = $('.menu__sub', menuElement);
      if (sub && !sub.contains(event.target)) { sub.hidden = true; $('[data-act="refresh"]', menuElement)?.classList.remove('is-hot'); }
    }
  });

  menuElement.addEventListener('click', (event) => {
    const tile = menu.tile;
    if (!tile) return;
    const every = event.target.closest('[data-every]');
    if (every) {
      setRefresh(tile, Number(every.dataset.every));
      closeMenu();
      return;
    }
    const button = event.target.closest('[data-act]');
    if (!button) return;
    const act = button.dataset.act;
    if (act === 'refresh') { openSubmenu(); return; }
    closeMenu();
    if (act === 'reload') reloadTile(tile);
    else if (act === 'remove') board.remove(tile);
    else if (act === 'browser') toast(`In Blink this opens ${tile.host} in your browser.`);
    else if (act === 'copy') toast(`In Blink this copies the address of ${tile.host}.`);
    else if (act === 'hide') toast('In Blink you would now click parts of the page to hide them for good.');
    else if (act === 'mobile') toast('In Blink the page reloads as its phone version.');
    else if (act === 'app') toast(`In Blink this opens ${tile.title} in its usual app.`);
    else if (act === 'finder') toast(`In Blink this shows ${tile.title} in Finder.`);
  });

  // ---- Auto-refresh ------------------------------------------------------
  // In the app the interval is real time. Here a minute takes a second.

  const demoSeconds = (seconds) => Math.max(2, seconds / 60);

  function setRefresh(tile, seconds) {
    const before = tile.refresh;
    tile.refresh = seconds;
    tile.nextAt = seconds ? performance.now() + demoSeconds(seconds) * 1000 : 0;
    if (seconds) markTried('refresh');
    if (demoDepth) tour.undo.push(() => { tile.refresh = before; tile.nextAt = before ? performance.now() + demoSeconds(before) * 1000 : 0; });
    refreshHints();
  }

  function reloadTile(tile) {
    tile.loads += 1;
    tile.element.classList.remove('is-loading');
    void tile.element.offsetWidth;
    tile.element.classList.add('is-loading');
    setTimeout(() => tile.update(), calm ? 0 : 320);
    setTimeout(() => tile.element.classList.remove('is-loading'), 950);
  }

  function refreshTick() {
    const now = performance.now();
    for (const tile of board.tiles) {
      if (!tile.refresh || !tile.nextAt) continue;
      if (now >= tile.nextAt) {
        reloadTile(tile);
        tile.nextAt = now + demoSeconds(tile.refresh) * 1000;
      }
    }
    if (tour.step === 5) renderStatus();
  }

  // ---- Finder ------------------------------------------------------------

  function showFinder(on) {
    finder.classList.toggle('is-shown', on);
    finder.inert = !on;
    if (!on) closeFinderMenu();
  }

  let finderRow = null;

  function openFinderMenu(row) {
    $$('.ffile', finder).forEach((other) => other.classList.toggle('is-selected', other === row));
    finderRow = row;
    const r = localRect(row);
    fmenu.hidden = false;
    fmenuSub.hidden = true;
    $$('.is-hot', fmenu).forEach((button) => button.classList.remove('is-hot'));
    fmenu.style.left = `${Math.min(W - 360, r.x + 110)}px`;
    fmenu.style.top = `${r.y + r.h - 2}px`;
    if (demoDepth) tour.undo.push(closeFinderMenu);
    focusOn(() => finderMenuRect());
    refreshHints();
  }

  function finderMenuRect() {
    const a = localRect(finder);
    const b = localRect(fmenu);
    const c = fmenuSub.hidden ? b : localRect(fmenuSub);
    const x = Math.min(a.x, b.x);
    const y = Math.min(a.y, b.y);
    return { x, y, w: Math.max(a.x + a.w, c.x + c.w) - x, h: Math.max(a.y + a.h, b.y + b.h, c.y + c.h) - y };
  }

  function openWithSub() {
    fmenuSub.hidden = false;
    $('[data-fmenu="with"]', fmenu).classList.add('is-hot');
    focusOn(() => finderMenuRect());
  }

  function closeFinderMenu() {
    if (fmenu.hidden) return;
    fmenu.hidden = true;
    fmenuSub.hidden = true;
    $$('.ffile', finder).forEach((other) => other.classList.remove('is-selected'));
    finderRow = null;
    focusOn(defaultFocus(tour.step));
    refreshHints();
  }

  $$('.ffile[data-file]', finder).forEach((row) => {
    row.addEventListener('click', (event) => { event.stopPropagation(); openFinderMenu(row); });
    row.addEventListener('contextmenu', (event) => { event.preventDefault(); openFinderMenu(row); });
  });
  fmenu.addEventListener('pointerover', (event) => {
    const button = event.target.closest('[data-fmenu]');
    if (!button) return;
    if (button.dataset.fmenu === 'with') openWithSub();
    else if (!fmenuSub.contains(button)) { fmenuSub.hidden = true; $('[data-fmenu="with"]', fmenu).classList.remove('is-hot'); }
  });
  fmenu.addEventListener('click', (event) => {
    const button = event.target.closest('[data-fmenu]');
    if (!button || !finderRow) return;
    const act = button.dataset.fmenu;
    const key = finderRow.dataset.file;
    if (act === 'with') { openWithSub(); return; }
    if (act === 'blink') { openFile(key); return; }
    closeFinderMenu();
    if (act === 'open' || act === 'preview') toast('That opens it in its usual app. Choose Open With, then Blink.');
    else if (act === 'look') toast('Quick Look shows it once. Blink keeps it a key away.');
  });
  screen.addEventListener('pointerdown', (event) => {
    if (!fmenu.hidden && !fmenu.contains(event.target) && !event.target.closest('.ffile')) closeFinderMenu();
  });

  // ---------------------------------------------------------------------
  // Hints: the line under the screen, a pulsing ring on what to use, and
  // the key's light when the key is what to press.
  // ---------------------------------------------------------------------

  const toastState = { text: '', timer: 0 };
  function toast(text) {
    toastState.text = text;
    clearTimeout(toastState.timer);
    toastState.timer = setTimeout(() => { toastState.text = ''; refreshHints(); }, 4200);
    refreshHints();
  }

  let hintsQueued = false;
  function refreshHints() {
    if (hintsQueued) return;
    hintsQueued = true;
    requestAnimationFrame(() => { hintsQueued = false; renderHints(); });
  }

  const pinned = () => peek.state === 'pinned';
  const spaceWord = coarse ? 'the space key' : 'Space';

  function stepHint(step) {
    const name = NAMES[step - 1];
    if (step === 0) return { text: coarse ? 'Press and hold the space key.' : 'Hold Space, or press and hold the key.', kind: 'turn', nudge: true };
    if (tried.has(name)) {
      if (step === 5) return refreshHint() || { text: 'Tried. Scroll on for the next one.', kind: 'done' };
      return { text: step === 7 ? (tried.size === NAMES.length ? 'All seven tried. Scroll on for the rest.' : 'Tried. Scroll on for the rest.') : 'Tried. Scroll on for the next one.', kind: 'done' };
    }
    const closed = { text: `Blink is closed. Tap ${spaceWord} to open it.`, kind: 'turn', nudge: true };
    switch (step) {
      case 1: return { text: `Your turn: hold ${spaceWord}, then let go.`, kind: 'turn', nudge: true };
      case 2: return parts.tap.has('tap')
        ? (pinned() ? { text: 'Now press esc to close it.', kind: 'turn', spot: null, escNudge: true } : { text: `Tap ${spaceWord} again, then esc.`, kind: 'turn', nudge: true })
        : { text: `Your turn: tap ${spaceWord} once.`, kind: 'turn', nudge: true };
      case 3: {
        if (!pinned()) return closed;
        const item = $('.w-rem__item:not(.is-done) i', boardElement);
        return { text: 'Your turn: click one of the circles.', kind: 'turn', spot: item };
      }
      case 4: {
        if (!pinned()) return closed;
        if (!paletteElement.hidden) {
          return paletteInput.value.trim()
            ? { text: 'Press Return to add the first one.', kind: 'turn', spot: coarse ? $('button', paletteList) : null }
            : { text: coarse ? 'Tap Weather, or type an address.' : 'Type weather, then press Return.', kind: 'turn', spot: coarse ? $('button', paletteList) : null };
        }
        return { text: 'Your turn: click + at the top right.', kind: 'turn', spot: $('#board-add') };
      }
      case 5: {
        if (!pinned()) return closed;
        const tile = targetSite();
        if (!menuElement.hidden) return { text: 'Choose Auto-Refresh, then 5 minutes.', kind: 'turn', spot: $('.menu__sub', menuElement)?.hidden === false ? $('[data-every="300"]', menuElement) : $('[data-act="refresh"]', menuElement) };
        if (tile) return { text: `Your turn: click ⋯ on ${tile.title}.`, kind: 'turn', spot: $('.more', tile.element), showBar: tile };
        return { text: 'Add a website first, with +.', kind: 'turn', spot: $('#board-add') };
      }
      case 6: {
        if (!pinned()) return closed;
        if (!parts.arrange.has('flow')) {
          const tile = board.tiles.find((t) => t.kind === 'widget' && t.key === 'calendar') || board.tiles[board.tiles.length - 1];
          return { text: 'Your turn: drag a tile to another column.', kind: 'turn', spot: tile && $('.tile__cover', tile.element), wide: true };
        }
        if (board.mode === 'flow') return { text: 'Now click Freeform at the top.', kind: 'turn', spot: $('.toolbar [data-board-mode="freeform"]') };
        return { text: 'Now drag a tile anywhere you like.', kind: 'turn' };
      }
      case 7: {
        if (!fmenu.hidden) return { text: 'Choose Open With, then Blink.', kind: 'turn', spot: fmenuSub.hidden ? $('[data-fmenu="with"]', fmenu) : $('[data-fmenu="blink"]', fmenu) };
        if (pinned()) return { text: `Close Blink with esc to see the Finder window.`, kind: 'turn' };
        return { text: 'Your turn: click Train times.pdf.', kind: 'turn', spot: $('.ffile[data-file="trains"]', finder), wide: true };
      }
      default: return { text: '', kind: 'turn' };
    }
  }

  function targetSite() {
    const sites = board.tiles.filter((tile) => tile.kind === 'web' && tile.key !== 'metrics');
    return sites[sites.length - 1] || board.tiles.find((tile) => tile.kind === 'web') || null;
  }

  function refreshHint() {
    const tile = board.tiles.find((each) => each.refresh && each === targetSite()) || board.tiles.find((each) => each.refresh);
    if (!tile) return null;
    const period = demoSeconds(tile.refresh) * 1000;
    const left = Math.max(0, tile.nextAt - performance.now());
    const seconds = Math.ceil(left / 1000);
    return {
      text: `Every <b>${presetLabel(tile.refresh)}</b>. Next reload in <b>${seconds} s</b>, sped up.`,
      html: true,
      kind: 'timer',
      ring: 1 - left / period,
    };
  }

  let lastStatus = '';
  function renderStatus() {
    let hint;
    if (toastState.text) hint = { text: toastState.text, kind: 'note' };
    else if (tour.resting) hint = { text: 'This is how it ends up. Have a go whenever you like.', kind: 'demo' };
    else if (tour.running && tour.step >= 0) hint = { text: tour.step === 0 ? 'Showing you. Hold Space yourself any time.' : 'Showing you. Have a go whenever you like.', kind: 'demo' };
    else hint = stepHint(tour.step);
    if (tour.step === 5 && !toastState.text) hint = refreshHint() || hint;
    if (coarse && hint.text) hint.text = hint.text.replace('Hold Space yourself', 'Press and hold the key yourself');
    const key = `${hint.kind}|${hint.text}`;
    if (key !== lastStatus) {
      lastStatus = key;
      statusElement.dataset.kind = hint.kind;
      if (hint.html) statusText.innerHTML = hint.text;
      else statusText.textContent = hint.text;
    }
    if (hint.kind === 'timer') {
      if (!$('.deck__ring', statusGlyph)) statusGlyph.innerHTML = '<svg class="deck__ring" viewBox="0 0 18 18"><circle class="bg" cx="9" cy="9" r="8"/><circle class="fg" cx="9" cy="9" r="8"/></svg>';
      $('.fg', statusGlyph).style.strokeDashoffset = (50.27 * (1 - Math.min(1, Math.max(0, hint.ring)))).toFixed(2);
    } else if (statusGlyph.firstChild) {
      statusGlyph.innerHTML = '';
    }
    return hint;
  }

  function renderHints() {
    const hint = renderStatus();
    keySpace.classList.toggle('is-nudge', Boolean(hint.nudge) && !tour.running);
    keyEsc.classList.toggle('is-nudge', Boolean(hint.escNudge) && !tour.running);
    $$('.tile.show-bar').forEach((element) => { if (!menu.tile || menu.tile.element !== element) element.classList.remove('show-bar'); });
    if (hint.showBar && !tour.running) hint.showBar.element.classList.add('show-bar');
    const target = !tour.running && !tour.resting && hint.spot && hint.spot.getClientRects().length ? hint.spot : null;
    if (target) {
      const r = localRect(target);
      const wide = hint.wide;
      const size = wide ? null : Math.max(26, Math.min(44, Math.max(r.w, r.h) + 14));
      const w = wide ? r.w + 8 : size;
      const h = wide ? r.h + 8 : size;
      hotspot.style.width = `${w}px`;
      hotspot.style.height = `${h}px`;
      hotspot.style.transform = `translate(${(r.x + r.w / 2 - w / 2).toFixed(1)}px, ${(r.y + r.h / 2 - h / 2).toFixed(1)}px)`;
      hotspot.classList.toggle('is-wide', Boolean(wide));
    }
    hotspot.classList.toggle('is-on', Boolean(target));
  }

  // ---------------------------------------------------------------------
  // The pointer that shows you, when you only watch.
  // ---------------------------------------------------------------------

  const ghost = { element: $('#ghost'), x: W * 0.6, y: H * 0.8, shown: false };

  function placeGhost(x, y) {
    ghost.x = x;
    ghost.y = y;
    ghost.element.style.transform = `translate(${x.toFixed(1)}px, ${y.toFixed(1)}px)`;
  }

  function ghostShow() {
    if (ghost.shown || calm) return;
    ghost.element.style.transitionDuration = '0s';
    placeGhost(ghost.x, ghost.y);
    void ghost.element.offsetWidth;
    ghost.element.classList.add('is-on');
    ghost.shown = true;
  }

  function ghostHide() {
    ghost.element.classList.remove('is-on', 'is-click');
    ghost.shown = false;
  }

  const center = (element, fx = 0.5, fy = 0.5) => {
    const r = localRect(element);
    return { x: r.x + r.w * fx, y: r.y + r.h * fy };
  };

  async function ghostMove(point, ms = 800) {
    ghostShow();
    ghost.element.style.transitionDuration = calm ? '0s' : `${ms}ms`;
    placeGhost(point.x, point.y);
    await sleep(ms);
  }

  async function ghostClick() {
    ghost.element.classList.remove('is-click');
    void ghost.element.offsetWidth;
    ghost.element.classList.add('is-click');
    await sleep(170);
  }

  const easeInOut = (t) => (t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2);

  function ghostDrag(tile, from, to, ms) {
    ghostly(() => board.dragStart(tile));
    const token = tour.token;
    const t0 = performance.now();
    ghost.element.style.transitionDuration = '0s';
    return new Promise((resolve) => {
      const frame = (now) => {
        if (token !== tour.token) return;
        const k = calm ? 1 : Math.min(1, (now - t0) / ms);
        const e = easeInOut(k);
        const x = from.x + (to.x - from.x) * e;
        const y = from.y + (to.y - from.y) * e;
        placeGhost(x, y);
        ghostly(() => board.dragMove(x - from.x, y - from.y, { x: x - BOARD_X, y: y - BOARD_Y }));
        if (k < 1) requestAnimationFrame(frame);
        else {
          ghostly(() => board.dragEnd());
          resolve();
        }
      };
      requestAnimationFrame(frame);
    });
  }

  function ghostKey(key, down) {
    (key === 'esc' ? keyEsc : keySpace).classList.toggle('is-ghost', down);
  }

  // ---------------------------------------------------------------------
  // The tour: which step is open, setting the screen up for it, and the
  // demonstration that plays when the visitor only watches.
  // ---------------------------------------------------------------------

  const tour = { step: -1, token: 0, timers: [], undo: [], running: false, resting: false, lastInput: -1e9, restart: 0, retired: false };
  const REST = { rest: true };

  function sleep(ms) {
    const token = tour.token;
    return new Promise((resolve) => {
      const id = setTimeout(() => { if (token === tour.token) resolve(); }, calm ? 0 : ms);
      tour.timers.push(id);
    });
  }

  // With reduced motion a demonstration stops here and leaves the result in place.
  function keyframe() { if (calm) throw REST; }

  async function rest(ms) {
    keyframe();
    await sleep(ms);
    undoAll();
    ghostHide();
    await sleep(1500);
  }

  function undoAll() {
    const list = tour.undo.splice(0).reverse();
    quiet(() => list.forEach((fn) => { try { fn(); } catch (error) { console.error(error); } }));
  }

  function stopDemo() {
    tour.token += 1;
    tour.timers.forEach(clearTimeout);
    tour.timers = [];
    ghostly(() => board.cancelDrag());
    undoAll();
    ghostHide();
    ghostKey('space', false);
    ghostKey('esc', false);
    $$('.palette__list .is-pressed').forEach((button) => button.classList.remove('is-pressed'));
    tour.running = false;
    tour.resting = false;
    refreshHints();
  }

  async function play(step) {
    stopDemo();
    const token = tour.token;
    tour.running = true;
    refreshHints();
    try {
      await sleep(step === 0 ? 500 : 1300);
      while (token === tour.token) {
        await SCRIPTS[step]();
        await sleep(200);
      }
    } catch (error) {
      if (error === REST) tour.resting = true;
      else console.error(error);
    }
    if (token === tour.token) {
      tour.running = false;
      refreshHints();
    }
  }

  // Anything the visitor does on the screen stops a demonstration at once.
  function userInput() {
    tour.lastInput = performance.now();
    tour.retired = true;
    if (tour.running || tour.undo.length) stopDemo();
    scheduleRestart();
  }

  let stageHover = false;
  stage.addEventListener('pointerenter', () => { stageHover = true; });
  stage.addEventListener('pointerleave', () => { stageHover = false; });
  stage.addEventListener('pointerdown', (event) => {
    if (event.target.closest('#key-space')) return; // handled there
    userInput();
  }, true);
  stage.addEventListener('focusin', () => { tour.lastInput = performance.now(); });

  function scheduleRestart() {
    clearTimeout(tour.restart);
    tour.restart = setTimeout(maybeRestart, 9000);
  }

  function maybeRestart() {
    const step = tour.step;
    if (step < 1 || tried.has(NAMES[step - 1]) || tour.running || calm) return;
    const idle = performance.now() - tour.lastInput;
    const busy = stageHover || spaceHeld || keyPressed || board.drag || !paletteElement.hidden || !menuElement.hidden || !fmenu.hidden
      || stage.contains(document.activeElement) && isTyping(document.activeElement);
    if (idle < 8500 || busy) { scheduleRestart(); return; }
    play(step);
  }

  function closeTransient() {
    closePalette();
    closeMenu();
    closeFinderMenu();
  }

  const SETUP = {
    0: () => { closeTransient(); showFinder(false); forceClose(); },
    1: () => { closeTransient(); showFinder(false); forceClose(); },
    2: () => { closeTransient(); showFinder(false); forceClose(); },
    3: () => { closeTransient(); showFinder(false); ensurePinned(); board.setEditing(false); },
    4: () => { closeTransient(); showFinder(false); ensurePinned(); board.setEditing(false); },
    5: () => {
      closeTransient(); showFinder(false); ensurePinned(); board.setEditing(false);
      if (!board.tiles.some((tile) => tile.kind === 'web' && tile.key !== 'metrics')) addSite('weather');
    },
    6: () => { closeTransient(); showFinder(false); ensurePinned(); board.setEditing(true); },
    7: () => { closeTransient(); board.setEditing(false); forceClose(); showFinder(true); },
  };

  function defaultFocus(step) {
    if (step === 3) {
      return () => {
        const tile = board.tiles.find((t) => t.kind === 'widget' && t.key === 'reminders');
        return tile ? { ...tileRect(tile), h: Math.min(tile.frame.h, 300) } : null;
      };
    }
    if (step === 4) return () => ({ x: W - 420, y: 0, w: 420, h: 250 });
    if (step === 5) {
      return () => {
        const tile = targetSite();
        return tile ? { ...tileRect(tile), h: Math.min(tile.frame.h, 280) } : null;
      };
    }
    if (step === 7) return () => localRect(finder);
    return null;
  }

  function setStep(step) {
    if (step === tour.step) return;
    tour.step = step;
    screen.dataset.step = step;
    todos.forEach((todo) => {
      const n = Number(todo.dataset.step);
      // On the cover the first line is already open, ready.
      todo.classList.toggle('is-on', n === step || (step === 0 && n === 1));
      if (n === step) $('.todo__row', todo).setAttribute('aria-current', 'step');
      else $('.todo__row', todo).removeAttribute('aria-current');
    });
    placeTab();
    stopDemo();
    quiet(() => SETUP[step]());
    focusOn(defaultFocus(step));
    if (step === 0) {
      if (!tour.retired) play(0);
    } else if (!tried.has(NAMES[step - 1]) && !calm) {
      if (performance.now() - tour.lastInput > 3000) play(step);
      else scheduleRestart();
    } else if (!tried.has(NAMES[step - 1]) && calm) {
      play(step);
    }
    refreshHints();
  }

  function placeTab() {
    const todo = todos.find((each) => each.classList.contains('is-on'));
    tab.classList.toggle('is-on', Boolean(todo) && wide);
    if (!todo || !wide) return;
    const listTop = $('#todos').offsetTop;
    const index = todos.indexOf(todo);
    // Rows above the open one are all one height, so this holds mid-animation.
    const rowHeight = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--row-h')) || 38;
    tab.style.transform = `translateY(${listTop + index * rowHeight + 5}px)`;
  }

  // ---- What each demonstration does --------------------------------------

  const SCRIPTS = {
    // The cover: Blink comes and goes by itself until someone tries it.
    async 0() {
      ghostKey('space', true);
      ghostly(shortcutDown);
      tour.undo.push(() => { forceClose(); ghostKey('space', false); });
      keyframe();
      await sleep(3300);
      ghostly(shortcutUp);
      ghostKey('space', false);
      tour.undo.length = 0;
      await sleep(1700);
    },

    async 1() {
      ghostKey('space', true);
      ghostly(shortcutDown);
      tour.undo.push(() => { forceClose(); ghostKey('space', false); });
      keyframe();
      await sleep(2500);
      ghostly(shortcutUp);
      ghostKey('space', false);
      tour.undo.length = 0;
      await sleep(3200);
    },

    async 2() {
      ghostKey('space', true);
      ghostly(shortcutDown);
      tour.undo.push(() => { forceClose(); ghostKey('space', false); });
      await sleep(130);
      ghostly(shortcutUp);
      ghostKey('space', false);
      keyframe();
      await sleep(2800);
      ghostKey('esc', true);
      await sleep(140);
      ghostly(dismiss);
      ghostKey('esc', false);
      tour.undo.length = 0;
      await sleep(2000);
    },

    async 3() {
      ghostly(ensurePinned);
      const item = $('.w-rem__item[data-demo]:not(.is-done)', boardElement) || $('.w-rem__item:not(.is-done)', boardElement);
      if (!item) { await sleep(1000); return; }
      await ghostMove(center($('i', item)), 900);
      await ghostClick();
      ghostly(() => toggleReminder(item));
      await rest(2600);
    },

    async 4() {
      ghostly(ensurePinned);
      await ghostMove(center($('#board-add')), 900);
      await ghostClick();
      ghostly(openPalette);
      await sleep(450);
      for (const letter of 'weather') {
        setPaletteQuery(paletteInput.value + letter);
        await sleep(95);
      }
      await sleep(550);
      const first = $('.palette__list button');
      if (first) first.classList.add('is-pressed');
      await sleep(260);
      ghostly(() => choosePaletteItem(0));
      ghostHide();
      await rest(2800);
    },

    async 5() {
      ghostly(ensurePinned);
      const tile = targetSite();
      if (!tile) { await sleep(1000); return; }
      tile.element.classList.add('show-bar-demo');
      tour.undo.push(() => tile.element.classList.remove('show-bar-demo'));
      await ghostMove(center($('.more', tile.element)), 900);
      await ghostClick();
      ghostly(() => openTileMenu(tile));
      await sleep(500);
      await ghostMove(center($('[data-act="refresh"]', menuElement), 0.4), 500);
      ghostly(openSubmenu);
      await sleep(450);
      const option = $('[data-every="300"]', menuElement);
      await ghostMove(center(option, 0.35), 450);
      option.classList.add('is-hot');
      await ghostClick();
      ghostly(() => { setRefresh(tile, 300); closeMenu(); });
      await ghostMove({ x: ghost.x + 60, y: ghost.y + 90 }, 500);
      ghostHide();
      keyframe();
      await sleep(5600);
      await rest(1400);
    },

    async 6() {
      ghostly(ensurePinned);
      ghostly(() => board.setEditing(true));
      const snap = board.snapshot();
      tour.undo.push(() => board.restore(snap));
      const moving = board.tiles.find((t) => t.kind === 'widget' && t.key === 'calendar') || board.tiles[board.tiles.length - 1];
      const target = board.tiles[0];
      if (!moving || !target || moving === target) { await sleep(1000); return; }
      const from = { x: BOARD_X + moving.frame.x + moving.frame.w / 2, y: BOARD_Y + moving.frame.y + moving.frame.h * 0.42 };
      const to = { x: BOARD_X + target.frame.x + 30, y: BOARD_Y + target.frame.y + target.frame.h * 0.4 };
      await ghostMove(from, 900);
      await ghostDrag(moving, from, to, 1300);
      await sleep(700);
      await ghostMove(center($('.toolbar [data-board-mode="freeform"]')), 800);
      await ghostClick();
      ghostly(() => board.setMode('freeform'));
      await sleep(600);
      const next = board.tiles.find((t) => t.kind === 'widget' && t.key === 'clock') || board.tiles[0];
      const from2 = { x: BOARD_X + next.frame.x + next.frame.w / 2, y: BOARD_Y + next.frame.y + next.frame.h / 2 };
      const to2 = { x: from2.x + 150, y: from2.y + 110 };
      await ghostMove(from2, 800);
      await ghostDrag(next, from2, to2, 1100);
      keyframe();
      await rest(2200);
    },

    async 7() {
      ghostly(() => showFinder(true));
      const row = $('.ffile[data-file="trains"]', finder);
      await ghostMove(center(row, 0.3), 900);
      await ghostClick();
      ghostly(() => openFinderMenu(row));
      await sleep(500);
      await ghostMove(center($('[data-fmenu="with"]', fmenu), 0.4), 450);
      ghostly(openWithSub);
      await sleep(450);
      const blink = $('[data-fmenu="blink"]', fmenu);
      await ghostMove(center(blink, 0.4), 450);
      blink.classList.add('is-hot');
      await ghostClick();
      blink.classList.remove('is-hot');
      ghostly(() => openFile('trains'));
      ghostHide();
      await rest(3000);
    },
  };

  // ---------------------------------------------------------------------
  // Scrolling picks the step. One rAF-throttled handler does all of it.
  // ---------------------------------------------------------------------

  let wide = wideQuery.matches;
  let pinTop = 140;
  let cardHeight = 600;

  function measure() {
    wide = wideQuery.matches;
    if (wide) {
      const vh = window.innerHeight;
      const innerTop = stageInner.offsetTop;
      const innerHeight = stageInner.offsetHeight;
      // The card lines up with the top of the screen and runs at least as
      // far down as the keys; on a short window it may run a little further.
      pinTop = Math.max(70, innerTop);
      cardHeight = Math.round(Math.min(660, Math.max(innerHeight, 610)));
      if (pinTop + cardHeight > vh - 16) cardHeight = Math.max(innerHeight, vh - 16 - pinTop);
      if (pinTop + cardHeight > vh - 16) pinTop = Math.max(66, vh - 16 - cardHeight);
      tourElement.style.setProperty('--pin-top', `${pinTop}px`);
      tourElement.style.setProperty('--card-h', `${cardHeight}px`);
    }
    applyCamera(false);
    placeTab();
    board.layout(false);
  }

  function readScroll() {
    const vh = window.innerHeight;
    topBar.classList.toggle('is-past', coverMark.getBoundingClientRect().bottom < 50);

    let step = 0;
    if (wide) {
      const run = runway.getBoundingClientRect();
      const into = pinTop + cardHeight - run.top;
      if (into > -vh * 0.14) step = 1 + Math.min(6, Math.max(0, Math.floor(into / (run.height / 7))));
    } else {
      const stageBottom = stage.getBoundingClientRect().bottom;
      const line = stageBottom + (vh - stageBottom) * 0.42;
      todos.forEach((todo, index) => { if (todo.getBoundingClientRect().top < line) step = index + 1; });
    }
    setStep(step);
    scrubFill(vh);
    scrubNoise(vh);
  }

  let scrollFrame = 0;
  const onScroll = () => {
    if (scrollFrame) return;
    scrollFrame = requestAnimationFrame(() => { scrollFrame = 0; readScroll(); });
  };
  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('resize', () => { measure(); onScroll(); });
  if ('ResizeObserver' in window) new ResizeObserver(() => { measure(); }).observe(viewport);

  function scrollToStep(step) {
    let y;
    if (wide) {
      const run = runway.getBoundingClientRect();
      y = window.scrollY + run.top - (pinTop + cardHeight) + (step - 1 + 0.3) * (run.height / 7);
    } else {
      const todo = todos[step - 1];
      const stageHeight = stage.getBoundingClientRect().height + 52;
      y = window.scrollY + todo.getBoundingClientRect().top - stageHeight - 8;
    }
    window.scrollTo({ top: Math.max(0, y), behavior: calm ? 'auto' : 'smooth' });
  }

  todos.forEach((todo, index) => {
    $('.todo__row', todo).addEventListener('click', () => { if (tour.step !== index + 1) scrollToStep(index + 1); });
    $('.todo__next', todo).addEventListener('click', (event) => {
      if (event.currentTarget.dataset.next) {
        $(`#${event.currentTarget.dataset.next}`).scrollIntoView({ behavior: calm ? 'auto' : 'smooth' });
      } else {
        scrollToStep(index + 2);
      }
    });
  });

  // The summary fills in word by word as it comes up the page.
  const fill = $('#fill');
  let fillWords = [];
  let fillShown = -1;
  (function splitFill() {
    const words = fill.textContent.trim().split(/\s+/);
    fill.innerHTML = words.map((word) => `<span class="w">${word}</span>`).join(' ');
    fillWords = $$('.w', fill);
  })();

  function scrubFill(vh) {
    const r = fill.getBoundingClientRect();
    const p = calm ? 1 : Math.min(1, Math.max(0, (vh * 0.86 - r.top) / (r.height + vh * 0.3)));
    const shown = Math.round(p * fillWords.length);
    if (shown === fillShown) return;
    fillShown = shown;
    fillWords.forEach((word, index) => word.classList.toggle('is-in', index < shown));
  }

  // Less noise: the adverts go first, then the cookie banner.
  const noise = $('#noise');
  let noiseLast = -1;
  function scrubNoise(vh) {
    const r = noise.getBoundingClientRect();
    const p = calm ? 1 : Math.min(1, Math.max(0, (vh * 0.78 - r.top) / (vh * 0.5)));
    if (Math.abs(p - noiseLast) < 0.004) return;
    noiseLast = p;
    noise.style.setProperty('--a', Math.min(1, p * 1.8).toFixed(3));
    noise.style.setProperty('--c', Math.min(1, Math.max(0, p * 1.8 - 0.8)).toFixed(3));
  }

  // ---------------------------------------------------------------------
  // Start.
  // ---------------------------------------------------------------------

  overlay.inert = true;
  finder.inert = true;
  quiet(() => {
    addTile({ kind: 'widget', key: 'clock', ...WIDGETS.clock });
    addTile({ kind: 'widget', key: 'reminders', ...WIDGETS.reminders });
    addTile({ kind: 'widget', key: 'calendar', ...WIDGETS.calendar });
    addTile({ kind: 'web', key: 'metrics', title: SITES.metrics.title, host: SITES.metrics.host, w: SITES.metrics.w, h: SITES.metrics.h });
  });
  board.tiles.forEach((tile) => tile.element.classList.remove('is-new'));
  renderProgress();
  updateClocks();
  updateCalendar();
  measure();
  readScroll();
  setInterval(updateClocks, 1000);
  setInterval(updateCalendar, 60000);
  setInterval(refreshTick, 250);

  // For checking the page.
  window.__blink = { peek, board, tour, tried, parts, setStep, shortcutDown, shortcutUp, scrollToStep };
})();
