// DayFlow — main process
// Owns storage, the reminder scheduler, system notifications, the tray icon,
// and the Google Calendar connection. The window is just a view onto this.

const {
  app, BrowserWindow, Tray, Menu, Notification, ipcMain, shell, nativeImage, dialog, globalShortcut, screen, systemPreferences,
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
  // Checks, skips and each day's result, on this Mac only (never exported). Same as the iPhone's.
  progress: path.join(DATA_DIR, 'progress.json'),
};
const SOUNDS_DIR = path.join(DATA_DIR, 'sounds');

function readJSON(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
}
function writeJSON(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(data, null, 2));
}

const WEEKDAYS = [1, 2, 3, 4, 5];
// "Add a sample day": eight weekday blocks, all Default. A new schedule starts empty.
const SAMPLE_SCHEDULE = {
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

// Your own clips: [{ id, name, ext, file }]. The id is a hash of the audio, so reminders and
// export files keep finding a clip whatever its file is called; `file` is its file in the Clips
// folder, e.g. "Ding.mp3". The folder is ~/Music/DayFlow Clips, where you can add, rename and
// delete clips in Finder (inside the data folder instead when DayFlow runs with --user-data-dir).
// Clips saved before the folder existed were kept as sounds/<id>.<ext> and are moved in.
let customSounds = readJSON(FILES.sounds, []);
const CLIPS_DIR = app.commandLine.hasSwitch('user-data-dir')
  ? path.join(DATA_DIR, 'Clips')
  : path.join(app.getPath('music'), 'DayFlow Clips');
const ORIGINALS_DIR = path.join(CLIPS_DIR, 'Originals');
const MAX_SOURCE_BYTES = 200 * 1024 * 1024; // the largest file a 30-second piece can come from
const MAX_HASH_BYTES = 40 * 1024 * 1024;
// Files in the folder that aren't clips: [{ file, problem: 'piece' | 'unusable', seconds?, message }]
let folderFiles = [];

const clipPath = (c) => path.join(CLIPS_DIR, c.file || `${c.id}.${c.ext}`);
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

// A file name made from a clip name: no slashes, colons or leading dots.
function safeFileName(name) {
  let s = String(name).replace(/[/:\\]/g, '-').trim().replace(/^\.+/, '');
  return s.slice(0, 60) || 'Sound clip';
}

// "Name", or "Name (2)"… if another clip has that name (ignoring case).
function uniqueClipName(base, exceptId = null) {
  const taken = new Set(customSounds.filter((c) => c.id !== exceptId).map((c) => c.name.toLowerCase()));
  let label = base;
  for (let n = 2; taken.has(label.toLowerCase()); n++) label = `${base} (${n})`;
  return label;
}

// "Name.ext", or "Name (2).ext"… if that file already exists in the folder.
function uniqueFileName(base, ext, dir = CLIPS_DIR, except = null) {
  let existing = [];
  try { existing = fs.readdirSync(dir).map((f) => f.toLowerCase()); } catch {}
  const taken = new Set(existing.filter((f) => f !== String(except || '').toLowerCase()));
  let file = `${base}.${ext}`;
  for (let n = 2; taken.has(file.toLowerCase()); n++) file = `${base} (${n}).${ext}`;
  return file;
}

// Clips kept as sounds/<id>.<ext> before the Clips folder move in, under their names.
function moveLegacyClips() {
  let moved = false;
  for (const c of customSounds) {
    if (c.file) continue;
    const old = path.join(SOUNDS_DIR, `${c.id}.${c.ext}`);
    if (!fs.existsSync(old)) continue;
    try {
      fs.mkdirSync(CLIPS_DIR, { recursive: true });
      const file = uniqueFileName(safeFileName(c.name), c.ext);
      fs.renameSync(old, path.join(CLIPS_DIR, file));
      c.file = file;
      moved = true;
    } catch (e) {
      try { // a different disk: copy, then delete
        const file = uniqueFileName(safeFileName(c.name), c.ext);
        fs.copyFileSync(old, path.join(CLIPS_DIR, file));
        fs.unlinkSync(old);
        c.file = file;
        moved = true;
      } catch { console.error(`Couldn't move ${c.name} into the Clips folder:`, e.message); }
    }
  }
  if (moved) {
    writeJSON(FILES.sounds, customSounds);
    try { if (!fs.readdirSync(SOUNDS_DIR).length) fs.rmdirSync(SOUNDS_DIR); } catch {}
  }
}

// Copies a clip into the Clips folder. The same audio is only ever stored once; a different clip
// whose name is taken becomes "Name (2)", and so does its file.
function installClip(name, ext, buf) {
  const type = checkClip(name, ext, buf);
  const id = clipHash(buf);
  const existing = customSounds.find((c) => c.id === id);
  if (existing) return existing;
  const label = uniqueClipName(String(name).trim().slice(0, 60) || 'Sound clip');
  fs.mkdirSync(CLIPS_DIR, { recursive: true });
  const file = uniqueFileName(safeFileName(label), type);
  fs.writeFileSync(path.join(CLIPS_DIR, file), buf);
  const clip = { id, name: label, ext: type, file };
  customSounds.push(clip);
  writeJSON(FILES.sounds, customSounds);
  return clip;
}

// Removes a clip; any reminder that used it goes back to that reminder's starting sound.
// Returns the names of the reminders that changed. The file is left to the caller (moved to the
// Trash by Remove, or already gone when you deleted it in Finder).
function removeClip(id) {
  const clip = customSounds.find((c) => c.id === id);
  if (!clip) return [];
  customSounds = customSounds.filter((c) => c !== clip);
  writeJSON(FILES.sounds, customSounds);
  // A reminder with other sounds too just loses this one; one that had only this clip goes back
  // to its starting sound, and is named in what's returned.
  const reset = [];
  let changed = false;
  const drop = (r, fallback) => {
    const list = choicesOf(r);
    if (!list.includes(customId(id))) return false;
    changed = true;
    const rest = list.filter((x) => x !== customId(id));
    Object.assign(r, cleanSounds({ sound: rest[0], sounds: rest }, fallback, () => true));
    if (!r.sounds) delete r.sounds;
    return !rest.length;
  };
  const resetIn = (reminders, spec, owner) => {
    for (const [k, s] of Object.entries(spec)) if (drop(reminders[k], s.sound)) reset.push(`${owner} · ${s.label}`);
  };
  for (const t of blockTypes) resetIn(t.reminders, REMINDERS, t.name);
  resetIn(settings.meetings, MEETING_REMINDERS, 'Meetings');
  const settingsChanged = changed;
  changed = false;
  for (const b of schedule?.blocks || []) {
    if (b.alert && drop(b.alert, EVENT_ALERT.sound)) reset.push(b.title);
  }
  if (settingsChanged) {
    writeJSON(FILES.blockTypes, blockTypes);
    writeJSON(FILES.settings, settings);
  }
  if (changed) writeJSON(FILES.schedule, schedule);
  return reset;
}

// Renames a clip and its file. Reminders that use it keep it.
function renameClip(id, newName) {
  const name = String(newName || '').trim().slice(0, 60);
  if (!name) throw new Error('A clip needs a name.');
  const clip = customSounds.find((c) => c.id === id);
  if (!clip) throw new Error('That clip has been removed.');
  if (customSounds.some((c) => c.id !== id && c.name.toLowerCase() === name.toLowerCase())) {
    throw new Error(`There's already a clip called "${name}".`);
  }
  const file = uniqueFileName(safeFileName(name), clip.ext, CLIPS_DIR, clip.file);
  if (file !== clip.file) fs.renameSync(clipPath(clip), path.join(CLIPS_DIR, file));
  clip.name = name;
  clip.file = file;
  writeJSON(FILES.sounds, customSounds);
  return clip;
}

// How long a file plays, worked out by the window (Web Audio decodes every format DayFlow takes,
// ogg included). Resolves to { seconds } or { error }, or null if the window can't check now.
const inspections = new Map();
function inspectInWindow(file) {
  if (!win || win.isDestroyed() || !winReady) return Promise.resolve(null);
  const token = crypto.randomUUID();
  return new Promise((resolve) => {
    const timer = setTimeout(() => { inspections.delete(token); resolve(null); }, 20000);
    inspections.set(token, (result) => { clearTimeout(timer); inspections.delete(token); resolve(result); });
    win.webContents.send('inspect-clip', { token, data: fs.readFileSync(file) });
  });
}

// Brings the clip list in line with the Clips folder. A file with the same audio as a clip whose
// file is gone is that clip, renamed; other new files are checked and added, or listed with what's
// wrong. Clips whose file is gone are removed. If the folder can't be read, nothing is removed.
let scanning = null;
let scanAgain = false;
function scanClipsFolder() {
  if (scanning) { scanAgain = true; return scanning; }
  scanning = (async () => {
    const result = { added: [], renamed: [], removed: [], reset: [] };
    try {
      fs.mkdirSync(CLIPS_DIR, { recursive: true });
      const names = fs.readdirSync(CLIPS_DIR, { withFileTypes: true })
        .filter((d) => d.isFile() && !d.name.startsWith('.')).map((d) => d.name)
        .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
      const lower = new Set(names.map((n) => n.toLowerCase()));
      const known = new Set(customSounds.map((c) => (c.file || '').toLowerCase()));
      let missing = customSounds.filter((c) => !lower.has((c.file || `${c.id}.${c.ext}`).toLowerCase()));
      const others = [];
      for (const name of names) {
        if (known.has(name.toLowerCase())) continue;
        const full = path.join(CLIPS_DIR, name);
        const { name: base, ext: dotExt } = path.parse(name);
        const ext = dotExt.slice(1).toLowerCase();
        const unusable = (message) => others.push({ file: name, problem: 'unusable', message });
        if (!CLIP_TYPES.includes(ext)) { unusable("Isn't an mp3, wav, m4a, aac or ogg file."); continue; }
        const size = fs.statSync(full).size;
        if (!size) { unusable('The file is empty.'); continue; }
        if (size > MAX_SOURCE_BYTES) { unusable('Larger than 200 MB.'); continue; }
        if (size <= MAX_HASH_BYTES) {
          const id = clipHash(fs.readFileSync(full));
          const renamed = missing.find((c) => c.id === id);
          if (renamed) { // you renamed it in Finder
            missing = missing.filter((c) => c !== renamed);
            renamed.file = name;
            renamed.ext = ext;
            renamed.name = uniqueClipName(base, id);
            result.renamed.push(renamed.name);
            continue;
          }
          const twin = customSounds.find((c) => c.id === id);
          if (twin) { unusable(`The same sound as ${twin.name}.`); continue; }
        }
        const info = await inspectInWindow(full);
        if (!info) { others.push({ file: name, problem: 'unchecked', message: 'Not checked yet.' }); continue; }
        if (info.error) { unusable("DayFlow can't play this file. Try converting it to mp3 or wav."); continue; }
        if (info.seconds > 30.5 || size > MAX_CLIP_BYTES) {
          others.push({ file: name, problem: 'piece', seconds: info.seconds,
            message: `${Math.round(info.seconds)} seconds. Choose 30 seconds of it to use it.` });
          continue;
        }
        const data = fs.readFileSync(full);
        const clip = { id: clipHash(data), name: uniqueClipName(base), ext, file: name };
        customSounds.push(clip);
        result.added.push(clip.name);
      }
      for (const gone of missing) { // you deleted or moved it in Finder
        result.reset.push(...removeClip(gone.id));
        result.removed.push(gone.name);
      }
      folderFiles = others;
      if (result.added.length || result.renamed.length || result.removed.length) {
        writeJSON(FILES.sounds, customSounds);
      }
    } catch (e) {
      console.error("Couldn't read the Clips folder:", e.message);
    }
    return result;
  })();
  return scanning.then(async (result) => {
    scanning = null;
    if (result.added.length || result.renamed.length || result.removed.length) {
      send('data-changed');
      const parts = [];
      const list = (names) => (names.length <= 2 ? names.join(' and ') : `${names.length} clips`);
      if (result.added.length) parts.push(`Added ${list(result.added)} from the Clips folder.`);
      if (result.removed.length) {
        parts.push(`${list(result.removed)} left the Clips folder${result.reset.length ? `, so ${result.reset.join(', ')} went back to the starting sound` : ''}.`);
      }
      if (parts.length) send('toast', parts.join(' '));
    }
    if (scanAgain) { scanAgain = false; return scanClipsFolder(); }
    return result;
  });
}

// Watches the folder, so a file you drop in, rename or delete in Finder shows up straight away.
let clipsWatcher = null;
function watchClipsFolder() {
  try {
    fs.mkdirSync(CLIPS_DIR, { recursive: true });
    let timer = null;
    clipsWatcher = fs.watch(CLIPS_DIR, () => {
      clearTimeout(timer);
      timer = setTimeout(() => scanClipsFolder(), 600);
    });
  } catch (e) {
    console.error("Couldn't watch the Clips folder:", e.message);
  }
}

// Saves a 30-second piece as "<name> (clip)". A song from the Clips folder then moves into
// Originals, so it isn't listed any more and nothing of yours is deleted.
function savePiece(name, buf, source) {
  const clip = installClip(`${name} (clip)`, 'wav', buf);
  if (source && path.dirname(path.resolve(source)) === path.resolve(CLIPS_DIR) && fs.existsSync(source)) {
    fs.mkdirSync(ORIGINALS_DIR, { recursive: true });
    const { name: base, ext } = path.parse(source);
    fs.renameSync(source, path.join(ORIGINALS_DIR, uniqueFileName(base, ext.slice(1), ORIGINALS_DIR)));
  }
  return clip;
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

// One reminder's sounds: `sound` is always the first, and `sounds` lists them all when there's
// more than one (each time it rings, one is picked at random, never the one it played last).
// Unusable ones are dropped; with none left it takes the starting sound. many: false keeps one.
function cleanSounds(r, fallback, isSound, many = true) {
  const list = [];
  for (const v of [r?.sound, ...(many && Array.isArray(r?.sounds) ? r.sounds : [])]) {
    if (typeof v === 'string' && isSound(v) && !list.includes(v)) list.push(v);
  }
  if (!list.length) list.push(fallback);
  return many && list.length > 1 ? { sound: list[0], sounds: list } : { sound: list[0] };
}
const choicesOf = (r) => (Array.isArray(r?.sounds) && r.sounds.length ? r.sounds : [r.sound]);

// Cleans one set of reminders; anything missing or unusable takes the starting value.
// Meetings keep one sound each (many: false).
function sanitizeReminders(next, spec, isSound = validSound, many = spec !== MEETING_REMINDERS) {
  const out = {};
  for (const [key, s] of Object.entries(spec)) {
    const r = next?.[key] || {};
    // fade: the sound starts quiet and grows to your volume, so it doesn't startle you
    out[key] = { on: flag(r.on, s.on), ...cleanSounds(r, s.sound, isSound, many), fade: flag(r.fade, false) };
    if (s.lead) out[key].lead = clamp(r.lead, 1, 60, DEFAULT_LEAD);
  }
  return out;
}

// An event's one reminder: its sound(s) and fade. It's always on.
const EVENT_TYPE = 'event';
const EVENT_ALERT = { label: 'Alarm', on: true, sound: 'elevator-announcement-bells' };
const sanitizeAlert = (r, isSound = validSound) => ({ on: true, ...cleanSounds(r, EVENT_ALERT.sound, isSound), fade: flag(r?.fade, false) });

// A repeat's rule: every `every` minutes from `first` to `last`, `last` included when the gap
// lands on it. Every event it made carries it; `id` ties them together. Same as the iPhone's.
const REPEAT_EVERY = [1, 720];
const MAX_REPEAT_EVENTS = 200;
function sanitizeSeries(v) {
  if (!v || typeof v !== 'object' || !v.id || !TIME_RE.test(v.first) || !TIME_RE.test(v.last)) return null;
  const every = Number(v.every);
  if (!Number.isInteger(every) || every < REPEAT_EVERY[0] || every > REPEAT_EVERY[1] || toMin(v.last) <= toMin(v.first)) return null;
  return { id: String(v.id), first: v.first, last: v.last, every };
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

const DEFAULT_SETTINGS = {
  sound: true,           // false mutes every reminder sound
  volume: 80,            // 0–100
  meetings: null, // filled in below, once MEETING_REMINDERS can be checked against
  launchAtLogin: false,
  shortcut: true,        // Control+Alt+D cycles the window modes
  alertStyle: 'cards',   // 'cards': a card that stays until you act; 'notifications': macOS notifications
  cardAutoClose: 0,      // minutes before a card closes itself; 0 = stays until you act
  offUntil: null,        // reminders are off until this moment (ms), for 1 or 24 hours
  remindersOff: false,   // reminders are off until you turn them on
};

DEFAULT_SETTINGS.meetings = sanitizeReminders({}, MEETING_REMINDERS);

function sanitizeSettings(next, prev) {
  return {
    sound: flag(next.sound, prev.sound),
    volume: clamp(next.volume, 0, 100, prev.volume),
    meetings: sanitizeReminders(next.meetings || prev.meetings, MEETING_REMINDERS),
    launchAtLogin: flag(next.launchAtLogin, prev.launchAtLogin),
    shortcut: flag(next.shortcut, prev.shortcut),
    // Earlier versions showed both, with cards: false turning cards off.
    alertStyle: ['cards', 'notifications'].includes(next.alertStyle) ? next.alertStyle
      : next.cards === false ? 'notifications' : (prev.alertStyle || 'cards'),
    cardAutoClose: [0, 1, 5].includes(Number(next.cardAutoClose)) ? Number(next.cardAutoClose) : prev.cardAutoClose,
    offUntil: next.offUntil === null ? null : (Number.isFinite(Number(next.offUntil)) && next.offUntil !== undefined ? Number(next.offUntil) : (prev.offUntil ?? null)),
    remindersOff: flag(next.remindersOff, prev.remindersOff ?? false),
  };
}

// ---------------------------------------------------------------------------
// Block types
// Every block has a type, and its type decides its reminders. Default can be renamed and
// changed like any other type, but not deleted: blocks of a deleted type move to it.
// ---------------------------------------------------------------------------

const DEFAULT_TYPE = 'default';
const STARTER_NAMES = ['Focus', 'Break', 'Admin', 'Meal']; // what version 1 data started with
const newType = (id, name) => ({ id, name, reminders: sanitizeReminders({}, REMINDERS) });
// A new schedule starts with just Default; you add a type when a block should sound different.
const starterTypes = () => [newType(DEFAULT_TYPE, 'Default')];

// Blocks used to be able to carry their own four reminders (type "own"). Now a block's reminders
// always come from its type, so each such block becomes a type of its own, named after the block
// ("Run", or "Run (2)" if that's taken), with those reminders. Same as the iPhone's OwnReminders.
const OWN_TYPE = 'own';
function ownRemindersToTypes(blocks) {
  if (!Array.isArray(blocks)) return { blocks, changed: false };
  const names = new Set(blockTypes.map((t) => t.name.toLowerCase()));
  let changed = false;
  const out = blocks.map((b) => {
    if (!b || b.type !== OWN_TYPE || !b.end || !b.reminders || typeof b.reminders !== 'object') return b;
    const base = String(b.title || '').trim().slice(0, 34) || 'Own reminders';
    let name = base;
    for (let n = 2; names.has(name.toLowerCase()); n++) name = `${base} (${n})`;
    names.add(name.toLowerCase());
    const t = { id: crypto.randomUUID(), name, reminders: sanitizeReminders(b.reminders, REMINDERS) };
    blockTypes.push(t);
    changed = true;
    const { reminders, ...rest } = b; // eslint-disable-line no-unused-vars
    return { ...rest, type: t.id };
  });
  return { blocks: out, changed };
}

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
    blocks: blocks.map((b) => ({ ...b, type: b.type === 'own' && b.reminders ? 'own' : ids.get(String(b.type)) || DEFAULT_TYPE })),
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
  moveLegacyClips();
  const raw = {
    schedule: readJSON(FILES.schedule, null),
    settings: readJSON(FILES.settings, {}),
    blockTypes: readJSON(FILES.blockTypes, null),
  };
  const oldSettings = 'sounds' in raw.settings || 'warnBeforeEndMin' in raw.settings || 'meetingLeadMin' in raw.settings;
  const oldTypes = raw.blockTypes ? raw.blockTypes.some((t) => !t?.reminders) : !!raw.schedule;
  if (!oldSettings && !oldTypes) {
    settings = sanitizeSettings(raw.settings, DEFAULT_SETTINGS);
    try { blockTypes = sanitizeTypes(raw.blockTypes || starterTypes()); } catch { blockTypes = starterTypes(); }
    const own = ownRemindersToTypes(raw.schedule?.blocks || []);
    if (own.changed) { blockTypes = sanitizeTypes(blockTypes); writeJSON(FILES.blockTypes, blockTypes); }
    schedule = { blocks: sanitizeBlocks(own.blocks) };
    if (own.changed) writeJSON(FILES.schedule, schedule);
    loadProgress();
    return;
  }

  const up = upgradeV1({ settings: raw.settings, blockTypes: raw.blockTypes, blocks: raw.schedule?.blocks || [] });
  blockTypes = sanitizeTypes(up.types);
  settings = sanitizeSettings({ ...raw.settings, meetings: up.meetings }, DEFAULT_SETTINGS);
  const own = ownRemindersToTypes(up.blocks);
  blockTypes = sanitizeTypes(blockTypes);
  schedule = { blocks: sanitizeBlocks(own.blocks) };
  writeJSON(FILES.blockTypes, blockTypes);
  writeJSON(FILES.settings, settings);
  writeJSON(FILES.schedule, schedule);
  loadProgress();
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

// A block with no end is an event: it happens at its start time and rings once, with its own
// `alert`. Its end is its start, so it's never "the current block". Skipped ones are left out
// (unless includeSkipped).
const isEvent = (b) => !b.end;
function blocksFor(date, { includeSkipped = false } = {}) {
  const dow = date.getDay();
  const skipped = new Set(progress.days[dayKey(date)]?.skipped || []);
  return (schedule.blocks || [])
    .filter((b) => Array.isArray(b.days) && b.days.includes(dow) && (isEvent(b) || toMin(b.end) > toMin(b.start)))
    .filter((b) => includeSkipped || !skipped.has(b.id))
    .map((b) => ({
      id: b.id, title: b.title, type: isEvent(b) ? EVENT_TYPE : typeOf(b.type).id,
      moment: isEvent(b), event: isEvent(b), alert: b.alert, series: b.series || null, days: b.days,
      rings: !isEvent(b) && !!b.ringOnSilent, start: at(date, b.start), end: at(date, b.end || b.start),
    }))
    .sort((a, b) => a.start - b.start);
}
// The reminders a block uses: its type's.
const remindersFor = (b) => typeOf(b.type).reminders;
const typeNameFor = (b) => (b.event ? (b.series ? 'Repeated event' : 'Event') : typeOf(b.type).name);

// The times a repeat rings, in minutes.
function repeatTimes(r) {
  const out = [];
  if (!r) return out;
  for (let m = toMin(r.first); m <= toMin(r.last) && out.length <= MAX_REPEAT_EVENTS; m += r.every) out.push(m);
  return out;
}

// ---------------------------------------------------------------------------
// Several sounds: which one rings this time. Worked out from the time's place in the run of
// times that reminder rings, so it's the same every time and on the iPhone (SoundPick in
// DayFlowCore): even places pick freely, odd places avoid both neighbours, two sounds take turns.
// ---------------------------------------------------------------------------

function fnv(str) {
  let h = 0x811c9dc5;
  for (const b of Buffer.from(str, 'utf8')) { h ^= b; h = Math.imul(h, 0x01000193) >>> 0; }
  return h >>> 0;
}
function soundPick(choices, stream, index) {
  const n = choices.length;
  if (n < 2) return choices[0];
  if (n === 2) return choices[(index + (fnv(stream) % 2)) % 2];
  const free = (i) => fnv(`${stream}|${i}`) % n;
  if (index % 2 === 0) return choices[free(index)];
  const avoid = new Set([free(index - 1), free(index + 1)]);
  const options = [...Array(n).keys()].filter((i) => !avoid.has(i));
  return choices[options[fnv(`${stream}|${index}|odd`) % options.length]];
}
const WEEK_ORDER = [1, 2, 3, 4, 5, 6, 0];
// stream: the run (a block's Start, a whole repeat); per/slot: a repeat's times in a day and this one's place.
function pickSound(r, stream, days, date, per = 1, slot = 0) {
  const choices = choicesOf(r);
  if (choices.length < 2) return r.sound;
  const order = WEEK_ORDER.filter((d) => days.includes(d));
  const pos = Math.max(0, order.indexOf(date.getDay()));
  const daysSince = Math.round((Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) - Date.UTC(2001, 0, 1)) / 864e5);
  const week = Math.floor(daysSince / 7);
  return soundPick(choices, stream, (week * Math.max(order.length, 1) + pos) * per + slot);
}
function eventSound(b, date) {
  const alert = b.alert || { sound: EVENT_ALERT.sound };
  if (b.series) {
    const times = repeatTimes(b.series);
    return pickSound(alert, `series|${b.series.id}`, b.days, date, Math.max(times.length, 1), Math.max(0, times.indexOf(toMin(fmtHHMM(b.start)))));
  }
  return pickSound(alert, b.id, b.days, date);
}
const fmtHHMM = (d) => `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;

// ---------------------------------------------------------------------------
// Checking off and skipping, and the streak. Same rules as the iPhone (DayProgress in
// DayFlowCore): checks and skips belong to their day, so everything is back the next morning;
// a day counts towards the streak when at least 80% of its events (skipped ones aside) are done.
// ---------------------------------------------------------------------------

let progress = { since: null, days: {} };
const KEEP_DAYS = 400;
const parseDay = (k) => { const [y, m, d] = String(k).split('-').map(Number); return y && m && d ? new Date(y, m - 1, d) : null; };
function loadProgress() {
  const raw = readJSON(FILES.progress, {});
  progress = { since: parseDay(raw.since) ? raw.since : null, days: {} };
  for (const [k, d] of Object.entries(raw.days || {})) {
    if (!parseDay(k) || !d || typeof d !== 'object') continue;
    const ids = (v) => [...new Set((Array.isArray(v) ? v : []).filter((x) => typeof x === 'string'))];
    const num = (v) => (Number.isFinite(Number(v)) && v !== null && v !== undefined ? Math.max(0, Math.round(Number(v))) : undefined);
    progress.days[k] = { done: ids(d.done), skipped: ids(d.skipped), total: num(d.total), count: num(d.count) };
  }
}
function changeDay(day, edit) {
  if (!progress.since || parseDay(day) < parseDay(progress.since)) progress.since = day;
  const r = progress.days[day] || { done: [], skipped: [] };
  edit(r);
  if (!r.done.length && !r.skipped.length && r.total === undefined) delete progress.days[day]; else progress.days[day] = r;
}
function setDone(id, on, day = dayKey(new Date())) {
  changeDay(day, (r) => {
    r.done = r.done.filter((x) => x !== id);
    if (on) { r.done.push(id); r.skipped = r.skipped.filter((x) => x !== id); }
  });
  saveProgress();
}
function setSkipped(id, on, day = dayKey(new Date())) {
  changeDay(day, (r) => {
    r.skipped = r.skipped.filter((x) => x !== id);
    if (on) { r.skipped.push(id); r.done = r.done.filter((x) => x !== id); }
  });
  saveProgress();
}
// A day's events that count, and how many are done.
function result(date) {
  const done = new Set(progress.days[dayKey(date)]?.done || []);
  const events = blocksFor(date).filter((b) => b.event);
  return { done: events.filter((b) => done.has(b.id)).length, total: events.length };
}
const counts = ({ done, total }) => total > 0 && done >= total * 0.8 - 1e-9;
function streak(now = new Date()) {
  const today = new Date(now); today.setHours(0, 0, 0, 0);
  let n = counts(result(today)) ? 1 : 0;
  const since = parseDay(progress.since);
  if (!since) return n;
  const d = new Date(today);
  for (let i = 0; i < KEEP_DAYS; i++) {
    d.setDate(d.getDate() - 1);
    if (d < since) break;
    const rec = progress.days[dayKey(d)];
    const live = rec?.total === undefined ? result(d) : null;
    const total = rec?.total ?? live.total;
    const done = rec?.count ?? live?.done ?? 0;
    if (!total) continue;
    if (counts({ done, total })) n += 1; else break;
  }
  return n;
}
// Saves progress with today's result noted, dropping checks of things no longer planned and
// days past KEEP_DAYS.
function saveProgress() {
  const day = dayKey(new Date());
  const r = result(new Date());
  if (r.total > 0 || progress.days[day]) changeDay(day, (x) => { x.total = r.total; x.count = r.done; });
  const ids = new Set((schedule?.blocks || []).map((b) => b.id));
  const oldest = new Date(); oldest.setDate(oldest.getDate() - KEEP_DAYS);
  for (const [k, rec] of Object.entries(progress.days)) {
    if (parseDay(k) < oldest) { delete progress.days[k]; continue; }
    rec.done = rec.done.filter((x) => ids.has(x));
    rec.skipped = rec.skipped.filter((x) => ids.has(x));
  }
  writeJSON(FILES.progress, progress);
}
const cheerData = () => ({ ...result(new Date()), streak: streak() });

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
  const all = blocksFor(now);
  // Blocks hand over to blocks; events ring on their own and are never merged.
  const blocks = all.filter((b) => !b.event);
  const pick = (b, role, r) => pickSound(r, `${b.id}|${role}`, b.days, now);

  for (const b of blocks) {
    const r = remindersFor(b);
    const prev = blocks.find((p) => p !== b && p.end.getTime() === b.start.getTime());
    const next = blocks.find((n) => n !== b && n.start >= b.end);
    const key = (role) => `${day}|block|${b.id}|${role}`;

    const prepAt = new Date(b.start - r.prep.lead * MIN_MS);
    if (r.prep.on && prepAt >= midnight) {
      events.push({
        key: key('prep'), at: prepAt, role: 'prep', block: b, sound: pick(b, 'prep', r.prep), fade: r.prep.fade,
        title: `In ${r.prep.lead} min: ${b.title}`,
        body: `Get ready. It starts at ${fmt(b.start)}.`,
      });
    }
    if (r.start.on) {
      events.push({
        key: key('start'), at: b.start, role: 'start', block: b, sound: pick(b, 'start', r.start), fade: r.start.fade,
        title: `Now: ${b.title}`,
        body: prev ? `${prev.title} is done. ${b.title} runs until ${fmt(b.end)}.` : `Runs until ${fmt(b.end)}.`,
      });
    }
    if (r.warn.on && b.end - b.start > r.warn.lead * MIN_MS) {
      events.push({
        key: key('warn'), at: new Date(b.end - r.warn.lead * MIN_MS), role: 'warn', block: b, sound: pick(b, 'warn', r.warn), fade: r.warn.fade,
        title: `${r.warn.lead} min left: ${b.title}`,
        body: next ? `Next: ${next.title} at ${fmt(next.start)}.` : 'This is your last block today.',
      });
    }
    if (r.end.on) {
      let body = 'That was your last block today.';
      if (next) body = next.start.getTime() === b.end.getTime() ? `${next.title} starts now.` : `Free until ${next.title} at ${fmt(next.start)}.`;
      events.push({ key: key('end'), at: b.end, role: 'end', block: b, sound: pick(b, 'end', r.end), fade: r.end.fade, title: `Time's up: ${b.title}`, body });
    }
  }

  const merged = mergeSameMoment(events);

  // Events: "Now: Take medicine", with the block it falls in. One that's checked off is done.
  const done = new Set(progress.days[day]?.done || []);
  for (const e of all.filter((b) => b.event && !done.has(b.id))) {
    const during = blocks.find((b) => b.start <= e.start && e.start < b.end);
    merged.push({ keys: [`${day}|event|${e.id}`], at: e.start, role: 'event', block: e, sound: eventSound(e, now), fade: !!e.alert?.fade,
      title: `Now: ${e.title}`, body: during ? `It's ${fmt(e.start)}, during ${during.title}.` : `It's ${fmt(e.start)}.` });
  }

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
  event: EVENT_ALERT.sound,
  meetBefore: MEETING_REMINDERS.before.sound,
  meetStart: MEETING_REMINDERS.start.sound,
};

// ---------------------------------------------------------------------------
// Reminder cards
// Each reminder gets a glass card at the top right that stays until you act on it, alongside
// the macOS notification. A card is a small floating window that's shown without being activated,
// so it sits over full-screen apps and on every Space without taking focus from what you're
// typing. (Electron's 'panel' window type isn't used: on macOS it only logs a warning, as the
// style it sets doesn't apply to ordinary windows, and showing inactive already does the job.)
// Up to three show at
// once, newest on top; the bottom one says how many more are waiting.
// ---------------------------------------------------------------------------

const CARD_SIZE = { width: 360, height: 124 };
const CARD_GAP = 10;
const CARD_MARGIN = 14;
const MAX_CARDS = 3;
const SNOOZE_CHOICES = [1, 5, 10]; // minutes
let cards = []; // newest first: { id, win, data, ev, notification, timer }

// ---------------------------------------------------------------------------
// Turning reminders off: For 1 hour, For 24 hours, or Until I turn them on. While off, nothing
// rings: no notifications, no sounds, no cards. Reminders that fall in that time are skipped,
// not delivered late. Kept in settings, so it lasts through a restart. Same as the iPhone app.
// ---------------------------------------------------------------------------

const TURN_OFF = {
  hour: { label: 'For 1 hour', ms: 60 * 60 * 1000 },
  day: { label: 'For 24 hours', ms: 24 * 60 * 60 * 1000 },
  untilOn: { label: 'Until I turn them on' },
};

// When reminders come back: Infinity until you turn them on, null while they're on.
function offUntil(now = Date.now()) {
  if (settings.remindersOff) return Infinity;
  return settings.offUntil && now < settings.offUntil ? settings.offUntil : null;
}
const remindersOff = () => offUntil() !== null;

// "Reminders off until 3:15 PM", "…until Thu 3:15 PM", "…until you turn them on".
function offStatus(now = new Date()) {
  const until = offUntil(+now);
  if (until === null) return null;
  if (until === Infinity) return 'Reminders off until you turn them on';
  const d = new Date(until);
  const sameDay = dayKey(d) === dayKey(now);
  return `Reminders off until ${sameDay ? '' : `${d.toLocaleDateString([], { weekday: 'short' })} `}${fmt(d)}`;
}

function turnOff(choice) {
  const c = TURN_OFF[choice];
  if (!c) return;
  settings = { ...settings, remindersOff: choice === 'untilOn', offUntil: c.ms ? Date.now() + c.ms : null };
  writeJSON(FILES.settings, settings);
  [...cards].forEach((card) => closeCard(card.id));
  send('stop-sound');
  afterOnOff();
}

function turnOn() {
  settings = { ...settings, remindersOff: false, offUntil: null };
  writeJSON(FILES.settings, settings);
  afterOnOff();
}

function afterOnOff() {
  lastTrayLabel = '';
  updateTray(new Date());
  send('data-changed');
}

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
    label: meeting ? 'Meeting' : b ? typeNameFor(b) : typeOf(DEFAULT_TYPE).name,
    meeting,
    title: ev.title,
    // Preparation already says when in its title, so its line is just the block's time.
    sub: ev.role === 'prep' ? `Get ready · ${fmt(b.start)} – ${fmt(b.end)}` : ev.body,
    join: meeting && ev.meeting.url ? 'join' : meeting && ev.meeting.htmlLink ? 'calendar' : null,
    snooze: target ? SNOOZE_CHOICES.filter((m) => target - Date.now() > m * MIN_MS + 20 * 1000) : [],
    // An event's card has Done, which checks it off.
    done: ev.role === 'event',
    more: 0,
  };
}

function showCard(ev, notification) {
  if (settings.alertStyle !== 'cards' || remindersOff()) return null;
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
      ? { vibrancy: 'popover', visualEffectState: 'active', backgroundColor: '#00000000' }
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
  // Done: the event is checked off, and the card cheers before it goes.
  if (action === 'done' && ev.role === 'event') {
    setDone(ev.block.id, true, ev.keys[0].split('|')[0]);
    send('data-changed');
    send('stop-sound');
    clearTimeout(card.timer);
    if (!card.win.isDestroyed()) card.win.webContents.send('card-cheer', cheerData());
    card.timer = setTimeout(() => closeCard(id), 2200);
    return;
  }
  if (action === 'join' && ev.meeting?.url) shell.openExternal(ev.meeting.url);
  if (action === 'calendar' && ev.meeting?.htmlLink) shell.openExternal(ev.meeting.htmlLink);
  if (action === 'open') showWindow();
  closeCard(id);
}


const liveNotifications = new Set(); // keep references so click handlers aren't garbage-collected

// One reminder: a card, or a macOS notification, as chosen in Settings → General.
function fire(ev) {
  if (settings.alertStyle === 'cards') {
    showCard(ev, null);
  } else if (Notification.isSupported()) {
    const n = new Notification({ title: ev.title, body: ev.body, silent: true });
    liveNotifications.add(n);
    n.on('click', () => {
      send('stop-sound');
      const url = ev.meeting ? ev.meeting.url || ev.meeting.htmlLink : null;
      if (url && /^https:\/\//.test(url)) shell.openExternal(url);
      else showWindow();
    });
    n.on('close', () => liveNotifications.delete(n));
    n.show();
    setTimeout(() => liveNotifications.delete(n), 10 * 60 * 1000);
  }
  if (settings.sound) send('chime', { sound: ev.sound, fade: ev.fade, fallback: FALLBACK_SOUNDS[ev.role] });
}

function tick() {
  const now = new Date();
  const day = dayKey(now);
  if (day !== currentDay) {
    currentDay = day;
    fired.clear();
    saveProgress(); // notes the new day's result, and drops very old days
    refreshMeetings();
    send('data-changed');
  }
  // A 1-hour or 24-hour stop that has ended is cleared, so the menu bar icon comes back.
  if (settings.offUntil && now >= settings.offUntil) {
    settings = { ...settings, offUntil: null };
    writeJSON(FILES.settings, settings);
    afterOnOff();
  }
  const off = remindersOff();
  for (const ev of buildEvents(now)) {
    const delta = now - ev.at;
    if (delta >= 0 && delta < FIRE_WINDOW_MS && !ev.keys.some((k) => fired.has(k))) {
      ev.keys.forEach((k) => fired.add(k)); // while off it's skipped, not saved for later
      if (!off) fire(ev);
    }
  }
  updateTray(now);
}

// ---------------------------------------------------------------------------
// The window, the Mini timer and the menu bar icon
// The window opens and closes like any Mac window; DayFlow keeps running in the menu bar, and
// its Dock icon shows only while the window is open. The Mini timer, a small floating
// countdown, is shown or hidden on its own. Reminders run the same either way.
// ---------------------------------------------------------------------------

const SHORTCUT = 'Control+Alt+D';
const MINI_SIZE = { width: 268, height: 76 };

let win = null;
let mini = null;
let tray = null;
let quitting = false;
let lastTrayLabel = '';
let winReady = false;
let showWhenReady = false;
let shortcutActive = false;

// windowOpen: whether the window was open when DayFlow last ran, so it reopens that way.
// miniShown: the Mini timer is showing. (Earlier versions kept a "mode": full, mini or
// backstage; it's read once to start the same way.)
const savedWindow = readJSON(FILES.windowState, {});
const windowState = {
  windowOpen: flag(savedWindow.windowOpen, savedWindow.mode ? savedWindow.mode === 'full' : true),
  miniShown: flag(savedWindow.miniShown, savedWindow.mode === 'mini'),
  miniPos: savedWindow.miniPos || null,
  miniOnTop: flag(savedWindow.miniOnTop, true),
  quitNoteShown: flag(savedWindow.quitNoteShown, false), // the one-time "Quit DayFlow?" note
};
const saveWindowState = () => writeJSON(FILES.windowState, windowState);

function quit() {
  quitting = true;
  app.quit();
}

// Quitting from the window (⌘Q or Quit DayFlow in the sidebar). The first time, a note says
// what quitting means, and how to silence reminders without quitting.
async function quitFromWindow() {
  if (!windowState.quitNoteShown) {
    windowState.quitNoteShown = true;
    saveWindowState();
    const { response } = await dialog.showMessageBox(win && !win.isDestroyed() && win.isVisible() ? win : undefined, {
      type: 'info',
      message: 'Quit DayFlow?',
      detail: 'Reminders stop until you open DayFlow again. To silence them without quitting, use Turn off reminders. (This note only shows once.)',
      buttons: ['Quit', 'Cancel'],
      defaultId: 0,
      cancelId: 1,
    });
    if (response !== 0) return;
  }
  quit();
}

// The app menu: ⌘Q quits through quitFromWindow; Edit keeps copy and paste working in fields.
function setAppMenu() {
  if (process.platform !== 'darwin') return;
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    {
      label: app.name,
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        { label: 'Settings…', accelerator: 'Cmd+,', click: () => { showWindow(); send('show-settings'); } },
        { type: 'separator' },
        { role: 'hide' }, { role: 'hideOthers' }, { role: 'unhide' },
        { type: 'separator' },
        { label: `Quit ${app.name}`, accelerator: 'Cmd+Q', click: quitFromWindow },
      ],
    },
    { role: 'editMenu' },
    { role: 'windowMenu' },
  ]));
}

function send(channel, payload) {
  for (const w of [win, mini]) {
    if (w && !w.isDestroyed()) w.webContents.send(channel, payload);
  }
}

// Opens the window (and the Dock icon with it).
async function showWindow() {
  if (!win) return;
  if (process.platform === 'darwin') await app.dock.show();
  if (!winReady) { showWhenReady = true; return; }
  if (win.isMinimized()) win.restore();
  win.show();
  win.focus();
  if (process.platform === 'darwin') app.focus({ steal: true });
  if (!windowState.windowOpen) { windowState.windowOpen = true; saveWindowState(); }
}

// Closes the window: DayFlow carries on in the menu bar, without a Dock icon.
function hideWindow() {
  showWhenReady = false;
  if (win && !win.isDestroyed()) win.hide();
  if (process.platform === 'darwin') app.dock.hide();
  if (windowState.windowOpen) { windowState.windowOpen = false; saveWindowState(); }
}

// ⌃⌥D: opens the window, or closes it if it's in front.
function toggleWindow() {
  if (win && win.isVisible() && win.isFocused()) hideWindow(); else showWindow();
}

function setMini(on) {
  windowState.miniShown = !!on;
  saveWindowState();
  if (on) { placeMini(); mini.showInactive(); } else mini.hide();
  lastTrayLabel = '';
  updateTray(new Date());
  send('mini-changed', windowState.miniShown);
}

function applyShortcut() {
  if (shortcutActive) globalShortcut.unregister(SHORTCUT);
  shortcutActive = settings.shortcut ? globalShortcut.register(SHORTCUT, toggleWindow) : false;
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
    // The window checks new clips (how long they play), so the folder is scanned once it's up.
    scanClipsFolder();
    if (!clipsWatcher) watchClipsFolder();
  });

  // Closing the window leaves DayFlow running in the menu bar.
  win.on('close', (e) => {
    if (quitting) return;
    e.preventDefault();
    hideWindow();
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
  mini.on('close', (e) => { if (!quitting) { e.preventDefault(); setMini(false); } });
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
    { label: 'Open DayFlow', click: showWindow },
    { label: 'Hide Mini timer', click: () => setMini(false) },
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

// The menu bar icon, crossed out while reminders are off.
function trayImage(off) {
  const file = process.platform === 'darwin' ? (off ? 'trayOffTemplate.png' : 'trayTemplate.png') : (off ? 'trayOff.png' : 'tray.png');
  let img = nativeImage.createFromPath(path.join(__dirname, '..', 'assets', file));
  if (process.platform !== 'darwin') img = img.resize({ width: 16, height: 16 });
  return img;
}

function createTray() {
  tray = new Tray(trayImage(remindersOff()));
  tray.setToolTip('DayFlow');
  tray.on('click', showWindow);
}

// Turn off reminders ▸ For 1 hour / For 24 hours / Until I turn them on, or, while off, the
// status and Turn on reminders.
function onOffMenuItems() {
  const status = offStatus();
  if (status) return [{ label: status, enabled: false }, { label: 'Turn on reminders', click: turnOn }];
  return [{ label: 'Turn off reminders', submenu: Object.entries(TURN_OFF).map(([id, c]) => ({ label: c.label, click: () => turnOff(id) })) }];
}

// The tray menu is the control panel while the window is closed: what's on now, the window and
// the Mini timer, turning reminders off.
function buildTrayMenu(label) {
  tray.setContextMenu(Menu.buildFromTemplate([
    { label, enabled: false },
    { type: 'separator' },
    { label: 'Open DayFlow', click: showWindow },
    { label: 'Show Mini timer', type: 'checkbox', checked: windowState.miniShown, click: (item) => setMini(item.checked) },
    { type: 'separator' },
    ...onOffMenuItems(),
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
  const status = offStatus(now);
  const key = `${label}|${status}`; // the menu also changes when reminders go off or on
  if (key === lastTrayLabel) return;
  lastTrayLabel = key;
  tray.setImage(trayImage(!!status));
  tray.setToolTip(status ? `DayFlow: ${status}` : `DayFlow: ${label}`);
  if (process.platform === 'darwin') tray.setTitle(short);
  buildTrayMenu(label);
}

// ---------------------------------------------------------------------------
// IPC
// ---------------------------------------------------------------------------

// Every block has a type: one that isn't in typeIds becomes the fallback (normally Default).
// (Blocks with their own reminders become types first, in ownRemindersToTypes.)
// No end (missing, null or empty) makes an event: type "event", one `alert`, maybe a repeat's
// `series`. A moment from before events existed becomes one with the sound and fade of its Start
// reminder (or Start preparation's, if only that was on), from its own reminders or its type's
// (typeReminders looks a type up).
function sanitizeBlocks(blocks, typeIds = new Set(blockTypes.map((t) => t.id)), fallback = DEFAULT_TYPE, isSound = validSound,
  typeReminders = (id) => typeOf(id).reminders) {
  if (!Array.isArray(blocks)) throw new Error('Schedule must be a list.');
  return blocks.map((b, i) => {
    const title = String(b.title || '').trim().slice(0, 120);
    if (!title) throw new Error(`Block ${i + 1} needs a name.`);
    const end = b.end ? String(b.end) : '';
    if (!TIME_RE.test(b.start) || (end && !TIME_RE.test(end))) throw new Error(`"${title}" has an invalid time.`);
    if (end && toMin(end) <= toMin(b.start)) throw new Error(`"${title}" must end after it starts.`);
    const days = [...new Set((b.days || []).map(Number).filter((d) => d >= 0 && d <= 6))].sort();
    const id = String(b.id || crypto.randomUUID());
    if (!end) {
      let alert;
      if (b.alert && typeof b.alert === 'object') {
        alert = sanitizeAlert(b.alert, isSound);
      } else {
        const r = b.type === OWN_TYPE && b.reminders && typeof b.reminders === 'object'
          ? sanitizeReminders(b.reminders, REMINDERS, isSound) : typeReminders(String(b.type));
        alert = sanitizeAlert(!r.start.on && r.prep.on ? r.prep : r.start, () => true);
      }
      const out = { id, title, start: b.start, end: '', days, type: EVENT_TYPE, alert };
      const series = sanitizeSeries(b.series);
      if (series) out.series = series;
      return out;
    }
    const out = { id, title, start: b.start, end, days, type: typeIds.has(String(b.type)) ? String(b.type) : fallback };
    // On iPhone its reminders ring as alarms, through silent mode and Focus. Kept here so it
    // travels in export files; the Mac's own reminders don't change.
    if (b.ringOnSilent) out.ringOnSilent = true;
    return out;
  }).sort((a, b) => toMin(a.start) - toMin(b.start));
}

function registerIpc() {
  ipcMain.handle('get-all', () => ({
    schedule,
    settings,
    google: googleStatus(),
    customSounds,
    folderFiles,
    clipsFolder: CLIPS_DIR,
    offStatus: offStatus(),
    builtinSounds: BUILTIN,
    blockTypes,
    miniShown: windowState.miniShown,
    shortcutActive,
    platform: process.platform,
  }));

  ipcMain.handle('get-today', () => {
    const now = new Date();
    const rec = progress.days[dayKey(now)] || { done: [], skipped: [] };
    return {
      // warnMin and prepMin (0 when that reminder is off) let the mini timer show the heads-up
      // and "Get ready". Skipped ones are included for the agenda, marked; the dial leaves them out.
      blocks: blocksFor(now, { includeSkipped: true }).map((b) => {
        const r = b.event ? null : remindersFor(b);
        return {
          ...b,
          start: b.start.toISOString(),
          end: b.end.toISOString(),
          warnMin: r && r.warn.on ? r.warn.lead : 0,
          prepMin: r && r.prep.on ? r.prep.lead : 0,
          done: rec.done.includes(b.id),
          skipped: rec.skipped.includes(b.id),
        };
      }),
      meetings,
      ...cheerData(),
    };
  });

  // Checking an event off (returns the cheer-up's numbers), and skipping for today.
  ipcMain.handle('set-done', (_e, id, on) => {
    setDone(String(id), !!on);
    updateTray(new Date());
    return cheerData();
  });
  ipcMain.handle('set-skipped', (_e, id, on) => {
    setSkipped(String(id), !!on);
    updateTray(new Date());
    return cheerData();
  });

  ipcMain.handle('save-schedule', (_e, blocks) => {
    schedule = { blocks: sanitizeBlocks(blocks) };
    writeJSON(FILES.schedule, schedule);
    saveProgress(); // checks of events that are gone go too
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

  // Reads a sound you pick (or drop on Your clips) so the window can check it: a short one is
  // then stored with add-sound, a long one opens Choose 30 seconds.
  const readSoundFile = (file) => {
    const { name, ext } = path.parse(file);
    const type = ext.slice(1).toLowerCase();
    if (!CLIP_TYPES.includes(type)) throw new Error(`"${name}" isn't an mp3, wav, m4a, aac or ogg file.`);
    const size = fs.statSync(file).size;
    if (!size) throw new Error(`"${name}" is empty.`);
    if (size > MAX_SOURCE_BYTES) throw new Error(`"${name}" is larger than 200 MB.`);
    return { name, ext: type, data: fs.readFileSync(file), path: file, inFolder: path.dirname(path.resolve(file)) === path.resolve(CLIPS_DIR) };
  };
  ipcMain.handle('pick-sound-file', async () => {
    const { canceled, filePaths } = await dialog.showOpenDialog(win, {
      title: 'Choose a sound clip',
      filters: [{ name: 'Audio', extensions: CLIP_TYPES }],
      properties: ['openFile'],
    });
    if (canceled || !filePaths[0]) return null;
    return readSoundFile(filePaths[0]);
  });
  ipcMain.handle('read-sound-file', (_e, file) => readSoundFile(String(file)));
  // A file in the Clips folder, by name (for Choose 30 seconds on a song you put there).
  ipcMain.handle('read-folder-file', (_e, name) => readSoundFile(path.join(CLIPS_DIR, path.basename(String(name)))));

  ipcMain.handle('add-sound', (_e, { name, ext, data }) => {
    const clip = installClip(name, ext, Buffer.from(data));
    return { clip, customSounds };
  });

  ipcMain.handle('save-piece', (_e, { name, data, source }) => {
    const clip = savePiece(String(name), Buffer.from(data), source ? String(source) : null);
    scanClipsFolder();
    return { clip, customSounds };
  });

  // Remove moves the clip's file to the Trash, so you can put it back.
  ipcMain.handle('remove-sound', async (_e, id) => {
    const clip = customSounds.find((c) => c.id === id);
    if (clip && fs.existsSync(clipPath(clip))) {
      try { await shell.trashItem(clipPath(clip)); } catch { fs.unlinkSync(clipPath(clip)); }
    }
    const reset = removeClip(id);
    return { reset, customSounds, settings, blockTypes };
  });

  ipcMain.handle('rename-sound', (_e, { id, name }) => {
    const clip = renameClip(String(id), name);
    return { clip, customSounds };
  });

  // Deletes a file in the Clips folder that isn't a clip (one DayFlow can't use), to the Trash.
  ipcMain.handle('trash-folder-file', async (_e, name) => {
    const file = path.join(CLIPS_DIR, path.basename(String(name)));
    if (fs.existsSync(file)) await shell.trashItem(file);
    await scanClipsFolder();
    return folderFiles;
  });

  ipcMain.handle('open-clips-folder', () => {
    fs.mkdirSync(CLIPS_DIR, { recursive: true });
    return shell.openPath(CLIPS_DIR);
  });

  ipcMain.handle('scan-clips', async () => {
    await scanClipsFolder();
    return { customSounds, folderFiles };
  });

  ipcMain.on('inspect-clip-result', (_e, { token, seconds, error }) => {
    inspections.get(token)?.(error ? { error } : { seconds });
  });

  // Native pop-up menus: Add a clip ▾, and ⋯ on a clip. Resolve to the chosen item's id.
  const popup = (items) => new Promise((resolve) => {
    let chosen = null;
    const menu = Menu.buildFromTemplate(items.map((it) => (it === '-' ? { type: 'separator' } : { label: it.label, click: () => { chosen = it.id; } })));
    menu.popup({ window: win, callback: () => setTimeout(() => resolve(chosen), 0) });
  });
  ipcMain.handle('add-clip-menu', () => popup([
    { id: 'record', label: 'Record a clip…' },
    { id: 'choose', label: 'Choose a file…' },
    '-',
    { id: 'help', label: 'How do I add music?' },
  ]));
  ipcMain.handle('clip-menu', () => popup([
    { id: 'rename', label: 'Rename…' },
    { id: 'reveal', label: 'Show in Finder' },
    '-',
    { id: 'remove', label: 'Remove' },
  ]));
  ipcMain.handle('reveal-sound', (_e, id) => {
    const clip = customSounds.find((c) => c.id === id);
    if (clip) shell.showItemInFolder(clipPath(clip));
  });

  // macOS asks once for the microphone; false if you've turned it off in System Settings.
  ipcMain.handle('ask-microphone', async () => {
    if (process.platform !== 'darwin') return true;
    const status = systemPreferences.getMediaAccessStatus('microphone');
    if (status === 'granted') return true;
    if (status === 'denied' || status === 'restricted') return false;
    return systemPreferences.askForMediaAccess('microphone');
  });
  ipcMain.handle('open-microphone-settings', () => shell.openExternal('x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone'));

  // Block types --------------------------------------------------------------

  ipcMain.handle('save-block-types', (_e, list) => {
    blockTypes = sanitizeTypes(list);
    writeJSON(FILES.blockTypes, blockTypes);
    // Blocks whose type was deleted move to Default.
    const ids = new Set(blockTypes.map((t) => t.id));
    if (schedule.blocks.some((b) => !isEvent(b) && !ids.has(b.type))) {
      schedule = { blocks: schedule.blocks.map((b) => (isEvent(b) || ids.has(b.type) ? b : { ...b, type: DEFAULT_TYPE })) };
      writeJSON(FILES.schedule, schedule);
    }
    send('data-changed');
    return { blockTypes, schedule };
  });

  // "Add a sample day": the eight sample blocks, added to whatever you have.
  ipcMain.handle('add-sample-day', () => {
    const taken = new Set(schedule.blocks.map((b) => b.id));
    const sample = SAMPLE_SCHEDULE.blocks.map((b) => ({ ...b, id: taken.has(b.id) ? crypto.randomUUID() : b.id, type: DEFAULT_TYPE }));
    schedule = { blocks: sanitizeBlocks([...schedule.blocks, ...sample]) };
    writeJSON(FILES.schedule, schedule);
    saveProgress();
    send('data-changed');
    return schedule;
  });

  // The window and the Mini timer -----------------------------------------------

  ipcMain.handle('show-window', () => showWindow());
  ipcMain.handle('set-mini', (_e, on) => setMini(!!on));
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

  ipcMain.handle('turn-off', (_e, choice) => { turnOff(String(choice)); return offStatus(); });
  ipcMain.handle('turn-on', () => { turnOn(); return null; });
  ipcMain.handle('turn-off-menu', () => popup(Object.entries(TURN_OFF).map(([id, c]) => ({ id, label: c.label }))).then((id) => {
    if (id) turnOff(id);
    return offStatus();
  }));
  ipcMain.handle('quit', () => quitFromWindow());

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
    setAppMenu();
    // Opening at login always starts with the window closed, without forgetting how you left it.
    const atLogin = process.argv.includes('--hidden') ||
      (process.platform === 'darwin' && app.getLoginItemSettings().wasOpenedAtLogin);
    createWindow();
    createMini();
    createTray();
    if (windowState.windowOpen && !atLogin) showWindow();
    else if (process.platform === 'darwin') app.dock.hide();
    if (windowState.miniShown) { placeMini(); mini.showInactive(); }
    updateTray(new Date());
    applyShortcut();
    for (const ev of ['display-added', 'display-removed', 'display-metrics-changed']) {
      screen.on(ev, () => { if (windowState.miniShown) placeMini(); });
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
