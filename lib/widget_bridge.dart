import 'dart:math' as math;

import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import 'db.dart';
import 'med.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/pet.dart';
import 'xp.dart';

/// Pushes today's numbers to the Android home-screen widget.
///
/// All values are stored as strings so the Kotlin side can parse them without
/// caring about Int/Long boxing.
class HomeWidgetBridge {
  static const _provider = 'GlpalsWidgetProvider';
  static const _qualified = 'com.glpbuddy.glp_buddy.GlpalsWidgetProvider';

  static Future<void> update() async {
    try {
      final db = AppDb.instance;
      final now = DateTime.now();
      final today = DateFormat('yyyy-MM-dd').format(now);
      final streak = await db.streak();
      final last = await db.lastShot();
      final site = await db.suggestedSite();
      final log = await db.logFor(today);
      final meals = await db.mealsOn(today);
      final mealProtein = meals.fold<int>(0, (a, m) => a + m.proteinG);
      final calories = meals.fold<int>(0, (a, m) => a + m.calories);
      final species = petSpecies.value;
      final xp = await Xp.compute();
      final stage = species.stageFor(xp.total);
      final nextStage = species.next(stage);
      final water = log?.waterMl ?? 0;
      final protein = math.max(log?.proteinG ?? 0, mealProtein);
      final med = MedPrefs.instance.product;

      String shotLine;
      String lastShotLine;
      // Countdown for the widget: a live chronometer under a day, plain text
      // above that.
      var countdown = '—';
      var dueMs = 0;
      var soon = false;
      var fridge = false;
      if (last == null) {
        shotLine = 'No ${med.injected ? 'shots' : 'doses'} logged yet';
        lastShotLine = 'Log your first one';
      } else {
        final due = nextDoseAt(
              last: last,
              lastSkipPlannedFor: (await db.lastSkip())?.plannedFor,
              intervalDays: MedPrefs.instance.intervalDays,
            ) ??
            last.takenAt.add(Duration(days: MedPrefs.instance.intervalDays));
        final left = due.difference(now);
        dueMs = due.millisecondsSinceEpoch;
        soon = !left.isNegative && left < const Duration(hours: 24);
        fridge = med.needsFridge &&
            !left.isNegative &&
            left <= const Duration(hours: 2);
        countdown = left.isNegative ? 'due now' : fmtCountdown(left);
        shotLine = left.isNegative
            ? '${med.injected ? 'Shot' : 'Dose'} day is here 🎯 · $site'
            : 'Next in ${fmtCountdown(left)} · $site';
        final dose = last.doseMg == last.doseMg.roundToDouble()
            ? last.doseMg.toStringAsFixed(0)
            : last.doseMg.toString();
        lastShotLine =
            'Last ${DateFormat('EEE, MMM d').format(last.takenAt)} · $dose mg · ${last.site}';
      }

      // Growth: how far to the next companion stage.
      final String stageLine;
      if (nextStage == null) {
        stageLine = 'Fully grown ✨';
      } else {
        stageLine = 'Next: ${nextStage.emoji} ${nextStage.name} · '
            '${Xp.toNext(xp.total)} XP to go';
      }

      // Weight: latest logged value and change since the entry before it.
      final logs = await db.logs(days: 365);
      final weighed = logs.where((l) => l.weightKg != null).toList();
      String weightLine;
      if (weighed.isEmpty) {
        weightLine = 'No weight yet';
      } else {
        final cur = weighed.last.weightKg!;
        weightLine = '${cur.toStringAsFixed(1)} kg';
        if (weighed.length >= 2) {
          final diff = cur - weighed[weighed.length - 2].weightKg!;
          if (diff.abs() >= 0.05) {
            weightLine +=
                ' (${diff > 0 ? '+' : '−'}${diff.abs().toStringAsFixed(1)})';
          }
        }
      }

      final mealsLine = meals.isEmpty
          ? 'No meals yet'
          : '${meals.length} meal${meals.length == 1 ? '' : 's'} · $calories kcal';

      final values = <String, String>{
        'pet_emoji': stage.emoji,
        'pet_name': stage.name,
        'streak': '$streak',
        'mood': PetStage.mood(streak),
        'water_ml': '$water',
        'water_goal': '${Goals.waterMl}',
        'protein_g': '$protein',
        'protein_goal': '${Goals.proteinG}',
        'calories': '$calories',
        'calories_goal': '${Goals.caloriesKcal}',
        'shot_line': shotLine,
        'last_shot_line': lastShotLine,
        'stage_line': stageLine,
        'stage_progress': '${(species.progress(xp.total) * 100).round()}',
        'xp_total': '${xp.total}',
        'xp_today': '${xp.today.earned}',
        'widget_style': WidgetPrefs.style,
        'widget_text': WidgetPrefs.textSize,
        'shot_countdown': countdown,
        'shot_due_ms': '$dueMs',
        'shot_soon': soon ? '1' : '0',
        'fridge_tip': fridge ? '1' : '0',
        'weight_line': weightLine,
        'meals_line': mealsLine,
        'checked_in': log == null ? '0' : '1',
        'updated': DateFormat('h:mm a').format(now),
      };
      for (final e in values.entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }
      await HomeWidget.updateWidget(
          androidName: _provider, qualifiedAndroidName: _qualified);
    } catch (_) {
      // The widget is a nice-to-have; never let it break a save.
    }
  }
}
