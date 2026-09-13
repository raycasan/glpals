import 'package:flutter_test/flutter_test.dart';
import 'package:glp_buddy/db.dart';
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
}
