// Exposes a small, explicit API to the windows. No Node access in the renderer.
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('dayflow', {
  platform: process.platform,
  getAll: () => ipcRenderer.invoke('get-all'),
  getToday: () => ipcRenderer.invoke('get-today'),
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
  saveBlockTypes: (types) => ipcRenderer.invoke('save-block-types', types),

  // Export and import
  exportSchedule: () => ipcRenderer.invoke('export-schedule'),
  previewImport: () => ipcRenderer.invoke('preview-import'),
  applyImport: (token, opts) => ipcRenderer.invoke('apply-import', token, opts),
  showBackups: () => ipcRenderer.invoke('show-backups'),

  // Window modes
  setMode: (mode) => ipcRenderer.invoke('set-mode', mode),
  onModeChanged: (fn) => ipcRenderer.on('mode-changed', (_e, mode) => fn(mode)),
  miniDragStart: () => ipcRenderer.send('mini-drag-start'),
  miniDragEnd: () => ipcRenderer.send('mini-drag-end'),
  miniMenu: () => ipcRenderer.send('mini-menu'),
  miniHover: (over) => ipcRenderer.send('mini-hover', over),

  // Reminder cards
  getCard: (id) => ipcRenderer.invoke('get-card', id),
  cardAction: (id, action) => ipcRenderer.send('card-action', id, action),
  onCardMore: (fn) => ipcRenderer.on('card-more', (_e, n) => fn(n)),
  onCardLeave: (fn) => ipcRenderer.on('card-leave', () => fn()),
});
