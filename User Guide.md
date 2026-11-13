# DayFlow User Guide

DayFlow runs your day in blocks and events. You set up your week once: **blocks** for the phases of your day (deep work, lunch, admin, a walk), and **events** for things that happen at one moment (take medicine, drink water every 30 minutes). DayFlow reminds you to get ready for each block, tells you when it starts, warns you before it ends, and lets you know when time's up; an event rings once, at its time, and you check it off when it's done. It can also remind you about meetings from Google Calendar.

Everything stays on your Mac. The only time DayFlow goes online is to talk to Google, and only if you connect your calendar.

There's also a beta of **DayFlow for iPhone**. Sections 1 to 15 describe the Mac app; [DayFlow on iPhone](#16-dayflow-on-iphone) covers what's different on the phone.

## Contents

1. [Install DayFlow](#1-install-dayflow)
2. [A quick tour](#2-a-quick-tour)
3. [Today](#3-today)
4. [Schedule: planning your events and blocks](#4-schedule-planning-your-events-and-blocks)
5. [Block types and their reminders](#5-block-types-and-their-reminders)
6. [How reminders work](#6-how-reminders-work)
7. [Reminder cards](#7-reminder-cards)
8. [Sounds](#8-sounds)
9. [Meetings from Google Calendar](#9-meetings-from-google-calendar)
10. [The window and the Mini timer](#10-the-window-and-the-mini-timer)
11. [The menu bar icon](#11-the-menu-bar-icon)
12. [General settings](#12-general-settings)
13. [Your data](#13-your-data)
14. [Troubleshooting](#14-troubleshooting)
15. [Quick reference](#15-quick-reference)
16. [DayFlow on iPhone](#16-dayflow-on-iphone)

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

DayFlow starts with an empty schedule and one block type, **Default**. Today and Schedule offer **Add a sample day**, eight weekday blocks, so you can see how it works:

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

Change or delete any of it in [Schedule](#4-schedule-planning-your-events-and-blocks), or skip it and add your own.

DayFlow keeps running after you close its window, and its Dock icon goes until you open the window again. A small **sun-over-water icon** appears in the menu bar, with the minutes left in the current block next to it. To quit, choose **Quit DayFlow** at the bottom of the sidebar, press **⌘Q**, or click the menu bar icon and choose **Quit DayFlow**. To silence it without quitting, see [Turning reminders off](#turning-reminders-off).

---

## 2. A quick tour

The window has a sidebar on the left:

- **Today**: what's happening now and the rest of today.
- **Schedule**: your weekly plan of blocks.
- **Settings**: block types, meetings, sounds, calendar, and general options, each in its own tab.
- **Mini timer**: a switch that shows a small floating countdown (see [The window and the Mini timer](#10-the-window-and-the-mini-timer)). The key shown underneath, **⌃⌥D**, opens or closes the window from any app.

DayFlow follows your Mac's light or dark appearance. If you've turned on **Reduce Motion** or **Reduce Transparency** in System Settings → Accessibility, DayFlow drops its animations or translucency to match.

---

## 3. Today

### The dial

The dial shows today's blocks and events in a ring around it, from the first to the last.

- **Teal arcs** are your blocks. Finished blocks fade, and the current one is thicker with a soft glow.
- **Dots** on the ring are events, gold once you've checked them off.
- **Amber arcs** around the outside are meetings from Google Calendar.
- **The hand** points to now and moves smoothly through the day.

In the middle you'll see:

- **The block type** of the current block, as a small label (for example *Focus*).
- **The block's name.**
- **A countdown** to the end of the current block. The digits roll as they change.
- **A note**: when the block ends and what's next.

Between blocks the middle says **Free time** and counts down to the next block. When the day's blocks are over it says **Done for today**. If nothing is planned for today, it says so and offers **Plan your blocks**.

### Today's flow

On the right is a timeline of today's events, blocks and meetings in order. Each row shows the start time, the name, the block type (or *Event*, *Repeated event* or *Meeting*), and when it ends. Finished items fade, and the current block sits on a raised card. When one block hands over to the next, the highlight slides down to the new one.

Meetings with a video link have a **Join** button until they end.

### Checking off events

Each event in Today's flow has a round **check** on its left. Click it when you've done it, at any time that day, even before it rings:

- The row turns **gold** with a star, and says *done*. Its dot on the dial turns gold too.
- A **cheer-up** pops up for a moment at the top: *Nice! 3 of 6 done today*, with a ring filling up and your streak. It goes by itself, or click it.
- If its time hasn't come yet, it won't ring today. Click the check again to uncheck it, and it rings after all.
- An event's [reminder card](#7-reminder-cards) has **✓ Done**, which checks it off from the card.

Next to the date, **★ 3 of 6** counts today's events done so far, and **🔥 5** is your streak.

Only events can be checked off. Blocks are time you spend, not tasks.

### Your streak

Your **streak** is how many days in a row you've checked off at least **80%** of that day's events. For example, 4 of 5 counts, and 3 of 4 (75%) doesn't.

- Today joins the streak once it reaches 80%. Until then, the streak counts up to yesterday.
- Events you [skipped](#skipping-for-today) don't count towards the day.
- A day with no events, a weekend with nothing planned say, is passed over: it doesn't break the streak.
- Checks and the streak stay on this Mac. They aren't in export files, and the iPhone keeps its own.

### Skipping for today

Every event and block in Today's flow has a **switch** on the right. Turn it off to **skip it today**: it's struck through and greyed out, and its reminders don't ring today. A skipped block also leaves the dial and the countdown. Turn the switch back on to bring it back.

Skipping lasts only for that day: everything is back the next morning. One event of a [repeat](#repeated-events) skips just that one time.

---

## 4. Schedule: planning your events and blocks

**Schedule** is your weekly plan. Each row is an **event** or a **block**:

- An **event** happens at one time and rings once, for example *Take medicine · 9:00 PM*.
- A **block** lasts from a start time to an end time and has four reminders, for example *Deep work · 9:20 – 11:30 AM*.

| Part | What it does |
|---|---|
| **Starts / Ends** | The start and end times. An event has only a time; its Ends shows **—**. |
| **Name** | What happens. |
| **Event · Block** | Switches between the two. A block that becomes an event drops its end and its reminders, and rings with its Start sound; switching back restores what it had. |
| **Type** | A block's type, in the small menu under the name. The type decides the block's reminders (see [Block types](#5-block-types-and-their-reminders) and [A block's reminders](#a-blocks-reminders)). **New type…** at the bottom of the menu takes you to Settings → Block types. Events have no type. |
| **Length** | Worked out for you, for example *2 h 10 min*. |
| **Reminders ▸** / **Alarm ▸** | Shows the block's reminders, or the event's alarm, under the row. |
| **Repeats on** | The days of the week, S M T W T F S. Click a day to turn it on or off. |
| **×** | Removes it. |

### Adding events and blocks

Click **＋ Add…** and choose **Event**, **Repeated event…** or **Block**. A new event or block starts where your latest one ends and copies its days (a new block lasts 30 minutes and takes its type too). Then type its name and adjust the times. A repeated event opens its own window: see [Repeated events](#repeated-events).

### Saving

Changes **save as you go**: a moment after you stop typing, or straight away when you click a day, a switch or a menu. Reminders follow at once. Each save shows **Saved · Undo** at the bottom; **Undo** puts the schedule back as it was before that change.

DayFlow checks each row. It needs a name, at least one day and, for a block, an end time after its start time. A row with a problem isn't saved until it's fixed: it gets a red outline and a message under it, and keeps its last saved version meanwhile (a new row isn't saved at all yet). Overlapping blocks are allowed, but the row tells you which block it overlaps.

### Events

An **event** is for something that happens at one moment rather than lasting, such as *Take medicine · 9:00 PM*. It rings **once**, at its time: *Now: Take medicine · It's 9:00 PM*, or *…during Lunch* when a block is running. There's no heads-up before it.

- **Alarm ▸** shows its one reminder: its sound (or [several](#several-sounds-for-one-reminder)), **Fade in** and ▶. New events start with your Default type's Start sound.
- On your iPhone, every event rings as an **alarm**, through silent mode and Focus (see [Ringing even on silent](#ringing-even-on-silent)). On the Mac it's a reminder with a card, like any other.
- On Today, an event is a **dot** on the dial and has a [check](#checking-off-events) in Today's flow. It's never "the current block", though it can be what's next.
- An event never counts as overlapping a block, and its reminder is never merged with a block's: at 1:00 PM you get the event's and the block's, each with its own sound.
- **Moments** from earlier versions (blocks with only a start time) became events. Each kept its Start reminder's sound and fade (or Start preparation's, if only that was on).

### Repeated events

A **repeated event** makes several events at once: *Drink water* every 30 minutes from 9:00 AM to 5:00 PM is 17 events. Choose **＋ Add… → Repeated event…** and fill in:

- **Name**, **First at**, **Last at** and **Every** (minutes, 1 to 720). *Last at* is included when the gap lands on it exactly: every 45 minutes from 9:00 to 5:00 ends at 4:30.
- **Repeats on**, and the **Alarm** sound(s) and Fade in that every event shares.

It shows how many events it makes as you type. **Create** then asks first, *Create 17 "Drink water" events?*, with their times, so you can catch a typo. If they'd need more alarms a week than your iPhone sets ahead (48), it says so: open DayFlow on your iPhone at least every couple of days. A repeat can make at most 200 events.

They're saved straight away, like any change. Each one is an event of its own in Today (you check off or skip each time on its own), but they stay tied to their repeat:

- Their rows show **↻** and the rule, *Every 30 min, 9:00 AM – 5:00 PM*, and their time, name and days can't be changed one by one.
- **Edit repeat…** changes all of them. Saving makes the events again from the new rule (with the same check first): change *Every* from 30 to 45, and the 17 events become 11. Today's checks and skips stay on the times it still has.
- **Edit only this one** takes the event out of its repeat. It becomes an event of its own that you can change, and later changes to the repeat leave it alone.
- **×** asks: **Delete all 17 events**, or **Delete only this one**.
- **Group repeats**, above the list, shows each repeat as one row: *Drink water · 17 events · Every 30 min, 9:00 AM – 5:00 PM*.

### A block's reminders

A block's reminders always come from its [type](#5-block-types-and-their-reminders). **Reminders ▸** under the row shows them, read-only (▶ still plays them), with **Edit Focus…** to open the type in Settings. Changing a type changes every block of that type. For a block that should sound different, choose another type, or **New type…** in the Type menu.

Earlier versions let a block have **Own reminders**. Each such block became a type of its own, named after it (*Run*, or *Run (2)* if that name was taken), with the same reminders.

### Ring on silent (iPhone)

At the bottom of **Reminders ▸**, **Ring on silent (iPhone)** sets a block to [ring even on silent](#ringing-even-on-silent) on your iPhone, where each of its reminders rings as an alarm. It's saved straight away, and an alarm clock ⏰ marks the block in the schedule and in Today's flow. Reminders on the Mac don't change: they already play whatever your Mac's Focus, and only the Mac's volume or mute silences them.

---

## 5. Block types and their reminders

Every block has a **type**, and the type decides the block's reminders. Change a type once and every block of that type follows.

Open **Settings → Block types**. Your types are listed on the left, each with a short summary (for example *Prep 10 min · 3 of 4 on*). Click one to edit it on the right.

### Default

DayFlow starts with one type, **Default**. Add another when you want a block to sound different: a quieter Break, say, or a Focus with an earlier heads-up.

**Default** is special in two ways:

- **It can't be deleted** (the **−** button is greyed out for it), though you can rename it and change its reminders.
- **It's where blocks go when they have nowhere else.** New blocks get Default unless they copy the block above, and deleting another type moves its blocks to Default.

### Adding, renaming and deleting types

- **＋** under the list adds a type called *New type* and selects its name so you can type over it.
- **Rename a type** by editing the name at the top of its details. Names must be unique (ignoring capitals) and up to 40 characters. Renaming keeps every block that uses the type.
- **−** deletes the selected type. If blocks use it, DayFlow asks first ("3 blocks use Focus. They'll move to Default.").
- **New type…** at the bottom of a block's Type menu, in Schedule, takes you here to add one.
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
- **Fade in**: when pressed (it turns teal), the sound starts quiet and grows to your full volume instead of starting at full volume. It starts at 10%, stays low for most of the fade (under half your volume at 10 seconds) and rises smoothly to full at 15 seconds. A sound shorter than that plays again and again until the fade is done, so a faded reminder rings for at least 15 seconds. Good for gentle reminders.
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

### Turning reminders off

To silence DayFlow without quitting, click **Turn off reminders…** under the dial on Today, or use the menu bar icon's **Turn off reminders** menu. Choose how long:

| Choice | Reminders come back |
|---|---|
| **For 1 hour** | An hour from now |
| **For 24 hours** | 24 hours from now |
| **Until I turn them on** | Only when you choose **Turn on**, even after restarting your Mac |

While reminders are off, nothing rings: no notifications, no sounds, no cards. Reminders that fall in that time are skipped, not delivered late. Today still shows your blocks, with *Reminders off until 3:15 PM · Turn on* under the dial, and the menu bar icon is crossed out. **Turn on** (on Today, or **Turn on reminders** in the menu bar icon's menu) brings them back straight away. DayFlow never sends a notification about being off, and a 1-hour or 24-hour stop ends quietly.

### Quitting DayFlow

Closing the window doesn't quit DayFlow (see [Window modes](#10-the-window-and-the-mini-timer)). To stop it completely, reminders included, use any of:

- **Quit DayFlow** at the bottom of the sidebar;
- **⌘Q** while the window is in front;
- the menu bar icon → **Quit DayFlow**;
- right-click the Mini timer → **Quit DayFlow**.

The first time you quit from the window, DayFlow explains once that reminders stop until you open it again. Open DayFlow from Applications to start again; with **Open at login** on, it also starts at your next login.

---

## 7. Reminder cards

Each reminder shows as a **card** at the top right of your screen, like Google Calendar's reminders, or as a macOS notification, whichever you choose in **Settings → General → Reminders show as** (Cards is the default). Unlike a notification, a card **stays until you deal with it**, and has Snooze, Join and Done.

- Cards float over full-screen apps and on every desktop (Space).
- **They never take focus**, so whatever you're typing keeps going.
- Each card shows the block type (or *Meeting*), the reminder title, and a line about timing.

### Buttons

| Reminder | Buttons |
|---|---|
| Start preparation, Heads-up | **Snooze ▾** and **Got it** |
| Start, Time's up | **Got it** |
| An event | **Got it** and **✓ Done** |
| Meeting, before it starts | **Snooze ▾**, **Got it**, and **Join** (or **Open in Calendar** if there's no video link) |
| Meeting, starting now | **Got it**, and **Join** (or **Open in Calendar**) |

- **Snooze ▾** offers 1, 5 or 10 minutes. It only lists times that still come before the moment the reminder is about, so you can't snooze past the start of the block. A snoozed card comes back with an updated title, for example *In 2 min: Coffee break*.
- **Got it** closes the card.
- **✓ Done** checks the event off: the card shows the cheer-up for a moment (*Great job! 2 of 6 done today*), then goes.
- **Join** opens the meeting's video link. **Open in Calendar** opens the event in Google Calendar.
- **Clicking the card's text** opens DayFlow's window.

Any button stops the sound.

### Several at once

Up to three cards show at once, newest on top. If more are waiting, the bottom card says **+N more**, and the next one slides into place as you close the others.

### Notifications instead, or pausing them

- **Settings → General → Reminders show as → Notifications** shows macOS notifications instead of cards. They follow Focus and go to Notification Center, without Snooze or Done.
- **Close cards on their own** can make cards close after **1 min** or **5 min**. The default is **Never**.
- To stop cards (and everything else) for a while, for example during a presentation, [turn reminders off](#turning-reminders-off) for 1 hour.

macOS doesn't let apps see whether **Focus** or **Do Not Disturb** is on. Notifications respect Focus, but cards can't, so choose Notifications, or [turn reminders off](#turning-reminders-off), when you need quiet.

---

## 8. Sounds

### Built-in sounds

Every reminder can use any of DayFlow's 18 built-in sounds, each 4 to 9 seconds long:

> Soft bell · Echo bells · Fairy bell · Magic bell · Mystery bells · Magic glitter · Fantasy bells · Flute · Elevator bells · Elegant chime · Airport ding · Classic door bell · Doorbell tone · Hour bells · Class bell · Sleigh bells · Classic alarm · Rooster crowing

Pick sounds per reminder in [Block types](#5-block-types-and-their-reminders), in an event's Alarm ▸, and in [Meetings](#9-meetings-from-google-calendar).

### Several sounds for one reminder

A reminder can have **more than one sound**, so a *Drink water* every 30 minutes doesn't get stale. Click its sound button (*Elevator bells ▾*) to open the list of sounds and check the ones you want. Clicking a checkbox plays that sound; ▶ beside each plays it too. One stays checked.

With several checked, the button says *3 sounds, shuffled*, and each time the reminder rings, **one is picked at random, never the one it played last**. ▶ on the reminder row plays a random one of them. Volume and Fade in apply to all of them.

This works for events (repeated ones included) and blocks' reminders (in their types). Meeting reminders keep one sound each. If you remove one of your clips, it drops out of any reminder that had other sounds too; a reminder left with none goes back to its starting sound.

### Settings → Sounds

- **Play a sound with each reminder**: turn this off to mute every reminder sound. Notifications and cards still appear.
- **Volume**: one slider for all DayFlow sounds. Previews play at the slider's level.
- Only **one sound plays at a time**: a new reminder cuts off one that's still playing.

### Adding your own sounds

Your own sounds are **clips**, kept as ordinary files in the **Clips folder**: **Music → DayFlow Clips**. **Open Clips Folder** in Settings → Sounds shows it in Finder.

**Add a Clip ▾** offers three choices:

| Choice | What it does |
|---|---|
| **Record a clip…** | Records with your Mac's microphone (macOS asks once). Click the red button to start and again to stop; it stops by itself at 30 seconds. Listen with **▶ Play**, or **Record again**. The quiet before you start and after you stop is trimmed off; turn on **Keep the silence** to keep it as recorded. Name it ("Recording 1" to start with) and **Save**. |
| **Choose a file…** | Picks a sound file; DayFlow copies it into the Clips folder. |
| **How do I add music?** | A short help page with all the ways to add sounds. |

You can also **drag sound files** from Finder onto Your clips, or **put them straight into the Clips folder**: they show up in Your clips as soon as they land there.

- **Formats:** mp3, wav, m4a, aac or ogg.
- **Long files:** a clip plays for up to 30 seconds. For a longer file (a song, say, up to 200 MB), DayFlow opens **Choose 30 seconds**: drag the slider to where the piece should start, **▶ Play** to hear it, turn on **Fade in** if you like, then **Save**. The piece is saved as *Name (clip)*. If the song was in the Clips folder, it moves into **DayFlow Clips → Originals**, which DayFlow doesn't list, so nothing of yours is deleted. A long file you put in the folder waits in Your clips, marked *Too long*, until you choose its 30 seconds.
- **Files DayFlow can't use** (a text file, a damaged file, a copy of a clip you already have) are listed with the reason, and **Move to Trash** clears them away.
- **Songs from the Music app or Apple Music can't be used.** They're protected, so no other app can play them; you need an actual audio file.
- Recordings and pieces are saved as wav files, which play on both the Mac and the iPhone.

Each clip in Your clips has **▶** to play it and **⋯** with:

- **Rename…** renames the clip and its file. Reminders that use it keep it. Renaming the file in Finder renames the clip too.
- **Show in Finder** shows its file.
- **Remove** moves its file to the Trash. Any reminder that used it goes back to its starting sound. Deleting the file in Finder does the same.

Clips appear under **Your clips** in every sound menu. Adding the same audio twice keeps one copy, and a different clip with a name you already have is renamed, for example *Gong (2)*.

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

## 10. The window and the Mini timer

### The window

The window described in this guide. It opens and closes like any Mac app's window:

- **Closing it** doesn't quit DayFlow. DayFlow keeps running in the [menu bar](#11-the-menu-bar-icon), with no window and no Dock icon, and reminders, sounds and cards work exactly as usual.
- **Open it again** from the menu bar icon (**Open DayFlow**), by opening DayFlow from Applications, with **⌃⌥D** from any app, or by clicking a reminder.
- **⌃⌥D** opens the window, or closes it if it's in front.

DayFlow reopens the way you left it: with the window open or closed. If you've set it to open when you log in, it starts with the window closed.

### Mini timer

Turn on **Mini timer** at the bottom of the sidebar, or in the menu bar icon's menu, for a small floating pill that always shows what you're doing:

- **The current block** and a countdown: minutes and seconds, or hours and minutes with a small *h* when more than an hour is left.
- **A progress bar** for how far through the block you are.
- **What's next**: *Next: Lunch*, or *Meeting in 4 min* when a meeting comes before the next block.
- It **turns amber** during the current block's heads-up minutes, with one gentle pulse as they begin.
- **Between blocks** it says **Free** and counts down to the next block, or **Get ready** once the next block's preparation time has begun. At the end of the day it says **Done for today**.

Using it:

- **Drag** it anywhere. It remembers the spot, and if that spot is off-screen later (say you unplugged a monitor), it moves back to the top-right corner.
- **Double-click** it to open the window.
- **Right-click** it for **Open DayFlow**, **Hide Mini timer**, **Always on top** (on by default) and **Quit DayFlow**.
- It's slightly see-through until you point at it, and it stays visible over full-screen apps and on every desktop.

The Mini timer is separate from the window: show it with the window open or closed.

---

## 11. The menu bar icon

The sun-over-water icon in the menu bar shows the minutes left in the current block (for example *23m*). Its menu has:

- **What's on now**: for example *Deep work, 23 min left*, or *No block right now*.
- **Open DayFlow**: opens the window.
- **Show Mini timer**: ticked while the Mini timer shows.
- **Turn off reminders ▸ For 1 hour / For 24 hours / Until I turn them on**. While they're off, the icon is crossed out and the menu shows *Reminders off until…* and **Turn on reminders** instead.
- **Sync calendar now.**
- **Quit DayFlow.**

---

## 12. General settings

**Settings → General**:

| Setting | What it does |
|---|---|
| **Reminders show as** | **Cards** (default): [reminder cards](#7-reminder-cards) that stay until you act. **Notifications**: macOS notifications, which follow Focus. |
| **Close cards on their own** | *Never* (default), *After 1 min*, or *After 5 min*. Shown with Cards. |
| **Send a test reminder** | Shows a reminder the way you chose and plays Default's start sound, so you can check everything works. |
| **Press ⌃⌥D anywhere…** | Turns the open-or-close-the-window shortcut on or off. If another app already uses ⌃⌥D, DayFlow says so and the shortcut stays off. |
| **Open DayFlow when I log in** | Starts DayFlow, with the window closed, every time you log in. |

---

## 13. Your data

DayFlow keeps everything in `~/Library/Application Support/Dayflow` on your Mac. In Finder, choose **Go → Go to Folder…** and paste that path.

| File or folder | What's in it |
|---|---|
| `schedule.json` | Your events and blocks |
| `block-types.json` | Your block types and their reminders |
| `settings.json` | Meetings reminders, volume, and other preferences |
| `sounds.json` | The list of your sound clips (the clips themselves are in **Music → DayFlow Clips**) |
| `progress.json` | What you've checked off and skipped, and each day's result for your streak |
| `window-state.json` | Whether the window and the Mini timer were open, and where the Mini timer sits |
| `google-credentials.json` | The Google client file you imported |
| `google-token.json` | Your Google sign-in; **Disconnect** deletes it |

**Upgrading DayFlow** keeps your data. If a new version changes how something is stored, DayFlow converts it, so nothing you hear or see changes unexpectedly. Your Mac and iPhone each keep their own schedule; there's no way to move one to the other yet.

**Your clips** are in **Music → DayFlow Clips**, outside that folder, so you can manage them in Finder. Clips from earlier versions (in `sounds/`) move there by themselves the first time this version opens.

**To uninstall**, quit DayFlow, drag it from Applications to the Trash, and delete the folder above, and **Music → DayFlow Clips**, if you also want to remove your data.

---

## 14. Troubleshooting

**macOS says DayFlow can't be opened or can't be verified.**
The beta isn't notarized by Apple yet. Use **Open Anyway** in System Settings → Privacy & Security, as in [Install](#install-it). It's needed once per install.

**No notifications appear.**
If **Reminders show as** is **Notifications**, check **System Settings → Notifications → DayFlow** and make sure notifications are allowed, and that **Focus / Do Not Disturb** is off. Cards appear even when notifications aren't allowed.

**No sound.**
Check **Settings → Sounds**: *Play a sound with each reminder* must be on and the volume above zero. Also check your Mac's volume and output device. Each reminder's own switch must be on, and its sound will play when you pick it in the menu.

**A reminder didn't come.**
Check that the block repeats on today in Schedule, that it isn't outlined in red (a row with a problem isn't saved), that it isn't skipped today, and that the reminder is switched on for the block's type. Remember a heads-up is skipped for blocks shorter than the heads-up time.

**⌃⌥D doesn't do anything.**
Another app may be using that shortcut. Settings → General says so if it is; open the window from the menu bar icon instead.

**I only see a small floating timer.**
That's the Mini timer. Double-click it to open the window, or right-click it → **Hide Mini timer**.

**I can't find DayFlow.**
With its window closed, DayFlow has no Dock icon. Click the sun icon in the menu bar → **Open DayFlow**.

**Google Calendar says access has expired.**
Click **Connect** in Settings → Calendar to sign in again. To stop it happening every 7 days, publish your Google consent screen, as described in [Connect your calendar](#connect-your-calendar-one-time-about-5-minutes).

**Opening DayFlow does nothing.**
Only one copy of DayFlow runs at a time; opening it again brings the running copy forward. If you just quit it, wait a moment and try again.

---

## 15. Quick reference

| To… | Do this |
|---|---|
| See what's on now | **Today**, the Mini timer, or the menu bar icon |
| Plan your week | **Schedule** (changes save as you go; **Undo** in the message) |
| See an example | **Add a sample day** on the empty Today or Schedule |
| Add something that rings once | **Schedule → ＋ Add… → Event** |
| Add an event every 30 minutes | **Schedule → ＋ Add… → Repeated event…** |
| Check an event off | Its check in **Today's flow**, or **✓ Done** on its card |
| Skip something today | Its switch in **Today's flow** |
| Shuffle several sounds | A reminder's sound button, then check several |
| Change a block's reminders | Change its **type** in Schedule, or edit the type in **Settings → Block types** |
| Hear a sound | Pick it in a sound menu, or click **▶** |
| Add your own sound | **Settings → Sounds → Add a Clip ▾** (record, choose a file), drag files onto Your clips, or put them in **Music → DayFlow Clips** |
| Make a sound gentler | Press **Fade in** next to it |
| Snooze a reminder | **Snooze ▾** on its card |
| Silence DayFlow for a while | **Turn off reminders…** on Today, or in the menu bar icon's menu |
| Open or close the window | **⌃⌥D**, or the menu bar icon → **Open DayFlow** |
| Show the Mini timer | **Mini timer** at the bottom of the sidebar, or in the menu bar icon's menu |
| Cards or notifications | **Settings → General → Reminders show as** |
| Get reminders for meetings | **Settings → Calendar**, then **Settings → Meetings** |
| Quit | **Quit DayFlow** in the sidebar, **⌘Q**, or menu bar icon → **Quit DayFlow** |

---

## 16. DayFlow on iPhone

DayFlow for iPhone is the same day planner, built for the phone: the same block types and four reminders, the same sounds, and the same kinds of data files. The iPhone keeps its own schedule: plan it there, or add the sample day. Some things work differently, because iOS runs apps differently from macOS. This section covers what's different. It needs **iOS 17 or later**.

### Install it (beta)

For now the iPhone app isn't on the App Store or TestFlight. You install it from a Mac with Xcode, using a free Apple ID:

1. Install **Xcode** from the Mac App Store, then run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` in Terminal.
2. In **Xcode → Settings → Accounts**, add your Apple ID. This creates your free "Personal Team".
3. Get the code: `git clone https://github.com/JRAntra/dayflow.git`, then in `dayflow/ios` run `xcodegen` (install it with `brew install xcodegen`) and open `DayFlow.xcodeproj`.
4. Select the **DayFlow** target → **Signing & Capabilities** → choose your Personal Team. Do the same for **DayFlowWidgets**.
5. Connect your iPhone with a cable and tap **Trust**. Turn on **Settings → Privacy & Security → Developer Mode** (the iPhone restarts).
6. Choose your iPhone at the top of Xcode and press **Run** (▶).
7. The first time, the iPhone won't open the app until you trust yourself as its developer: **Settings → General → VPN & Device Management** → your Apple ID → **Trust**.

**Every 7 days**, an app signed with a free Apple ID stops opening. Connect the iPhone and press **Run** in Xcode again. Your schedule and settings are kept.

If Xcode can't sign the **App Groups** capability with your free Apple ID, delete the two `com.apple.security.application-groups` entries in `ios/project.yml` and run `xcodegen` again. Only the Home Screen widgets stop working; the Live Activity still works.

### The first time you open it

DayFlow explains its events and blocks, then asks to send notifications. If you choose **Not now**, Today shows *Reminders are off* until you allow notifications in iOS Settings.

### Around the app

Three tabs at the bottom:

| Tab | What's there |
|---|---|
| **Today** | The dial, the current block with its countdown, **Turn off reminders…**, today's done count and streak, and today's flow, with checks for events and meetings' **Join** buttons |
| **Schedule** | Your weekly plan as a **List** or one **Day** at a time. **＋** adds an event, a repeated event or a block |
| **Settings** | **Block types**, **Meetings**, **Sounds**, **Calendars** and **General** |

### Planning your blocks

**List** shows every event and block, earliest first: events with a bell 🔔, blocks with a bar, with each one's type, days and length. The day strip (**All · M T W T F S S**) shows one day's.

- On an empty schedule, **Add a sample day** (in Today and in Schedule) adds the eight sample weekday blocks.
- **＋** asks what to add: **Event**, **Repeated event** or **Block**. A new event or block follows the Mac's rule: it starts where your latest one ends and copies its days (a block lasts 30 minutes and takes its type).
- **Tap an event or block** to edit it. **Event · Block** at the top switches between them, as on the Mac. **Save** applies the change straight away and updates reminders, with **Undo** in the message.
- An **event** has a name, a time, its days and its **Alarm**: the sound (or [several](#several-sounds-for-one-reminder)) and Fade in. It always rings as an alarm, through silent mode and Focus. The first event you save asks whether DayFlow may set alarms. See [Ringing even on silent](#ringing-even-on-silent).
- A **block** has a type, start and end times, days and its four **Reminders**. **Ring even on silent**, at the top of **Reminders**, makes each of them ring as an alarm. Below it, **From the Focus type** sums up the type's reminders; tap it to open the type and change them (for every block of that type). See [A block's reminders](#a-blocks-reminders).
- **Save** stays greyed out until it has a name, repeats on at least one day and, for a block, ends after it starts. Overlapping blocks are allowed; the block shows which one it overlaps.
- **Swipe left** to delete. **Undo** appears for a few seconds.
- **New type…** in the Type menu adds a block type and opens its reminders.

**Repeated events** work as on the Mac (see [Repeated events](#repeated-events)): **＋ → Repeated event** asks for a name, **First at**, **Last at**, **Every** (minutes), days and the alarm's sound, shows how many events that makes, and **Create** checks with you first, *Create 17 "Drink water" events?*. Then:

- Their rows show **↻**. Tapping one asks: **Edit all events in this repeat** (the repeat's form, which makes the events again when you save) or **Edit only this one** (it leaves the repeat and becomes an event of its own).
- Swiping one to delete asks: **Delete all 17 events in this repeat**, or **Delete only this one**.
- **Group repeats**, at the top of the list, shows each repeat as one row. Tapping it edits the whole repeat.

**Day** shows one weekday as an hour grid, like the Calendar app:

- **Press and hold** a block, then drag, to move it. Times snap to 5 minutes, with a light tick. An event is a pill with a bell 🔔 and its time; hold and drag it to move it. A repeat's events (marked ↻) don't drag: change the repeat instead.
- On today's weekday, a checked-off event's pill is gold with a star, and anything skipped today is struck through.
- A held block shows **handles** at its top and bottom edges. Drag one to change its start or end time. A block can't be shorter than 5 minutes.
- **Tap** a block to edit it. **Tap an empty slot** to add a 30-minute block there.
- If the block repeats on several days, DayFlow asks after each change: **This day only** (the block is split off for that day, and the original keeps its other days) or **All N days**. A block on just one day never asks.
- With VoiceOver, use the actions to move a block, or change its length, 5 minutes at a time.

### Today on iPhone

Today works as on the Mac (see [Checking off events](#checking-off-events)):

- Each event in **Today's flow** has a round **check**. Tap it when you've done it: the row turns gold with a star, and the cheer-up drops in from the top, *Nice! 3 of 6 done today*, with your streak. It goes by itself, or tap it. Tap the check again to uncheck it. Checking off an event before its time cancels today's alarm; unchecking brings it back.
- **Swipe a row left** for **Skip today**: the event or block is struck through and greyed, and its reminders and alarms don't ring today. A skipped block leaves the dial, the countdown and the Live Activity. Swipe again for **Bring back**. Everything is back the next morning.
- **★ 3 of 6** and **🔥 5** at the top count today's events done and your [streak](#your-streak), with the Mac's rules. The iPhone keeps its own checks and streak; they aren't exported.
- An event's alarm has **Done** beside Stop. It stops the alarm and checks the event off without opening DayFlow; the cheer-up shows the next time you open it. If DayFlow can't set alarms, the event's notification has **Done** instead (press and hold it).

### How reminders work on iPhone

iOS doesn't let an app run in the background all day, so DayFlow **schedules your reminders ahead of time**, as ordinary iPhone notifications. iOS allows up to 64 scheduled notifications per app, and DayFlow uses up to 62, which is usually three to five days of reminders. It schedules more each time it gets to run: when you open it, change something, or tap a reminder, and when iOS lets it refresh in the background.

If DayFlow hasn't run for several days, the last notification it scheduled says *Open DayFlow to keep your reminders coming*. Open the app, and the next ones are scheduled.

The reminders themselves are the Mac's: the same four per type, the same wording, the same lead times, and the same merge rule (*"the block that's coming up wins"*).

What's different on iPhone:

- **The silent switch and Focus apply**, except to events and to blocks that [ring even on silent](#ringing-even-on-silent). With the switch on silent, reminders vibrate without a sound. During a Focus, iOS holds DayFlow's notifications back unless you allow DayFlow in that Focus: **Settings → Focus →** the Focus **→ Apps → Add DayFlow**.
- **There's no Snooze** and no reminder cards. Swipe a notification away when you're done with it.
- **Meeting reminders** with a video link have a **Join** button (press and hold the notification to see it). Tapping the notification joins too. Without a link, the button is **Open in Calendar**.
- **Tapping a block reminder** opens Today.
- **Turn off reminders…** on Today (or in Settings → General) silences everything **For 1 hour**, **For 24 hours** or **Until I turn them on**. DayFlow removes every scheduled notification and ends the Live Activity, so nothing rings, even if you then swipe DayFlow away. Today shows *Reminders off… · Turn on*, the widgets show *Reminders off*, and **Turn on** reschedules everything. Reminders that fall in the off time are skipped.
- **Swiping DayFlow away doesn't stop reminders.** iOS delivers the notifications DayFlow scheduled ahead whether or not the app is running, and doesn't tell an app it's been swiped away. Use **Turn off reminders** instead.
- **Settings → General → Send a test notification** shows what a block starting looks like. **Scheduled ahead** says how far ahead your reminders go.

### Ringing even on silent

Every **event** rings as an **alarm**, like the Clock app's: through the silent switch and any Focus, on the Lock Screen and in the Dynamic Island, until you tap **Stop**, or **Done** to check it off. For a **block** you can't afford to miss, turn on **Ring even on silent** at the top of its **Reminders** section, and each of its reminders rings that way too. Alarms need iOS 26 or later; on earlier versions events ring as normal reminders and the switch isn't shown.

- **Every reminder the block has** rings this way: Start preparation, Start, Heads-up and Time's up, whichever are on. Each uses its own sound, at your volume, with Fade in if it's set. When one of its reminders merges with another block's, the merged reminder rings as an alarm too.
- **The first time** you save an event or turn the switch on, iOS asks whether DayFlow may set alarms. If you say no, the switch turns back off and says why, with **Open Settings**: turn on **Alarms** in **Settings → Apps → DayFlow**, then turn the switch on again. If you later turn Alarms off there, the block's reminders come as normal reminders, quiet on silent, and its edit sheet says *Alarms are off in Settings*.
- An **alarm clock** ⏰ marks these blocks in the list, the day view and Today's flow. Events don't need it: they all ring.
- **Turn off reminders** turns their alarms off too, and **Turn on** brings them back. Turning off **Play sounds** in Settings → Sounds makes them normal, silent reminders.
- Alarms are set ahead of time like notifications, and don't count towards the 62. Up to 48 are set at once; any after that are normal reminders until DayFlow next runs. A repeat every 30 minutes uses 17 a day, so open DayFlow every couple of days to keep them all alarms.
- **Snooze** isn't offered, as with every reminder on iPhone: tap Stop.

### Sounds on iPhone

The 18 built-in sounds are the same as the Mac's.

- iOS plays a reminder's sound at your **ringer volume**. DayFlow's **Volume** (Settings → Sounds) sets how loud DayFlow is within that, so it can make sounds quieter than the ringer but never louder.
- **Fade in** works as on the Mac: the sound starts at 10% and rises smoothly to your volume over 15 seconds, playing a short sound again and again until the fade is done. DayFlow builds the fade and volume into its own copy of each sound, so they work even while the app is closed.
- Choosing a sound plays it, and **Play** plays it again. For events and blocks' reminders, tap a sound's **circle** to check it, and check several to [shuffle them](#several-sounds-for-one-reminder); tapping its name plays it. Each ring picks one at random, never the one it played last, and **Play** plays a random one. **Previews play even when the iPhone is on silent**, because you tapped them; reminders still follow the switch.

**Your own sounds** work as on the Mac, with the Clips folder in the Files app: **On My iPhone → DayFlow → Clips**. In Settings → Sounds, **Add a clip** offers:

- **Record a clip…**: records with the iPhone's microphone (iOS asks once). Tap the red button to start and again to stop; it stops by itself at 30 seconds. The quiet start and end are trimmed off unless you turn on **Keep the silence**. Play it, name it and **Save**.
- **Choose a file…**: picks a sound from Files or iCloud Drive and copies it into the Clips folder.
- **How do I add music?**: the help page.

Other ways in: **AirDrop** a sound file to your iPhone and choose DayFlow; tap **Share** on a sound in Files, Mail or Voice Memos and choose DayFlow; or put files in the Clips folder in the Files app. DayFlow checks the folder whenever it opens and when you open Sounds.

A file longer than 30 seconds opens **Choose 30 seconds**, as on the Mac; a song from the Clips folder then moves into **Clips → Originals**. Recordings and pieces are saved as m4a files. In Your clips, tap a clip to hear it, and touch and hold (or swipe left) to **Rename** or **Remove** it. Remove deletes its file, after asking. iOS may not be able to play some files (OGG in particular); DayFlow says so.

### Meetings on iPhone

On iPhone, DayFlow reads meetings from **the calendars on your iPhone**, not straight from Google, so there's no Google Cloud setup and no sign-in.

1. Add your Google account to the iPhone if it isn't there: **Settings → Apps → Calendar → Calendar Accounts → Add Account → Google** (on iOS 17: **Settings → Calendar → Accounts**).
2. In DayFlow, open **Settings → Calendars** and tap **Allow calendar access**. Your default calendar is switched on to start with; switch on any others whose meetings you want reminders for.

The rules are the Mac's: timed events only, skipping all-day, cancelled and declined events. DayFlow finds **Join** links for Google Meet, Zoom, Microsoft Teams and Webex in the event's link, location or notes. Meetings show on Today's dial (the amber outer ring) and timeline, and get the two reminders from **Settings → Meetings**.

If a meeting moves while DayFlow isn't running, its reminder keeps the old time until DayFlow next runs.

### Lock Screen and Home Screen

- **Live Activity:** while a block is running, DayFlow shows it on the Lock Screen and in the Dynamic Island, with its type, the time left, a progress bar and what's next. When the block ends, it shows *Up next* until DayFlow runs again and moves it on. Turn it off in **Settings → General**. The first time, iOS asks whether to allow DayFlow's Live Activities.
- **Widgets:** add **DayFlow → Current block** to the Home Screen (small or medium) or the Lock Screen. Widgets show the current block and its countdown, and switch blocks by themselves through the day. They need the App Groups capability; if your free Apple ID can't sign it, the widgets say *Open DayFlow*.

### Mac and iPhone

The Mac and the iPhone each keep their own schedule, types and checks; changes on one don't reach the other. Syncing between them is planned for a later version.

### Your data on iPhone

Your clips are in **On My iPhone → DayFlow → Clips**. Your schedule, types and settings live in DayFlow's own storage on the iPhone, in the same file formats as the Mac's. Deleting the app deletes all of it, Clips folder included.

### iPhone troubleshooting

**Reminders don't make a sound.**
Check the silent switch (on silent, reminders only vibrate), then the ringer volume, then **Settings → Sounds → Play sounds** in DayFlow.

**An event, or a block set to ring even on silent, doesn't ring through silent.**
Open it: if it says DayFlow isn't allowed to set alarms, tap **Open Settings** and turn on **Alarms**. Alarms need iOS 26 or later.

**A repeat's later events came as quiet reminders.**
DayFlow sets 48 alarms ahead. Open DayFlow every couple of days so it can set the next ones.

**Reminders don't show during a Focus.**
Allow DayFlow in that Focus: **Settings → Focus →** the Focus **→ Apps → Add DayFlow**.

**No reminders at all.**
Open **Settings → General** in DayFlow. If *Reminders* says *Off*, tap **Open Settings** and allow notifications. If *Scheduled ahead* is missing, open Today once so DayFlow can schedule them.

**The Lock Screen shows a block that has ended.**
The Live Activity moves on when DayFlow runs. Open the app, or tap a reminder.

**The app won't open any more.**
With a free Apple ID, the app has to be re-installed from Xcode every 7 days. Connect the iPhone and press **Run** in Xcode.

**A meeting is missing.**
Check that its calendar is switched on in **Settings → Calendars**, and that it isn't all-day, cancelled or declined.

