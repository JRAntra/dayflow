/* global dayflow */
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmt = (d) => d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
// "9:20 – 11:30 AM" when both ends share AM/PM, otherwise "11:30 AM – 1:00 PM"
function fmtRange(a, b) {
  const A = fmt(a); const B = fmt(b);
  const suffix = (s) => (s.match(/\s?[AaPp]\.?[Mm]\.?$/) || [''])[0];
  const sa = suffix(A);
  return sa && sa === suffix(B) ? `${A.slice(0, -sa.length)} – ${B}` : `${A} – ${B}`;
}
const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;
const DAY_LETTERS = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

const state = {
  today: { blocks: [], meetings: [] },
  schedule: { blocks: [] },
  settings: {},
  google: {},
  customSounds: [],
  builtinSounds: [],
  blockTypes: [],
  shortcutActive: false,
  platform: '',
  draft: [],
  dirty: false,
};

// ---------------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------------

document.documentElement.dataset.platform = dayflow.platform;
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');

// Runs a DOM change as a view transition (a short cross-fade or morph), unless motion is reduced.
function transition(change) {
  if (!document.startViewTransition || reduceMotion.matches) { change(); return; }
  document.startViewTransition(change);
}

document.querySelectorAll('.nav-item[data-view]').forEach((tab) => {
  tab.addEventListener('click', () => showView(tab.dataset.view));
});
function showView(name) {
  if (!document.querySelector(`#view-${name}[hidden]`)) return;
  transition(() => {
    document.querySelectorAll('.nav-item[data-view]').forEach((t) => {
      if (t.dataset.view === name) t.setAttribute('aria-current', 'page');
      else t.removeAttribute('aria-current');
    });
    document.querySelectorAll('.view').forEach((v) => { v.hidden = v.id !== `view-${name}`; });
    document.querySelector('.content').scrollTop = 0;
  });
}
$('now-plan').addEventListener('click', () => showView('schedule'));

// Brief messages, at the bottom of the window
let toastTimer;
function toast(msg, err = false) {
  const t = $('toast');
  t.textContent = msg;
  t.classList.toggle('err', err);
  t.dataset.state = 'shown';
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.dataset.state = 'hidden'; }, err ? 6000 : 3500);
}

// ---------------------------------------------------------------------------
// Data loading
// ---------------------------------------------------------------------------

async function loadAll() {
  const all = await dayflow.getAll();
  state.schedule = all.schedule;
  state.settings = all.settings;
  state.google = all.google;
  state.customSounds = all.customSounds;
  state.builtinSounds = all.builtinSounds;
  if (!typesTimer) state.blockTypes = all.blockTypes;
  state.shortcutActive = all.shortcutActive;
  state.platform = all.platform;
  if (!state.dirty) {
    state.draft = structuredClone(all.schedule.blocks);
    renderEditor();
  }
  refreshEditorTypes();
  renderSettings();
  await loadToday();
}
let dialKey = '';
async function loadToday() {
  const t = await dayflow.getToday();
  state.today = {
    blocks: t.blocks.map((b) => ({ ...b, kind: 'block', start: new Date(b.start), end: new Date(b.end) })),
    meetings: t.meetings.map((m) => ({ ...m, kind: 'meeting', start: new Date(m.start), end: new Date(m.end) })),
  };
  dialKey = ''; // rebuild the dial for the new data
  renderAgenda();
  renderNow();
  renderSettings();
}
dayflow.onDataChanged(loadAll);

// ---------------------------------------------------------------------------
// Today: dial
// Built once per change of data (the arcs draw themselves in the first time); after that
// only the "now" hand and the current block's highlight move.
// ---------------------------------------------------------------------------

const C = 180;            // dial center
const R_BLOCK = 132;
const R_MEET = 162;
const SWEEP = 300;        // degrees used; the gap sits at the bottom
const START_ANGLE = -150;

function polar(r, deg) {
  const rad = (deg - 90) * Math.PI / 180;
  return [C + r * Math.cos(rad), C + r * Math.sin(rad)];
}
function arc(r, a0, a1) {
  const [x0, y0] = polar(r, a0);
  const [x1, y1] = polar(r, a1);
  const large = a1 - a0 > 180 ? 1 : 0;
  return `M${x0.toFixed(2)} ${y0.toFixed(2)} A${r} ${r} 0 ${large} 1 ${x1.toFixed(2)} ${y1.toFixed(2)}`;
}

function dayRange() {
  const items = [...state.today.blocks, ...state.today.meetings];
  if (!items.length) return null;
  const s = new Date(Math.min(...items.map((i) => i.start)));
  const e = new Date(Math.max(...items.map((i) => i.end)));
  s.setMinutes(0, 0, 0);
  if (e.getMinutes() || e.getSeconds()) { e.setHours(e.getHours() + 1, 0, 0, 0); }
  return { s, e };
}

let dialDrawn = false;
let dialAngle = null;
function renderDial(now) {
  const svg = $('dial');
  const range = dayRange();
  const key = JSON.stringify([range, state.today]);
  if (key !== dialKey) {
    dialKey = key;
    const parts = [`<path class="dial-track" stroke-width="22" stroke-linecap="round" d="${arc(R_BLOCK, START_ANGLE, START_ANGLE + SWEEP)}"/>`];
    if (range) {
      const span = range.e - range.s;
      const angle = (t) => START_ANGLE + SWEEP * Math.min(1, Math.max(0, (t - range.s) / span));
      const hours = span / 3600000;
      const step = hours > 12 ? 3 : hours > 7 ? 2 : 1;
      for (let t = new Date(range.s); t <= range.e; t.setHours(t.getHours() + 1)) {
        const a = angle(t);
        const [x0, y0] = polar(R_BLOCK - 22, a);
        const [x1, y1] = polar(R_BLOCK - 18, a);
        parts.push(`<line class="dial-tick" x1="${x0}" y1="${y0}" x2="${x1}" y2="${y1}"/>`);
        if (t.getHours() % step === 0) {
          const [lx, ly] = polar(R_BLOCK - 33, a);
          parts.push(`<text class="dial-hour" x="${lx}" y="${ly}">${t.getHours() % 12 || 12}</text>`);
        }
      }
      const gap = 3.2; // degrees between neighbouring arcs, so rounded ends don't touch
      for (const b of state.today.blocks) {
        const a0 = angle(b.start) + gap / 2;
        const a1 = Math.max(angle(b.end) - gap / 2, a0 + 0.5);
        parts.push(`<path class="dial-block" pathLength="1" stroke-width="20" data-start="${+b.start}" data-end="${+b.end}" d="${arc(R_BLOCK, a0, a1)}"><title>${esc(b.title)}, ${fmt(b.start)} to ${fmt(b.end)}</title></path>`);
      }
      for (const m of state.today.meetings) {
        const a0 = angle(m.start);
        const a1 = Math.max(angle(m.end), a0 + 1.5);
        parts.push(`<path class="dial-meet" pathLength="1" stroke-width="6" d="${arc(R_MEET, a0, a1)}"><title>${esc(m.title)}, ${fmt(m.start)}</title></path>`);
      }
      // The hand points straight up and is rotated into place, so it can glide.
      const [hx0, hy0] = polar(R_BLOCK - 14, 0);
      const [hx1, hy1] = polar(R_MEET + 8, 0);
      parts.push(`<g class="dial-hand" id="dial-hand"><line x1="${hx0}" y1="${hy0}" x2="${hx1}" y2="${hy1}"/><circle cx="${hx1}" cy="${hy1}" r="4.5"/></g>`);
      svg.dataset.start = +range.s;
      svg.dataset.end = +range.e;
    }
    svg.classList.toggle('draw', !!range && !dialDrawn);
    if (range) dialDrawn = true;
    svg.innerHTML = parts.join('');
    dialAngle = null;
  }
  if (!range) return;

  svg.querySelectorAll('.dial-block').forEach((p) => {
    const s = Number(p.dataset.start);
    const e = Number(p.dataset.end);
    p.classList.toggle('past', now >= e);
    p.classList.toggle('current', now >= s && now < e);
  });
  const hand = $('dial-hand');
  const inside = now >= range.s && now <= range.e;
  hand.style.display = inside ? '' : 'none';
  if (inside) {
    const a = START_ANGLE + SWEEP * ((now - range.s) / (range.e - range.s));
    if (dialAngle === null) hand.style.transition = 'none'; // jump into place, then glide
    hand.style.transform = `rotate(${a}deg)`;
    if (dialAngle === null) requestAnimationFrame(() => { hand.style.transition = ''; });
    dialAngle = a;
  }
}

// ---------------------------------------------------------------------------
// Today: center readout and timeline
// ---------------------------------------------------------------------------

function countdown(ms) {
  const total = Math.max(0, Math.ceil(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const pad = (n) => String(n).padStart(2, '0');
  return h ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}

// Writes text one character per span; characters that changed roll up into place.
function rollText(el, text) {
  const old = el.dataset.text || '';
  if (old === text) return;
  el.dataset.text = text;
  if (old.length !== text.length) {
    el.innerHTML = [...text].map((c) => `<span>${esc(c)}</span>`).join('');
    return;
  }
  [...text].forEach((c, i) => {
    if (c === old[i]) return;
    const span = document.createElement('span');
    span.className = 'in';
    span.textContent = c;
    el.children[i].replaceWith(span);
  });
}

function renderNow() {
  const now = new Date();
  $('today-date').textContent = `${DAY_NAMES[now.getDay()]}, ${now.toLocaleDateString([], { month: 'long', day: 'numeric' })}`;
  $('today-clock').textContent = now.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });

  const { blocks } = state.today;
  const current = blocks.find((b) => now >= b.start && now < b.end);
  const next = blocks.find((b) => b.start > now);
  const title = $('now-title');
  const count = $('now-count');
  const note = $('now-note');
  const badge = $('now-type');
  $('now-plan').hidden = true;
  badge.hidden = true;

  if (!blocks.length) {
    title.textContent = 'Nothing planned today';
    rollText(count, '');
    note.textContent = state.schedule.blocks.length
      ? `None of your blocks repeat on ${DAY_NAMES[now.getDay()]}s.`
      : 'Add the phases of your day to get reminders.';
    $('now-plan').hidden = false;
  } else if (current) {
    badge.hidden = false;
    badge.textContent = typeName(current.type);
    title.textContent = current.title;
    rollText(count, countdown(current.end - now));
    const after = blocks.find((b) => b.start >= current.end);
    note.textContent = after
      ? `Ends at ${fmt(current.end)}. Next is ${after.title}.`
      : `Ends at ${fmt(current.end)}. Last block today.`;
  } else if (next) {
    title.textContent = 'Free time';
    rollText(count, countdown(next.start - now));
    note.textContent = `${next.title} starts at ${fmt(next.start)}.`;
  } else {
    title.textContent = 'Done for today';
    rollText(count, '');
    note.textContent = 'Every block has finished.';
  }
  renderDial(now);
}

let currentShown = null;
function renderAgenda() {
  const now = new Date();
  const items = [...state.today.blocks, ...state.today.meetings].sort((a, b) => a.start - b.start || (a.kind === 'meeting' ? 1 : -1));
  const current = items.find((i) => i.kind === 'block' && now >= i.start && now < i.end);
  const draw = () => {
    const list = $('agenda-list');
    list.innerHTML = items.map((i, idx) => {
      const status = now >= i.end ? 'past' : now >= i.start ? 'current' : '';
      const join = i.kind === 'meeting' && i.url && now < i.end
        ? `<button class="btn small" data-join="${idx}">Join</button>` : '';
      const label = i.kind === 'meeting' ? 'Meeting' : typeName(i.type);
      return `<li class="tl-item ${i.kind} ${status}">
        <span class="tl-time">${fmt(i.start)}</span>
        <span class="tl-dot" aria-hidden="true"></span>
        <div class="tl-body">
          <span class="tl-what"><span class="tl-title">${esc(i.title)}</span><span class="tl-sub">${esc(label)}</span></span>
          <span class="tl-range">until ${fmt(i.end)}</span>
          ${join}
        </div>
      </li>`;
    }).join('');
    list.querySelectorAll('[data-join]').forEach((btn) => {
      btn.addEventListener('click', () => dayflow.openUrl(items[Number(btn.dataset.join)].url));
    });
    $('agenda-empty').hidden = items.length > 0;
    $('calendar-hint').hidden = !!state.google.connected;
  };
  // When a block hands over to the next, its highlight slides down to the new one.
  const key = current ? `${current.id}|${+current.start}` : null;
  const handOff = currentShown !== null && key !== null && key !== currentShown && !$('view-today').hidden;
  currentShown = key;
  if (handOff) transition(draw); else draw();
}

let lastMinute = -1;
setInterval(() => {
  renderNow();
  const m = new Date().getMinutes();
  if (m !== lastMinute) { lastMinute = m; renderAgenda(); }
}, 1000);

// ---------------------------------------------------------------------------
// Schedule editor
// ---------------------------------------------------------------------------

const toMin = (t) => { const [h, m] = t.split(':').map(Number); return h * 60 + m; };
const newId = () => `b${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

// Unsaved changes bring up the floating save bar.
function setDirty(d) {
  state.dirty = d;
  $('savebar').dataset.state = d ? 'shown' : 'hidden';
  if (d) setSaveText('Unsaved changes');
}
function setSaveText(msg, err = false) {
  $('sched-status').textContent = msg;
  $('sched-status').classList.toggle('err', err);
}
const setSchedStatus = (msg, err = false) => toast(msg, err);

function rowProblems(b, i) {
  if (!b.title.trim()) return 'Give this block a name.';
  if (!b.start || !b.end) return 'Set a start and end time.';
  if (toMin(b.end) <= toMin(b.start)) return 'End time must be after the start time.';
  if (!b.days.length) return 'Pick at least one day, or this block never runs.';
  const clash = state.draft.find((o, j) => j !== i && o.start && o.end &&
    o.days.some((d) => b.days.includes(d)) &&
    toMin(o.start) < toMin(b.end) && toMin(b.start) < toMin(o.end));
  if (clash) return `Overlaps with "${clash.title || 'an unnamed block'}" on a shared day.`;
  return '';
}

function durationText(b) {
  if (!b.start || !b.end || toMin(b.end) <= toMin(b.start)) return '';
  const d = toMin(b.end) - toMin(b.start);
  const h = Math.floor(d / 60);
  return h ? `${h} h${d % 60 ? ` ${d % 60} min` : ''}` : `${d} min`;
}

// enter: the id of a block that was just added, so its row can expand into place.
function renderEditor({ enter = null } = {}) {
  const list = $('block-list');
  list.innerHTML = '';
  state.draft.forEach((b, i) => {
    const li = document.createElement('li');
    li.className = `block-row${b.id === enter ? ' enter' : ''}`;
    li.innerHTML = `
      <input type="time" aria-label="Start time" value="${esc(b.start)}" data-f="start">
      <input type="time" aria-label="End time" value="${esc(b.end)}" data-f="end">
      <div class="name-cell">
        <input type="text" aria-label="Block name" placeholder="What happens in this block?" value="${esc(b.title)}" data-f="title">
        <div class="meta">
          <label class="type-pick"><span class="dot" aria-hidden="true"></span><select class="type-select" aria-label="Block type"></select></label>
          <span class="dur"></span>
        </div>
      </div>
      <span class="days" role="group" aria-label="Repeats on">
        ${DAY_LETTERS.map((l, d) => `<button class="day" aria-label="${DAY_NAMES[d]}" aria-pressed="${b.days.includes(d)}" data-day="${d}">${l}</button>`).join('')}
      </span>
      <button class="remove" aria-label="Remove block">×</button>
      <span class="note"></span>`;

    li.querySelectorAll('input').forEach((inp) => {
      inp.addEventListener('input', () => {
        b[inp.dataset.f] = inp.value;
        setDirty(true);
        refreshNotes();
      });
    });
    li.querySelectorAll('.day').forEach((btn) => {
      btn.addEventListener('click', () => {
        const d = Number(btn.dataset.day);
        b.days = b.days.includes(d) ? b.days.filter((x) => x !== d) : [...b.days, d].sort();
        btn.setAttribute('aria-pressed', String(b.days.includes(d)));
        setDirty(true);
        refreshNotes();
      });
    });
    const typeSel = li.querySelector('.type-select');
    fillTypeSelect(typeSel, b.type);
    typeSel.addEventListener('change', () => {
      if (typeSel.value === NEW_TYPE) {
        fillTypeSelect(typeSel, b.type);
        showView('settings');
        showTab('types');
        $('add-type').focus();
        return;
      }
      b.type = typeSel.value;
      setDirty(true);
    });
    // The row shrinks away before it's removed.
    li.querySelector('.remove').addEventListener('click', () => {
      const go = () => {
        state.draft.splice(state.draft.indexOf(b), 1);
        setDirty(true);
        renderEditor();
      };
      if (reduceMotion.matches) { go(); return; }
      li.classList.add('leave');
      li.addEventListener('animationend', go, { once: true });
    });
    list.appendChild(li);
  });
  refreshNotes();
}

// Block types: each block's dropdown lists your types, then "New type…".
const NEW_TYPE = '__new';
const DEFAULT_TYPE = 'default'; // can be renamed, never deleted
const typeName = (id) => state.blockTypes.find((t) => t.id === id)?.name || '';
function fillTypeSelect(sel, value) {
  sel.innerHTML = state.blockTypes.map((t) => `<option value="${esc(t.id)}">${esc(t.name)}</option>`).join('')
    + '<option disabled>──────</option>'
    + `<option value="${NEW_TYPE}">New type…</option>`;
  sel.value = state.blockTypes.some((t) => t.id === value) ? value : DEFAULT_TYPE;
}
// Keeps the dropdowns current when types change while the schedule has unsaved edits.
function refreshEditorTypes() {
  [...$('block-list').children].forEach((li, i) => {
    const b = state.draft[i];
    if (b && !state.blockTypes.some((t) => t.id === b.type)) b.type = DEFAULT_TYPE;
    if (b) fillTypeSelect(li.querySelector('.type-select'), b.type);
  });
}

// Update each row's validation message in place, so typing never loses focus.
function refreshNotes() {
  [...$('block-list').children].forEach((li, i) => {
    const b = state.draft[i];
    const problem = rowProblems(b, i);
    const note = li.querySelector('.note');
    li.classList.toggle('invalid', !!problem && !problem.startsWith('Overlaps'));
    note.textContent = problem;
    li.querySelector('.dur').textContent = durationText(b);
    li.querySelector('.remove').setAttribute('aria-label', `Remove ${b.title || 'block'}`);
  });
}

$('add-block').addEventListener('click', () => {
  const last = [...state.draft].sort((a, b) => toMin(a.end || '00:00') - toMin(b.end || '00:00')).pop();
  const start = last?.end || '09:00';
  const endMin = Math.min(toMin(start) + 30, 23 * 60 + 59);
  const end = `${String(Math.floor(endMin / 60)).padStart(2, '0')}:${String(endMin % 60).padStart(2, '0')}`;
  const id = newId();
  state.draft.push({ id, title: '', start, end, days: last ? [...last.days] : [1, 2, 3, 4, 5], type: last?.type || DEFAULT_TYPE });
  setDirty(true);
  renderEditor({ enter: id });
  const row = $('block-list').lastElementChild;
  row.scrollIntoView({ block: 'nearest', behavior: reduceMotion.matches ? 'auto' : 'smooth' });
  row.querySelector('input[type="text"]').focus();
});

$('discard').addEventListener('click', () => {
  state.draft = structuredClone(state.schedule.blocks);
  setDirty(false);
  renderEditor();
});

$('save-schedule').addEventListener('click', async () => {
  const bad = state.draft.map(rowProblems).find((p) => p && !p.startsWith('Overlaps'));
  if (bad) { setSaveText('Fix the highlighted blocks first', true); return; }
  try {
    const saved = await dayflow.saveSchedule(state.draft);
    state.schedule = saved;
    state.draft = structuredClone(saved.blocks);
    setDirty(false);
    toast('Schedule saved');
    renderEditor();
    loadToday();
  } catch (e) {
    setSaveText(cleanError(e), true);
  }
});

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

function cleanError(e) {
  return String(e?.message || e).replace(/^Error invoking remote method '[^']+': (Error: )?/, '');
}

// Settings tabs: Block types, Meetings, Sounds, Calendar, General. The last one used is remembered.
const TAB_KEY = 'dayflow.settingsTab';
function showTab(name, { animate = true } = {}) {
  const change = () => {
    document.querySelectorAll('.tabs [data-tab]').forEach((t) => t.setAttribute('aria-selected', String(t.dataset.tab === name)));
    document.querySelectorAll('.pane').forEach((p) => { p.hidden = p.id !== `pane-${name}`; });
  };
  if (animate) transition(change); else change();
  try { localStorage.setItem(TAB_KEY, name); } catch {}
}
document.querySelectorAll('.tabs [data-tab]').forEach((t) => t.addEventListener('click', () => showTab(t.dataset.tab)));
try { showTab(localStorage.getItem(TAB_KEY) || 'types', { animate: false }); } catch { showTab('types', { animate: false }); }

function renderSettings() {
  const s = state.settings;
  $('set-sound').checked = !!s.sound;
  $('set-cards').checked = !!s.cards;
  $('set-card-close').value = String(s.cardAutoClose ?? 0);
  if (document.activeElement !== $('set-volume')) $('set-volume').value = s.volume;
  $('volume-val').textContent = `${$('set-volume').value}%`;
  $('set-login').checked = !!s.launchAtLogin;
  renderSounds();
  renderTypes();
  renderMeetings();

  const key = state.platform === 'darwin' ? '⌃⌥D' : 'Ctrl+Alt+D';
  $('shortcut-kbd').textContent = key;
  $('rail-kbd').textContent = key;
  $('rail-kbd').hidden = !state.shortcutActive;
  $('set-shortcut').checked = !!s.shortcut;
  $('shortcut-note').textContent = s.shortcut && !state.shortcutActive
    ? `Another app is already using ${key}, so the shortcut is off. Use the tray menu to switch modes.` : '';

  const g = state.google;
  const steps = document.querySelectorAll('#pane-calendar .step');
  steps[0].classList.toggle('done', !!g.hasCredentials);
  steps[1].classList.toggle('done', !!g.connected);
  $('g-import').textContent = g.hasCredentials ? 'Replace file' : 'Choose file';
  $('g-connect').disabled = !g.hasCredentials;
  $('g-connect').textContent = g.connected ? 'Reconnect' : 'Connect';
  $('g-sync-now').disabled = !g.connected;
  $('g-disconnect').disabled = !g.connected;

  const st = $('g-state');
  st.className = `g-state${g.connected ? ' on' : ''}`;
  st.innerHTML = `<span class="dot" aria-hidden="true"></span>${g.connected
    ? `Connected. ${state.today.meetings.length} meeting${state.today.meetings.length === 1 ? '' : 's'} today.`
    : 'Not connected. Meeting reminders are off.'}`;
  $('g-sync').textContent = g.lastSync ? `Last synced at ${fmt(new Date(g.lastSync))}. Syncs every 5 minutes.` : '';
  $('g-error').textContent = g.error || '';
}

// Each settings group has its own status line, so "Settings saved" shows next to what you changed.
const groupStatus = (el) => el.closest('.settings-group').querySelector('.status');
function flashStatus(el, msg, err = false) {
  el.textContent = msg;
  el.classList.toggle('err', err);
  clearTimeout(el.timer);
  if (!err) el.timer = setTimeout(() => { el.textContent = ''; }, 4000);
}

let settingsTimer;
function saveSettingsSoon(el, delay = 400) {
  const status = groupStatus(el);
  clearTimeout(settingsTimer);
  settingsTimer = setTimeout(async () => {
    const saved = await dayflow.saveSettings({
      sound: $('set-sound').checked,
      volume: $('set-volume').value,
      meetings: readReminderRows($('meeting-rows'), MEETING_REMINDERS),
      launchAtLogin: $('set-login').checked,
      shortcut: $('set-shortcut').checked,
      cards: $('set-cards').checked,
      cardAutoClose: $('set-card-close').value,
    });
    state.settings = saved.settings;
    state.shortcutActive = saved.shortcutActive;
    renderSettings();
    flashStatus(status, 'Settings saved');
  }, delay);
}
['set-sound', 'set-volume', 'set-login', 'set-shortcut', 'set-cards', 'set-card-close']
  .forEach((id) => $(id).addEventListener('change', (e) => saveSettingsSoon(e.currentTarget)));
$('set-volume').addEventListener('input', () => { $('volume-val').textContent = `${$('set-volume').value}%`; });
$('test-notify').addEventListener('click', () => dayflow.testNotification());

async function googleAction(btn, fn, busyLabel) {
  const label = btn.textContent;
  btn.disabled = true;
  btn.textContent = busyLabel;
  $('g-error').textContent = '';
  try {
    state.google = await fn();
    await loadToday();
  } catch (e) {
    state.google = { ...state.google, error: cleanError(e) };
  } finally {
    btn.textContent = label;
    renderSettings();
  }
}
$('g-import').addEventListener('click', (e) => googleAction(e.currentTarget, dayflow.importCredentials, 'Choosing…'));
$('g-connect').addEventListener('click', (e) => googleAction(e.currentTarget, dayflow.connectGoogle, 'Waiting for browser…'));
$('g-sync-now').addEventListener('click', (e) => googleAction(e.currentTarget, dayflow.syncNow, 'Syncing…'));
$('g-disconnect').addEventListener('click', (e) => googleAction(e.currentTarget, dayflow.disconnectGoogle, 'Disconnecting…'));

// ---------------------------------------------------------------------------
// Sounds
// Every sound is a short audio clip: the built-ins ship in assets/sounds, and yours are copied
// into the data folder. The main process hands over the bytes; the window decodes and plays them.
// ---------------------------------------------------------------------------

const MAX_CLIP_SECONDS = 30;

let audio;
let playing = [];  // nodes of the sound now playing, so the next one cuts it off
let playSeq = 0;
const clipCache = new Map();
const toArrayBuffer = (bytes) => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
const ctx = () => { audio = audio || new AudioContext(); return audio; };

function stopSound() {
  playSeq++;
  for (const n of playing) { try { n.stop(); } catch {} }
  playing = [];
}

// id: a built-in sound's id, or custom:<id> for one of yours
function clipBuffer(id) {
  if (!clipCache.has(id)) {
    clipCache.set(id, dayflow.getSoundData(id).then((bytes) => ctx().decodeAudioData(toArrayBuffer(bytes))));
  }
  return clipCache.get(id);
}

// Fade in: the sound starts at 10% of your volume and grows to full over its first 8 seconds
// (the whole of a short clip), so it doesn't startle you.
const FADE_SECONDS = 8;

// fallback: the sound to play instead if this one can't be loaded (a clip that's gone, say).
async function play(soundId, fallback = null, volume = state.settings.volume, { fade = false } = {}) {
  stopSound();
  const seq = playSeq;
  const level = (Number(volume) / 100) ** 2; // squared so the slider feels even
  let buffer;
  try {
    buffer = await clipBuffer(soundId);
  } catch {
    if (seq !== playSeq || !fallback || fallback === soundId) return;
    try { buffer = await clipBuffer(fallback); } catch { return; }
  }
  if (seq !== playSeq) return; // another sound started while this one loaded
  const out = audio.createGain();
  out.connect(audio.destination);
  const t = audio.currentTime;
  if (fade) {
    out.gain.setValueAtTime(level * 0.1, t);
    out.gain.linearRampToValueAtTime(level, t + Math.min(buffer.duration, FADE_SECONDS));
  } else {
    out.gain.value = level;
  }
  const src = audio.createBufferSource();
  src.buffer = buffer;
  src.connect(out);
  src.start();
  playing.push(src);
}
dayflow.onChime(({ sound, fallback, fade }) => play(sound, fallback, undefined, { fade })); // main picks the sound from the block's type
dayflow.onStopSound(stopSound);

// Checks a clip will play and isn't too long before DayFlow keeps it.
async function checkClipPlays(name, bytes) {
  let buffer;
  try { buffer = await ctx().decodeAudioData(toArrayBuffer(bytes)); } catch {
    throw new Error(`DayFlow can't play "${name}". Try converting it to mp3 or wav.`);
  }
  if (buffer.duration > MAX_CLIP_SECONDS + 0.5) {
    throw new Error(`"${name}" is ${Math.round(buffer.duration)} seconds long. Clips can be up to ${MAX_CLIP_SECONDS} seconds.`);
  }
}

// Sound settings ------------------------------------------------------------

function soundOptions() {
  const builtIn = state.builtinSounds.map((s) => `<option value="${esc(s.id)}">${esc(s.name)}</option>`).join('');
  const mine = state.customSounds.map((c) => `<option value="custom:${esc(c.id)}">${esc(c.name)}</option>`).join('');
  return `<optgroup label="Built-in">${builtIn}</optgroup>${mine ? `<optgroup label="Your clips">${mine}</optgroup>` : ''}`;
}

let clipsShown = null;
function renderSounds() {
  // Rebuild the lists only when your clips change, so an open dropdown isn't disturbed.
  const sig = JSON.stringify(state.customSounds);
  if (sig !== clipsShown) {
    clipsShown = sig;
    $('clip-list').innerHTML = state.customSounds.map((c) => `
      <li><span>${esc(c.name)}</span>
        <span><button class="btn small" data-play-clip="${esc(c.id)}" aria-label="Play ${esc(c.name)}">▶</button>
        <button class="btn small ghost" data-remove-clip="${esc(c.id)}">Remove</button></span></li>`).join('');
    $('clip-empty').hidden = state.customSounds.length > 0;
    $('clip-list').querySelectorAll('[data-play-clip]').forEach((btn) => {
      btn.addEventListener('click', () => play(`custom:${btn.dataset.playClip}`, null, $('set-volume').value));
    });
    $('clip-list').querySelectorAll('[data-remove-clip]').forEach((btn) => {
      btn.addEventListener('click', () => removeClip(btn.dataset.removeClip));
    });
  }
}

$('add-clip').addEventListener('click', async (e) => {
  const status = groupStatus(e.currentTarget);
  try {
    const picked = await dayflow.pickSoundFile();
    if (!picked) return;
    await checkClipPlays(picked.name, picked.data);
    const { clip } = await dayflow.addSound(picked);
    await loadAll();
    flashStatus(status, `Added "${clip.name}". Pick it for any reminder above.`);
  } catch (err) {
    flashStatus(status, cleanError(err), true);
  }
});

async function removeClip(id) {
  const status = groupStatus($('clip-list'));
  const name = state.customSounds.find((c) => c.id === id)?.name || 'that clip';
  stopSound();
  const { reset } = await dayflow.removeSound(id);
  clipCache.delete(`custom:${id}`);
  await loadAll();
  flashStatus(status, reset.length
    ? `Removed "${name}". ${reset.join(', ')} went back to the starting sound.`
    : `Removed "${name}".`);
}

// ---------------------------------------------------------------------------
// Reminder rows
// Used by every block type and by Meetings: a switch, a − 5 + stepper where the reminder
// comes early, a sound menu, and ▶. Keys and starting sounds match REMINDERS and
// MEETING_REMINDERS in main.js.
// ---------------------------------------------------------------------------

const TYPE_REMINDERS = [
  { key: 'prep', label: 'Start preparation', lead: true, sound: 'fairy-bell-bless' },
  { key: 'start', label: 'Start', sound: 'elevator-announcement-bells' },
  { key: 'warn', label: 'Heads-up', lead: true, sound: 'notification-bell' },
  { key: 'end', label: "Time's up", sound: 'clock-bells-hour-signal' },
];
const MEETING_REMINDERS = [
  { key: 'before', label: 'Before it starts', lead: true, sound: 'airport-announcement-ding' },
  { key: 'start', label: 'Starting now', sound: 'elegant-door-announcement' },
];
const clampLead = (v) => Math.min(60, Math.max(1, Math.round(Number(v)) || 5));

function reminderRowsHtml(spec, owner) {
  const options = soundOptions();
  return spec.map(({ key, label, lead }) => `
    <div class="rem-row" data-key="${key}">
      <label class="rem-label"><input type="checkbox" class="switch rem-on" aria-label="${esc(owner)}: ${label}"> <span>${label}</span></label>
      <span class="rem-lead">${lead ? `<span class="stepper">
          <button type="button" class="step-down" aria-label="One minute earlier">−</button>
          <input type="number" class="rem-min" min="1" max="60" aria-label="${esc(owner)}: minutes before">
          <button type="button" class="step-up" aria-label="One minute later">+</button>
        </span> min before` : ''}</span>
      <span class="slot"><select class="rem-sound" aria-label="${esc(owner)}: ${label} sound">${options}</select>
        <button type="button" class="btn small fade-toggle rem-fade" aria-pressed="false" title="Start quiet and grow to your volume">Fade in</button>
        <button type="button" class="btn small icon rem-play" aria-label="Play the ${esc(owner)} ${label.toLowerCase()} sound">▶</button></span>
    </div>`).join('');
}

function fillReminderRows(box, reminders) {
  box.querySelectorAll('.rem-row').forEach((row) => {
    const r = reminders[row.dataset.key];
    row.querySelector('.rem-on').checked = r.on;
    row.querySelector('.rem-fade').setAttribute('aria-pressed', String(!!r.fade));
    row.querySelector('.rem-sound').value = r.sound;
    const min = row.querySelector('.rem-min');
    if (min && document.activeElement !== min) min.value = r.lead;
    row.classList.toggle('off', !r.on);
  });
}

function readReminderRows(box, spec) {
  return Object.fromEntries(spec.map(({ key, lead }) => {
    const row = box.querySelector(`.rem-row[data-key="${key}"]`);
    const r = {
      on: row.querySelector('.rem-on').checked,
      sound: row.querySelector('.rem-sound').value,
      fade: row.querySelector('.rem-fade').getAttribute('aria-pressed') === 'true',
    };
    if (lead) r.lead = clampLead(row.querySelector('.rem-min').value);
    return [key, r];
  }));
}

// onChange(delay): typing minutes waits a moment; switches, steppers and menus save sooner.
function wireReminderRows(box, spec, onChange) {
  box.querySelectorAll('.rem-row').forEach((row) => {
    const s = spec.find((x) => x.key === row.dataset.key);
    row.querySelector('.rem-on').addEventListener('change', (e) => {
      row.classList.toggle('off', !e.currentTarget.checked);
      onChange(0);
    });
    row.querySelector('.rem-sound').addEventListener('change', (e) => {
      onChange(0);
      const fade = row.querySelector('.rem-fade').getAttribute('aria-pressed') === 'true';
      play(e.currentTarget.value, s.sound, $('set-volume').value, { fade });
    });
    const min = row.querySelector('.rem-min');
    if (min) {
      min.addEventListener('input', () => onChange(700));
      min.addEventListener('change', () => { min.value = clampLead(min.value); });
      for (const [cls, d] of [['.step-down', -1], ['.step-up', 1]]) {
        row.querySelector(cls).addEventListener('click', () => {
          min.value = clampLead(Number(min.value) + d);
          onChange(450);
        });
      }
    }
    const fade = row.querySelector('.rem-fade');
    fade.addEventListener('click', () => {
      fade.setAttribute('aria-pressed', String(fade.getAttribute('aria-pressed') !== 'true'));
      onChange(0);
    });
    row.querySelector('.rem-play').addEventListener('click', () => {
      play(row.querySelector('.rem-sound').value, s.sound, $('set-volume').value, { fade: fade.getAttribute('aria-pressed') === 'true' });
    });
  });
}

// ---------------------------------------------------------------------------
// Block types (Settings → Block types)
// Your types on the left; the selected one's name and four reminders on the right.
// Edits change state.blockTypes straight away and are saved a moment later.
// ---------------------------------------------------------------------------

let selectedType = DEFAULT_TYPE;
const currentType = () => state.blockTypes.find((t) => t.id === selectedType);
const usedBy = (id) => state.schedule.blocks.filter((b) => b.type === id).length;

function typeSummary(t) {
  const on = Object.values(t.reminders).filter((r) => r.on).length;
  return [t.reminders.prep.on ? `Prep ${t.reminders.prep.lead} min` : '', `${on} of 4 on`].filter(Boolean).join(' · ');
}

function renderTypes({ force = false } = {}) {
  if (!currentType()) selectedType = DEFAULT_TYPE;
  renderTypeList();
  renderTypeDetail({ force });
}

function renderTypeList({ enter = null } = {}) {
  $('type-list').innerHTML = state.blockTypes.map((t) => `
    <li class="type-item${t.id === enter ? ' enter' : ''}" role="option" data-id="${esc(t.id)}" aria-selected="${t.id === selectedType}">
      <span class="dot" aria-hidden="true"></span>
      <span class="type-label">${esc(t.name || 'Untitled')}</span>
      <span class="type-sum">${esc(typeSummary(t))}</span>
    </li>`).join('');
  $('type-list').querySelectorAll('.type-item').forEach((li) => {
    li.addEventListener('click', () => selectType(li.dataset.id));
  });
  $('remove-type').disabled = selectedType === DEFAULT_TYPE;
}

let detailShown = null;
function renderTypeDetail({ force = false, swap = false } = {}) {
  const t = currentType();
  if (!t) return;
  // Rebuild the rows only for another type or new clips, so typing and menus aren't disturbed.
  const sig = JSON.stringify([t.id, state.customSounds]);
  if (sig !== detailShown || force) {
    detailShown = sig;
    $('type-rem-rows').innerHTML = reminderRowsHtml(TYPE_REMINDERS, t.name);
    wireReminderRows($('type-rem-rows'), TYPE_REMINDERS, (delay) => {
      const cur = currentType();
      cur.reminders = readReminderRows($('type-rem-rows'), TYPE_REMINDERS);
      renderTypeList();
      saveTypesSoon(delay);
    });
  }
  if (document.activeElement !== $('type-name')) $('type-name').value = t.name;
  $('type-badge').hidden = t.id !== DEFAULT_TYPE;
  const n = usedBy(t.id);
  $('type-used').textContent = n ? `Used by ${plural(n, 'block')}` : 'Not used by any block yet';
  fillReminderRows($('type-rem-rows'), t.reminders);
  if (swap && !reduceMotion.matches) {
    const d = $('type-detail');
    d.classList.remove('swap');
    void d.offsetWidth; // restart the slide-in
    d.classList.add('swap');
  }
}

function selectType(id) {
  if (id === selectedType) return;
  selectedType = id;
  renderTypeList();
  renderTypeDetail({ swap: true });
}

$('type-name').addEventListener('input', (e) => {
  currentType().name = e.currentTarget.value.trim();
  renderTypeList();
  saveTypesSoon();
});

function typeProblem(types) {
  const seen = new Set();
  for (const t of types) {
    if (!t.name) return { id: t.id, msg: 'Every block type needs a name.' };
    if (seen.has(t.name.toLowerCase())) return { id: t.id, msg: `There are two block types called "${t.name}".` };
    seen.add(t.name.toLowerCase());
  }
  return null;
}

// While a save is waiting, data reloads keep your unsaved edits instead of the stored list.
let typesTimer = null;
function saveTypesSoon(delay = 400) {
  clearTimeout(typesTimer);
  typesTimer = setTimeout(() => { typesTimer = null; saveTypes(); }, delay);
}
async function saveTypes() {
  const problem = typeProblem(state.blockTypes);
  $('type-name').classList.toggle('bad', problem?.id === selectedType);
  $('type-error').textContent = problem ? problem.msg : '';
  if (problem) return false;
  try {
    const saved = await dayflow.saveBlockTypes(state.blockTypes);
    if (!typesTimer) state.blockTypes = saved.blockTypes;
    refreshEditorTypes();
    renderAgenda();
    flashStatus(groupStatus($('type-list')), 'Block types saved');
    return true;
  } catch (e) {
    $('type-error').textContent = cleanError(e);
    return false;
  }
}

$('add-type').addEventListener('click', async () => {
  const names = new Set(state.blockTypes.map((t) => t.name.toLowerCase()));
  let name = 'New type';
  for (let n = 2; names.has(name.toLowerCase()); n++) name = `New type ${n}`;
  const id = crypto.randomUUID();
  const reminders = Object.fromEntries(TYPE_REMINDERS.map(({ key, lead, sound }) => (
    [key, { on: key !== 'prep', sound, ...(lead ? { lead: 5 } : {}) }])));
  state.blockTypes = [...state.blockTypes, { id, name, reminders }];
  selectedType = id;
  renderTypeList({ enter: id });
  renderTypeDetail({ swap: true });
  if (await saveTypes()) {
    $('type-name').focus();
    $('type-name').select();
  }
});

$('remove-type').addEventListener('click', () => deleteType(selectedType));

async function deleteType(id) {
  if (id === DEFAULT_TYPE) return;
  const t = state.blockTypes.find((x) => x.id === id);
  const used = usedBy(id) + state.draft.filter((b) => b.type === id && !state.schedule.blocks.some((s) => s.id === b.id)).length;
  const target = typeName(DEFAULT_TYPE);
  if (used && !window.confirm(`${plural(used, 'block')} ${used === 1 ? 'uses' : 'use'} ${t.name}. ${used === 1 ? 'It' : 'They'}'ll move to ${target}.`)) return;
  const index = state.blockTypes.indexOf(t);
  state.blockTypes = state.blockTypes.filter((x) => x !== t);
  state.draft.forEach((b) => { if (b.type === id) b.type = DEFAULT_TYPE; });
  selectedType = (state.blockTypes[index] || state.blockTypes[index - 1] || {}).id || DEFAULT_TYPE;
  renderTypeList();
  renderTypeDetail({ swap: true });
  if (!(await saveTypes())) return;
  if (!state.dirty) await loadAll();
}

// ---------------------------------------------------------------------------
// Meetings (Settings)
// ---------------------------------------------------------------------------

let meetingsShown = null;
function renderMeetings() {
  const sig = JSON.stringify(state.customSounds);
  if (sig !== meetingsShown) {
    meetingsShown = sig;
    $('meeting-rows').innerHTML = reminderRowsHtml(MEETING_REMINDERS, 'Meetings');
    wireReminderRows($('meeting-rows'), MEETING_REMINDERS, (delay) => saveSettingsSoon($('meeting-rows'), delay));
  }
  if (state.settings.meetings) fillReminderRows($('meeting-rows'), state.settings.meetings);
}

// ---------------------------------------------------------------------------
// Export and import
// ---------------------------------------------------------------------------

const atToday = (hhmm) => { const d = new Date(); d.setHours(...hhmm.split(':').map(Number), 0, 0); return d; };

$('export-schedule').addEventListener('click', async () => {
  try {
    const file = await dayflow.exportSchedule();
    if (!file) return;
    setSchedStatus(state.dirty
      ? `Exported your saved schedule to ${file}. Unsaved changes weren't included.`
      : `Exported to ${file}`);
  } catch (e) {
    setSchedStatus(cleanError(e), true);
  }
});

$('show-backups').addEventListener('click', () => dayflow.showBackups());

let pendingImport = null;
$('import-schedule').addEventListener('click', async () => {
  let preview;
  try { preview = await dayflow.previewImport(); } catch (e) { setSchedStatus(cleanError(e), true); return; }
  if (!preview) return;

  // Clips the file's settings use must play here, or those reminders fall back to the default.
  const rejected = [];
  const problems = [...preview.problems];
  for (const c of preview.clips) {
    try { await checkClipPlays(c.name, c.data); } catch (e) {
      rejected.push(c.id);
      problems.push(`${cleanError(e)} ${c.slots} will use the default sound.`);
    }
  }
  pendingImport = { token: preview.token, rejected };

  $('imp-summary').textContent = `This will replace your ${plural(preview.current, 'block')} with ${plural(preview.blocks.length, 'block')} from ${preview.fileName}.`;
  $('imp-blocks').innerHTML = preview.blocks.map((b) => `
    <li><span class="time">${fmtRange(atToday(b.start), atToday(b.end))}</span>
      <span>${esc(b.title)}${b.typeName ? ` <span class="muted">· ${esc(b.typeName)}</span>` : ''}</span>
      <span class="muted">${b.days.map((d) => DAY_NAMES[d].slice(0, 3)).join(' ') || 'No days'}</span></li>`).join('');
  $('imp-types').textContent = preview.isBackup
    ? 'With settings applied, your block types go back to how they were in this backup.'
    : preview.newTypes.length
      ? `Adds ${plural(preview.newTypes.length, 'new block type')}: ${preview.newTypes.join(', ')}.`
      : '';
  $('imp-settings-row').hidden = !preview.hasSettings;
  $('imp-settings').checked = preview.hasSettings;
  $('imp-problems').innerHTML = problems.map((p) => `<li>${esc(p)}</li>`).join('');
  $('imp-problems').hidden = !problems.length || !preview.hasSettings;
  $('imp-unsaved').hidden = !state.dirty;
  $('imp-error').textContent = '';
  $('import-dialog').showModal();
});

$('imp-settings').addEventListener('change', () => {
  $('imp-problems').hidden = !$('imp-settings').checked || !$('imp-problems').children.length;
});
$('imp-cancel').addEventListener('click', () => $('import-dialog').close());
$('import-dialog').addEventListener('close', () => { pendingImport = null; });

$('imp-apply').addEventListener('click', async () => {
  if (!pendingImport) return;
  try {
    const result = await dayflow.applyImport(pendingImport.token, {
      applySettings: $('imp-settings').checked,
      rejectClips: pendingImport.rejected,
    });
    $('import-dialog').close();
    setDirty(false);
    await loadAll();
    setSchedStatus(`Imported ${plural(result.blocks, 'block')}. Your previous setup was saved as ${result.backup}.`);
  } catch (e) {
    $('imp-error').textContent = cleanError(e);
  }
});

// ---------------------------------------------------------------------------
// Window modes
// ---------------------------------------------------------------------------

document.querySelectorAll('[data-mode]').forEach((btn) => {
  btn.addEventListener('click', () => dayflow.setMode(btn.dataset.mode));
});

loadAll();
