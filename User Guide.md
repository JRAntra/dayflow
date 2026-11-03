# DayFlow User Guide

DayFlow runs your day in blocks. You set up the phases of your day once (deep work, lunch, admin, a walk), and DayFlow reminds you to get ready for each one, tells you when it starts, warns you before it ends, and lets you know when time's up. It can also remind you about meetings from Google Calendar.

Everything stays on your Mac. The only time DayFlow goes online is to talk to Google, and only if you connect your calendar.

## Contents

1. [Install DayFlow](#1-install-dayflow)
2. [A quick tour](#2-a-quick-tour)
3. [Today](#3-today)
4. [Schedule: planning your blocks](#4-schedule-planning-your-blocks)
5. [Block types and their reminders](#5-block-types-and-their-reminders)
6. [How reminders work](#6-how-reminders-work)
7. [Reminder cards](#7-reminder-cards)
8. [Sounds](#8-sounds)
9. [Meetings from Google Calendar](#9-meetings-from-google-calendar)
10. [Window modes: Full, Mini timer and Backstage](#10-window-modes-full-mini-timer-and-backstage)
11. [The menu bar icon](#11-the-menu-bar-icon)
12. [General settings](#12-general-settings)
13. [Export, import and backups](#13-export-import-and-backups)
14. [Your data](#14-your-data)
15. [Troubleshooting](#15-troubleshooting)
16. [Quick reference](#16-quick-reference)

---

## 1. Install DayFlow

### Pick the right download

Download DayFlow from the [Releases page](https://github.com/JRAntra/dayflow/releases). To choose the file, open the Apple menu → **About This Mac**. It shows your macOS version and either *Chip: Apple M…* (Apple Silicon) or *Processor: Intel*.

| Your Mac | macOS 13 Ventura or later | macOS 11 Big Sur or 12 Monterey |
|---|---|---|
| Apple Silicon | `DayFlow-<version>-arm64.dmg` | `DayFlow-<version>-macos11-arm64.dmg` |
| Intel | `DayFlow-<version>-x64.dmg` | `DayFlow-<version>-macos11-x64.dmg` |

The `macos11` files are the same app built for older macOS versions. If your Mac runs macOS 13 or later, use the regular file: it's built on a newer, still-maintained foundation.

### Install it

1. Open the DMG and drag **DayFlow** onto **Applications**.
2. Open DayFlow from Applications. The beta isn't notarized by Apple yet, so macOS says it can't verify the app. Click **Done** (or **OK** on older macOS).
3. Open **System Settings → Privacy & Security** (on macOS 11 and 12: **System Preferences → Security & Privacy → General**). Find the message about DayFlow, click **Open Anyway**, and confirm. You only do this once.
4. When macOS asks whether DayFlow may send notifications, click **Allow**.

### What you see first

DayFlow opens with a sample weekday schedule so you can see how it works:

| Time | Block |
|---|---|
| 9:00 – 9:20 | Plan the day |
| 9:20 – 11:30 | Deep work |
| 11:30 – 12:00 | Email and messages |
| 12:00 – 1:00 | Lunch |
| 1:00 – 3:00 | Focus block |
| 3:00 – 3:15 | Walk and stretch |
| 3:15 – 5:00 | Admin and follow-ups |
| 5:00 – 5:15 | Shut down for the day |

Change or delete any of it in [Schedule](#4-schedule-planning-your-blocks).

DayFlow keeps running after you close its window. A small **sun-over-water icon** appears in the menu bar, with the minutes left in the current block next to it. To quit, click that icon and choose **Quit DayFlow**.

---

## 2. A quick tour

The window has a sidebar on the left:

- **Today**: what's happening now and the rest of today.
- **Schedule**: your weekly plan of blocks.
- **Settings**: block types, meetings, sounds, calendar, and general options, each in its own tab.
- **Switch to: Mini timer / Backstage**: switch to a smaller way of running DayFlow (see [Window modes](#10-window-modes-full-mini-timer-and-backstage)). The key shown underneath, **⌃⌥D**, does the same from anywhere.

DayFlow follows your Mac's light or dark appearance. If you've turned on **Reduce Motion** or **Reduce Transparency** in System Settings → Accessibility, DayFlow drops its animations or translucency to match.

---

## 3. Today

### The dial

The dial shows today's blocks in a ring around it, from your first block to your last.

- **Teal arcs** are your blocks. Finished blocks fade, and the current one is thicker with a soft glow.
- **Amber arcs** around the outside are meetings from Google Calendar.
- **The hand** points to now and moves smoothly through the day.

In the middle you'll see:

- **The block type** of the current block, as a small label (for example *Focus*).
- **The block's name.**
- **A countdown** to the end of the current block. The digits roll as they change.
- **A note**: when the block ends and what's next.

Between blocks the middle says **Free time** and counts down to the next block. When the day's blocks are over it says **Done for today**. If nothing is planned for today, it says so and offers **Plan your blocks**.

### Today's flow

On the right is a timeline of today's blocks and meetings in order. Each row shows the start time, the name, the block type (or *Meeting*), and when it ends. Finished items fade, and the current block sits on a raised card. When one block hands over to the next, the highlight slides down to the new one.

Meetings with a video link have a **Join** button until they end.

---

## 4. Schedule: planning your blocks

**Schedule** is your weekly plan. Each row is one block:

| Part | What it does |
|---|---|
| **Starts / Ends** | The block's start and end times. |
| **Name** | What happens in the block. |
| **Type** | The small menu under the name. The type decides the block's reminders (see [Block types](#5-block-types-and-their-reminders)). **New type…** at the bottom of the menu takes you to Settings → Block types. |
| **Length** | Worked out for you, for example *2 h 10 min*. |
| **Repeats on** | The days of the week, S M T W T F S. Click a day to turn it on or off. |
| **×** | Removes the block. |

### Adding blocks

Click **＋ Add block**. The new block starts where your latest block ends, lasts 30 minutes, and copies that block's days and type. Then type its name and adjust the times.

### Saving

As soon as you change anything, a bar appears at the bottom: **Unsaved changes · Discard · Save schedule**.

- **Save schedule** saves your changes and updates reminders straight away.
- **Discard** puts the schedule back to how it was last saved.

DayFlow checks each block before saving. A block needs a name, an end time after its start time, and at least one day. A block with a problem gets a red outline and a message under it. Overlapping blocks are allowed, but the row tells you which block it overlaps.

### Import, export and backups

The **Import…**, **Export…** and **Backups** buttons at the top are explained in [Export, import and backups](#13-export-import-and-backups).

---

## 5. Block types and their reminders

Every block has a **type**, and the type decides the block's reminders. Change a type once and every block of that type follows.

Open **Settings → Block types**. Your types are listed on the left, each with a short summary (for example *Prep 10 min · 3 of 4 on*). Click one to edit it on the right.

### The starter types

DayFlow starts with **Default**, **Focus**, **Break**, **Admin** and **Meal**.

**Default** is special in two ways:

- **It can't be deleted** (the **−** button is greyed out for it), though you can rename it and change its reminders.
- **It's where blocks go when they have nowhere else.** New blocks get Default unless they copy the block above, and deleting another type moves its blocks to Default.

### Adding, renaming and deleting types

- **＋** under the list adds a type called *New type* and selects its name so you can type over it.
- **Rename a type** by editing the name at the top of its details. Names must be unique (ignoring capitals) and up to 40 characters. Renaming keeps every block that uses the type.
- **−** deletes the selected type. If blocks use it, DayFlow asks first ("3 blocks use Focus. They'll move to Default.").
- **"Used by N blocks"** next to the name shows how many blocks use the type.

### The four reminders

Each type has four reminders:

| Reminder | When | Example notification |
|---|---|---|
| **Start preparation** | A set number of minutes before the block starts | *In 10 min: Deep work. Get ready. It starts at 9:20 AM.* |
| **Start** | When the block starts | *Now: Deep work. Plan the day is done. Deep work runs until 11:30 AM.* |
| **Heads-up** | A set number of minutes before the block ends | *5 min left: Deep work. Next: Email and messages at 11:30 AM.* |
| **Time's up** | When the block ends | *Time's up: Shut down for the day. That was your last block today.* (or *Free until Lunch at 12:00 PM.* when there's a gap before the next block) |

Each reminder row has:

- **A switch** to turn the reminder on or off. A switched-off row is dimmed.
- **A − 5 + stepper** (Start preparation and Heads-up only): how many minutes ahead, from 1 to 60. Click − or +, or type a number.
- **A sound menu.** Picking a sound plays it straight away, so you can hear it as you choose.
- **Fade in**: when pressed (it turns teal), the sound starts quiet and grows to your full volume instead of starting at full volume. Good for gentle reminders.
- **▶** plays the sound again, with Fade in if it's on.

Changes save automatically; "Block types saved" appears under the list.

### Starting values for new types

| Reminder | On? | Minutes | Sound |
|---|---|---|---|
| Start preparation | Off | 5 | Fairy bell |
| Start | On | | Elevator bells |
| Heads-up | On | 5 | Soft bell |
| Time's up | On | | Hour bells |

---

## 6. How reminders work

Each reminder shows a macOS notification and, if [reminder cards](#7-reminder-cards) are on, a DayFlow card. It also plays its sound, unless you've turned sounds off.

### When reminders don't fire

- A **heads-up** is skipped for a block that isn't longer than the heads-up time. A 5-minute block doesn't get a "5 min left" warning the moment it starts.
- A **start preparation** reminder that would land before midnight is skipped. DayFlow plans one day at a time.
- Reminders only fire on the days a block repeats on.

### When reminders land at the same moment

With back-to-back blocks, reminders often land together. Say Deep work ends at 11:30 with a 5-minute heads-up, and Email starts at 11:30 with 5 minutes of preparation:

- **At 11:25**, Deep work's heads-up and Email's preparation become **one** notification, *5 min left: Deep work. Next: Email and messages at 11:30 AM.*, playing **Email's preparation sound**.
- **At 11:30**, Deep work's time's up and Email's start become **one** notification, *Now: Email and messages. Deep work is done.*, playing **Email's start sound**.

The rule is simple: **the block that's coming up wins**. If the incoming block has that reminder switched off, the outgoing block's reminder plays as normal instead, for example *Time's up: Deep work. Email and messages starts now.*

### Clicking a notification

Clicking a block reminder opens DayFlow's window, and clicking a meeting reminder opens its video link. Either way, the sound stops and the matching reminder card closes.

---

## 7. Reminder cards

Alongside each notification, DayFlow shows a **card** at the top right of your screen, like Google Calendar's reminders. Unlike a notification, a card **stays until you deal with it**.

- Cards float over full-screen apps and on every desktop (Space).
- **They never take focus**, so whatever you're typing keeps going.
- Each card shows the block type (or *Meeting*), the reminder title, and a line about timing.

### Buttons

| Reminder | Buttons |
|---|---|
| Start preparation, Heads-up | **Snooze ▾** and **Got it** |
| Start, Time's up | **Got it** |
| Meeting, before it starts | **Snooze ▾**, **Got it**, and **Join** (or **Open in Calendar** if there's no video link) |
| Meeting, starting now | **Got it**, and **Join** (or **Open in Calendar**) |

- **Snooze ▾** offers 1, 5 or 10 minutes. It only lists times that still come before the moment the reminder is about, so you can't snooze past the start of the block. A snoozed card comes back with an updated title, for example *In 2 min: Coffee break*.
- **Got it** closes the card.
- **Join** opens the meeting's video link. **Open in Calendar** opens the event in Google Calendar.
- **Clicking the card's text** opens DayFlow's window.

Any button stops the sound. Closing a card also clears its notification from Notification Center, and clicking the notification closes the card.

### Several at once

Up to three cards show at once, newest on top. If more are waiting, the bottom card says **+N more**, and the next one slides into place as you close the others.

### Turning cards off or pausing them

- **Settings → General → Show reminder cards** turns cards off. You still get notifications.
- **Close cards on their own** can make cards close after **1 min** or **5 min**. The default is **Never**.
- The menu bar icon's **Pause reminder cards for 1 hour** hides cards for an hour, for example during a presentation. While paused, the menu says *Resume reminder cards (paused until 3:15 PM)*.

macOS doesn't let apps see whether **Focus** or **Do Not Disturb** is on. Notifications respect Focus, but cards can't, so pause or turn them off when you need quiet.

---

## 8. Sounds

### Built-in sounds

Every reminder can use any of DayFlow's 18 built-in sounds, each 4 to 9 seconds long:

> Soft bell · Echo bells · Fairy bell · Magic bell · Mystery bells · Magic glitter · Fantasy bells · Flute · Elevator bells · Elegant chime · Airport ding · Classic door bell · Doorbell tone · Hour bells · Class bell · Sleigh bells · Classic alarm · Rooster crowing

Pick sounds per reminder in [Block types](#5-block-types-and-their-reminders) and [Meetings](#9-meetings-from-google-calendar).

### Settings → Sounds

- **Play a sound with each reminder**: turn this off to mute every reminder sound. Notifications and cards still appear.
- **Volume**: one slider for all DayFlow sounds. Previews play at the slider's level.
- Only **one sound plays at a time**: a new reminder cuts off one that's still playing.

### Adding your own sounds

Click **Add a sound clip…** and choose a file.

- **Formats:** mp3, wav, m4a, aac or ogg.
- **Limits:** up to 5 MB and 30 seconds. DayFlow tells you if a file is too big, too long, or can't be played.
- DayFlow **copies** the clip into its own data folder, so moving or deleting your original doesn't matter.
- Your clips appear under **Your clips** in every sound menu, and in the list in Settings → Sounds. **▶** plays one, and **Remove** deletes it. Any reminder that used a removed clip goes back to its starting sound.
- Adding the same audio twice keeps one copy. A different clip with a name you already have is renamed, for example *Gong (2)*.

---

## 9. Meetings from Google Calendar

### Connect your calendar (one time, about 5 minutes)

Google asks every app that reads a calendar to have its own sign-in client. Because DayFlow runs only on your Mac, you create one for yourself in your own Google Cloud project. It's free.

1. Go to [console.cloud.google.com](https://console.cloud.google.com/) and create a project (any name, such as "DayFlow").
2. Open **APIs & Services → Library**, search for **Google Calendar API**, and click **Enable**.
3. Open **APIs & Services → OAuth consent screen** (called **Google Auth Platform** in newer consoles).
   - User type: **External**, or Internal if you use Google Workspace and only you will use it.
   - Fill in the app name and your email.
   - Under **Audience / Test users**, add your own Google account.
4. Open **Credentials → Create credentials → OAuth client ID**, choose **Desktop app**, click **Create**, then **Download JSON**.
5. In DayFlow, go to **Settings → Calendar**, click **Choose file**, and select the JSON you downloaded.
6. Click **Connect**. Your browser opens; sign in and allow access. Google warns that the app isn't verified; that's expected for a personal project, so click **Continue**.

DayFlow only asks to **read** your calendar. It syncs today's events every 5 minutes; **Sync now** syncs straight away. **Disconnect** signs DayFlow out of Google.

**Staying signed in:** while your consent screen is in **Testing** status, Google signs DayFlow out after 7 days and DayFlow asks you to connect again. To avoid that, click **Publish app** on the consent screen. You don't need Google's verification for personal use.

### Which events

DayFlow uses today's timed events from your main calendar. All-day events, cancelled events, and events you've declined are skipped. Meetings appear in amber on the dial and in Today's flow, with a **Join** button when there's a Google Meet or other video link.

### Meeting reminders

**Settings → Meetings** has two reminders, each with a switch, a sound menu, Fade in, and ▶:

| Reminder | Starting value |
|---|---|
| **Before it starts** | On, 5 minutes before, Airport ding |
| **Starting now** | On, Elegant chime |

---

## 10. Window modes: Full, Mini timer and Backstage

DayFlow can run three ways. Switch with the buttons at the bottom of the sidebar, the menu bar icon, or **⌃⌥D** from any app, which cycles **Full → Mini timer → Backstage**.

### Full

The full window described in this guide.

**Closing the full window** doesn't quit DayFlow. It switches to whichever of Mini timer or Backstage you used last, so DayFlow keeps reminding you.

### Mini timer

A small floating pill that always shows what you're doing:

- **The current block** and a countdown: minutes and seconds, or hours and minutes with a small *h* when more than an hour is left.
- **A progress bar** for how far through the block you are.
- **What's next**: *Next: Lunch*, or *Meeting in 4 min* when a meeting comes before the next block.
- It **turns amber** during the current block's heads-up minutes, with one gentle pulse as they begin.
- **Between blocks** it says **Free** and counts down to the next block, or **Get ready** once the next block's preparation time has begun. At the end of the day it says **Done for today**.

Using it:

- **Drag** it anywhere. It remembers the spot, and if that spot is off-screen later (say you unplugged a monitor), it moves back to the top-right corner.
- **Double-click** it to open the full window.
- **Right-click** it for **Open full window**, **Switch to Backstage**, **Always on top** (on by default) and **Quit DayFlow**.
- It's slightly see-through until you point at it, and it stays visible over full-screen apps and on every desktop.

### Backstage

No window and no Dock icon: DayFlow lives only in the menu bar. Reminders, sounds and cards work exactly as usual. Clicking a block reminder opens the full window for a quick look, and closing it puts you back in Backstage.

### Which mode DayFlow opens in

DayFlow reopens in the mode you left it in. If you've set it to open when you log in, it always starts in Backstage.

---

## 11. The menu bar icon

The sun-over-water icon in the menu bar shows the minutes left in the current block (for example *23m*). Its menu has:

- **What's on now**: for example *Deep work, 23 min left*, or *No block right now*.
- **Full window / Mini timer / Backstage (tray only)**: the current mode is ticked.
- **Pause reminder cards for 1 hour**, or **Resume reminder cards** while paused.
- **Sync calendar now.**
- **Quit DayFlow.**

---

## 12. General settings

**Settings → General**:

| Setting | What it does |
|---|---|
| **Show reminder cards** | Turns [reminder cards](#7-reminder-cards) on or off. |
| **Close cards on their own** | *Never* (default), *After 1 min*, or *After 5 min*. |
| **Send a test reminder** | Shows a card and a notification and plays Default's start sound, so you can check everything works. |
| **Press ⌃⌥D anywhere…** | Turns the mode-switching shortcut on or off. If another app already uses ⌃⌥D, DayFlow says so and the shortcut stays off. |
| **Open DayFlow when I log in** | Starts DayFlow, in Backstage, every time you log in. |

---

## 13. Export, import and backups

### Export

**Schedule → Export…** saves a `.json` file containing:

- your blocks;
- the block types they use, with all four reminders each;
- your Meetings reminders and volume;
- any of your own sound clips those reminders use (built into the file, so it works on another Mac).

It **never** includes your Google sign-in. Use exports to back up your plan, move it to another Mac, or share a schedule with someone.

### Import

**Schedule → Import…** shows a preview before anything changes:

- *This will replace your 8 blocks with 6 blocks from file.json*, followed by the incoming blocks with their times, types and days.
- Any new types the file adds, for example *Adds 1 new block type: Deep reading*.
- **Also apply reminder and sound settings from this file**, on by default. Turn it off to keep your own reminders and sounds and take only the blocks.
- Anything that can't be used, for example a sound clip that's damaged or too long. Those reminders fall back to their starting sound.
- A warning if you have unsaved schedule changes, which the import would replace.

Click **Replace schedule** to import, or **Cancel**.

How the file's types are matched to yours:

- **The file's Default always matches your Default**, even if either has been renamed.
- Other types match **by name**, ignoring capitals. A type you already have keeps your reminders unless the settings switch is on. A type you don't have is added.
- Your other types are left alone.

Files from earlier versions of DayFlow import too; they're converted automatically.

### Backups and undo

Before every import, DayFlow saves your current schedule, types and settings to its **backups** folder, keeping the newest ten. **Schedule → Backups** opens that folder in Finder.

**To undo an import**, import the most recent backup with the settings switch on. That restores your schedule and puts your block types back exactly as they were.

---

## 14. Your data

DayFlow keeps everything in `~/Library/Application Support/Dayflow` on your Mac. In Finder, choose **Go → Go to Folder…** and paste that path.

| File or folder | What's in it |
|---|---|
| `schedule.json` | Your blocks |
| `block-types.json` | Your block types and their reminders |
| `settings.json` | Meetings reminders, volume, and other preferences |
| `sounds.json` and `sounds/` | The sound clips you added |
| `backups/` | Backups taken before each import or upgrade |
| `window-state.json` | Your last mode and where the mini timer sits |
| `google-credentials.json` | The Google client file you imported |
| `google-token.json` | Your Google sign-in; **Disconnect** deletes it |

**Upgrading DayFlow** keeps your data. If a new version changes how something is stored, DayFlow first saves your old setup to `backups/`, then converts it, so nothing you hear or see changes unexpectedly.

**To uninstall**, quit DayFlow, drag it from Applications to the Trash, and delete the folder above if you also want to remove your data.

---

## 15. Troubleshooting

**macOS says DayFlow can't be opened or can't be verified.**
The beta isn't notarized by Apple yet. Use **Open Anyway** in System Settings → Privacy & Security, as in [Install](#install-it). It's needed once per install.

**No notifications appear.**
Check **System Settings → Notifications → DayFlow** and make sure notifications are allowed, and that **Focus / Do Not Disturb** is off. Reminder cards appear even when notifications are off.

**No sound.**
Check **Settings → Sounds**: *Play a sound with each reminder* must be on and the volume above zero. Also check your Mac's volume and output device. Each reminder's own switch must be on, and its sound will play when you pick it in the menu.

**A reminder didn't come.**
Check that the block repeats on today in Schedule, that you clicked **Save schedule**, and that the reminder is switched on for the block's type. Remember a heads-up is skipped for blocks shorter than the heads-up time.

**⌃⌥D doesn't do anything.**
Another app may be using that shortcut. Settings → General says so if it is; switch modes from the sidebar or the menu bar icon instead.

**I only see a small floating timer.**
That's the Mini timer. Double-click it for the full window.

**I can't find DayFlow.**
In Backstage, DayFlow has no window or Dock icon. Click the sun icon in the menu bar.

**Google Calendar says access has expired.**
Click **Connect** in Settings → Calendar to sign in again. To stop it happening every 7 days, publish your Google consent screen, as described in [Connect your calendar](#connect-your-calendar-one-time-about-5-minutes).

**Opening DayFlow does nothing.**
Only one copy of DayFlow runs at a time; opening it again brings the running copy forward. If you just quit it, wait a moment and try again.

---

## 16. Quick reference

| To… | Do this |
|---|---|
| See what's on now | **Today**, the Mini timer, or the menu bar icon |
| Plan your week | **Schedule**, then **Save schedule** |
| Change a block's reminders | Change its **type** in Schedule, or edit the type in **Settings → Block types** |
| Hear a sound | Pick it in a sound menu, or click **▶** |
| Make a sound gentler | Press **Fade in** next to it |
| Snooze a reminder | **Snooze ▾** on its card |
| Silence cards for a while | Menu bar icon → **Pause reminder cards for 1 hour** |
| Switch Full / Mini / Backstage | **⌃⌥D**, the sidebar, or the menu bar icon |
| Get reminders for meetings | **Settings → Calendar**, then **Settings → Meetings** |
| Back up or share your plan | **Schedule → Export…** |
| Undo an import | **Schedule → Backups**, then import the newest backup |
| Quit | Menu bar icon → **Quit DayFlow** |
