import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'db.dart';
import 'med.dart';
import 'notification_actions.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// A meal slot the user can be nudged about.
class MealSlot {
  const MealSlot(this.id, this.label, this.emoji, this.defaultMinutes);
  final String id;
  final String label;
  final String emoji;

  /// Default time as minutes since midnight.
  final int defaultMinutes;

  static const all = [
    MealSlot('breakfast', 'Breakfast', '🍳', 8 * 60),
    MealSlot('lunch', 'Lunch', '🥗', 12 * 60 + 30),
    MealSlot('snack', 'Snack', '🍎', 16 * 60),
    MealSlot('dinner', 'Dinner', '🍲', 19 * 60),
  ];
}

/// User-configurable reminder settings, persisted in the settings table.
class ReminderPrefs extends ChangeNotifier {
  ReminderPrefs._();
  static final ReminderPrefs instance = ReminderPrefs._();

  bool shotOn = true;
  int shotWeekday = DateTime.saturday;
  int shotMinutes = 9 * 60;

  /// Heads-up before the dose is due, and the nudge to warm the pen.
  bool countdownOn = true;
  int countdownMinutes = 60;
  bool fridgeOn = true;
  int fridgeMinutes = 45;

  bool waterOn = false;
  int waterStart = 8 * 60;
  int waterEnd = 20 * 60;
  int waterEveryHours = 2;

  final Map<String, bool> mealOn = {for (final m in MealSlot.all) m.id: false};
  final Map<String, int> mealMinutes = {
    for (final m in MealSlot.all) m.id: m.defaultMinutes
  };

  Future<void> load() async {
    final db = AppDb.instance;
    Future<String?> g(String k) => db.getSetting(k);
    shotOn = (await g('rem_shot_on') ?? 'true') == 'true';
    shotWeekday =
        int.tryParse(await g('reminder_weekday') ?? '') ?? DateTime.saturday;
    shotMinutes = int.tryParse(await g('rem_shot_minutes') ?? '') ?? 9 * 60;
    countdownOn = (await g('rem_countdown_on') ?? 'true') == 'true';
    countdownMinutes =
        int.tryParse(await g('rem_countdown_minutes') ?? '') ?? 60;
    fridgeOn = (await g('rem_fridge_on') ?? 'true') == 'true';
    fridgeMinutes = int.tryParse(await g('rem_fridge_minutes') ?? '') ?? 45;
    waterOn = (await g('rem_water_on') ?? 'false') == 'true';
    waterStart = int.tryParse(await g('rem_water_start') ?? '') ?? 8 * 60;
    waterEnd = int.tryParse(await g('rem_water_end') ?? '') ?? 20 * 60;
    waterEveryHours = int.tryParse(await g('rem_water_every') ?? '') ?? 2;
    for (final m in MealSlot.all) {
      mealOn[m.id] = (await g('rem_meal_${m.id}_on') ?? 'false') == 'true';
      mealMinutes[m.id] =
          int.tryParse(await g('rem_meal_${m.id}_minutes') ?? '') ??
              m.defaultMinutes;
    }
    notifyListeners();
  }

  Future<void> save() async {
    final db = AppDb.instance;
    Future<void> s(String k, Object v) => db.setSetting(k, v.toString());
    await s('rem_shot_on', shotOn);
    await s('reminder_weekday', shotWeekday);
    await s('rem_shot_minutes', shotMinutes);
    await s('rem_countdown_on', countdownOn);
    await s('rem_countdown_minutes', countdownMinutes);
    await s('rem_fridge_on', fridgeOn);
    await s('rem_fridge_minutes', fridgeMinutes);
    await s('rem_water_on', waterOn);
    await s('rem_water_start', waterStart);
    await s('rem_water_end', waterEnd);
    await s('rem_water_every', waterEveryHours);
    for (final m in MealSlot.all) {
      await s('rem_meal_${m.id}_on', mealOn[m.id]!);
      await s('rem_meal_${m.id}_minutes', mealMinutes[m.id]!);
    }
    notifyListeners();
    await Reminders.sync();
  }

  static String fmt(int minutes) {
    final t = DateTime(2000, 1, 1, minutes ~/ 60, minutes % 60);
    return DateFormat('h:mm a').format(t);
  }
}

/// Schedules local notifications from [ReminderPrefs] plus what is already
/// logged today, so nudges disappear once the thing is done. Each notification
/// carries action buttons so the user can log without opening the app.
class Reminders {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Invoked in the foreground after a notification action changed data.
  static VoidCallback? onChanged;

  static const _shotId = 1;
  static const _snoozeId = 2;
  static const _countdownId = 3;
  static const _fridgeId = 4;
  static const _waterBase = 100; // 100..123 by hour of day
  static const _mealBase = 200; // 200..203 by slot index

  /// iOS only shows action buttons for categories declared up front, and only
  /// on notifications that name their category. Android takes its actions from
  /// the channel details instead, so the two lists must be kept in step: the
  /// identifiers here are the ones NotificationActions handles.
  static final _iosCategories = <DarwinNotificationCategory>[
    DarwinNotificationCategory(
      'shot',
      actions: [
        DarwinNotificationAction.plain('shot_now', 'Took it'),
        DarwinNotificationAction.plain('shot_snooze', 'Remind in 1 h'),
      ],
    ),
    DarwinNotificationCategory(
      'water',
      actions: [
        DarwinNotificationAction.plain('water_1', '+1 glass'),
        DarwinNotificationAction.plain('water_2', '+2 glasses'),
      ],
    ),
    DarwinNotificationCategory(
      'meal',
      actions: [
        DarwinNotificationAction.text(
          'meal_text',
          'Log meal',
          buttonTitle: 'Save',
          placeholder: 'What did you eat?',
        ),
        DarwinNotificationAction.plain('meal_skip', 'Skip today'),
      ],
    ),
  ];

  static final _initSettings = InitializationSettings(
    android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(notificationCategories: _iosCategories),
  );

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Manila'));
    await _plugin.initialize(
      _initSettings,
      onDidReceiveNotificationResponse: _onForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: notificationActionBackground,
    );
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    // iOS asks during initialize, but asking again is harmless and covers an
    // install that predates these categories.
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    // Pre-chime channels; their settings are frozen by Android, so they were
    // replaced by *_v2 channels that carry the custom sound.
    for (final old in const ['shots', 'water', 'meals']) {
      try {
        await android?.deleteNotificationChannel(old);
      } catch (_) {}
    }
    _ready = true;
    await ReminderPrefs.instance.load();
    await sync();
    // Build with --dart-define=GLPALS_TEST_NOTIFY=true to hear the chime on
    // launch; dead code otherwise.
    if (_fireTestOnLaunch) await playChime();
  }

  static const _fireTestOnLaunch = bool.fromEnvironment('GLPALS_TEST_NOTIFY');
  static const _testId = 999;

  /// Posts a one-off notification so the user can hear the reminder chime.
  static Future<void> playChime() async {
    if (!_ready) return;
    await _plugin.show(
      _testId,
      'This is your reminder chime 🔔',
      'Shot, water and meal reminders all sound like this.',
      const NotificationDetails(
        android: _shotDetails,
        iOS: DarwinNotificationDetails(sound: 'glpals_chime.wav'),
      ),
    );
  }

  /// Posts a live water reminder so the action buttons (and any paired watch)
  /// can be checked without waiting for a scheduled one.
  static Future<void> testReminder() async {
    if (!_ready) return;
    await AppDb.instance.logNotif(NotifLog(
      at: DateTime.now(),
      kind: 'water',
      title: 'Sip time 💧',
      body: 'Test reminder sent from Settings.',
    ));
    await _plugin.show(
      _waterBase,
      'Sip time 💧',
      'Tap +1 glass to check the buttons. This also shows on a paired watch.',
      const NotificationDetails(
        android: _waterDetails,
        iOS: DarwinNotificationDetails(
          sound: 'glpals_chime.wav',
          categoryIdentifier: 'water',
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      payload: 'water',
    );
  }

  /// Minimal setup for the background isolate (no permission prompts).
  static Future<void> initBackground() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Manila'));
    // The same callbacks are passed here: initialize() rewrites the stored
    // background dispatcher handle, and dropping it would break every later
    // action button.
    await _plugin.initialize(
      _initSettings,
      onDidReceiveNotificationResponse: _onForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: notificationActionBackground,
    );
    _ready = true;
    await ReminderPrefs.instance.load();
  }

  static Future<void> _onForegroundResponse(NotificationResponse r) async {
    if (r.actionId == null || r.actionId!.isEmpty) return;
    await NotificationActions.handle(r);
    onChanged?.call();
  }

  /// Recomputes every scheduled notification. Cheap; call after any save.
  static Future<void> sync() async {
    if (!_ready) return;
    final p = ReminderPrefs.instance;
    final db = AppDb.instance;
    final now = tz.TZDateTime.now(tz.local);
    final todayKey = DateFormat('yyyy-MM-dd').format(now);

    await _plugin.cancelAll();
    await db.clearQueuedNotifs();

    // ---- Shot: anchored to the last logged shot, plus a heads-up and a
    // "warm the pen" nudge before it. The gap between doses comes from the
    // product (weekly for most pens, daily for liraglutide and the tablet).
    final med = MedPrefs.instance;
    if (p.shotOn) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestExactAlarmsPermission();
      final last = await db.lastShot();
      final site = await db.suggestedSite();
      final noun = med.product.injected ? 'Shot' : 'Dose';
      tz.TZDateTime? due;
      var overdue = false;

      if (last == null) {
        // Nothing logged yet: fall back to the chosen day (or every day for a
        // daily product) at the chosen time.
        var next = _at(now, p.shotMinutes);
        if (med.intervalDays == 1) {
          if (next.isBefore(now)) next = next.add(const Duration(days: 1));
        } else {
          while (next.weekday != p.shotWeekday || next.isBefore(now)) {
            next = next.add(const Duration(days: 1));
          }
        }
        due = next;
        await _schedule(
          id: _shotId,
          when: next,
          title: '$noun day 💉',
          body: med.product.injected
              ? "Time for this week's dose. Suggested site: $site."
              : 'Time for your ${med.product.brand} tablet.',
          details: _shotDetails,
          payload: 'shot',
          repeat: med.intervalDays == 1
              ? DateTimeComponents.time
              : DateTimeComponents.dayOfWeekAndTime,
          exact: true,
        );
      } else {
        final skipped = await db.lastSkip();
        final anchor = nextDoseAt(
              last: last,
              lastSkipPlannedFor: skipped?.plannedFor,
              intervalDays: med.intervalDays,
            ) ??
            last.takenAt.add(Duration(days: med.intervalDays));
        final target = tz.TZDateTime.from(anchor, tz.local);
        var next = _at(target, p.shotMinutes);
        overdue = next.isBefore(now);
        if (overdue) {
          // Overdue: nudge once a day at the chosen time until it is logged.
          next = _at(now, p.shotMinutes);
          if (next.isBefore(now)) next = next.add(const Duration(days: 1));
        }
        due = next;
        await _schedule(
          id: _shotId,
          when: next,
          title: overdue ? '$noun still due 💉' : '$noun day 💉',
          body: overdue
              ? 'Your last dose was ${DateFormat('EEE, MMM d').format(last.takenAt)}. Tap "Took it" when you have.'
              : med.product.injected
                  ? 'Time for your ${fmtDose(last.doseMg)} mg dose. Suggested site: $site.'
                  : 'Time for your ${fmtDose(last.doseMg)} mg tablet.',
          details: _shotDetails,
          payload: 'shot',
          repeat: overdue ? DateTimeComponents.time : null,
          exact: true,
        );
      }

      if (!overdue) {
        // One hour to go, with its own chime.
        if (p.countdownOn) {
          final when = due.subtract(Duration(minutes: p.countdownMinutes));
          if (when.isAfter(now)) {
            await _schedule(
              id: _countdownId,
              when: when,
              title:
                  '$noun in ${fmtCountdown(Duration(minutes: p.countdownMinutes))} ⏳',
              body: med.product.injected
                  ? 'Due at ${ReminderPrefs.fmt(p.shotMinutes)}. Suggested site: $site.'
                  : 'Due at ${ReminderPrefs.fmt(p.shotMinutes)} on an empty stomach.',
              details: _countdownDetails,
              payload: 'shot',
              exact: true,
            );
          }
        }
        // Pens sit more comfortably at room temperature.
        if (p.fridgeOn && med.product.needsFridge) {
          final when = due.subtract(Duration(minutes: p.fridgeMinutes));
          if (when.isAfter(now)) {
            await _schedule(
              id: _fridgeId,
              when: when,
              title: 'Take your pen out of the fridge 🧊',
              body:
                  'About ${p.fridgeMinutes} minutes at room temperature makes the shot '
                  'much more comfortable. Due at ${ReminderPrefs.fmt(p.shotMinutes)}.',
              details: _countdownDetails,
              payload: 'shot',
              exact: true,
            );
          }
        }
      }
    }

    // ---- Water: repeating daily slots, skipped for today once the goal is met.
    if (p.waterOn) {
      final today = await db.logFor(todayKey);
      final water = today?.waterMl ?? 0;
      final goalMet = water >= Goals.waterMl;
      final every = p.waterEveryHours.clamp(1, 6);
      var i = 0;
      for (var m = p.waterStart; m <= p.waterEnd; m += every * 60) {
        var when = _at(now, m);
        if (when.isBefore(now) || goalMet) {
          when = when.add(const Duration(days: 1));
        }
        final left = (Goals.waterMl - water).clamp(0, Goals.waterMl);
        await _schedule(
          id: _waterBase + (m ~/ 60).clamp(0, 23),
          when: when,
          title: _waterTitles[i % _waterTitles.length],
          body: goalMet
              ? 'A fresh day, a fresh ${Goals.waterMl} ml. Log a glass below.'
              : 'You are at $water ml, $left ml to go. Log a glass below.',
          details: _waterDetails,
          payload: 'water',
          repeat: DateTimeComponents.time,
        );
        i++;
      }
    }

    // ---- Meals: daily per slot, skipped for today once something is logged nearby.
    final mealsToday = await db.mealsOn(todayKey);
    for (var s = 0; s < MealSlot.all.length; s++) {
      final slot = MealSlot.all[s];
      if (!(p.mealOn[slot.id] ?? false)) continue;
      final minutes = p.mealMinutes[slot.id] ?? slot.defaultMinutes;
      var when = _at(now, minutes);
      final windowStart = when.subtract(const Duration(hours: 2));
      final loggedNearby =
          mealsToday.any((m) => !m.eatenAt.isBefore(windowStart));
      final skipped =
          await db.getSetting('rem_meal_${slot.id}_skip') == todayKey;
      if (when.isBefore(now) || loggedNearby || skipped) {
        when = when.add(const Duration(days: 1));
      }
      await _schedule(
        id: _mealBase + s,
        when: when,
        title: '${slot.label} ${slot.emoji}',
        body: _mealBodies[s],
        details: _mealDetails,
        payload: 'meal:${slot.id}',
        repeat: DateTimeComponents.time,
      );
    }
  }

  /// One-off shot nudge an hour from now (from the "Remind in 1 h" action).
  static Future<void> snoozeShot() async {
    if (!_ready) return;
    final when = tz.TZDateTime.now(tz.local).add(const Duration(hours: 1));
    await _schedule(
      id: _snoozeId,
      when: when,
      title: 'Shot reminder 💉',
      body: 'Snoozed an hour ago. Ready now?',
      details: _shotDetails,
      payload: 'shot',
      exact: true,
    );
  }

  static Future<void> cancelAll() => _plugin.cancelAll();

  // ---- helpers ----

  static tz.TZDateTime _at(tz.TZDateTime day, int minutes) => tz.TZDateTime(
      tz.local, day.year, day.month, day.day, minutes ~/ 60, minutes % 60);

  static Future<void> _schedule({
    required int id,
    required tz.TZDateTime when,
    required String title,
    required String body,
    required AndroidNotificationDetails details,
    required String payload,
    DateTimeComponents? repeat,
    bool exact = false,
  }) async {
    // Queued entry for the in-app panel; past entries are the delivery log.
    await AppDb.instance.logNotif(NotifLog(
      // TZDateTime.toLocal() hands back the UTC wall clock, so go through the
      // epoch to get a plain local DateTime the panel can format.
      at: DateTime.fromMillisecondsSinceEpoch(when.millisecondsSinceEpoch),
      kind: payload.split(':').first,
      title: title,
      body: body,
    ));
    return _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      NotificationDetails(
        android: details,
        // iOS resolves the sound from a file in the app bundle. The same WAVs
        // the Android channels use are copied into ios/Runner, so the
        // countdown keeps its distinct chime there too.
        iOS: DarwinNotificationDetails(
          sound: details.channelId == 'countdown_v1'
              ? 'glpals_countdown.wav'
              : 'glpals_chime.wav',
          // Without a category iOS shows no buttons at all.
          categoryIdentifier: payload.split(':').first,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      payload: payload,
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: repeat,
    );
  }

  /// Short custom chime in android/app/src/main/res/raw/glpals_chime.wav.
  static const _chime = RawResourceAndroidNotificationSound('glpals_chime');

  static const _shotDetails = AndroidNotificationDetails(
    'shots_v2',
    'Shot reminders',
    channelDescription: 'Weekly dose reminders',
    importance: Importance.high,
    priority: Priority.high,
    sound: _chime,
    category: AndroidNotificationCategory.reminder,
    visibility: NotificationVisibility.public,
    ticker: 'Shot reminder',
    actions: [
      AndroidNotificationAction('shot_now', 'Took it ✅'),
      AndroidNotificationAction('shot_snooze', 'Remind in 1 h'),
    ],
  );

  /// A rising arpeggio, deliberately different from the reminder chime so the
  /// pre-shot heads-up is recognisable without looking.
  static const _countdownChime =
      RawResourceAndroidNotificationSound('glpals_countdown');

  static const _countdownDetails = AndroidNotificationDetails(
    'countdown_v1',
    'Shot countdown',
    channelDescription:
        'Heads-up before your dose, and the nudge to warm the pen',
    importance: Importance.high,
    priority: Priority.high,
    sound: _countdownChime,
    category: AndroidNotificationCategory.reminder,
    visibility: NotificationVisibility.public,
    ticker: 'Shot countdown',
    actions: [
      AndroidNotificationAction('shot_now', 'Took it ✅'),
    ],
  );

  static const _waterDetails = AndroidNotificationDetails(
    'water_v2',
    'Water reminders',
    channelDescription: 'Hydration nudges during the day',
    importance: Importance.high,
    priority: Priority.high,
    sound: _chime,
    category: AndroidNotificationCategory.reminder,
    visibility: NotificationVisibility.public,
    ticker: 'Water reminder',
    actions: [
      AndroidNotificationAction('water_1', '+1 glass'),
      AndroidNotificationAction('water_2', '+2 glasses'),
    ],
  );
  static const _mealDetails = AndroidNotificationDetails(
    'meals_v2',
    'Meal logging reminders',
    channelDescription: 'Reminders to log meals',
    importance: Importance.high,
    priority: Priority.high,
    sound: _chime,
    category: AndroidNotificationCategory.reminder,
    visibility: NotificationVisibility.public,
    ticker: 'Meal reminder',
    actions: [
      AndroidNotificationAction(
        'meal_text',
        'Log meal',
        inputs: [AndroidNotificationActionInput(label: 'What did you eat?')],
      ),
      AndroidNotificationAction('meal_skip', 'Skip today'),
    ],
  );

  static const _waterTitles = [
    'Sip time 💧',
    'Water break 💦',
    'Hydration check 🚰',
    'Little sip, big win 💧',
  ];
  static const _mealBodies = [
    'Had breakfast? Type it below and it is logged.',
    'Lunch logged? Type what you ate and your buddy keeps count.',
    'Snack time. Type it below to log it in one go.',
    'Dinner done? Type it below to close out the day.',
  ];
}
