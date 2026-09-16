import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'db.dart';
import 'med.dart';
import 'reminders.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/pet.dart';
import 'xp.dart';

/// Whether the dose countdown is mirrored into the Dynamic Island and Lock
/// Screen, and how early it appears.
///
/// Off by default: a Live Activity is an always-on surface on someone's Lock
/// Screen, so it is something to opt into rather than something that appears
/// on its own after an update.
class LiveActivityPrefs {
  static const _onKey = 'live_activity_on';
  static const _leadKey = 'live_activity_lead_hours';

  static bool on = false;

  /// How long before a dose is due the activity appears.
  ///
  /// The default is 8 hours because that is roughly how long iOS lets an
  /// activity live before ending it on its own: starting much earlier would
  /// only mean it is gone by the time the dose is actually due.
  static int leadHours = 8;

  static const leadChoices = [2, 4, 8, 12];

  static final revision = ValueNotifier<int>(0);

  static Future<void> load() async {
    final db = AppDb.instance;
    on = (await db.getSetting(_onKey) ?? 'false') == 'true';
    leadHours = int.tryParse(await db.getSetting(_leadKey) ?? '') ?? 8;
    revision.value++;
  }

  static Future<void> set({bool? on, int? leadHours}) async {
    final db = AppDb.instance;
    if (on != null) {
      LiveActivityPrefs.on = on;
      await db.setSetting(_onKey, '$on');
    }
    if (leadHours != null) {
      LiveActivityPrefs.leadHours = leadHours;
      await db.setSetting(_leadKey, '$leadHours');
    }
    revision.value++;
    await LiveActivities.sync();
  }
}

/// What the Dynamic Island shows for an upcoming or late dose.
///
/// A plain value, so the decision of *whether* there should be an activity and
/// what it says can be tested without a phone. Everything the island renders is
/// here; the Swift side only hands it to ActivityKit.
@immutable
class DoseActivityState {
  const DoseActivityState({
    required this.dueAt,
    required this.staleAt,
    required this.overdue,
    required this.fridgeTip,
    required this.site,
    required this.doseMg,
    required this.productBrand,
    required this.productEmoji,
    required this.injected,
    required this.waterMl,
    required this.waterGoal,
    required this.proteinG,
    required this.proteinGoal,
    required this.palEmoji,
    this.headline = '',
  });

  /// When the dose is due. iOS counts down to this by itself, with nothing of
  /// ours running — that is what makes the island tick while the app is closed.
  final DateTime dueAt;

  /// When what the island says stops being true. iOS dims the activity after
  /// this, which is honest: past it, nobody has updated the content.
  final DateTime staleAt;

  final bool overdue;

  /// Inside the window where a fridge-kept pen is worth taking out.
  final bool fridgeTip;

  final String site;
  final double doseMg;
  final String productBrand;
  final String productEmoji;

  /// False for the oral tablet, which turns "shot" into "dose" in the island.
  final bool injected;

  final int waterMl;
  final int waterGoal;
  final int proteinG;
  final int proteinGoal;

  /// The companion's current stage emoji, for the one-glyph presentation the
  /// island falls back to when something else is competing for the space.
  final String palEmoji;

  /// What a reminder last said, so a water or meal nudge reads in the island
  /// and not only in a notification that has already been swiped away. Empty
  /// means "just show the dose".
  final String headline;

  String get noun => injected ? 'Shot' : 'Dose';

  /// Headline line: what this activity is about right now.
  String get title {
    if (overdue) return '$noun overdue';
    if (fridgeTip) return 'Warm the pen';
    return '$noun in';
  }

  /// The line under the countdown.
  String get detail {
    if (headline.isNotEmpty) return headline;
    if (overdue) {
      return injected ? 'Take it when you can · $site' : 'Take it when you can';
    }
    if (fridgeTip) return 'Out of the fridge now · $site';
    return injected
        ? '$productBrand ${fmtDose(doseMg)} mg · $site'
        : '$productBrand ${fmtDose(doseMg)} mg';
  }

  Map<String, Object?> toMap() => {
        'due_ms': dueAt.millisecondsSinceEpoch,
        'stale_ms': staleAt.millisecondsSinceEpoch,
        'overdue': overdue,
        'fridge_tip': fridgeTip,
        'title': title,
        'detail': detail,
        'brand': productBrand,
        'product_emoji': productEmoji,
        'pal_emoji': palEmoji,
        'water_ml': waterMl,
        'water_goal': waterGoal,
        'protein_g': proteinG,
        'protein_goal': proteinGoal,
      };

  /// Decides whether an activity belongs on screen at [now].
  ///
  /// Returns null when there should not be one: nothing to count down to, the
  /// dose is still days away, or it is so late that the product's make-up
  /// window has closed and nagging about it no longer helps anyone.
  static DoseActivityState? stateFor({
    required DateTime now,
    required DateTime? dueAt,
    required GlpProduct product,
    required double doseMg,
    required String site,
    required int leadHours,
    required bool fridgeOn,
    required int fridgeMinutes,
    int waterMl = 0,
    int proteinG = 0,
    int waterGoal = kWaterGoalMl,
    int proteinGoal = kProteinGoalG,
    String palEmoji = '🥚',
    String headline = '',
  }) {
    if (dueAt == null) return null;
    final left = dueAt.difference(now);
    final overdue = left.isNegative;

    // Past the window the label allows a late dose in, this stops being a
    // useful nudge. Daily products get a day: the next one is tomorrow anyway.
    final grace = Duration(days: product.makeUpDays == 0 ? 1 : product.makeUpDays);

    if (overdue) {
      if (-left > grace) return null;
    } else if (left > Duration(hours: leadHours)) {
      return null;
    }

    return DoseActivityState(
      dueAt: dueAt,
      staleAt: overdue ? dueAt.add(grace) : dueAt,
      overdue: overdue,
      fridgeTip: product.needsFridge &&
          fridgeOn &&
          !overdue &&
          left <= Duration(minutes: fridgeMinutes),
      site: site,
      doseMg: doseMg,
      productBrand: product.brand,
      productEmoji: product.emoji,
      injected: product.injected,
      waterMl: waterMl,
      waterGoal: waterGoal,
      proteinG: proteinG,
      proteinGoal: proteinGoal,
      palEmoji: palEmoji,
      headline: headline,
    );
  }
}

/// Mirrors the dose countdown into the iOS Dynamic Island and Lock Screen.
///
/// Android has no equivalent surface — its version of this is the home-screen
/// widget in HomeWidgetBridge — so every call here is a no-op off iOS.
///
/// Only the clock updates itself: iOS renders the countdown from
/// [DoseActivityState.dueAt] with nothing of ours running, which is why the
/// island keeps ticking while the app is closed. Everything else changes when
/// the app or a notification action runs. Pushing content to a closed app would
/// need ActivityKit push tokens and a server to hold them, and GLPals
/// deliberately has neither, so a reminder reaches the island the next time
/// anything of ours runs rather than the instant it fires.
class LiveActivities {
  static const _channel = MethodChannel('glpals/live_activity');

  /// How long a delivered reminder keeps its place in the island. A nudge from
  /// this morning should not still be sitting there this afternoon.
  static const headlineTtl = Duration(minutes: 90);

  /// A reminder this new is worth buzzing the island for. Older than this and
  /// the content is updated quietly: the notification itself already alerted.
  static const alertWindow = Duration(minutes: 10);

  /// Reminders the island should not echo, because it already says this itself
  /// and with a live clock.
  ///
  /// Only 'shot' is needed: Reminders derives a row's kind from the payload, and
  /// the dose reminder, the heads-up before it and the warm-the-pen nudge all
  /// carry the 'shot' payload, so one entry covers all three.
  static const _ownKinds = {'shot'};

  static bool get _available => Platform.isIOS;

  /// The most recent delivered reminder worth showing in the island, or null.
  ///
  /// Pulled from notif_log rather than remembered in a field, so it survives
  /// the app being killed and works the same in the background isolate.
  /// Anything already acted on is skipped: there is nothing left to nudge about.
  static NotifLog? headlineFrom(List<NotifLog> notifs, DateTime now) {
    for (final n in notifs) {
      // Deliberately not NotifLog.delivered: that reads the wall clock, and
      // every decision here has to come from the [now] it was handed.
      if (n.at.isAfter(now)) continue; // still queued
      if (now.difference(n.at) > headlineTtl) break; // newest first: done
      if (_ownKinds.contains(n.kind)) continue;
      if (n.action != null) continue;
      return n;
    }
    return null;
  }

  /// Recomputes the activity from what is in the database and starts, updates
  /// or ends it to match. Cheap; called from Reminders.sync, which every save
  /// already goes through.
  static Future<void> sync() async {
    if (!_available) return;
    try {
      if (!LiveActivityPrefs.on) {
        await _channel.invokeMethod('end');
        return;
      }

      final db = AppDb.instance;
      final now = DateTime.now();
      final med = MedPrefs.instance;
      final last = await db.lastShot();
      final dueAt = last == null
          ? null
          : nextDoseAt(
                last: last,
                lastSkipPlannedFor: (await db.lastSkip())?.plannedFor,
                intervalDays: med.intervalDays,
              ) ??
              last.takenAt.add(Duration(days: med.intervalDays));

      final today = dayKey(now);
      final log = await db.logFor(today);
      final meals = await db.mealsOn(today);
      final mealProtein = meals.fold<int>(0, (a, m) => a + m.proteinG);
      final xp = await Xp.compute();
      final prefs = ReminderPrefs.instance;
      final nudge = headlineFrom(await db.notifs(limit: 20), now);

      final state = DoseActivityState.stateFor(
        now: now,
        dueAt: dueAt,
        product: med.product,
        doseMg: last?.doseMg ?? med.doseMg,
        site: await db.suggestedSite(),
        leadHours: LiveActivityPrefs.leadHours,
        fridgeOn: prefs.fridgeOn,
        fridgeMinutes: prefs.fridgeMinutes,
        waterMl: log?.waterMl ?? 0,
        proteinG:
            (log?.proteinG ?? 0) > mealProtein ? log!.proteinG : mealProtein,
        waterGoal: Goals.waterMl,
        proteinGoal: Goals.proteinG,
        palEmoji: petSpecies.value.stageFor(xp.total).emoji,
        // Titles are short ('Sip time 💧'); bodies are a sentence written for
        // a notification and would only be cut off on the island's one line.
        headline: nudge?.title ?? '',
      );

      if (state == null) {
        await _channel.invokeMethod('end');
        return;
      }

      // An update carrying an alert is what makes the island expand and buzz,
      // so it is reserved for a reminder that has only just landed.
      final fresh = nudge != null && now.difference(nudge.at) <= alertWindow;

      await _channel.invokeMethod('sync', {
        ...state.toMap(),
        'alert': fresh,
        'alert_title': nudge?.title ?? state.title,
        'alert_body': nudge?.body ?? state.detail,
      });
    } catch (e) {
      // The island is a nice-to-have, exactly like the home-screen widget:
      // never let it break a save.
      debugPrint('Live activity sync failed: $e');
    }
  }

  /// Takes the activity down, e.g. when the feature is switched off.
  static Future<void> end() async {
    if (!_available) return;
    try {
      await _channel.invokeMethod('end');
    } catch (_) {}
  }
}
