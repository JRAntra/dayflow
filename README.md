# DayFlow

A local desktop app for running your day in blocks. You set up the phases of your day once (deep work, lunch, admin…), and DayFlow can remind you to get ready for each one, tell you when it starts, warn you a few minutes before it ends, and announce the hand-off to the next. Connect Google Calendar and it also reminds you before meetings, with a one-click Join for Google Meet links.

Everything stays on your computer. The only network traffic is to Google, and only if you connect your calendar.

**New to DayFlow?** The [User Guide](User%20Guide.md) walks through every feature, from installing to reminder cards and backups.

**On iPhone:** a native SwiftUI version lives in [`ios/`](ios/README.md), for iOS 17 or later. It has the same block types, reminders, sounds and export files, with a day view you can drag, a Lock Screen Live Activity and widgets. It's a beta you install from Xcode; see [DayFlow on iPhone](User%20Guide.md#17-dayflow-on-iphone).

## Install (macOS)

Download the DMG for your Mac from the [latest release](https://github.com/JRAntra/dayflow/releases). Apple menu → **About This Mac** shows both things you need: the macOS version, and *Chip: Apple M…* (Apple Silicon) or *Processor: Intel*.

| Your Mac | macOS 13 Ventura or later | macOS 11 Big Sur or 12 Monterey |
|---|---|---|
| Apple Silicon | `DayFlow-<version>-arm64.dmg` | `DayFlow-<version>-macos11-arm64.dmg` |
| Intel | `DayFlow-<version>-x64.dmg` | `DayFlow-<version>-macos11-x64.dmg` |

The macOS 11 builds are the same app on an older Electron (37), which no longer gets security updates from the Electron project; use the regular builds if your Mac can run them.

1. Open the DMG and drag **DayFlow** onto **Applications**.
2. Open DayFlow from Applications. Beta builds aren't notarized by Apple yet, so macOS says it can't check the app. Click **Done**.
3. Go to **System Settings → Privacy & Security**, scroll to the message about DayFlow, and click **Open Anyway**, then confirm. You only do this once.
4. Allow notifications when macOS asks.

## Run it

You need Node.js 20 or newer.

```bash
npm install
npm start
```

On macOS, `npm start` runs DayFlow from a copy of Electron named **DayFlow.app** (made once in `.dev/`, and again whenever Electron or the icon changes), so the menu bar, Dock, notifications and System Settings all say DayFlow rather than Electron. The first time, macOS asks again whether DayFlow may send notifications. If you see an old "Electron" entry under System Settings → Notifications, you can remove it.

DayFlow keeps running in the system tray (menu bar on macOS, where it also shows the minutes left in the current block). Quit with **Quit DayFlow** in the sidebar, ⌘Q, or the tray menu. To silence it without quitting, **Turn off reminders** (on Today or in the tray menu) for 1 hour, 24 hours, or until you turn them back on; the tray icon is crossed out while they're off. The iPhone app has the same Turn off.

## The look

DayFlow follows Apple's Human Interface Guidelines: the system font, a translucent sidebar (the macOS sidebar material, or Mica on Windows 11), the window buttons inset in the sidebar, frosted cards, and light or dark to match your system. Motion is short and soft: the dial's arcs draw themselves in, the "now" hand glides, countdown digits roll into place, the timeline's highlight slides to the next block at a hand-off, and tabs and pages cross-fade. Reduce Motion and Reduce Transparency in System Settings turn those off.

The styling is a small design system in plain CSS: `src/renderer/tokens.css` holds every colour, size, radius, shadow and timing, and `src/renderer/components.css` builds the buttons, fields, switches, steppers, menus, tabs, cards, toasts and dialogs from them. Change a token and every window follows.

## Reminder cards

Alongside each macOS notification, DayFlow shows a card at the top right of your screen, like Google Calendar's reminders. It floats over full-screen apps and on every Space, stays until you act on it, and never takes focus from what you're typing.

- **Start preparation** and **Heads-up**: *Snooze* (1, 5 or 10 minutes, offering only times that still come before the moment it's warning about) and *Got it*. A snoozed card comes back with an updated title ("In 2 min: Coffee break").
- **Start** and **Time's up**: *Got it*.
- **Meetings**: *Join* when there's a Meet link, otherwise *Open in Calendar*; *Snooze* on the "before" reminder; and *Got it*.

Clicking a card's text opens the full window. Any button stops the sound, and clearing a card clears its notification (and the other way round). Up to three cards show at once, newest on top, with "+N more" on the bottom one.

**Settings → General** turns cards off (you'll still get notifications) or has them close on their own after 1 or 5 minutes. **Send a test reminder** shows one. macOS doesn't let apps see Focus or Do Not Disturb, so **Turn off reminders** (or turn cards off) when you don't want them.

## Three ways to run it

- **Full**: the main window, with today's dial, the schedule editor and settings.
- **Mini timer**: a small floating pill showing the current block, a countdown, a progress bar and what's next (or "Meeting in 4 min" when a meeting comes first). It turns amber during your heads-up minutes. It stays on top of other windows, including full-screen apps and every Space. Drag it anywhere and it reopens there; if that spot is off-screen it snaps back to the top-right corner. Double-click it for the full window; right-click for Backstage, "Always on top" and Quit.
- **Backstage**: no window and no Dock icon, just the tray (reminder cards still appear). Reminders and sounds work as usual, and the tray menu shows what's on now and switches modes. Clicking a block reminder opens the full window for a look; closing it puts you back in Backstage.

Switch with the buttons at the bottom of the side rail, the tray menu, or **⌃⌥D** (Ctrl+Alt+D on Windows and Linux), which cycles Full → Mini → Backstage from any app. The shortcut can be turned off in Settings → General. Closing the full window takes you to whichever of Mini or Backstage you used last. DayFlow reopens in the mode you left it in, except that opening at login always starts in Backstage.

## What you get reminded about

Every block has a **block type**, and the type decides the block's reminders. Each type has four, and each one can be switched on or off and has its own sound:

- **Start preparation**: "In 10 min: Deep work. Get ready." You choose how many minutes ahead (1–60). Off for new types.
- **Start**: "Now: Deep work". If the previous block ends at that moment, it says so: "Email is done."
- **Heads-up**: "5 min left: Deep work. Next: Email at 11:30". You choose how many minutes ahead (1–60). It's skipped for a block that isn't longer than that.
- **Time's up**: "Time's up: Deep work. Free until Lunch at 12:00."

Reminders that land on the same moment become one notification, and the block that's coming up wins: its sound plays. At a hand-off you get "Now: Email. Deep work is done." with Email's start sound; when Deep work's heads-up lands on Email's preparation you get "5 min left: Deep work. Next: Email at 11:30" with Email's preparation sound. If the incoming block has that reminder switched off, the outgoing block's reminder plays as usual.

For each Google Calendar event today (all-day events, cancelled events and ones you declined are skipped), **Settings → Meetings** has two reminders, *Before it starts* (with its own lead time) and *Starting now*, each with a switch and a sound. Clicking a meeting reminder opens the Meet link, or the event in Google Calendar if there is no video link.

Blocks can repeat on any days of the week.

## Sounds

Every reminder picks from 18 built-in sounds (bells, chimes, a class bell, door and announcement tones, an alarm clock and a rooster, each 4 to 9 seconds) or your own clips. Picking a sound plays it straight away, and ▶ next to it plays it again. **Settings → Sounds** has one volume slider and a switch to mute everything.

Your own clips are ordinary files in the **Clips folder**, `~/Music/DayFlow Clips` (**Open Clips Folder** in Settings → Sounds). **Add a Clip ▾** can **Record a clip…** with the microphone (up to 30 seconds, with the quiet start and end trimmed off), **Choose a file…**, or explain **How do I add music?**. You can also drag sound files onto Your clips, or drop them into the folder, which DayFlow watches. Files can be mp3, wav, m4a, aac or ogg. A file longer than 30 seconds (or over 5 MB, up to 200 MB) opens **Choose 30 seconds**, which saves a piece as *Name (clip)* and moves a song from the folder into `Originals`. Renaming or deleting a file in Finder renames or removes its clip; **⋯ → Rename…** and **Remove** (to the Trash) do the same from DayFlow. A removed clip puts any reminder that used it back on that reminder's starting sound. Songs from the Music app or Apple Music are protected and can't be used.

**Fade in**, next to each reminder's sound, makes it start quiet and grow to your volume so it doesn't startle you: the sound rises from 10% to full over its first 8 seconds (the whole of a built-in sound). ▶ previews it the same way.

The built-in sounds are in `assets/sounds/`. All but `class-bell.mp3` (your own file) come from [Mixkit](https://mixkit.co/free-sound-effects/)'s free sound effects, which may be used without credit; Mixkit's licence doesn't allow redistributing the files on their own, so read [its terms](https://mixkit.co/license/) before sharing or selling a build of DayFlow that includes them.

A sound plays once. A new reminder cuts off one still playing, and clicking the notification stops it.

## Block types

**Settings → Block types** lists your types on the left; select one to edit its name and four reminders on the right (each with a switch, a − 5 + stepper for the minutes where it comes early, and a sound menu with ▶). It starts with Default, Focus, Break, Admin and Meal; **＋** and **−** under the list add and delete. Add, rename or delete them as you like (names must be unique). **Default** is special in two ways: it can be renamed and changed but never deleted, and it's where blocks go when they have nowhere else. New blocks get Default unless they copy the type of the block above, and deleting a type moves its blocks to Default (DayFlow asks first).

New types start with preparation off (5 min, Marimba), start on (Rising), heads-up on (5 min, Soft note) and time's up on (Falling).

Pick a block's type from the small dropdown under its name in the schedule; **New type…** at the bottom jumps to Settings. Today's flow shows each block's type under its name, and the mini timer uses it too: it turns amber during the current block's heads-up minutes, and says **Get ready** in free time once the next block's preparation window opens.

**Upgrading from an earlier version.** The first time the new version starts, it saves your old setup to `backups/`, then builds a Default type from your old global sounds and "warn me before a block ends" minutes, resolves any "Same as default" sounds in your other types, moves blocks without a type to Default, and gives Meetings your old meeting lead time and sound. Nothing you hear changes.

Besides blocks there are **events**, with only a time (Schedule → ＋ Add… → Event): an event rings once, with its own sound, shows as a dot on the dial, and is never merged with block reminders. A **repeated event** makes several at once (*Drink water* every 30 minutes from 9:00 to 5:00 is 17 events), checked before they're made and edited together through their repeat. In Today, you **check off** events as you do them (a cheer-up pops up, and done events turn gold, with a streak for days at least 80% done) and can **skip** any event or block for the day with its switch. A reminder can have **several sounds**, one picked at random each time, never the same twice in a row. A block can also have **Own reminders** (first in its Type menu) instead of a type's. On iPhone, events always ring as alarms (iOS 26 and later), through the silent switch and Focus, until you tap Stop or Done, and a block can **ring even on silent** too (Reminders ▸ → Ring on silent on the Mac). Export files are version 5 (`dayflowExport: 5`) because of these; versions 1 to 4 still import, and older moments (blocks with no end) become events.

## Export and import your schedule

**Schedule → Export…** saves a `.json` file with your blocks, the block types they use (all four reminders each), the Meetings reminders, volume, and any of your clips those reminders use (embedded, so the file works on another computer). It never includes your Google sign-in.

**Import…** shows what's in the file before anything changes: "This will replace your 8 blocks with 6 blocks from file.json". Untick **Also apply reminder and sound settings** to keep your own reminders and sounds. If a clip in the file can't be used, that reminder falls back to its starting sound and the preview says so.

The file's Default always matches your Default, even if either has been renamed. Other types match yours by name (ignoring case). A type you already have keeps your reminders unless settings are applied; a type you don't have is added ("Adds 1 new block type: Deep reading"), with the file's reminders if settings are applied or the starting ones if not. Your other types are left alone. Files from earlier versions still import: they're converted the same way your own data was upgraded.

Before every import DayFlow saves your current schedule, block types and settings to the `backups` folder (the newest ten are kept) in the same format. To undo an import, import the backup with settings applied; that puts your block types back exactly as they were. **Schedule → Backups** opens the folder.

## Connect Google Calendar (one-time, about 5 minutes)

Google requires every app that reads a calendar to have its own OAuth client. Because DayFlow runs only on your machine, you create that client yourself in your own Google Cloud project. It's free.

1. Go to https://console.cloud.google.com/ and create a project (any name, such as "DayFlow").
2. Open **APIs & Services → Library**, search for **Google Calendar API**, and click **Enable**.
3. Open **APIs & Services → OAuth consent screen** (called **Google Auth Platform** in newer consoles).
   - User type: **External** (or Internal if you're on a Google Workspace account and only you will use it).
   - Fill in the app name and your email.
   - Under **Audience / Test users**, add your own Google account.
   - Under **Data access / Scopes**, you can add `.../auth/calendar.readonly`. DayFlow asks for only this read-only scope.
4. Open **Credentials → Create credentials → OAuth client ID**.
   - Application type: **Desktop app**.
   - Click **Create**, then **Download JSON**.
5. In DayFlow, go to **Settings → Calendar**, click **Choose file**, and select the JSON you downloaded.
6. Click **Connect**. Your browser opens; sign in and allow access. Google will warn that the app isn't verified; that's expected for a personal project. Click **Continue**.

DayFlow then syncs today's events every 5 minutes (or use **Sync now**).

**Staying signed in.** While the consent screen is in **Testing** status, Google expires the sign-in after 7 days, and DayFlow will ask you to connect again. To avoid that, go to the consent screen and click **Publish app**. You don't need Google's verification for personal use; you'll just keep seeing the "unverified app" notice when you connect.

## Where your data lives

In your OS's app-data folder (`~/Library/Application Support/Dayflow` on macOS, `%APPDATA%\Dayflow` on Windows, `~/.config/Dayflow` on Linux). The folder keeps its original spelling from before the app was renamed DayFlow.

- `schedule.json`: your blocks
- `settings.json`: Meetings reminders, volume, and other preferences
- `block-types.json`: your block types and their reminders
- `sounds.json`: the list of your sound clips; the clips themselves are files in `~/Music/DayFlow Clips` (inside the data folder instead when you run with `--user-data-dir`). Clips from earlier versions, in `sounds/`, move there on first launch.
- `backups/`: your schedule, types and settings as they were before each import (and before upgrading)
- `window-state.json`: last mode and where the mini timer sits
- `google-credentials.json`: the OAuth client file you imported
- `google-token.json`: your Google sign-in (delete it or click **Disconnect** to sign out)

## Build an installer

```bash
npm run dist
```

This produces a `.dmg` (macOS), an `.exe` installer (Windows) or an AppImage (Linux) in `dist/`. `npm run dist:legacy` adds the macOS 11 builds in `dist/legacy/`. Build on the OS you're targeting. On macOS it makes two DMGs, one for Apple Silicon and one for Intel, with a free ad-hoc signature; signing with an Apple Developer ID and notarizing would remove the Open Anyway step.

The icon is drawn in `assets/icon.svg` (the app) and `assets/tray.svg` / `assets/trayTemplate.svg` (the tray; macOS tints the template version for light and dark menu bars). After editing them, `npm run icons` renders the PNGs and `icon.icns`, using Electron itself.

## Notes by platform

- **macOS**: the first reminder triggers a notification permission prompt. Notifications come from DayFlow both with `npm start` and in the built app, since they share the bundle id `com.dayflow.app`. Activity Monitor still lists the helper processes as "Electron Helper"; renaming those would mean rebuilding the app bundle the way the installer does.
- **Windows**: if notifications don't appear, check that Focus Assist / Do Not Disturb is off.
- **Linux**: notifications need a notification daemon (all major desktops have one). "Open at login" isn't wired up on Linux; add DayFlow to your desktop's autostart instead.

## Project layout

```
src/main.js              scheduler, notifications, window modes, tray, storage, sounds,
                         export/import, Google Calendar
src/preload.js           the small API the windows are allowed to call
src/renderer/index.html  the full window
src/renderer/tokens.css  design system: colours, type, spacing, radii, shadows, motion (all windows)
src/renderer/components.css  design system: buttons, fields, switches, tabs, cards, toasts, dialogs
src/renderer/styles.css  the full window's layout
src/renderer/renderer.js Today dial and agenda, schedule editor, settings, sound playback,
                         import preview
src/renderer/mini.html   the mini timer (mini.css, mini.js)
src/renderer/card.html   a reminder card (card.css, card.js)
scripts/dev.js           npm start: builds .dev/DayFlow.app on macOS and runs it
scripts/build-icons.js   npm run icons: renders assets/*.svg to PNG and .icns
assets/                  tray and app icons (SVG sources and rendered files)
assets/sounds/           the 18 built-in reminder sounds (MP3; 17 from Mixkit, plus Class bell),
                         also bundled in the iPhone app
ios/                     DayFlow for iPhone (SwiftUI); see ios/README.md
```

## Ideas for later

- Pull from more than one calendar (change `calendars/primary` in `src/main.js`, or add a picker).
- A "snooze" or "extend this block 10 minutes" action on the end-of-block reminder.
- Several saved schedules you can switch between (for example a lighter Friday) without going through files.
- "+10 min" and "skip" buttons on the mini timer.
- A colour per block type on the dial, the agenda and the mini timer.
- Per-block overrides for a type's reminders ("this Focus block gets 15 min preparation").
