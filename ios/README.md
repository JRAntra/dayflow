# DayFlow for iPhone

A native SwiftUI version of DayFlow for iOS 17 or later. It shares the Mac app's data model, reminder rules and export format, so schedules move between the two as files. The [User Guide](../User%20Guide.md#17-dayflow-on-iphone) explains how it works for people using it; this page is for building it.

## Build and run

You need a Mac with **Xcode** (tested with Xcode 27.2) and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```
cd ios
xcodegen          # makes DayFlow.xcodeproj from project.yml (the project isn't committed)
open DayFlow.xcodeproj
```

Choose an iPhone Simulator and press Run. To install on your own iPhone with a free Apple ID, pick your Personal Team under **Signing & Capabilities** for both the **DayFlow** and **DayFlowWidgets** targets (or set `DEVELOPMENT_TEAM` in `project.yml`); the [User Guide](../User%20Guide.md#install-it-beta) lists the iPhone-side steps. Free signing lasts 7 days.

If your Apple ID can't sign the App Groups capability, remove the `com.apple.security.application-groups` entries from `project.yml` and run `xcodegen` again: only the Home Screen widgets stop working.

## Tests

- `swift test` in `Packages/DayFlowCore` runs the core tests on the Mac, no Simulator needed: the planner's wording and merge rules against the Mac's, the rolling window, editing rules, cleaning, import and export (including a Mac export and version 1 files), backups and clips.
- **Product → Test** in Xcode (or `xcodebuild test -scheme DayFlow -destination 'platform=iOS Simulator,name=iPhone 17'`) runs the UI tests in the Simulator: the welcome screens and notification prompt, scheduling, the test notification, the edit sheet's checks with Undo, the day view's tap, drag, resize and "This day only", the Live Activity, meetings from the calendar, every Settings page, and your own clips (the Clips folder, Choose 30 seconds, the recorder, Rename and Remove). Each test relaunches DayFlow if the Simulator hands it a copy already running without the test's launch options.

## How it's put together

```
project.yml                       XcodeGen project: the app, the widget extension, UI tests
Packages/DayFlowCore/             the parts that don't need iOS, tested with `swift test`
  Models.swift                    Block, BlockType, Reminder, Settings…, shaped like the Mac's JSON
  Specs.swift                     starting values, built-in sounds, the sample schedule
  Sanitize.swift                  the Mac's cleaning rules, and the version 1 upgrade
  Planner.swift                   reminders for a day (wording and merge rules), the rolling window
  ScheduleEdits.swift             checks, ＋ rules, moving and resizing, "This day only", day-view columns
  DataStore.swift, Import.swift   files, clips, backups, export and import
  ClipFolder.swift                the Clips folder: scanning, renames, long files, Originals
DayFlow/                          the app
  AppModel.swift                  state for every screen; refreshes reminders after each change
  DayFlowApp.swift                notification taps and actions, background refresh, opened files
  Services/ReminderScheduler.swift  the next 62 reminders as notifications, plus the notice
  Services/AlarmScheduler.swift  blocks that ring even on silent, as AlarmKit alarms (iOS 26+)
  Services/CalendarService.swift  meetings from the iPhone's calendars (EventKit), Join links
  Services/LiveActivityController.swift  the Live Activity and the widgets' data
  Sound/SoundLibrary.swift        writes each sound as CAF with your volume and Fade in built in
  Sound/SoundPlayer.swift         previews (they play on silent)
  Sound/AudioEdit.swift           trimming silence, 30-second pieces, writing m4a
  Views/Settings/ClipSheets.swift the recorder and Choose 30 seconds
  Views/                          Today (dial, timeline), Schedule (list, day grid, edit sheet,
                                  import, backups), Settings, Welcome
DayFlowWidgets/                   Live Activity (Lock Screen, Dynamic Island) and widgets
Shared/                           types used by the app and the widgets
DayFlowUITests/                   UI tests run in the Simulator
```

The built-in sounds come from `../assets/sounds`, shared with the Mac app. The app icon is rendered from `../assets/icon.svg` by `npm run icons` in the repo root, which writes the light, dark and tinted iPhone icons into `DayFlow/Assets.xcassets`.

## How iOS changes things

- **Reminders are scheduled ahead.** iOS suspends apps in the background, so instead of the Mac's once-a-second check, the next reminders are scheduled as notifications (up to 62, as iOS allows 64), refilled whenever the app runs. A final notice asks you to open DayFlow if it hasn't run for a while.
- **Sounds are pre-rendered.** Notifications play their sound at the ringer volume, from start to end, so the volume and Fade in are built into a copy of each sound (`Library/Sounds/df-<hash>.caf`, 16-bit PCM, at most 30 seconds).
- **Ring even on silent uses AlarmKit.** Notifications always follow the silent switch, so a block set to ring even on silent has its reminders set as alarms instead (iOS 26 and later, after you allow alarms). Each alarm's id is a hash of what it says and when, so unchanged alarms are left alone on each refresh. The iOS 27 Simulator refuses AlarmKit permission without asking; turn on **Alarms** in the Simulator's Settings → Apps → DayFlow instead (the UI test does this).
- **No snooze, no cards, no window modes.** Meeting reminders have Join or Open in Calendar; the Mini timer's job goes to the Live Activity and widgets.
- **Meetings come from EventKit**, not Google's API, so there's no OAuth client to set up.
