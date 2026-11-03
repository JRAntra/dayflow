// DayFlow — main process
// Owns storage, the reminder scheduler, system notifications, the tray icon,
// and the Google Calendar connection. The window is just a view onto this.

const {
  app, BrowserWindow, Tray, Menu, Notification, ipcMain, shell, nativeImage, dialog, globalShortcut, screen,
} = require('electron');
const path = require('path');
const fs = require('fs');
const http = require('http');
const crypto = require('crypto');
const { OAuth2Client } = require('google-auth-library');

// ---------------------------------------------------------------------------
// Storage
// ---------------------------------------------------------------------------

// The app was called "Dayflow" before it became "DayFlow". Keep using that data folder, which
// matters on case-sensitive disks. A --user-data-dir on the command line still wins.
if (!app.commandLine.hasSwitch('user-data-dir')) {
  app.setPath('userData', path.join(app.getPath('appData'), 'Dayflow'));
}
const DATA_DIR = app.getPath('userData');
const FILES = {
  schedule: path.join(DATA_DIR, 'schedule.json'),
  settings: path.join(DATA_DIR, 'settings.json'),
  credentials: path.join(DATA_DIR, 'google-credentials.json'),
  token: path.join(DATA_DIR, 'google-token.json'),
  sounds: path.join(DATA_DIR, 'sounds.json'),
  windowState: path.join(DATA_DIR, 'window-state.json'),
  blockTypes: path.join(DATA_DIR, 'block-types.json'),
};
const SOUNDS_DIR = path.join(DATA_DIR, 'sounds');
const BACKUP_DIR = path.join(DATA_DIR, 'backups');

function readJSON(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
}
function writeJSON(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(data, null, 2));
}

const WEEKDAYS = [1, 2, 3, 4, 5];
const DEFAULT_SCHEDULE = {
  blocks: [
    { id: 'b1', title: 'Plan the day', start: '09:00', end: '09:20', days: WEEKDAYS },
    { id: 'b2', title: 'Deep work', start: '09:20', end: '11:30', days: WEEKDAYS },
    { id: 'b3', title: 'Email and messages', start: '11:30', end: '12:00', days: WEEKDAYS },
    { id: 'b4', title: 'Lunch', start: '12:00', end: '13:00', days: WEEKDAYS },
    { id: 'b5', title: 'Focus block', start: '13:00', end: '15:00', days: WEEKDAYS },
    { id: 'b6', title: 'Walk and stretch', start: '15:00', end: '15:15', days: WEEKDAYS },
    { id: 'b7', title: 'Admin and follow-ups', start: '15:15', end: '17:00', days: WEEKDAYS },
    { id: 'b8', title: 'Shut down for the day', start: '17:00', end: '17:15', days: WEEKDAYS },
  ],
};
// ---------------------------------------------------------------------------
// Sounds
// ---------------------------------------------------------------------------

// The built-in sounds: short clips from Mixkit's free sound effects (mixkit.co), shipped in
// assets/sounds/<id>.mp3. Free to use without credit; see the README before redistributing them.
const BUILTIN = [
  ['notification-bell', 'Soft bell'],
  ['alert-bells-echo', 'Echo bells'],
  ['fairy-bell-bless', 'Fairy bell'],
  ['christmas-magic-bell', 'Magic bell'],
  ['bells-of-mystery', 'Mystery bells'],
  ['magic-glitter', 'Magic glitter'],
  ['fantasy-bells', 'Fantasy bells'],
  ['flute-notification', 'Flute'],
  ['elevator-announcement-bells', 'Elevator bells'],
  ['elegant-door-announcement', 'Elegant chime'],
  ['airport-announcement-ding', 'Airport ding'],
  ['melodic-classic-door-bell', 'Classic door bell'],
  ['doorbell-tone', 'Doorbell tone'],
  ['clock-bells-hour-signal', 'Hour bells'],
  ['class-bell', 'Class bell'], // added from your own file, not from Mixkit
  ['sleigh-bells', 'Sleigh bells'],
  ['classic-alarm', 'Classic alarm'],
  ['rooster-crowing', 'Rooster crowing'],
].map(([id, name]) => ({ id, name }));
const BUILTIN_SOUNDS = BUILTIN.map((b) => b.id);
const BUILTIN_DIR = path.join(__dirname, '..', 'assets', 'sounds');
const CLIP_TYPES = ['mp3', 'wav', 'm4a', 'aac', 'ogg'];
const MAX_CLIP_BYTES = 5 * 1024 * 1024;

// Your own clips: [{ id, name, ext }], with the audio copied to sounds/<id>.<ext>.
// The id is a hash of the audio, so the same clip is only ever stored once.
let customSounds = readJSON(FILES.sounds, []);

const clipPath = (c) => path.join(SOUNDS_DIR, `${c.id}.${c.ext}`);
const clipHash = (buf) => crypto.createHash('sha256').update(buf).digest('hex').slice(0, 16);
const customId = (id) => `custom:${id}`;

function validSound(id) {
  if (BUILTIN_SOUNDS.includes(id)) return true;
  return typeof id === 'string' && customSounds.some((c) => customId(c.id) === id);
}

function checkClip(name, ext, buf) {
  const type = String(ext || '').toLowerCase();
  if (!CLIP_TYPES.includes(type)) throw new Error(`"${name}" isn't an mp3, wav, m4a, aac or ogg file.`);
  if (!buf.length) throw new Error(`"${name}" is empty.`);
  if (buf.length > MAX_CLIP_BYTES) throw new Error(`"${name}" is larger than 5 MB.`);
  return type;
}

// Copies a clip into the sounds folder. A different clip whose name is taken becomes "Name (2)".
function installClip(name, ext, buf) {
  const type = checkClip(name, ext, buf);
  const id = clipHash(buf);
  const existing = customSounds.find((c) => c.id === id);
  if (existing) return existing;
  const base = String(name).trim().slice(0, 60) || 'Sound clip';
  let label = base;
  for (let n = 2; customSounds.some((c) => c.name === label); n++) label = `${base} (${n})`;
  const clip = { id, name: label, ext: type };
  fs.mkdirSync(SOUNDS_DIR, { recursive: true });
  fs.writeFileSync(clipPath(clip), buf);
  customSounds.push(clip);
  writeJSON(FILES.sounds, customSounds);
  return clip;
}

// Deletes a clip; any reminder that used it goes back to that reminder's starting sound.
// Returns the names of the reminders that changed.
function removeClip(id) {
  const clip = customSounds.find((c) => c.id === id);
  if (!clip) return [];
  try { fs.unlinkSync(clipPath(clip)); } catch {}
  customSounds = customSounds.filter((c) => c !== clip);
  writeJSON(FILES.sounds, customSounds);
  const reset = [];
  const resetIn = (reminders, spec, owner) => {
    for (const [k, s] of Object.entries(spec)) {
      if (reminders[k].sound !== customId(id)) continue;
      reminders[k].sound = s.sound;
      reset.push(`${owner} · ${s.label}`);
    }
  };
  for (const t of blockTypes) resetIn(t.reminders, REMINDERS, t.name);
  resetIn(settings.meetings, MEETING_REMINDERS, 'Meetings');
  if (reset.length) {
    writeJSON(FILES.blockTypes, blockTypes);
    writeJSON(FILES.settings, settings);
  }
  return reset;
}

// ---------------------------------------------------------------------------
// Reminders
// Each block type has four reminders and Meetings has two. Every reminder can be switched
// off and has its own sound; the ones that come early also say how many minutes ahead.
// ---------------------------------------------------------------------------

const clamp = (v, lo, hi, d) => (Number.isFinite(Number(v)) ? Math.min(hi, Math.max(lo, Math.round(Number(v)))) : d);
const flag = (v, d) => (v === undefined ? d : !!v);

const DEFAULT_LEAD = 5; // minutes
const REMINDERS = {
  prep: { label: 'Start preparation', on: false, lead: true, sound: 'fairy-bell-bless' },
  start: { label: 'Start', on: true, sound: 'elevator-announcement-bells' },
  warn: { label: 'Heads-up', on: true, lead: true, sound: 'notification-bell' },
  end: { label: "Time's up", on: true, sound: 'clock-bells-hour-signal' },
};
const MEETING_REMINDERS = {
  before: { label: 'Before it starts', on: true, lead: true, sound: 'airport-announcement-ding' },
  start: { label: 'Starting now', on: true, sound: 'elegant-door-announcement' },
};

// Cleans one set of reminders; anything missing or unusable takes the starting value.
function sanitizeReminders(next, spec, isSound = validSound) {
  const out = {};
  for (const [key, s] of Object.entries(spec)) {
    const r = next?.[key] || {};
    // fade: the sound starts quiet and grows to your volume, so it doesn't startle you
    out[key] = { on: flag(r.on, s.on), sound: isSound(r.sound) ? r.sound : s.sound, fade: flag(r.fade, false) };
    if (s.lead) out[key].lead = clamp(r.lead, 1, 60, DEFAULT_LEAD);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

const DEFAULT_SETTINGS = {
  sound: true,           // false mutes every reminder sound
  volume: 80,            // 0–100
  meetings: sanitizeReminders({}, MEETING_REMINDERS),
  launchAtLogin: false,
  shortcut: true,        // Control+Alt+D cycles the window modes
  cards: true,           // show a reminder card as well as the macOS notification
  cardAutoClose: 0,      // minutes before a card closes itself; 0 = stays until you act
};

function sanitizeSettings(next, prev) {
  return {
    sound: flag(next.sound, prev.sound),
    volume: clamp(next.volume, 0, 100, prev.volume),
    meetings: sanitizeReminders(next.meetings || prev.meetings, MEETING_REMINDERS),
    launchAtLogin: flag(next.launchAtLogin, prev.launchAtLogin),
    shortcut: flag(next.shortcut, prev.shortcut),
    cards: flag(next.cards, prev.cards),
    cardAutoClose: [0, 1, 5].includes(Number(next.cardAutoClose)) ? Number(next.cardAutoClose) : prev.cardAutoClose,
  };
}

// ---------------------------------------------------------------------------
// Block types
// Every block has a type, and its type decides its reminders. Default can be renamed and
// changed like any other type, but not deleted: blocks of a deleted type move to it.
// ---------------------------------------------------------------------------

const DEFAULT_TYPE = 'default';
const STARTER_NAMES = ['Focus', 'Break', 'Admin', 'Meal'];
const newType = (id, name) => ({ id, name, reminders: sanitizeReminders({}, REMINDERS) });
const starterTypes = () => [newType(DEFAULT_TYPE, 'Default'), ...STARTER_NAMES.map((n) => newType(n.toLowerCase(), n))];

// Names must be unique (ignoring case). Default always comes first.
function sanitizeTypes(list) {
  if (!Array.isArray(list)) throw new Error('Block types must be a list.');
  if (!list.some((t) => t?.id === DEFAULT_TYPE)) throw new Error("The Default type can't be deleted.");
  const seen = new Set();
  return list.map((t) => {
    const name = String(t?.name || '').trim().slice(0, 40);
    if (!name) throw new Error('Every block type needs a name.');
    if (seen.has(name.toLowerCase())) throw new Error(`There are two block types called "${name}".`);
    seen.add(name.toLowerCase());
    return { id: String(t.id || crypto.randomUUID()), name, reminders: sanitizeReminders(t.reminders, REMINDERS) };
  }).sort((a, b) => (b.id === DEFAULT_TYPE) - (a.id === DEFAULT_TYPE));
}

const typeOf = (id) => blockTypes.find((t) => t.id === id) || blockTypes.find((t) => t.id === DEFAULT_TYPE);

// Earlier versions set one sound per kind of reminder, and types could say "same as default".
// This turns that setup into types with four reminders without changing anything you hear.
// Sounds are passed through as they are; the caller checks them.
function upgradeV1({ settings: s = {}, blockTypes: oldTypes, blocks = [] }) {
  const pick = (v, d) => (typeof v === 'string' && v && v !== 'default' ? v : d);
  const old = s.sounds || {};
  const g = {
    start: pick(old.transition, REMINDERS.start.sound),
    warn: pick(old.warning, REMINDERS.warn.sound),
    end: pick(old.end, REMINDERS.end.sound),
    meeting: pick(old.meeting, MEETING_REMINDERS.start.sound),
  };
  const warn = clamp(s.warnBeforeEndMin, 0, 60, DEFAULT_LEAD); // 0 used to mean "no heads-up"
  const reminders = (sounds = {}) => ({
    prep: { on: false, lead: DEFAULT_LEAD, sound: REMINDERS.prep.sound },
    start: { on: true, sound: pick(sounds.transition, g.start) },
    warn: { on: warn > 0, lead: warn || DEFAULT_LEAD, sound: pick(sounds.warning, g.warn) },
    end: { on: true, sound: pick(sounds.end, g.end) },
  });
  const list = (Array.isArray(oldTypes) ? oldTypes : STARTER_NAMES.map((n) => ({ id: n.toLowerCase(), name: n })))
    .filter((t) => t && String(t.name || '').trim());
  // A type you had already called "Default" becomes the Default type.
  const named = list.find((t) => String(t.name).trim().toLowerCase() === 'default');
  const types = [{ id: DEFAULT_TYPE, name: named ? String(named.name).trim() : 'Default', isDefault: true, reminders: reminders(named?.sounds) }];
  const ids = new Map();
  for (const t of list) {
    if (t === named) { ids.set(String(t.id), DEFAULT_TYPE); continue; }
    const id = String(t.id) === DEFAULT_TYPE ? crypto.randomUUID() : String(t.id);
    ids.set(String(t.id), id);
    types.push({ id, name: String(t.name).trim(), reminders: reminders(t.sounds) });
  }
  const lead = clamp(s.meetingLeadMin, 0, 60, DEFAULT_LEAD);
  return {
    types,
    blocks: blocks.map((b) => ({ ...b, type: ids.get(String(b.type)) || DEFAULT_TYPE })),
    meetings: {
      before: { on: lead > 0, lead: lead || DEFAULT_LEAD, sound: g.meeting },
      start: { on: true, sound: g.meeting },
    },
  };
}

let schedule;
let settings;
let blockTypes;

// Loads your data, upgrading it first if it was saved before reminders lived on block types.
// Called once the app is ready, so the upgrade can save a backup.
function loadData() {
  const raw = {
    schedule: readJSON(FILES.schedule, null),
    settings: readJSON(FILES.settings, {}),
    blockTypes: readJSON(FILES.blockTypes, null),
  };
  const oldSettings = 'sounds' in raw.settings || 'warnBeforeEndMin' in raw.settings || 'meetingLeadMin' in raw.settings;
  const oldTypes = raw.blockTypes ? raw.blockTypes.some((t) => !t?.reminders) : !!raw.schedule;
  if (!oldSettings && !oldTypes) {
    schedule = raw.schedule || DEFAULT_SCHEDULE;
    settings = sanitizeSettings(raw.settings, DEFAULT_SETTINGS);
    try { blockTypes = sanitizeTypes(raw.blockTypes || starterTypes()); } catch { blockTypes = starterTypes(); }
    schedule = { blocks: sanitizeBlocks(schedule.blocks || []) };
    return;
  }

  // Keep what was there, in the old export format, so importing it puts things back.
  const used = new Set([...Object.values(raw.settings.sounds || {}), ...(raw.blockTypes || []).flatMap((t) => Object.values(t?.sounds || {}))]);
  try {
    writeBackup({
      dayflowExport: 1,
      exportedAt: new Date().toISOString(),
      backup: true,
      schedule: raw.schedule || { blocks: [] },
      ...(raw.blockTypes ? { blockTypes: raw.blockTypes } : {}),
      settings: raw.settings,
      clips: clipsFor(used),
    });
  } catch (e) {
    console.error('Could not back up before upgrading:', e.message);
  }

  const up = upgradeV1({ settings: raw.settings, blockTypes: raw.blockTypes, blocks: raw.schedule?.blocks || [] });
  blockTypes = sanitizeTypes(up.types);
  settings = sanitizeSettings({ ...raw.settings, meetings: up.meetings }, DEFAULT_SETTINGS);
  schedule = { blocks: sanitizeBlocks(up.blocks) };
  writeJSON(FILES.blockTypes, blockTypes);
  writeJSON(FILES.settings, settings);
  writeJSON(FILES.schedule, schedule);
}

// ---------------------------------------------------------------------------
// Time helpers
// ---------------------------------------------------------------------------

const TIME_RE = /^([01]\d|2[0-3]):([0-5]\d)$/;
const toMin = (hhmm) => { const [h, m] = hhmm.split(':').map(Number); return h * 60 + m; };
function at(base, hhmm) {
  const d = new Date(base);
  const [h, m] = hhmm.split(':').map(Number);
  d.setHours(h, m, 0, 0);
  return d;
}
const dayKey = (d) => `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
const fmt = (d) => d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });

function blocksFor(date) {
  const dow = date.getDay();
  return (schedule.blocks || [])
    .filter((b) => Array.isArray(b.days) && b.days.includes(dow) && toMin(b.end) > toMin(b.start))
    .map((b) => ({ id: b.id, title: b.title, type: typeOf(b.type).id, start: at(date, b.start), end: at(date, b.end) }))
    .sort((a, b) => a.start - b.start);
}

// ---------------------------------------------------------------------------
// Google Calendar
// ---------------------------------------------------------------------------

const SCOPES = ['https://www.googleapis.com/auth/calendar.readonly'];
let meetings = [];          // today's timed events
let google = { lastSync: null, error: null };

function loadCredentials() {
  const raw = readJSON(FILES.credentials, null);
  const c = raw && (raw.installed || raw.web);
  return c && c.client_id ? { clientId: c.client_id, clientSecret: c.client_secret } : null;
}

function makeClient(redirectUri) {
  const creds = loadCredentials();
  if (!creds) return null;
  const client = new OAuth2Client({ ...creds, redirectUri });
  // Persist refreshed access tokens so we stay signed in across restarts.
  client.on('tokens', (tokens) => {
    writeJSON(FILES.token, { ...readJSON(FILES.token, {}), ...tokens });
  });
  return client;
}

function authedClient() {
  const token = readJSON(FILES.token, null);
  if (!token) return null;
  const client = makeClient();
  if (!client) return null;
  client.setCredentials(token);
  return client;
}

function googleStatus() {
  return {
    hasCredentials: !!loadCredentials(),
    connected: !!readJSON(FILES.token, null),
    lastSync: google.lastSync,
    error: google.error,
  };
}

// Desktop OAuth "loopback" flow: open the browser, catch the redirect on 127.0.0.1.
function connectGoogle() {
  if (!loadCredentials()) {
    return Promise.reject(new Error('Import your Google OAuth client file first.'));
  }
  return new Promise((resolve, reject) => {
    const state = crypto.randomBytes(16).toString('hex');
    let client;
    let codeVerifier;
    let settled = false;
    const finish = (err) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      server.close();
      err ? reject(err) : resolve();
    };

    const server = http.createServer(async (req, res) => {
      const url = new URL(req.url, 'http://127.0.0.1');
      const code = url.searchParams.get('code');
      const error = url.searchParams.get('error');
      if (!code && !error) { res.writeHead(404); res.end(); return; }

      const ok = code && url.searchParams.get('state') === state;
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(`<!doctype html><meta charset="utf-8"><title>DayFlow</title>
        <body style="font-family:system-ui;padding:48px;max-width:520px">
        <h2>${ok ? 'DayFlow is connected to Google Calendar.' : 'Google sign-in did not finish.'}</h2>
        <p>${ok ? 'You can close this tab and go back to DayFlow.' : 'Go back to DayFlow and choose Connect again.'}</p></body>`);

      if (!ok) return finish(new Error(error ? `Google returned: ${error}` : 'Sign-in state did not match.'));
      try {
        const { tokens } = await client.getToken({ code, codeVerifier });
        writeJSON(FILES.token, tokens);
        finish();
      } catch (e) {
        finish(e);
      }
    });

    const timer = setTimeout(() => finish(new Error('Sign-in timed out after 5 minutes.')), 5 * 60 * 1000);

    server.listen(0, '127.0.0.1', async () => {
      try {
        const { port } = server.address();
        client = makeClient(`http://127.0.0.1:${port}`);
        const pkce = await client.generateCodeVerifierAsync();
        codeVerifier = pkce.codeVerifier;
        const authUrl = client.generateAuthUrl({
          access_type: 'offline',
          prompt: 'consent',
          scope: SCOPES,
          state,
          code_challenge_method: 'S256',
          code_challenge: pkce.codeChallenge,
        });
        shell.openExternal(authUrl);
      } catch (e) {
        finish(e);
      }
    });
  });
}

function meetLink(e) {
  if (e.hangoutLink) return e.hangoutLink;
  const video = e.conferenceData?.entryPoints?.find((p) => p.entryPointType === 'video');
  return video?.uri || null;
}
const declined = (e) => (e.attendees || []).some((a) => a.self && a.responseStatus === 'declined');

async function refreshMeetings() {
  const client = authedClient();
  if (!client) { meetings = []; return; }
  const start = new Date(); start.setHours(0, 0, 0, 0);
  const end = new Date(start); end.setDate(end.getDate() + 1);
  try {
    const res = await client.request({
      url: 'https://www.googleapis.com/calendar/v3/calendars/primary/events',
      params: {
        timeMin: start.toISOString(),
        timeMax: end.toISOString(),
        singleEvents: true,
        orderBy: 'startTime',
        maxResults: 100,
      },
    });
    meetings = (res.data.items || [])
      .filter((e) => e.start?.dateTime && e.status !== 'cancelled' && !declined(e))
      .map((e) => ({
        id: e.id,
        title: e.summary || '(No title)',
        start: e.start.dateTime,
        end: e.end?.dateTime || e.start.dateTime,
        url: meetLink(e),
        htmlLink: e.htmlLink || null,
      }));
    google = { lastSync: new Date().toISOString(), error: null };
  } catch (e) {
    const msg = String(e?.response?.data?.error || e.message || e);
    if (msg.includes('invalid_grant')) {
      try { fs.unlinkSync(FILES.token); } catch {}
      meetings = [];
      google = { ...google, error: 'Google access has expired. Choose Connect to sign in again.' };
    } else {
      google = { ...google, error: `Could not reach Google Calendar: ${msg}` };
    }
  }
  send('data-changed');
}

// ---------------------------------------------------------------------------
// Reminder scheduler
// ---------------------------------------------------------------------------

const FIRE_WINDOW_MS = 90 * 1000; // fire if we're within 90s after the moment (covers sleep/wake jitter)
const MIN_MS = 60 * 1000;
const fired = new Set();
let currentDay = dayKey(new Date());

function buildEvents(now) {
  const events = [];
  const day = dayKey(now);
  const midnight = new Date(now);
  midnight.setHours(0, 0, 0, 0);
  const blocks = blocksFor(now);

  for (const b of blocks) {
    const r = typeOf(b.type).reminders;
    const prev = blocks.find((p) => p !== b && p.end.getTime() === b.start.getTime());
    const next = blocks.find((n) => n !== b && n.start >= b.end);
    const key = (role) => `${day}|block|${b.id}|${role}`;

    const prepAt = new Date(b.start - r.prep.lead * MIN_MS);
    if (r.prep.on && prepAt >= midnight) {
      events.push({
        key: key('prep'), at: prepAt, role: 'prep', block: b, sound: r.prep.sound, fade: r.prep.fade,
        title: `In ${r.prep.lead} min: ${b.title}`,
        body: `Get ready. It starts at ${fmt(b.start)}.`,
      });
    }
    if (r.start.on) {
      events.push({
        key: key('start'), at: b.start, role: 'start', block: b, sound: r.start.sound, fade: r.start.fade,
        title: `Now: ${b.title}`,
        body: prev ? `${prev.title} is done. ${b.title} runs until ${fmt(b.end)}.` : `Runs until ${fmt(b.end)}.`,
      });
    }
    if (r.warn.on && b.end - b.start > r.warn.lead * MIN_MS) {
      events.push({
        key: key('warn'), at: new Date(b.end - r.warn.lead * MIN_MS), role: 'warn', block: b, sound: r.warn.sound, fade: r.warn.fade,
        title: `${r.warn.lead} min left: ${b.title}`,
        body: next ? `Next: ${next.title} at ${fmt(next.start)}.` : 'This is your last block today.',
      });
    }
    if (r.end.on) {
      let body = 'That was your last block today.';
      if (next) body = next.start.getTime() === b.end.getTime() ? `${next.title} starts now.` : `Free until ${next.title} at ${fmt(next.start)}.`;
      events.push({ key: key('end'), at: b.end, role: 'end', block: b, sound: r.end.sound, fade: r.end.fade, title: `Time's up: ${b.title}`, body });
    }
  }

  const merged = mergeSameMoment(events);

  const m = settings.meetings;
  for (const mt of meetings) {
    const start = new Date(mt.start);
    if (dayKey(start) !== day) continue;
    const joinLine = mt.url ? ' Click to join.' : '';
    if (m.before.on) {
      merged.push({
        keys: [`${day}|meet|${mt.id}|${mt.start}|lead`],
        at: new Date(start - m.before.lead * MIN_MS), role: 'meetBefore', sound: m.before.sound, fade: m.before.fade, meeting: mt,
        title: `In ${m.before.lead} min: ${mt.title}`,
        body: `Starts at ${fmt(start)}.${joinLine}`,
      });
    }
    if (m.start.on) {
      merged.push({
        keys: [`${day}|meet|${mt.id}|${mt.start}|start`],
        at: start, role: 'meetStart', sound: m.start.sound, fade: m.start.fade, meeting: mt,
        title: `Starting now: ${mt.title}`,
        body: mt.url ? 'Click to join.' : `Started at ${fmt(start)}.`,
      });
    }
  }
  return merged;
}

// Block reminders that land on the same moment become one notification, and the block that's
// coming up wins: its sound plays. "Now: Email. Deep work is done." at a hand-off, and
// "5 min left: Deep work. Next: Email at 11:30" when a heads-up meets the next block's preparation.
function mergeSameMoment(events) {
  const groups = new Map();
  for (const ev of events) {
    const t = ev.at.getTime();
    groups.set(t, [...(groups.get(t) || []), ev]);
  }
  return [...groups.values()].map((group) => {
    const keys = group.map((e) => e.key);
    const find = (role) => group.find((e) => e.role === role);
    const start = find('start');
    const prep = find('prep');
    const outgoing = find('end') || find('warn');
    if (start) return { ...start, keys };
    if (prep && outgoing) {
      return { ...prep, keys, title: outgoing.title, body: `Next: ${prep.block.title} at ${fmt(prep.block.start)}.` };
    }
    return { ...(prep || outgoing), keys };
  });
}

// The sound to fall back on if a reminder's clip won't play.
const FALLBACK_SOUNDS = {
  ...Object.fromEntries(Object.entries(REMINDERS).map(([k, s]) => [k, s.sound])),
  meetBefore: MEETING_REMINDERS.before.sound,
  meetStart: MEETING_REMINDERS.start.sound,
};

// ---------------------------------------------------------------------------
// Reminder cards
// Each reminder gets a glass card at the top right that stays until you act on it, alongside
// the macOS notification. A card is a small non-activating panel, so it floats over full-screen
// apps and on every Space without taking focus from what you're typing. Up to three show at
// once, newest on top; the bottom one says how many more are waiting.
// ---------------------------------------------------------------------------

const CARD_SIZE = { width: 360, height: 124 };
const CARD_GAP = 10;
const CARD_MARGIN = 14;
const MAX_CARDS = 3;
const SNOOZE_CHOICES = [1, 5, 10]; // minutes
let cards = []; // newest first: { id, win, data, ev, notification, timer }
let cardsPausedUntil = 0;

const cardsPaused = () => Date.now() < cardsPausedUntil;

// The moment a reminder is warning you about, which Snooze must not go past.
function reminderTarget(ev) {
  if (ev.role === 'prep') return ev.block.start;
  if (ev.role === 'warn') return ev.block.end;
  if (ev.role === 'meetBefore') return new Date(ev.meeting.start);
  return null;
}

// "In 4 min: Deep work" after a snooze, rather than the lead time it first had.
function retitle(ev) {
  const target = reminderTarget(ev);
  if (!target) return ev.title;
  const mins = Math.max(1, Math.ceil((target - Date.now()) / MIN_MS));
  const name = ev.block?.title || ev.meeting?.title;
  return ev.role === 'warn' ? `${mins} min left: ${name}` : `In ${mins} min: ${name}`;
}

function cardData(id, ev) {
  const target = reminderTarget(ev);
  const meeting = ev.role === 'meetBefore' || ev.role === 'meetStart';
  const b = ev.block;
  return {
    id,
    role: ev.role,
    label: meeting ? 'Meeting' : b ? typeOf(b.type).name : typeOf(DEFAULT_TYPE).name,
    meeting,
    title: ev.title,
    // Preparation already says when in its title, so its line is just the block's time.
    sub: ev.role === 'prep' ? `Get ready · ${fmt(b.start)} – ${fmt(b.end)}` : ev.body,
    join: meeting && ev.meeting.url ? 'join' : meeting && ev.meeting.htmlLink ? 'calendar' : null,
    snooze: target ? SNOOZE_CHOICES.filter((m) => target - Date.now() > m * MIN_MS + 20 * 1000) : [],
    more: 0,
  };
}

function showCard(ev, notification) {
  if (!settings.cards || cardsPaused()) return null;
  const id = crypto.randomUUID();
  const w = new BrowserWindow({
    ...CARD_SIZE,
    show: false,
    frame: false,
    resizable: false,
    minimizable: false,
    maximizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    acceptFirstMouse: true, // the first click presses the button, even though the card isn't focused
    title: 'DayFlow reminder',
    ...(process.platform === 'darwin'
      ? { type: 'panel', vibrancy: 'popover', visualEffectState: 'active', backgroundColor: '#00000000' }
      : { transparent: true, focusable: false }),
    webPreferences,
  });
  w.setAlwaysOnTop(true, 'pop-up-menu');
  w.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  hardenWebContents(w);
  w.loadFile(path.join(__dirname, 'renderer', 'card.html'), { query: { id } });

  const card = { id, win: w, data: cardData(id, ev), ev, notification };
  cards.unshift(card);
  w.once('ready-to-show', () => {
    if (w.isDestroyed()) return;
    layoutCards(card);
    w.showInactive();
  });
  if (settings.cardAutoClose > 0) card.timer = setTimeout(() => closeCard(id), settings.cardAutoClose * MIN_MS);
  return card;
}

// Stacks the newest three down from the top-right corner. A new card slides in from the right.
function layoutCards(entering = null) {
  const area = screen.getPrimaryDisplay().workArea;
  const x = area.x + area.width - CARD_SIZE.width - CARD_MARGIN;
  cards.forEach((c, i) => {
    if (c.win.isDestroyed()) return;
    if (i >= MAX_CARDS) { c.win.hide(); return; }
    const bounds = { x, y: area.y + CARD_MARGIN + i * (CARD_SIZE.height + CARD_GAP), ...CARD_SIZE };
    if (c === entering) c.win.setBounds({ ...bounds, x: x + 28 });
    else if (!c.win.isVisible()) c.win.showInactive();
    c.win.setBounds(bounds, process.platform === 'darwin'); // macOS animates the move
    const more = i === Math.min(cards.length, MAX_CARDS) - 1 ? cards.length - MAX_CARDS : 0;
    if (c.data.more !== more) {
      c.data.more = Math.max(0, more);
      c.win.webContents.send('card-more', c.data.more);
    }
  });
}

// fromNotification: the card is closing because its notification was clicked, which already
// cleared that notification.
function closeCard(id, { fromNotification = false } = {}) {
  const card = cards.find((c) => c.id === id);
  if (!card) return;
  cards = cards.filter((c) => c !== card);
  clearTimeout(card.timer);
  send('stop-sound');
  if (!fromNotification) {
    try { card.notification?.close(); } catch {}
  }
  if (!card.win.isDestroyed()) {
    card.win.webContents.send('card-leave'); // the card slides out, then goes
    setTimeout(() => { if (!card.win.isDestroyed()) card.win.destroy(); }, 260);
  }
  layoutCards();
}

function cardAction(id, action) {
  const card = cards.find((c) => c.id === id);
  if (!card) return;
  const { ev } = card;
  if (action === 'snooze') {
    Menu.buildFromTemplate(cardData(id, ev).snooze.map((m) => ({
      label: `Snooze ${m} min`,
      click: () => {
        closeCard(id);
        setTimeout(() => {
          const again = { ...ev, title: retitle(ev) };
          showCard(again, null);
          if (settings.sound) send('chime', { sound: again.sound, fade: again.fade, fallback: FALLBACK_SOUNDS[again.role] });
        }, m * MIN_MS);
      },
    }))).popup({ window: card.win });
    return;
  }
  if (action === 'join' && ev.meeting?.url) shell.openExternal(ev.meeting.url);
  if (action === 'calendar' && ev.meeting?.htmlLink) shell.openExternal(ev.meeting.htmlLink);
  if (action === 'open') showWindow();
  closeCard(id);
}

function toggleCardPause() {
  cardsPausedUntil = cardsPaused() ? 0 : Date.now() + 60 * MIN_MS;
  if (cardsPaused()) [...cards].forEach((c) => closeCard(c.id));
  lastTrayLabel = '';
  updateTray(new Date());
}

const liveNotifications = new Set(); // keep references so click handlers aren't garbage-collected

function fire(ev) {
  let n = null;
  if (Notification.isSupported()) {
    n = new Notification({ title: ev.title, body: ev.body, silent: true });
    liveNotifications.add(n);
    n.on('click', () => {
      send('stop-sound');
      if (card) closeCard(card.id, { fromNotification: true });
      const url = ev.meeting ? ev.meeting.url || ev.meeting.htmlLink : null;
      if (url && /^https:\/\//.test(url)) shell.openExternal(url);
      else showWindow();
    });
    n.on('close', () => liveNotifications.delete(n));
    n.show();
    setTimeout(() => liveNotifications.delete(n), 10 * 60 * 1000);
  }
  const card = showCard(ev, n);
  if (settings.sound) send('chime', { sound: ev.sound, fade: ev.fade, fallback: FALLBACK_SOUNDS[ev.role] });
}

function tick() {
  const now = new Date();
  const day = dayKey(now);
  if (day !== currentDay) {
    currentDay = day;
    fired.clear();
    refreshMeetings();
    send('data-changed');
  }
  for (const ev of buildEvents(now)) {
    const delta = now - ev.at;
    if (delta >= 0 && delta < FIRE_WINDOW_MS && !ev.keys.some((k) => fired.has(k))) {
      ev.keys.forEach((k) => fired.add(k));
      fire(ev);
    }
  }
  updateTray(now);
}

// ---------------------------------------------------------------------------
// Window modes and tray
// Full is the main window. Mini is a small floating timer. Backstage is tray only:
// no window and no Dock icon. Reminders run the same in all three.
// ---------------------------------------------------------------------------

const MODES = ['full', 'mini', 'backstage'];
const MODE_LABELS = { full: 'Full window', mini: 'Mini timer', backstage: 'Backstage (tray only)' };
const SHORTCUT = 'Control+Alt+D';
const MINI_SIZE = { width: 268, height: 76 };

let win = null;
let mini = null;
let tray = null;
let quitting = false;
let lastTrayLabel = '';
let winReady = false;
let showWhenReady = false;
let mode = 'full';
let shortcutActive = false;

// lastCompact is where closing the full window takes you: the last Mini or Backstage you used.
const savedWindow = readJSON(FILES.windowState, {});
const windowState = {
  mode: MODES.includes(savedWindow.mode) ? savedWindow.mode : 'full',
  lastCompact: ['mini', 'backstage'].includes(savedWindow.lastCompact) ? savedWindow.lastCompact : 'backstage',
  miniPos: savedWindow.miniPos || null,
  miniOnTop: flag(savedWindow.miniOnTop, true),
};
const saveWindowState = () => writeJSON(FILES.windowState, windowState);

function quit() {
  quitting = true;
  app.quit();
}

function send(channel, payload) {
  for (const w of [win, mini]) {
    if (w && !w.isDestroyed()) w.webContents.send(channel, payload);
  }
}

// Shows the full window. Outside Full mode this is a one-off peek: closing it returns to the mode.
function showWindow() {
  if (!win) return;
  if (!winReady) { showWhenReady = true; return; }
  if (win.isMinimized()) win.restore();
  win.show();
  win.focus();
  if (process.platform === 'darwin') app.focus({ steal: true });
}

async function setMode(next, { persist = true } = {}) {
  if (!MODES.includes(next)) return;
  mode = next;
  if (persist) {
    windowState.mode = next;
    if (next !== 'full') windowState.lastCompact = next;
    saveWindowState();
  }

  if (process.platform === 'darwin') {
    if (next === 'backstage') app.dock.hide();
    else await app.dock.show();
  }
  if (next === 'mini') { placeMini(); mini.showInactive(); } else mini.hide();
  if (next === 'full') showWindow(); else { showWhenReady = false; win.hide(); }

  lastTrayLabel = '';
  updateTray(new Date());
  send('mode-changed', mode);
}

const cycleMode = () => setMode(MODES[(MODES.indexOf(mode) + 1) % MODES.length]);

function applyShortcut() {
  if (shortcutActive) globalShortcut.unregister(SHORTCUT);
  shortcutActive = settings.shortcut ? globalShortcut.register(SHORTCUT, cycleMode) : false;
}

function hardenWebContents(w) {
  w.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  w.webContents.on('will-navigate', (e) => e.preventDefault());
}

const webPreferences = {
  preload: path.join(__dirname, 'preload.js'),
  contextIsolation: true,
  nodeIntegration: false,
  sandbox: true,
};

function createWindow() {
  win = new BrowserWindow({
    width: 1080,
    height: 760,
    minWidth: 780,
    minHeight: 560,
    show: false,
    title: 'DayFlow',
    icon: path.join(__dirname, '..', 'assets', 'icon.png'),
    // macOS: window buttons inset in the sidebar, which shows the system sidebar material.
    // Windows 11: the Mica material. Linux draws a solid window.
    ...(process.platform === 'darwin' ? {
      titleBarStyle: 'hiddenInset',
      trafficLightPosition: { x: 18, y: 18 },
      vibrancy: 'sidebar',
      backgroundColor: '#00000000',
    } : {}),
    ...(process.platform === 'win32' ? { backgroundMaterial: 'mica', backgroundColor: '#00000000' } : {}),
    webPreferences: {
      ...webPreferences,
      backgroundThrottling: false, // the window plays every reminder sound, even while hidden
      autoplayPolicy: 'no-user-gesture-required',
    },
  });
  win.setMenuBarVisibility(false);
  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  win.once('ready-to-show', () => {
    winReady = true;
    if (showWhenReady) showWindow();
  });

  // Closing Full drops you into your usual compact mode; closing a peek just hides it.
  win.on('close', (e) => {
    if (quitting) return;
    e.preventDefault();
    if (mode === 'full') setMode(windowState.lastCompact);
    else win.hide();
  });
  hardenWebContents(win);
}

function createMini() {
  mini = new BrowserWindow({
    ...MINI_SIZE,
    show: false,
    frame: false,
    resizable: false,
    minimizable: false,
    maximizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    title: 'DayFlow timer',
    // HUD glass on macOS; elsewhere a solid pill drawn by the page.
    ...(process.platform === 'darwin' ? { vibrancy: 'hud', visualEffectState: 'active', backgroundColor: '#00000000' } : { transparent: true }),
    webPreferences,
  });
  mini.setOpacity(0.9); // fully solid while the pointer is over it
  mini.loadFile(path.join(__dirname, 'renderer', 'mini.html'));
  mini.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  applyMiniOnTop();
  mini.on('close', (e) => { if (!quitting) e.preventDefault(); }); // leave Mini by switching modes
  hardenWebContents(mini);
}

function applyMiniOnTop() {
  mini.setAlwaysOnTop(windowState.miniOnTop, 'floating');
}

// Puts the mini timer where you left it, or in the top-right corner if that spot is off-screen
// (a monitor was unplugged, say).
function placeMini() {
  const { width, height } = MINI_SIZE;
  const p = windowState.miniPos;
  const inside = (a, x, y) => x >= a.x && x < a.x + a.width && y >= a.y && y < a.y + a.height;
  const display = p && screen.getAllDisplays().find((d) => inside(d.workArea, p.x + width / 2, p.y + height / 2));
  let x;
  let y;
  if (display) {
    const a = display.workArea;
    x = Math.min(Math.max(p.x, a.x), a.x + a.width - width);
    y = Math.min(Math.max(p.y, a.y), a.y + a.height - height);
  } else {
    const a = screen.getPrimaryDisplay().workArea;
    x = a.x + a.width - width - 16;
    y = a.y + 16;
  }
  mini.setPosition(Math.round(x), Math.round(y));
}

// The mini timer has no title bar, so the window drags itself: it follows the cursor
// from mouse-down until mouse-up.
let drag = null;
function startMiniDrag() {
  stopMiniDrag();
  const c = screen.getCursorScreenPoint();
  const [x, y] = mini.getPosition();
  const dx = c.x - x;
  const dy = c.y - y;
  drag = setInterval(() => {
    const p = screen.getCursorScreenPoint();
    mini.setPosition(p.x - dx, p.y - dy);
  }, 16);
}
function stopMiniDrag() {
  if (!drag) return;
  clearInterval(drag);
  drag = null;
  const [x, y] = mini.getPosition();
  windowState.miniPos = { x, y };
  placeMini(); // pulls it back on-screen if it was dropped off the edge
  const [px, py] = mini.getPosition();
  windowState.miniPos = { x: px, y: py };
  saveWindowState();
}

function showMiniMenu() {
  Menu.buildFromTemplate([
    { label: 'Open full window', click: () => setMode('full') },
    { label: 'Switch to Backstage', click: () => setMode('backstage') },
    { type: 'separator' },
    {
      label: 'Always on top',
      type: 'checkbox',
      checked: windowState.miniOnTop,
      click: (item) => { windowState.miniOnTop = item.checked; saveWindowState(); applyMiniOnTop(); },
    },
    { type: 'separator' },
    { label: 'Quit DayFlow', click: quit },
  ]).popup({ window: mini });
}

function createTray() {
  const file = process.platform === 'darwin' ? 'trayTemplate.png' : 'tray.png';
  let img = nativeImage.createFromPath(path.join(__dirname, '..', 'assets', file));
  if (process.platform !== 'darwin') img = img.resize({ width: 16, height: 16 });
  tray = new Tray(img);
  tray.setToolTip('DayFlow');
  tray.on('click', showWindow);
}

// The tray menu doubles as the control panel in Backstage: what's on now, then the modes.
function buildTrayMenu(label) {
  tray.setContextMenu(Menu.buildFromTemplate([
    { label, enabled: false },
    { type: 'separator' },
    ...MODES.map((m) => ({ label: MODE_LABELS[m], type: 'radio', checked: mode === m, click: () => setMode(m) })),
    { type: 'separator' },
    {
      label: cardsPaused() ? `Resume reminder cards (paused until ${fmt(new Date(cardsPausedUntil))})` : 'Pause reminder cards for 1 hour',
      enabled: settings.cards,
      click: toggleCardPause,
    },
    { label: 'Sync calendar now', click: () => refreshMeetings() },
    { type: 'separator' },
    { label: 'Quit DayFlow', click: quit },
  ]));
}

function updateTray(now) {
  if (!tray) return;
  const current = blocksFor(now).find((b) => now >= b.start && now < b.end);
  let label = 'No block right now';
  let short = '';
  if (current) {
    const mins = Math.ceil((current.end - now) / 60000);
    label = `${current.title}, ${mins} min left`;
    short = ` ${mins}m`;
  }
  const key = `${label}|${cardsPaused()}`; // the menu also changes when a card pause ends
  if (key === lastTrayLabel) return;
  lastTrayLabel = key;
  tray.setToolTip(`DayFlow: ${label}`);
  if (process.platform === 'darwin') tray.setTitle(short);
  buildTrayMenu(label);
}

// ---------------------------------------------------------------------------
// Export and import
// An export holds the blocks, their block types, the reminder settings, and the custom clips
// those sounds use.
// Importing replaces the schedule, after backing up the current one in the same format.
// ---------------------------------------------------------------------------

const EXPORT_VERSION = 2;
const MAX_IMPORT_BYTES = 40 * 1024 * 1024;
const MAX_BACKUPS = 10;
let pendingImport = null; // what the import preview showed, waiting for Replace

// The custom clips behind a set of sound ids, embedded for an export file.
function clipsFor(soundIds) {
  return customSounds.filter((c) => soundIds.has(customId(c.id))).flatMap((c) => {
    try {
      return [{ id: c.id, name: c.name, ext: c.ext, data: fs.readFileSync(clipPath(c)).toString('base64') }];
    } catch { return []; }
  });
}

const soundsIn = (reminders) => Object.values(reminders).map((r) => r.sound);

// A backup carries every block type, so importing it puts the type list back exactly;
// an ordinary export carries only the types its blocks use. Default is marked, so it
// matches the Default of whoever imports the file whatever either is called.
function exportPayload({ backup = false } = {}) {
  const usedTypes = new Set(schedule.blocks.map((b) => b.type));
  const types = blockTypes.filter((t) => backup || usedTypes.has(t.id));
  const used = new Set([...types.flatMap((t) => soundsIn(t.reminders)), ...soundsIn(settings.meetings)]);
  return {
    dayflowExport: EXPORT_VERSION,
    exportedAt: new Date().toISOString(),
    ...(backup ? { backup: true } : {}),
    schedule: { blocks: schedule.blocks },
    blockTypes: types.map((t) => (t.id === DEFAULT_TYPE ? { ...t, isDefault: true } : t)),
    settings: { volume: settings.volume, meetings: settings.meetings },
    clips: clipsFor(used),
  };
}

function stamp(d = new Date()) {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

// Saves a payload to backups/, keeping the newest ten.
function writeBackup(payload) {
  fs.mkdirSync(BACKUP_DIR, { recursive: true });
  const now = new Date();
  const file = path.join(BACKUP_DIR, `schedule-${stamp(now)}-${String(now.getMilliseconds()).padStart(3, '0')}.json`);
  writeJSON(file, payload);
  const old = fs.readdirSync(BACKUP_DIR).filter((f) => /^schedule-.*\.json$/.test(f)).sort().slice(0, -MAX_BACKUPS);
  for (const f of old) { try { fs.unlinkSync(path.join(BACKUP_DIR, f)); } catch {} }
  return file;
}
const backupNow = () => writeBackup(exportPayload({ backup: true }));

// Reads and checks an export file. Nothing changes until applyImport.
function readImport(file) {
  const notExport = "That file isn't a DayFlow export.";
  let raw;
  try {
    if (fs.statSync(file).size > MAX_IMPORT_BYTES) throw new Error('That file is too large to be a DayFlow export.');
    raw = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    throw new Error(e.message.startsWith('That file') ? e.message : notExport);
  }
  if (!raw || typeof raw !== 'object' || !Number.isInteger(raw.dayflowExport)) throw new Error(notExport);
  if (raw.dayflowExport > EXPORT_VERSION) {
    throw new Error('That file was made by a newer version of DayFlow. Update DayFlow to import it.');
  }

  // Version 1 files had global sounds; convert them the same way your own data was upgraded.
  let data = raw;
  if (raw.dayflowExport === 1) {
    const up = upgradeV1({ settings: raw.settings || {}, blockTypes: raw.blockTypes || [], blocks: raw.schedule?.blocks || [] });
    data = {
      ...raw,
      schedule: { blocks: up.blocks },
      // Without settings the file has no Default of its own, so its blocks join yours.
      blockTypes: raw.settings ? up.types : up.types.filter((t) => !t.isDefault),
      settings: raw.settings ? { volume: raw.settings.volume, meetings: up.meetings } : null,
    };
  }

  const clips = new Map(); // the file's clip id -> { name, ext, buf }
  const badClips = new Map(); // the file's clip id -> why it can't be used
  for (const c of Array.isArray(data.clips) ? data.clips : []) {
    const name = String(c?.name || 'Sound clip').slice(0, 60);
    try {
      const buf = Buffer.from(String(c.data || ''), 'base64');
      clips.set(String(c.id), { name, ext: checkClip(name, c.ext, buf), buf });
    } catch (e) {
      badClips.set(String(c?.id), e.message);
    }
  }

  // Each sound in the file is checked against its clips. clipSlots records which reminders
  // each usable clip serves, so the window can name them if the clip turns out not to play.
  const problems = [];
  const missing = [];
  const clipSlots = new Map();
  function soundFromFile(v, label, fallback) {
    if (BUILTIN_SOUNDS.includes(v)) return v;
    if (typeof v !== 'string' || !v.startsWith('custom:')) return fallback;
    const fid = v.slice('custom:'.length);
    if (clips.has(fid)) {
      clipSlots.set(fid, [...(clipSlots.get(fid) || []), label]);
      return v;
    }
    if (badClips.has(fid)) problems.push(`${badClips.get(fid)} ${label} will use its starting sound.`);
    else missing.push(label);
    return fallback;
  }
  const remindersFromFile = (src, spec, owner) => sanitizeReminders(
    Object.fromEntries(Object.entries(spec).map(([k, s]) => [k, { ...src?.[k], sound: soundFromFile(src?.[k]?.sound, `${owner} · ${s.label}`, s.sound) }])),
    spec,
    (v) => typeof v === 'string',
  );

  const types = new Map(); // the file's type id -> { name, isDefault, reminders }
  const typeNames = new Set();
  let fileDefault = null;
  for (const t of Array.isArray(data.blockTypes) ? data.blockTypes : []) {
    const name = String(t?.name || '').trim().slice(0, 40);
    if (!name || typeNames.has(name.toLowerCase())) continue;
    typeNames.add(name.toLowerCase());
    const isDefault = t.isDefault === true && !fileDefault;
    if (isDefault) fileDefault = String(t.id);
    types.set(String(t.id), { name, isDefault, reminders: remindersFromFile(t.reminders, REMINDERS, name) });
  }

  let incoming = null;
  if (data.settings && typeof data.settings === 'object') {
    incoming = {
      volume: clamp(data.settings.volume, 0, 100, settings.volume),
      meetings: remindersFromFile(data.settings.meetings, MEETING_REMINDERS, 'Meetings'),
    };
  }
  if (missing.length) problems.push(`A sound clip is missing from the file, so ${missing.join(', ')} will use the starting sound.`);

  let blocks;
  try { blocks = sanitizeBlocks(data.schedule?.blocks, new Set(types.keys()), fileDefault || DEFAULT_TYPE); } catch (e) {
    throw new Error(`The schedule in that file has a problem: ${e.message}`);
  }

  const known = new Set(blockTypes.map((t) => t.name.toLowerCase()));
  const newTypes = [...types.values()].filter((t) => !t.isDefault && !known.has(t.name.toLowerCase())).map((t) => t.name);
  const isBackup = raw.backup === true;

  pendingImport = { token: crypto.randomUUID(), blocks, settings: incoming, types, clips, isBackup };
  return {
    token: pendingImport.token,
    fileName: path.basename(file),
    current: schedule.blocks.length,
    blocks: blocks.map((b) => {
      const t = types.get(b.type);
      return { ...b, typeName: t ? (t.isDefault ? typeOf(DEFAULT_TYPE).name : t.name) : typeOf(DEFAULT_TYPE).name };
    }),
    newTypes,
    isBackup,
    hasSettings: !!incoming || types.size > 0,
    problems,
    // The window decodes these clips to check that they play and are short enough.
    clips: [...clipSlots].map(([id, slots]) => ({ id, name: clips.get(id).name, data: clips.get(id).buf, slots: slots.join(', ') })),
  };
}

function applyImport(token, { applySettings, rejectClips = [] }) {
  const p = pendingImport;
  if (!p || p.token !== token) throw new Error('That import has expired. Choose the file again.');
  let backup;
  try { backup = backupNow(); } catch (e) {
    throw new Error(`DayFlow couldn't back up your current schedule, so nothing was changed. (${e.message})`);
  }

  // Copies in the clips a reminder needs; a clip that won't play gives way to the starting sound.
  const fromFile = (reminders, spec) => Object.fromEntries(Object.entries(reminders).map(([k, r]) => {
    if (!r.sound.startsWith('custom:')) return [k, r];
    const fid = r.sound.slice('custom:'.length);
    const clip = p.clips.get(fid);
    const sound = clip && !rejectClips.includes(fid) ? customId(installClip(clip.name, clip.ext, clip.buf).id) : spec[k].sound;
    return [k, { ...r, sound }];
  }));

  // The file's Default is your Default; other types match by name. A backup with its
  // settings applied replaces the list outright.
  const typeIds = new Map(); // the file's type id -> your type id
  if (p.isBackup && applySettings) {
    const restored = [...p.types].map(([id, t]) => {
      const mine = t.isDefault ? DEFAULT_TYPE : id;
      typeIds.set(id, mine);
      return { id: mine, name: t.name, reminders: fromFile(t.reminders, REMINDERS) };
    });
    if (!restored.some((t) => t.id === DEFAULT_TYPE)) restored.unshift(typeOf(DEFAULT_TYPE));
    blockTypes = restored;
  } else {
    for (const [id, t] of p.types) {
      let mine = t.isDefault
        ? typeOf(DEFAULT_TYPE)
        : blockTypes.find((x) => x.name.toLowerCase() === t.name.toLowerCase());
      if (!mine) {
        mine = newType(crypto.randomUUID(), t.name);
        blockTypes.push(mine);
      }
      if (applySettings) mine.reminders = fromFile(t.reminders, REMINDERS);
      typeIds.set(id, mine.id);
    }
  }
  blockTypes = sanitizeTypes(blockTypes);
  writeJSON(FILES.blockTypes, blockTypes);

  schedule = { blocks: p.blocks.map((b) => ({ ...b, type: typeIds.get(b.type) || DEFAULT_TYPE })) };
  writeJSON(FILES.schedule, schedule);

  if (applySettings && p.settings) {
    settings = sanitizeSettings({ ...settings, volume: p.settings.volume, meetings: fromFile(p.settings.meetings, MEETING_REMINDERS) }, settings);
    writeJSON(FILES.settings, settings);
  }
  pendingImport = null;
  send('data-changed');
  return { backup: path.basename(backup), blocks: schedule.blocks.length };
}

// ---------------------------------------------------------------------------
// IPC
// ---------------------------------------------------------------------------

// Every block has a type: one that isn't in typeIds becomes the fallback (normally Default).
function sanitizeBlocks(blocks, typeIds = new Set(blockTypes.map((t) => t.id)), fallback = DEFAULT_TYPE) {
  if (!Array.isArray(blocks)) throw new Error('Schedule must be a list.');
  return blocks.map((b, i) => {
    const title = String(b.title || '').trim().slice(0, 120);
    if (!title) throw new Error(`Block ${i + 1} needs a name.`);
    if (!TIME_RE.test(b.start) || !TIME_RE.test(b.end)) throw new Error(`"${title}" has an invalid time.`);
    if (toMin(b.end) <= toMin(b.start)) throw new Error(`"${title}" must end after it starts.`);
    const days = [...new Set((b.days || []).map(Number).filter((d) => d >= 0 && d <= 6))].sort();
    const type = typeIds.has(String(b.type)) ? String(b.type) : fallback;
    return { id: String(b.id || crypto.randomUUID()), title, start: b.start, end: b.end, days, type };
  }).sort((a, b) => toMin(a.start) - toMin(b.start));
}

function registerIpc() {
  ipcMain.handle('get-all', () => ({
    schedule,
    settings,
    google: googleStatus(),
    customSounds,
    builtinSounds: BUILTIN,
    blockTypes,
    mode,
    shortcutActive,
    platform: process.platform,
  }));

  ipcMain.handle('get-today', () => ({
    // warnMin and prepMin (0 when that reminder is off) let the mini timer show the heads-up and "Get ready".
    blocks: blocksFor(new Date()).map((b) => {
      const r = typeOf(b.type).reminders;
      return {
        ...b,
        start: b.start.toISOString(),
        end: b.end.toISOString(),
        warnMin: r.warn.on ? r.warn.lead : 0,
        prepMin: r.prep.on ? r.prep.lead : 0,
      };
    }),
    meetings,
  }));

  ipcMain.handle('save-schedule', (_e, blocks) => {
    schedule = { blocks: sanitizeBlocks(blocks) };
    writeJSON(FILES.schedule, schedule);
    send('data-changed');
    return schedule;
  });

  ipcMain.handle('save-settings', (_e, next) => {
    const was = settings;
    settings = sanitizeSettings(next, settings);
    writeJSON(FILES.settings, settings);
    // Only touch these when their switch changed: every save would otherwise re-register them.
    if (settings.launchAtLogin !== was.launchAtLogin) applyLoginItem();
    if (settings.shortcut !== was.shortcut) applyShortcut();
    return { settings, shortcutActive };
  });

  // Sounds ------------------------------------------------------------------

  // id is a built-in sound's id, or custom:<id> for one of your clips.
  ipcMain.handle('get-sound-data', (_e, id) => {
    if (BUILTIN_SOUNDS.includes(id)) return fs.readFileSync(path.join(BUILTIN_DIR, `${id}.mp3`));
    const clip = customSounds.find((c) => customId(c.id) === id);
    if (!clip) throw new Error('That sound clip has been removed.');
    return fs.readFileSync(clipPath(clip));
  });

  // Reads a clip you pick so the window can check that it plays; add-sound then stores it.
  ipcMain.handle('pick-sound-file', async () => {
    const { canceled, filePaths } = await dialog.showOpenDialog(win, {
      title: 'Choose a sound clip',
      filters: [{ name: 'Audio', extensions: CLIP_TYPES }],
      properties: ['openFile'],
    });
    if (canceled || !filePaths[0]) return null;
    const file = filePaths[0];
    const { name, ext } = path.parse(file);
    if (fs.statSync(file).size > MAX_CLIP_BYTES) throw new Error(`"${name}" is larger than 5 MB.`);
    const data = fs.readFileSync(file);
    return { name, ext: checkClip(name, ext.slice(1), data), data };
  });

  ipcMain.handle('add-sound', (_e, { name, ext, data }) => {
    const clip = installClip(name, ext, Buffer.from(data));
    return { clip, customSounds };
  });

  ipcMain.handle('remove-sound', (_e, id) => {
    const reset = removeClip(id);
    return { reset, customSounds, settings, blockTypes };
  });

  // Block types --------------------------------------------------------------

  ipcMain.handle('save-block-types', (_e, list) => {
    blockTypes = sanitizeTypes(list);
    writeJSON(FILES.blockTypes, blockTypes);
    // Blocks whose type was deleted move to Default.
    const ids = new Set(blockTypes.map((t) => t.id));
    if (schedule.blocks.some((b) => !ids.has(b.type))) {
      schedule = { blocks: schedule.blocks.map((b) => ({ ...b, type: ids.has(b.type) ? b.type : DEFAULT_TYPE })) };
      writeJSON(FILES.schedule, schedule);
    }
    send('data-changed');
    return { blockTypes, schedule };
  });

  // Export and import -------------------------------------------------------

  ipcMain.handle('export-schedule', async () => {
    const { canceled, filePath } = await dialog.showSaveDialog(win, {
      title: 'Export schedule',
      defaultPath: path.join(app.getPath('documents'), `DayFlow schedule ${stamp().slice(0, 10)}.json`),
      filters: [{ name: 'DayFlow schedule', extensions: ['json'] }],
    });
    if (canceled || !filePath) return null;
    writeJSON(filePath, exportPayload());
    return path.basename(filePath);
  });

  ipcMain.handle('preview-import', async () => {
    const { canceled, filePaths } = await dialog.showOpenDialog(win, {
      title: 'Import a schedule',
      filters: [{ name: 'DayFlow schedule', extensions: ['json'] }],
      properties: ['openFile'],
    });
    if (canceled || !filePaths[0]) return null;
    return readImport(filePaths[0]);
  });

  ipcMain.handle('apply-import', (_e, token, opts) => applyImport(token, opts || {}));

  ipcMain.handle('show-backups', () => {
    fs.mkdirSync(BACKUP_DIR, { recursive: true });
    return shell.openPath(BACKUP_DIR);
  });

  // Window modes ------------------------------------------------------------

  ipcMain.handle('set-mode', (_e, next) => setMode(next));
  ipcMain.on('mini-drag-start', startMiniDrag);
  ipcMain.on('mini-drag-end', stopMiniDrag);
  ipcMain.on('mini-menu', showMiniMenu);
  ipcMain.on('mini-hover', (_e, over) => { if (mini && !mini.isDestroyed()) mini.setOpacity(over ? 1 : 0.9); });

  // Reminder cards -----------------------------------------------------------

  ipcMain.handle('get-card', (_e, id) => cards.find((c) => c.id === id)?.data || null);
  ipcMain.on('card-action', (_e, id, action) => cardAction(id, action));

  ipcMain.handle('import-credentials', async () => {
    const { canceled, filePaths } = await dialog.showOpenDialog(win, {
      title: 'Choose your Google OAuth client file',
      filters: [{ name: 'JSON', extensions: ['json'] }],
      properties: ['openFile'],
    });
    if (canceled || !filePaths[0]) return googleStatus();
    const raw = readJSON(filePaths[0], null);
    const c = raw && (raw.installed || raw.web);
    if (!c || !c.client_id) {
      throw new Error('That file is not a Google OAuth client. Download it from Google Cloud Console > Credentials.');
    }
    writeJSON(FILES.credentials, raw);
    return googleStatus();
  });

  ipcMain.handle('connect-google', async () => {
    await connectGoogle();
    await refreshMeetings();
    return googleStatus();
  });

  ipcMain.handle('disconnect-google', async () => {
    const client = authedClient();
    try { if (client) await client.revokeCredentials(); } catch {}
    try { fs.unlinkSync(FILES.token); } catch {}
    meetings = [];
    google = { lastSync: null, error: null };
    send('data-changed');
    return googleStatus();
  });

  ipcMain.handle('sync-now', async () => { await refreshMeetings(); return googleStatus(); });

  ipcMain.handle('open-url', (_e, url) => {
    if (typeof url === 'string' && /^https:\/\//.test(url)) shell.openExternal(url);
  });

  ipcMain.handle('test-notification', () => {
    const r = typeOf(DEFAULT_TYPE).reminders.start;
    fire({ role: 'start', sound: r.sound, fade: r.fade, title: 'Now: Test block', body: 'This is what a block starting looks like.' });
  });
}

function applyLoginItem() {
  if (process.platform === 'linux') return; // use your desktop's autostart settings instead
  app.setLoginItemSettings({ openAtLogin: settings.launchAtLogin, args: ['--hidden'] });
}

// ---------------------------------------------------------------------------
// App lifecycle
// ---------------------------------------------------------------------------

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', showWindow);

  app.whenReady().then(() => {
    if (process.platform === 'win32') app.setAppUserModelId('com.dayflow.app');
    loadData();
    registerIpc();
    // Opening at login always starts backstage, without forgetting the mode you last used.
    const atLogin = process.argv.includes('--hidden') ||
      (process.platform === 'darwin' && app.getLoginItemSettings().wasOpenedAtLogin);
    createWindow();
    createMini();
    createTray();
    setMode(atLogin ? 'backstage' : windowState.mode, { persist: false });
    applyShortcut();
    for (const ev of ['display-added', 'display-removed', 'display-metrics-changed']) {
      screen.on(ev, () => { if (mode === 'mini') placeMini(); });
    }

    refreshMeetings();
    setInterval(refreshMeetings, 5 * 60 * 1000);
    tick();
    setInterval(tick, 1000);
  });

  app.on('activate', showWindow);
  app.on('before-quit', () => { quitting = true; });
  app.on('will-quit', () => globalShortcut.unregisterAll());
  app.on('window-all-closed', () => { /* stay alive in the tray */ });
}
