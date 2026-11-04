// `npm start`: runs DayFlow from source.
// On macOS, running Electron straight from node_modules makes the menu bar, Dock, notifications
// and System Settings call the app "Electron". So this launches a copy of Electron.app named
// DayFlow.app (kept in .dev/, rebuilt when Electron or the icon changes) with DayFlow's name,
// bundle id and icon. node_modules itself is never changed. Other systems run Electron as usual.

const { spawn, execFileSync } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const DEV_DIR = path.join(ROOT, '.dev');
const NAME = 'DayFlow';
const BUNDLE_ID = 'com.dayflow.app'; // the same as the built app, so they share notification settings
const electronBinary = require('electron');

function devApp() {
  const source = path.resolve(electronBinary, '..', '..', '..'); // .../Electron.app
  const app = path.join(DEV_DIR, `${NAME}.app`);
  const icon = path.join(ROOT, 'assets', 'icon.icns');
  const iconHash = fs.existsSync(icon) ? crypto.createHash('sha1').update(fs.readFileSync(icon)).digest('hex') : 'none';
  const MIC = 'DayFlow uses the microphone only when you record a clip.';
  const stamp = [require('electron/package.json').version, iconHash, NAME, BUNDLE_ID, MIC].join('|');
  const stampFile = path.join(DEV_DIR, 'stamp');
  const binary = path.join(app, 'Contents', 'MacOS', 'Electron');
  if (fs.existsSync(binary) && fs.existsSync(stampFile) && fs.readFileSync(stampFile, 'utf8') === stamp) return binary;

  console.log(`Preparing ${NAME}.app for development…`);
  fs.rmSync(app, { recursive: true, force: true });
  fs.mkdirSync(DEV_DIR, { recursive: true });
  try {
    execFileSync('cp', ['-cR', source, app]); // an APFS clone: instant, and shares disk space with the original
  } catch {
    execFileSync('cp', ['-R', source, app]);
  }
  const plist = path.join(app, 'Contents', 'Info.plist');
  const set = (key, value) => execFileSync('/usr/libexec/PlistBuddy', ['-c', `Set :${key} ${value}`, plist]);
  set('CFBundleName', NAME);
  set('CFBundleDisplayName', NAME);
  set('CFBundleIdentifier', BUNDLE_ID);
  set('NSMicrophoneUsageDescription', `"${MIC}"`);
  if (iconHash !== 'none') {
    fs.copyFileSync(icon, path.join(app, 'Contents', 'Resources', 'dayflow.icns'));
    set('CFBundleIconFile', 'dayflow.icns');
  }
  // Editing Info.plist breaks the bundle's signature; macOS won't run it until it's signed again.
  execFileSync('codesign', ['--force', '--deep', '--sign', '-', app], { stdio: 'ignore' });
  fs.writeFileSync(stampFile, stamp);
  return binary;
}

let binary = electronBinary;
if (process.platform === 'darwin') {
  try {
    binary = devApp();
  } catch (e) {
    console.warn(`Couldn't prepare ${NAME}.app (${e.message.split('\n')[0]}); running plain Electron instead.`);
  }
}

// From here on this mirrors node_modules/electron/cli.js.
const child = spawn(binary, [ROOT, ...process.argv.slice(2)], { stdio: 'inherit' });
child.on('close', (code, signal) => process.exit(code === null ? 1 : code));
for (const sig of ['SIGINT', 'SIGTERM', 'SIGUSR2']) {
  process.on(sig, () => child.kill(sig));
}
