# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

GLPals — a single-package Flutter app (Android + iOS) for tracking a GLP-1
medication: shots/doses, daily check-ins, meals, trends, an AI "buddy" chat,
and a code-drawn companion pet that grows with logged activity. All health data
lives on the device in SQLite; the only network calls are to Gemini (assistant,
meal estimates) and Google Drive appdata (backup). Everything else works
offline.

## Commands

The Flutter SDK's real path contains a space, which breaks the native-assets
hook runner and `sdkmanager`. A junction `C:\flutter` points at it — **always
invoke Flutter through `C:\flutter\bin\flutter.bat` from PowerShell**, never the
Git Bash wrapper `/c/flutter/bin/flutter` (it resolves back to the space path
and rewrites `android/local.properties`, after which Gradle dies with a bare
"finished with non-zero exit value 1"). `android/local.properties` must read
`flutter.sdk=C:\\flutter`.

```powershell
$env:FLUTTER_ROOT='C:\flutter'; & C:\flutter\bin\flutter.bat pub get
```

```powershell
$env:FLUTTER_ROOT='C:\flutter'; & C:\flutter\bin\flutter.bat analyze
```

```powershell
$env:FLUTTER_ROOT='C:\flutter'; & C:\flutter\bin\flutter.bat test
```

```powershell
$env:FLUTTER_ROOT='C:\flutter'; & C:\flutter\bin\flutter.bat build apk --release
```

Single test file, or one test by name:

```powershell
& C:\flutter\bin\flutter.bat test test/widget_test.dart --plain-name "a skipped dose moves the schedule on"
```

On-device work targets the Samsung S25 Ultra, ADB serial `R5CY12DJDVE`. For live
preview, run `tail -f cmds.txt | flutter.bat run -d R5CY12DJDVE > run.log` as a
background task, then `echo r >> cmds.txt` to hot reload and `echo R >> cmds.txt`
to hot restart. `cmds.txt` and `run.log` are gitignored scratch.

`test/pal_preview_test.dart` renders every pal at every stage to PNG contact
sheets instead of asserting; set `PAL_PREVIEW_DIR` to a directory to keep them.
`test/widget_test.dart` is pure logic only — anything that pumps the app needs
sqflite and the notifications plugin, which are unavailable in a plain
`flutter test` run.

### Build-time defines

- `GEMINI_API_KEY` — bakes an assistant key in so a fresh install answers
  without typing one. A key entered on the phone still wins.
- `GOOGLE_SERVER_CLIENT_ID` / `GOOGLE_IOS_CLIENT_ID` — Google Sign-In for Drive
  backup; see `lib/google_config.dart` and `docs/google-backup-setup.md`.
- `GLPALS_TEST_NOTIFY=true` — fires a reminder at launch so the chime can be
  heard in a release build.

### iOS

The Xcode project has **two** targets that ship: `Runner` and `GlpalsWidgets`,
a WidgetKit app extension (`ios/GlpalsWidgets/`) holding the Dynamic Island /
Lock Screen Live Activity. It is wired as a target dependency of `Runner` plus
an "Embed Foundation Extensions" phase, so `flutter build ipa` builds it with no
extra steps. Two things about it are easy to break:

- `GlpalsDoseAttributes.swift` is compiled into **both** targets. ActivityKit
  matches the app's activity to the extension's view by that type, and if the
  two ever disagree the activity silently never appears.
- The extension's `CFBundleShortVersionString`/`CFBundleVersion` come from
  `$(FLUTTER_BUILD_NAME)`/`$(FLUTTER_BUILD_NUMBER)`, so its build configurations
  are based on `Flutter/Generated.xcconfig`. **Not** `Debug.xcconfig` /
  `Release.xcconfig`: flutter_local_notifications has no `Package.swift`, so
  the build machine falls back to CocoaPods for it and Flutter prepends the
  `Pods-Runner` include to those two files — inheriting that would link every
  pod into a widget process with a ~30 MB memory ceiling. The versions must
  match the app exactly or App Store Connect rejects the upload.
- `AppDelegate.swift` must keep calling
  `FlutterLocalNotificationsPlugin.setPluginRegistrantCallback`. The plugin
  runs notification-action buttons tapped while the app is closed on its own
  headless engine and calls that callback unconditionally; without it the tap
  crashes. The Live Activity bridge is registered there too, so a "+1 glass"
  from the Lock Screen can update the island (but not start one — ActivityKit
  only starts activities from a foreground app).

Editing `project.pbxproj` by hand is the only option here (no Mac, no Xcode), so
after touching it check that it still parses before relying on a CI build — the
file has no tooling to catch a mistake and a broken one fails late and cryptically.

There is no Mac here: iOS builds run on Codemagic (`codemagic.yaml`, Flutter
pinned to 3.47.2). `ios-unsigned` answers "does it still compile for iOS?"
without any Apple paperwork; `ios-testflight` is the route onto someone else's
phone. Every workflow runs `pub get`, `analyze` and `test` before building, so a
lint or test failure fails the build.

## Architecture

### Startup and the app shell

`main()` draws `SplashScreen` immediately and runs `_startup()` behind it. Every
step is wrapped in `_guard` — a misbehaving plugin must never leave the app
stuck on the splash. `_startup` loads each preference singleton and returns
whether this is a first run (no `onboarded` and no `pet_species` setting), which
decides onboarding vs. `Shell`.

`Shell` is a six-tab `IndexedStack` (Home, Shots, Check-in, Meals, Trends,
Buddy) with Reminders / Calendar / Settings in the app bar. Tabs communicate
through `GlobalKey`s and `onSaved` callbacks rather than a state-management
package.

### The save fan-out

`_ShellState._onSaved` is the single place that reacts to a write:

```
refresh Home → BackupService.scheduleAutoBackup() → Reminders.sync() → HomeWidgetBridge.update()
```

`Reminders.sync()` in turn ends with `LiveActivities.sync()`, so the Dynamic
Island rides along with the notification schedule.

Any new screen or code path that writes data must run the same fan-out (see
`NotificationActions.handle` for the background-isolate version), otherwise the
countdown, reminders, home-screen widget and island silently go stale.

### Persistence (`lib/db.dart`)

`AppDb.instance` is a lazily opened sqflite singleton, schema version 6.
Migrations are additive `if (old < N)` blocks; use the `_addColumn` helper, which
checks `PRAGMA table_info` first so a half-applied migration can be retried.
Tables: `shots`, `daily_logs` (keyed by `yyyy-MM-dd`), `meals`, `med_changes`,
`dose_skips`, `notif_log`, and `settings` (key/value).

**`settings` is the store for every preference** — theme, goals, medication,
companion, reminders, widget style, Google client ID. `_backupTables` must list
any new table or it silently drops out of Drive backups and restores.

### Preferences pattern

There is no DI or provider package. Preferences are either static-field holders
(`Goals`, `WidgetPrefs`, `ThemePrefs`, `PetPrefs`) or `ChangeNotifier`
singletons (`MedPrefs.instance`, `Profile.instance`, `ReminderPrefs.instance`),
each with a `load()` called from `_startup` and a `save()`/`set()` that writes
back to the `settings` table. Some also expose a `revision` `ValueNotifier` for
widgets that need to rebuild on change.

### Experience and the companion

`lib/xp.dart` stores nothing. `Xp.compute()` re-derives the total from all logs,
meals and shots every time, so backfilling a day from the calendar, editing a
meal or restoring a backup can never leave a counter drifting. `Quest` defines
the daily list and its XP values; `Xp.tiers` are the five companion stages.
`lib/widgets/pal_art.dart` draws all six species × five stages with a
`CustomPainter` in a 100×100 unit box (no image assets); `pet.dart` owns the
animation tickers and mood, `pal_evolution.dart` the stage strip.

### Medication model (`lib/med.dart`)

`GlpProduct.all` is a static table of products with their usual titration steps,
schedule and label-derived `makeUpDays`. **Dose steps exist to make the picker
easy, never to recommend one** — every dose decision belongs to the prescriber,
and the UI keeps product changes behind an explicit warning (`dose_alert.dart`,
`MedicationPage`).

`med_changes` is append-only: a product or dose switch opens a new chapter
rather than rewriting history, and shots carry the `product` they were taken
from. `nextDoseAt()` anchors the countdown to the last shot *or* the last
deliberately skipped dose, whichever is later — skipping moves the schedule on
without inventing an injection. `forecastDoses()` projects forward and continues
the `injectionSites` rotation.

### Reminders (`lib/reminders.dart`, `lib/notification_actions.dart`)

`Reminders.sync()` cancels everything and rebuilds the whole schedule from
`ReminderPrefs` plus what is already logged today, so a nudge disappears once
the thing is done. It is cheap; call it after any save. Scheduled rows are
mirrored into `notif_log` (future rows = queued, past rows = delivered) because
Android cannot read its own posted notifications back — the in-app panel reads
that table.

Notification action buttons run `notificationActionBackground` in a separate
isolate, so it must re-`load()` the preference singletons before touching
anything. Two platform gotchas:

- `ActionBroadcastReceiver` must stay declared in
  `android/app/src/main/AndroidManifest.xml`; the plugin does not declare it and
  without it button taps are broadcast to nothing.
- A channel's sound is frozen when Android first creates it, so **changing a
  sound requires a new channel id** (currently `shots_v2`, `water_v2`,
  `meals_v2`). iOS only shows action buttons for categories declared up front in
  `_iosCategories`, and those identifiers must stay in step with what
  `NotificationActions` handles.

### Assistant (`lib/ai_service.dart`)

Static client for Gemini `generateContent`. `models` is a fallback list tried in
order when one is overloaded (503) or rate limited (429). The key comes from the
device keychain (`flutter_secure_storage`) first, then the `GEMINI_API_KEY` build
define. `buildContext()` compacts recent logs into the prompt. Three call shapes
share it: `ask` (chat), `analyzeMeal` (photo and/or typed ingredients → JSON
schema), `onboardingPlan` (starting targets and tips). Every failure is
normalised into an `AiException` carrying user-facing wording, so all screens
render the same message for the same cause. The system prompt keeps the
assistant explanatory and points medical decisions at the doctor.

### Backup (`lib/backup_service.dart`)

`ChangeNotifier` singleton uploading `AppDb.exportJson()` (plus the Gemini key)
to the signed-in account's Drive `appdata` folder. `GoogleBackupState` models the
connection in plain terms — note `needsReconnect`, which is *not* signed out:
Credential Manager routinely refuses a silent restore at cold start and succeeds
once the app is foregrounded again.

### Dynamic Island (`lib/live_activity.dart`, `ios/GlpalsWidgets/`)

An ActivityKit Live Activity carrying the next-dose countdown. Worth knowing
before changing it:

- **The Dynamic Island is not a notification surface.** Local notifications
  never appear there; it hosts Live Activities. The countdown is one, and an
  *update carrying an `AlertConfiguration`* is the only way to make the island
  expand and buzz — that is what `alert: true` on the channel does, and it is
  as close as iOS gets to putting a reminder in the island.
- **The clock needs no code.** iOS renders it from `dueAt` with
  `Text(timerInterval:)`, so it keeps ticking with the app closed. Everything
  else only changes when the app or a notification action runs: pushing content
  to a closed app would need ActivityKit push tokens and a server, which this
  app deliberately does not have.
- All the policy lives in Dart. `DoseActivityState.stateFor` decides whether
  there should be an activity at all (inside the lead window, or late but still
  inside the product's `makeUpDays`) and every string it shows;
  `LiveActivityBridge.swift` only forwards. That keeps it testable — see the
  `dynamic island` and `island headline` groups in `test/widget_test.dart`.
- The reminder echoed in the island is derived from `notif_log`, not remembered
  in a field, so it survives a restart and works in the background isolate.
  `headlineFrom` takes its `now` as an argument and must never consult the wall
  clock — notably **not** via `NotifLog.delivered`, which does.
- `LiveActivities.sync()` hangs off the end of `Reminders.sync()` rather than
  being a separate step in the save fan-out, because the island is part of the
  same notification state and every write already goes through there. Two
  consequences: the background isolate has to load `LiveActivityPrefs` before
  it syncs, and in `_startup` `LiveActivityPrefs.load` and `PetPrefs.load`
  must run *before* `Reminders.init` (which ends with a sync). Either one at
  its default would end the island on every launch or show the wrong pal.
- Opt-in, off by default, and the setting only appears on iOS — there is no
  Android equivalent to promise.

### Home-screen widget

`lib/widget_bridge.dart` composes today's numbers and pushes them through
`home_widget` **as strings only**, so the Kotlin side never deals with Int/Long
boxing. The native half is
`android/app/src/main/kotlin/com/glpbuddy/glp_buddy/GlpalsWidgetProvider.kt`
with four `res/layout/widget_*.xml` sizes. Failures are swallowed — the widget
must never break a save.

## Conventions

- Doc comments explain *why* a thing is the way it is (schedule anchoring,
  swallowed errors, channel ids). Match that when adding code; those comments
  are the design record.
- Shared UI primitives live in `lib/widgets/common.dart` (`SoftCard`, `Pill`,
  `GoalRing`, `SiteBadge`, `fmtCountdown`, `dayKey`, `confirmDelete`). Reuse
  `fmtCountdown`/`fmtDose` so Home, the reminders and the widget always read
  identically.
- Colors come from `Palette` in `lib/theme.dart`; each nav tab and quest has an
  assigned palette color.
- Release builds are R8-shrunk and depend on `android/app/proguard-rules.pro`
  (Gson/TypeToken keeps for `flutter_local_notifications`, plus `home_widget`).
  Without them the release APK hangs on the splash while debug builds are fine —
  check `adb logcat --pid=<pid>` first whenever that happens, and add keeps when
  introducing a plugin that uses reflection.
- `android/gradle.properties` sets `android.builtInKotlin=true`. A plugin that
  applies `kotlin-android` unconditionally breaks this mode; the "plugins that
  apply KGP: home_widget" build warning is a known false positive.
- `/backups/` holds real personal health data pulled off the phone and is
  gitignored. Never commit it.
- `README.md` predates the current assistant: it describes an Anthropic
  `claude_service.dart`, which no longer exists (the assistant is Gemini, in
  `lib/ai_service.dart`). Trust the code over that section.
