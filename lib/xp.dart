import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'db.dart';
import 'theme.dart';

/// One thing worth doing in a day. Completing it feeds the companion.
class Quest {
  const Quest(this.id, this.label, this.emoji, this.xp, this.color,
      {this.repeatable = 1});

  final String id;
  final String label;
  final String emoji;

  /// Experience for one completion.
  final int xp;
  final Color color;

  /// How many times a day it can pay out (meals pay up to three times).
  final int repeatable;

  int get maxXp => xp * repeatable;

  static const checkIn =
      Quest('checkin', 'Save a check-in', '📝', 5, Palette.lavender);
  static const meal =
      Quest('meal', 'Log a meal', '🍽️', 5, Palette.sunshine, repeatable: 3);
  static const protein =
      Quest('protein', 'Reach your protein goal', '🥩', 20, Palette.mint);
  static const water =
      Quest('water', 'Reach your water goal', '💧', 15, Palette.sky);
  static const fiber =
      Quest('fiber', 'Reach your fiber goal', '🌾', 10, Palette.peach);
  static const weight =
      Quest('weight', 'Log your weight', '⚖️', 10, Palette.lavender);
  static const shot = Quest('shot', 'Log your shot', '💉', 50, Palette.coral);
  static const perfect =
      Quest('perfect', 'Perfect day bonus', '🌟', 25, Palette.berry);

  /// Order shown on the Home quest card.
  static const daily = [checkIn, meal, protein, water, fiber, weight];
}

/// What one day earned, plus which quests were completed.
class DayScore {
  DayScore({
    required this.day,
    required this.earned,
    required this.done,
    required this.mealCount,
    required this.streakBonus,
  });

  final String day;
  final int earned;

  /// Quest id to times completed.
  final Map<String, int> done;
  final int mealCount;
  final int streakBonus;

  static final empty = DayScore(
      day: '', earned: 0, done: const {}, mealCount: 0, streakBonus: 0);

  bool has(Quest q) => (done[q.id] ?? 0) > 0;
  int count(Quest q) => done[q.id] ?? 0;
  int xpFor(Quest q) => q.xp * count(q);

  /// Everything on the daily list, ignoring the weekly shot.
  int get dailyMax =>
      Quest.daily.fold<int>(0, (a, q) => a + q.maxXp) + Quest.perfect.xp;
}

/// Experience totals for the companion.
///
/// Nothing is stored: every value is recomputed from the logs, meals and shots
/// already in the database. That keeps it honest when a day is backfilled from
/// the calendar, when a meal is edited, or when a cloud backup is restored —
/// there is no counter that can drift away from the data.
class Xp {
  /// Experience needed to reach each companion stage. The gap roughly doubles
  /// each time, so later evolutions feel earned.
  static const tiers = [0, 150, 500, 1200, 2500];

  /// Consistency bonus, capped so a long streak cannot run away with it.
  static const maxStreakBonus = 10;

  static DayScore scoreDay({
    required String day,
    DailyLog? log,
    List<Meal> meals = const [],
    List<Shot> shots = const [],
    int streak = 0,
  }) {
    final done = <String, int>{};
    var earned = 0;

    void award(Quest q, [int times = 1]) {
      if (times <= 0) return;
      final n = times.clamp(1, q.repeatable);
      done[q.id] = n;
      earned += q.xp * n;
    }

    if (log != null) award(Quest.checkIn);
    if (meals.isNotEmpty) award(Quest.meal, meals.length);

    final mealProtein = meals.fold<int>(0, (a, m) => a + m.proteinG);
    final protein =
        (log?.proteinG ?? 0) > mealProtein ? log!.proteinG : mealProtein;
    final fiber = meals.fold<int>(0, (a, m) => a + m.fiberG);
    if (protein >= Goals.proteinG) award(Quest.protein);
    if ((log?.waterMl ?? 0) >= Goals.waterMl) award(Quest.water);
    if (fiber >= Goals.fiberG) award(Quest.fiber);
    if (log?.weightKg != null) award(Quest.weight);
    if (shots.isNotEmpty) award(Quest.shot);

    final perfect = done.containsKey(Quest.checkIn.id) &&
        done.containsKey(Quest.meal.id) &&
        done.containsKey(Quest.protein.id) &&
        done.containsKey(Quest.water.id);
    if (perfect) award(Quest.perfect);

    // Showing up repeatedly is worth a little on its own.
    final bonus = log == null ? 0 : streak.clamp(0, maxStreakBonus);
    earned += bonus;

    return DayScore(
      day: day,
      earned: earned,
      done: done,
      mealCount: meals.length,
      streakBonus: bonus,
    );
  }

  /// Recomputes the whole history. Cheap enough for a personal log.
  static Future<XpSummary> compute() async {
    final db = AppDb.instance;
    final logs = await db.allLogs();
    final meals = await db.meals();
    final shots = await db.shots();

    final logByDay = {for (final l in logs) l.day: l};
    final mealsByDay = <String, List<Meal>>{};
    for (final m in meals) {
      mealsByDay.putIfAbsent(_key(m.eatenAt), () => []).add(m);
    }
    final shotsByDay = <String, List<Shot>>{};
    for (final s in shots) {
      shotsByDay.putIfAbsent(_key(s.takenAt), () => []).add(s);
    }

    final days = <String>{
      ...logByDay.keys,
      ...mealsByDay.keys,
      ...shotsByDay.keys,
    }.toList()
      ..sort();

    final logged = logByDay.keys.toSet();
    var total = 0;
    DayScore? todayScore;
    final today = _key(DateTime.now());
    for (final d in days) {
      final score = scoreDay(
        day: d,
        log: logByDay[d],
        meals: mealsByDay[d] ?? const [],
        shots: shotsByDay[d] ?? const [],
        streak: _streakEndingOn(d, logged),
      );
      total += score.earned;
      if (d == today) todayScore = score;
    }

    return XpSummary(
      total: total,
      today: todayScore ??
          scoreDay(day: today, streak: _streakEndingOn(today, logged)),
      streak: await db.streak(),
    );
  }

  /// Consecutive logged days ending on [day] (inclusive).
  static int _streakEndingOn(String day, Set<String> logged) {
    if (!logged.contains(day)) return 0;
    var d = DateTime.parse(day);
    var n = 0;
    while (logged.contains(_key(d))) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  static String _key(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  // ---- Stage maths ----

  static int stageIndexFor(int xp) {
    var i = 0;
    for (var s = 0; s < tiers.length; s++) {
      if (xp >= tiers[s]) i = s;
    }
    return i;
  }

  /// Experience still needed for the next stage, or null when fully grown.
  static int? toNext(int xp) {
    final i = stageIndexFor(xp);
    return i >= tiers.length - 1 ? null : tiers[i + 1] - xp;
  }

  /// Progress through the current stage, 0..1.
  static double progress(int xp) {
    final i = stageIndexFor(xp);
    if (i >= tiers.length - 1) return 1;
    final from = tiers[i], to = tiers[i + 1];
    return ((xp - from) / (to - from)).clamp(0, 1).toDouble();
  }
}

class XpSummary {
  const XpSummary(
      {required this.total, required this.today, required this.streak});
  final int total;
  final DayScore today;
  final int streak;

  static final empty = XpSummary(total: 0, today: DayScore.empty, streak: 0);
}
