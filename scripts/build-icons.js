// Renders the SVG artwork in assets/ to the PNG and .icns files the app and installers use.
// Run with `npm run icons` after editing assets/icon.svg, assets/tray.svg or assets/trayTemplate.svg.
// It uses Electron itself to draw the SVGs, so nothing extra needs installing.

const { app, BrowserWindow } = require('electron');
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const ASSETS = path.join(__dirname, '..', 'assets');

// [source svg, output png, size in pixels]
const OUTPUTS = [
  ['icon.svg', 'icon.png', 1024],
  ['tray.svg', 'tray.png', 32],
  ['trayTemplate.svg', 'trayTemplate.png', 16],
  ['trayTemplate.svg', 'trayTemplate@2x.png', 32],
];
const ICNS_SIZES = [16, 32, 64, 128, 256, 512, 1024];

// The iPhone icon: the same artwork, full-bleed (iOS rounds the corners itself), in the three
// looks iOS 18 offers: light, dark and tinted (a grayscale image the system colours).
const IOS_ICONS = path.join(__dirname, '..', 'ios', 'DayFlow', 'Assets.xcassets', 'AppIcon.appiconset');
function iosIcon(svg, look) {
  const scale = 1024 / 824;
  let out = svg
    .replace(/<rect x="101\.5"[^>]*\/>/, '') // the macOS tile's rim
    .replace('<g clip-path="url(#tile)">', `<g transform="scale(${scale}) translate(-100 -100)">`);
  if (look === 'dark') {
    out = out.replace('stop-color="#4C9C9C"', 'stop-color="#24504F"')
      .replace('stop-color="#2F6F73"', 'stop-color="#173B3E"')
      .replace('stop-color="#173A3E"', 'stop-color="#0B1C1E"');
  }
  if (look === 'tinted') {
    out = out.replace('</svg>', '').replace(/(<svg[^>]*>)/, '$1<filter id="gray"><feColorMatrix type="saturate" values="0"/></filter><g filter="url(#gray)">') + '</g></svg>';
  }
  return out;
}

// One offscreen window draws every size; each SVG is laid out at its target size and cropped,
// so small icons are drawn sharp at that size instead of being shrunk from a big one.
let win;
async function render(svgFile, size, transform = (svg) => svg) {
  if (!win) {
    win = new BrowserWindow({
      width: 1024,
      height: 1024,
      show: false,
      frame: false,
      transparent: true,
      backgroundColor: '#00000000',
      useContentSize: true,
      webPreferences: { offscreen: true },
    });
  }
  const svg = transform(fs.readFileSync(path.join(ASSETS, svgFile), 'utf8'));
  const html = `<!doctype html><style>html,body{margin:0;background:transparent;overflow:hidden}
    svg{display:block;width:${size}px;height:${size}px}</style>${svg}`;
  const file = path.join(os.tmpdir(), 'dayflow-icon.html');
  fs.writeFileSync(file, html);
  await win.loadFile(file);
  await new Promise((r) => setTimeout(r, 150)); // let the gradients paint
  let img = await win.webContents.capturePage({ x: 0, y: 0, width: size, height: size });
  if (img.getSize().width !== size) img = img.resize({ width: size, height: size, quality: 'best' });
  return img;
}

app.whenReady().then(async () => {
  for (const [src, out, size] of OUTPUTS) {
    fs.writeFileSync(path.join(ASSETS, out), (await render(src, size)).toPNG());
    console.log(`assets/${out} (${size}px)`);
  }

  fs.mkdirSync(IOS_ICONS, { recursive: true });
  for (const look of ['light', 'dark', 'tinted']) {
    fs.writeFileSync(path.join(IOS_ICONS, `icon-${look}.png`), (await render('icon.svg', 1024, (svg) => iosIcon(svg, look))).toPNG());
    console.log(`ios/.../AppIcon.appiconset/icon-${look}.png`);
  }

  // macOS wants an .icns holding every size; iconutil (part of macOS) builds it from an .iconset.
  if (process.platform === 'darwin') {
    const set = fs.mkdtempSync(path.join(os.tmpdir(), 'dayflow-')) + '/icon.iconset';
    fs.mkdirSync(set);
    for (const size of ICNS_SIZES) {
      const png = (await render('icon.svg', size)).toPNG();
      if (size <= 512) fs.writeFileSync(path.join(set, `icon_${size}x${size}.png`), png);
      if (size >= 32) fs.writeFileSync(path.join(set, `icon_${size / 2}x${size / 2}@2x.png`), png);
    }
    execFileSync('iconutil', ['-c', 'icns', set, '-o', path.join(ASSETS, 'icon.icns')]);
    fs.rmSync(path.dirname(set), { recursive: true, force: true });
    console.log('assets/icon.icns');
  }
  app.quit();
});
