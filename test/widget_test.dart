import 'package:flutter_test/flutter_test.dart';
import 'package:glp_buddy/db.dart';
import 'package:glp_buddy/live_activity.dart';
import 'package:glp_buddy/med.dart';
import 'package:glp_buddy/widgets/common.dart';
import 'package:glp_buddy/xp.dart';

/// Pure logic only: anything that pumps the app needs sqflite and the
/// notification plugin, which are not available in a plain test run.
void main() {
  group('experience tiers', () {
    test('stage rises with total experience', () {
      expect(Xp.stageIndexFor(0), 0);
      expect(Xp.stageIndexFor(149), 0);
      expect(Xp.stageIndexFor(150), 1);
      expect(Xp.stageIndexFor(500), 2);
      expect(Xp.stageIndexFor(1200), 3);
      expect(Xp.stageIndexFor(2500), 4);
      expect(Xp.stageIndexFor(99999), 4);
    });

    test('each tier costs more than the one before', () {
      final gaps = [
        for (var i = 1; i < Xp.tiers.length; i++)
          Xp.tiers[i] - Xp.tiers[i - 1],
      ];
      for (var i = 1; i < gaps.length; i++) {
        expect(gaps[i], greaterThan(gaps[i - 1]));
      }
    });

    test('progress fills between tiers and caps at the top', () {
      expect(Xp.progress(0), 0);
      expect(Xp.progress(75), closeTo(0.5, 0.01));
      expect(Xp.progress(2500), 1);
      expect(Xp.toNext(2500), isNull);
      expect(Xp.toNext(100), 50);
    });
  });

  group('dose schedule', () {
    final last = Shot(
      takenAt: DateTime(2026, 9, 1, 9),
      doseMg: 2.5,
      site: 'Abdomen L',
    );

    test('next dose follows the product interval', () {
      final due = nextDoseAt(
          last: last, lastSkipPlannedFor: null, intervalDays: 7);
      expect(due, DateTime(2026, 9, 8, 9));
    });

    test('a skipped dose moves the schedule on', () {
      final due = nextDoseAt(
        last: last,
        lastSkipPlannedFor: DateTime(2026, 9, 8, 9),
        intervalDays: 7,
      );
      expect(due, DateTime(2026, 9, 15, 9));
    });

    test('forecast rotates the injection site', () {
      final doses =
          forecastDoses(last: last, intervalDays: 7, count: 3);
      expect(doses.length, 3);
      expect(doses.map((d) => d.site).toSet().length, 3);
      expect(doses.first.due, DateTime(2026, 9, 8, 9));
    });

    test('make-up window matches the molecule', () {
      expect(GlpProduct.byId('ozempic').makeUpDays, 5);
      expect(GlpProduct.byId('mounjaro').makeUpDays, 4);
      expect(GlpProduct.byId('saxenda').makeUpDays, 0);
    });
  });

  group('countdown formatting', () {
    test('reads in the largest useful unit', () {
      expect(fmtCountdown(const Duration(days: 2, hours: 4)), '2d 4h');
      expect(fmtCountdown(const Duration(hours: 3, minutes: 20)), '3h 20m');
      expect(fmtCountdown(const Duration(minutes: 45)), '45m');
      expect(fmtCountdown(const Duration(seconds: -5)), 'now');
    });
  });

  group('dynamic island', () {
    final mounjaro = GlpProduct.byId('mounjaro'); // weekly pen, 4 make-up days
    final rybelsus = GlpProduct.all.firstWhere((p) => !p.injected);
    final now = DateTime(2026, 9, 16, 9);

    DoseActivityState? state({
      DateTime? due,
      GlpProduct? product,
      int leadHours = 8,
      int fridgeMinutes = 45,
      bool fridgeOn = true,
      String headline = '',
    }) =>
        DoseActivityState.stateFor(
          now: now,
          dueAt: due,
          product: product ?? mounjaro,
          doseMg: 7.5,
          site: 'Thigh L',
          leadHours: leadHours,
          fridgeOn: fridgeOn,
          fridgeMinutes: fridgeMinutes,
          headline: headline,
        );

    test('stays away until the dose is inside the lead window', () {
      expect(state(due: now.add(const Duration(hours: 9))), isNull);
      expect(state(due: now.add(const Duration(hours: 7))), isNotNull);
      expect(state(due: now.add(const Duration(days: 6))), isNull);
    });

    test('nothing logged yet means nothing to count down to', () {
      expect(state(due: null), isNull);
    });

    test('a late dose stays up only while it can still be taken', () {
      // Tirzepatide allows 4 days.
      expect(state(due: now.subtract(const Duration(days: 3)))?.overdue, true);
      expect(state(due: now.subtract(const Duration(days: 5))), isNull);
    });

    test('a daily product gets a day of grace, not the weekly window', () {
      expect(state(due: now.subtract(const Duration(hours: 20)),
              product: rybelsus)
          ?.overdue, true);
      expect(
          state(due: now.subtract(const Duration(days: 2)), product: rybelsus),
          isNull);
    });

    test('the fridge tip appears only inside its own window', () {
      expect(state(due: now.add(const Duration(minutes: 30)))?.fridgeTip, true);
      expect(state(due: now.add(const Duration(hours: 4)))?.fridgeTip, false);
      expect(
          state(due: now.add(const Duration(minutes: 30)), fridgeOn: false)
              ?.fridgeTip,
          false);
    });

    test('a tablet is never asked to come out of the fridge', () {
      expect(
          state(due: now.add(const Duration(minutes: 30)), product: rybelsus)
              ?.fridgeTip,
          false);
    });

    test('wording follows the product and the state', () {
      final soon = state(due: now.add(const Duration(hours: 4)))!;
      expect(soon.title, 'Shot in');
      expect(soon.detail, contains('Mounjaro'));
      expect(soon.detail, contains('Thigh L'));

      expect(state(due: now.subtract(const Duration(hours: 2)))!.title,
          'Shot overdue');
      expect(
          state(due: now.add(const Duration(hours: 4)), product: rybelsus)!
              .title,
          'Dose in');
    });

    test('a reminder takes over the detail line', () {
      final s = state(
          due: now.add(const Duration(hours: 4)), headline: 'Time for water')!;
      expect(s.detail, 'Time for water');
    });

    test('stale date is the due time, or the end of grace once late', () {
      final due = now.add(const Duration(hours: 4));
      expect(state(due: due)!.staleAt, due);
      final late = now.subtract(const Duration(hours: 4));
      expect(state(due: late)!.staleAt, late.add(const Duration(days: 4)));
    });

    test('the island is handed everything it draws', () {
      final map = state(due: now.add(const Duration(hours: 4)))!.toMap();
      expect(map['due_ms'], now.add(const Duration(hours: 4))
          .millisecondsSinceEpoch);
      expect(map['overdue'], false);
      expect(map.keys, containsAll(<String>[
        'due_ms', 'stale_ms', 'title', 'detail', 'water_ml', 'water_goal',
        'protein_g', 'protein_goal', 'pal_emoji', 'product_emoji',
      ]));
    });
  });

  group('island headline', () {
    final now = DateTime(2026, 9, 16, 12);

    NotifLog log(String kind, {required int minutesAgo, String? action}) =>
        NotifLog(
          at: now.subtract(Duration(minutes: minutesAgo)),
          kind: kind,
          title: '$kind title',
          body: '$kind body',
          action: action,
        );

    test('echoes the most recent delivered nudge', () {
      final n = LiveActivities.headlineFrom(
          [log('water', minutesAgo: 5), log('meal', minutesAgo: 60)], now);
      expect(n?.kind, 'water');
    });

    test('ignores what the island already says itself', () {
      // The dose reminder, its heads-up and the warm-the-pen nudge all log as
      // kind 'shot', because Reminders takes the kind from the payload.
      final n = LiveActivities.headlineFrom(
          [log('shot', minutesAgo: 2), log('water', minutesAgo: 30)], now);
      expect(n?.kind, 'water');
      expect(LiveActivities.headlineFrom([log('shot', minutesAgo: 1)], now),
          isNull);
    });

    test('drops one already acted on', () {
      expect(
          LiveActivities.headlineFrom(
              [log('water', minutesAgo: 5, action: 'water 1')], now),
          isNull);
    });

    test('forgets a nudge once it is stale', () {
      expect(LiveActivities.headlineFrom([log('water', minutesAgo: 91)], now),
          isNull);
      expect(LiveActivities.headlineFrom([log('water', minutesAgo: 89)], now),
          isNotNull);
    });

    test('a reminder that has not fired yet is not a headline', () {
      final queued = NotifLog(
        at: now.add(const Duration(hours: 2)),
        kind: 'water',
        title: 'later',
        body: 'later',
      );
      expect(LiveActivities.headlineFrom([queued], now), isNull);
    });
  });
}
