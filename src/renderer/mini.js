/* global dayflow */
// The mini timer: the current block counting down, how far through it you are, and what's next.
const $ = (id) => document.getElementById(id);
const fmt = (d) => d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
const pad = (n) => String(n).padStart(2, '0');
document.documentElement.dataset.platform = dayflow.platform;

// Each block carries warnMin and prepMin from its type (0 when that reminder is off).
let today = { blocks: [], meetings: [] };

async function load() {
  const t = await dayflow.getToday();
  today = {
    // Skipped ones aren't part of today.
    blocks: t.blocks.filter((b) => !b.skipped).map((b) => ({ ...b, start: new Date(b.start), end: new Date(b.end) })),
    meetings: t.meetings.map((m) => ({ ...m, start: new Date(m.start), end: new Date(m.end) })),
  };
  render();
}
dayflow.onDataChanged(load);

// m:ss under an hour, h:mm (with a small "h") above it
function clock(ms) {
  const total = Math.max(0, Math.ceil(ms / 1000));
  if (total >= 3600) return { text: `${Math.floor(total / 3600)}:${pad(Math.floor((total % 3600) / 60))}`, hours: true };
  return { text: `${Math.floor(total / 60)}:${pad(total % 60)}`, hours: false };
}

// Characters that changed roll up into place, as in the main window.
function rollText(el, { text, hours }) {
  const key = `${text}|${hours}`;
  const old = el.dataset.text || '';
  if (old === key) return;
  el.dataset.text = key;
  const oldText = old.split('|')[0];
  if (oldText.length !== text.length || old.split('|')[1] !== String(hours)) {
    el.innerHTML = [...text].map((c) => `<span>${c}</span>`).join('') + (hours ? '<small>h</small>' : '');
    return;
  }
  [...text].forEach((c, i) => {
    if (c === oldText[i]) return;
    const span = document.createElement('span');
    span.className = 'in';
    span.textContent = c;
    el.children[i].replaceWith(span);
  });
}

function render() {
  const now = new Date();
  const { blocks, meetings } = today;
  const current = blocks.find((b) => now >= b.start && now < b.end);
  const next = blocks.find((b) => b.start >= (current ? current.end : now) && b.start > now);
  const meeting = meetings.find((m) => m.start > now);

  let title;
  let count = { text: '', hours: false };
  let progress = null;
  let ending = false;
  let getReady = false;
  if (current) {
    title = current.title;
    count = clock(current.end - now);
    progress = (now - current.start) / (current.end - current.start);
    ending = current.warnMin > 0 && current.end - now <= current.warnMin * 60000;
  } else if (next) {
    getReady = next.prepMin > 0 && next.start - now <= next.prepMin * 60000;
    title = getReady ? 'Get ready' : 'Free';
    count = clock(next.start - now);
    const prev = [...blocks].reverse().find((b) => b.end <= now);
    if (prev) progress = (now - prev.end) / (next.start - prev.end);
  } else {
    title = blocks.length ? 'Done for today' : 'Nothing planned today';
  }

  // A meeting wins the "next" spot when it comes before the next block, unless it's time
  // to get ready for that block.
  let nextText = '';
  let nextTip = '';
  if (!getReady && meeting && (!next || meeting.start < next.start)) {
    const mins = Math.ceil((meeting.start - now) / 60000);
    nextText = mins <= 60 ? `Meeting in ${mins} min` : `Meeting at ${fmt(meeting.start)}`;
    nextTip = meeting.title;
  } else if (next) {
    nextText = `Next: ${next.title}`;
    nextTip = `${next.title} at ${fmt(next.start)}`;
  }

  const pill = $('pill');
  if (ending && !pill.classList.contains('ending')) {
    pill.classList.remove('pulse');
    void pill.offsetWidth;
    pill.classList.add('pulse');
  }
  pill.classList.toggle('ending', ending);
  pill.classList.toggle('ready', getReady);
  pill.classList.toggle('idle', !current && !next);
  pill.title = current ? `${current.title} until ${fmt(current.end)}` : '';
  $('m-title').textContent = title;
  rollText($('m-count'), count);
  $('m-bar').hidden = progress === null;
  if (progress !== null) $('m-bar').firstElementChild.style.transform = `scaleX(${Math.min(1, Math.max(0, progress))})`;
  $('m-next').textContent = nextText;
  $('m-next').title = nextTip;
  $('m-sub').hidden = progress === null && !nextText;
}
setInterval(render, 1000);

// The main process moves the window while the button is held.
const pill = $('pill');
pill.addEventListener('pointerdown', (e) => {
  if (e.button !== 0) return;
  pill.setPointerCapture(e.pointerId);
  dayflow.miniDragStart();
});
pill.addEventListener('pointerup', () => dayflow.miniDragEnd());
pill.addEventListener('lostpointercapture', () => dayflow.miniDragEnd());
pill.addEventListener('dblclick', () => dayflow.showWindow());
pill.addEventListener('pointerenter', () => dayflow.miniHover(true));
pill.addEventListener('pointerleave', () => dayflow.miniHover(false));
pill.addEventListener('contextmenu', (e) => {
  e.preventDefault();
  dayflow.miniMenu();
});

load();
