// Exposes a small, explicit API to the windows. No Node access in the renderer.
const { contextBridge, ipcRenderer, webUtils } = require('electron');

contextBridge.exposeInMainWorld('dayflow', {
  platform: process.platform,
  getAll: () => ipcRenderer.invoke('get-all'),
  getToday: () => ipcRenderer.invoke('get-today'),
  // Checking an event off for today, and skipping an event or block today. Both return
  // { done, total, streak } for the cheer-up.
  setDone: (id, on) => ipcRenderer.invoke('set-done', id, on),
  setSkipped: (id, on) => ipcRenderer.invoke('set-skipped', id, on),
  saveSchedule: (blocks) => ipcRenderer.invoke('save-schedule', blocks),
  saveSettings: (settings) => ipcRenderer.invoke('save-settings', settings),
  importCredentials: () => ipcRenderer.invoke('import-credentials'),
  connectGoogle: () => ipcRenderer.invoke('connect-google'),
  disconnectGoogle: () => ipcRenderer.invoke('disconnect-google'),
  syncNow: () => ipcRenderer.invoke('sync-now'),
  openUrl: (url) => ipcRenderer.invoke('open-url', url),
  testNotification: () => ipcRenderer.invoke('test-notification'),
  onDataChanged: (fn) => ipcRenderer.on('data-changed', () => fn()),
  onChime: (fn) => ipcRenderer.on('chime', (_e, chime) => fn(chime)), // { kind, sound }
  onStopSound: (fn) => ipcRenderer.on('stop-sound', () => fn()),

  // Sounds
  getSoundData: (id) => ipcRenderer.invoke('get-sound-data', id),
  pickSoundFile: () => ipcRenderer.invoke('pick-sound-file'),
  addSound: (clip) => ipcRenderer.invoke('add-sound', clip),
  removeSound: (id) => ipcRenderer.invoke('remove-sound', id),
  readSoundFile: (file) => ipcRenderer.invoke('read-sound-file', file),
  readFolderFile: (name) => ipcRenderer.invoke('read-folder-file', name),
  savePiece: (piece) => ipcRenderer.invoke('save-piece', piece),
  renameSound: (id, name) => ipcRenderer.invoke('rename-sound', { id, name }),
  revealSound: (id) => ipcRenderer.invoke('reveal-sound', id),
  trashFolderFile: (name) => ipcRenderer.invoke('trash-folder-file', name),
  openClipsFolder: () => ipcRenderer.invoke('open-clips-folder'),
  scanClips: () => ipcRenderer.invoke('scan-clips'),
  addClipMenu: () => ipcRenderer.invoke('add-clip-menu'),
  clipMenu: () => ipcRenderer.invoke('clip-menu'),
  askMicrophone: () => ipcRenderer.invoke('ask-microphone'),
  openMicrophoneSettings: () => ipcRenderer.invoke('open-microphone-settings'),
  // The path of a file dropped on the window, so the main process can read it.
  pathForFile: (file) => webUtils.getPathForFile(file),
  // The main process asks how long a clip plays; fn(data) resolves to seconds or throws.
  onInspectClip: (fn) => ipcRenderer.on('inspect-clip', async (_e, { token, data }) => {
    try { ipcRenderer.send('inspect-clip-result', { token, seconds: await fn(data) }); } catch (e) {
      ipcRenderer.send('inspect-clip-result', { token, error: String(e?.message || e) });
    }
  }),
  onToast: (fn) => ipcRenderer.on('toast', (_e, msg) => fn(msg)),
  turnOffMenu: () => ipcRenderer.invoke('turn-off-menu'),
  turnOff: (choice) => ipcRenderer.invoke('turn-off', choice), // 'hour', 'day' or 'untilOn'
  turnOn: () => ipcRenderer.invoke('turn-on'),
  quit: () => ipcRenderer.invoke('quit'),
  onShowSettings: (fn) => ipcRenderer.on('show-settings', () => fn()),
  saveBlockTypes: (types) => ipcRenderer.invoke('save-block-types', types),

  // "Add a sample day": the eight sample blocks; returns the schedule.
  addSampleDay: () => ipcRenderer.invoke('add-sample-day'),

  // The window and the Mini timer
  showWindow: () => ipcRenderer.invoke('show-window'),
  setMini: (on) => ipcRenderer.invoke('set-mini', on),
  onMiniChanged: (fn) => ipcRenderer.on('mini-changed', (_e, on) => fn(on)),
  miniDragStart: () => ipcRenderer.send('mini-drag-start'),
  miniDragEnd: () => ipcRenderer.send('mini-drag-end'),
  miniMenu: () => ipcRenderer.send('mini-menu'),
  miniHover: (over) => ipcRenderer.send('mini-hover', over),

  // Reminder cards
  getCard: (id) => ipcRenderer.invoke('get-card', id),
  cardAction: (id, action) => ipcRenderer.send('card-action', id, action),
  onCardMore: (fn) => ipcRenderer.on('card-more', (_e, n) => fn(n)),
  onCardLeave: (fn) => ipcRenderer.on('card-leave', () => fn()),
  onCardCheer: (fn) => ipcRenderer.on('card-cheer', (_e, c) => fn(c)),
});
