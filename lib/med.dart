import 'package:flutter/material.dart';

import 'db.dart';

/// How often a product is taken.
enum MedSchedule {
  weekly('Once a week', 7),
  daily('Once a day', 1);

  const MedSchedule(this.label, this.days);
  final String label;

  /// Days between doses.
  final int days;
}

/// A GLP-1 (or GLP-1/GIP) product the user might be on.
///
/// Doses are the usual titration steps printed on the pen or tablet; they are
/// here to make the dose picker easy, never to suggest a change. Every dose
/// decision belongs to the prescriber.
class GlpProduct {
  const GlpProduct({
    required this.id,
    required this.brand,
    required this.molecule,
    required this.maker,
    required this.schedule,
    required this.doses,
    this.injected = true,
    this.emoji = '💉',
    this.note = '',
  });

  final String id;
  final String brand;
  final String molecule;
  final String maker;
  final MedSchedule schedule;

  /// Usual dose steps in mg.
  final List<double> doses;

  /// False for the oral tablet, which changes the reminder wording.
  final bool injected;
  final String emoji;
  final String note;

  /// How long after the scheduled time a missed dose can still be taken,
  /// per the product labelling. Semaglutide allows 5 days, tirzepatide 4,
  /// dulaglutide 3. Daily products get 0: you simply take the next one.
  int get makeUpDays {
    if (schedule == MedSchedule.daily) return 0;
    final m = molecule.toLowerCase();
    if (m.contains('semaglutide')) return 5;
    if (m.contains('tirzepatide')) return 4;
    if (m.contains('dulaglutide')) return 3;
    return 3;
  }

  bool get isWeekly => schedule == MedSchedule.weekly;

  /// Pens are kept cold until first use, so they are worth warming before a
  /// shot. Tablets are not.
  bool get needsFridge => injected;

  String get subtitle => '$molecule · ${schedule.label}';

  static const all = [
    GlpProduct(
      id: 'mounjaro',
      brand: 'Mounjaro',
      molecule: 'Tirzepatide',
      maker: 'Eli Lilly',
      schedule: MedSchedule.weekly,
      doses: [2.5, 5, 7.5, 10, 12.5, 15],
    ),
    GlpProduct(
      id: 'zepbound',
      brand: 'Zepbound',
      molecule: 'Tirzepatide',
      maker: 'Eli Lilly',
      schedule: MedSchedule.weekly,
      doses: [2.5, 5, 7.5, 10, 12.5, 15],
    ),
    GlpProduct(
      id: 'ozempic',
      brand: 'Ozempic',
      molecule: 'Semaglutide',
      maker: 'Novo Nordisk',
      schedule: MedSchedule.weekly,
      doses: [0.25, 0.5, 1, 2],
    ),
    GlpProduct(
      id: 'wegovy',
      brand: 'Wegovy',
      molecule: 'Semaglutide',
      maker: 'Novo Nordisk',
      schedule: MedSchedule.weekly,
      doses: [0.25, 0.5, 1, 1.7, 2.4],
    ),
    GlpProduct(
      id: 'trulicity',
      brand: 'Trulicity',
      molecule: 'Dulaglutide',
      maker: 'Eli Lilly',
      schedule: MedSchedule.weekly,
      doses: [0.75, 1.5, 3, 4.5],
    ),
    GlpProduct(
      id: 'saxenda',
      brand: 'Saxenda',
      molecule: 'Liraglutide',
      maker: 'Novo Nordisk',
      schedule: MedSchedule.daily,
      doses: [0.6, 1.2, 1.8, 2.4, 3.0],
    ),
    GlpProduct(
      id: 'victoza',
      brand: 'Victoza',
      molecule: 'Liraglutide',
      maker: 'Novo Nordisk',
      schedule: MedSchedule.daily,
      doses: [0.6, 1.2, 1.8],
    ),
    GlpProduct(
      id: 'rybelsus',
      brand: 'Rybelsus',
      molecule: 'Semaglutide (tablet)',
      maker: 'Novo Nordisk',
      schedule: MedSchedule.daily,
      doses: [3, 7, 14],
      injected: false,
      emoji: '💊',
      note: 'Taken on an empty stomach with a sip of water, 30 minutes before '
          'anything else.',
    ),
    GlpProduct(
      id: 'compounded_sema',
      brand: 'Compounded semaglutide',
      molecule: 'Semaglutide',
      maker: 'Compounding pharmacy',
      schedule: MedSchedule.weekly,
      doses: [0.25, 0.5, 1, 1.7, 2.4],
      emoji: '🧪',
    ),
    GlpProduct(
      id: 'compounded_tirz',
      brand: 'Compounded tirzepatide',
      molecule: 'Tirzepatide',
      maker: 'Compounding pharmacy',
      schedule: MedSchedule.weekly,
      doses: [2.5, 5, 7.5, 10, 12.5, 15],
      emoji: '🧪',
    ),
    GlpProduct(
      id: 'other',
      brand: 'Something else',
      molecule: 'Other GLP-1',
      maker: '',
      schedule: MedSchedule.weekly,
      doses: [0.25, 0.5, 1, 2.5, 5, 7.5, 10],
      emoji: '❓',
    ),
  ];

  static GlpProduct byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => all.first);
}

/// Plain-language risk note shown before a product is changed.
///
/// Sources: no validated dose equivalence exists between molecules, so a
/// switch normally restarts titration at the lowest step; two brands of the
/// same molecule still differ in maximum dose and titration schedule.
String switchRiskText(GlpProduct from, GlpProduct to) {
  final sameMolecule = from.molecule.split(' ').first.toLowerCase() ==
      to.molecule.split(' ').first.toLowerCase();
  if (sameMolecule) {
    return 'Same active ingredient, different product. ${from.brand} and '
        '${to.brand} are still not interchangeable: the maximum doses and the '
        'titration steps differ, so matching the number on the pen can leave '
        'you under- or over-dosed. Your prescriber decides the starting dose '
        'and when to switch.';
  }
  return 'Different medicine. There is no validated dose equivalence between '
      '${from.molecule} and ${to.molecule}, so the milligrams do not carry '
      'over. A switch normally means starting again at the lowest dose and '
      'titrating up, even from a maximum dose. Going straight to a matching '
      'number raises the risk of severe nausea, vomiting and dehydration. '
      'Only your prescriber can make this change.';
}

/// What to do about a dose that is already late, per the product labelling.
String missedDoseText(GlpProduct p, Duration late) {
  if (p.schedule == MedSchedule.daily) {
    return 'This one is a daily ${p.injected ? 'injection' : 'tablet'}. Skip '
        'the missed one and take the next at your usual time. Never take two '
        'to catch up.';
  }
  final days = p.makeUpDays;
  final within = late.inDays < days;
  if (within) {
    return 'You are still inside the $days-day window for ${p.molecule}, so '
        'this dose can usually be taken now and your normal day kept. Never '
        'take two doses within 48 hours.';
  }
  return 'More than $days days late. For ${p.molecule} the usual advice is to '
      'skip this one and resume on your normal day rather than double up. If '
      'you have missed more than one dose, ask your prescriber before '
      'restarting: tolerance fades, and they often step the dose down for a '
      'while.';
}

/// The product, dose and start date the user told us about during onboarding.
class MedPrefs extends ChangeNotifier {
  MedPrefs._();
  static final MedPrefs instance = MedPrefs._();

  GlpProduct product = GlpProduct.all.first;
  double doseMg = 2.5;
  DateTime? startedOn;

  MedSchedule get schedule => product.schedule;

  /// Days between doses, the basis of every countdown.
  int get intervalDays => product.schedule.days;

  Future<void> load() async {
    final db = AppDb.instance;
    product = GlpProduct.byId(await db.getSetting('med_product'));
    doseMg = double.tryParse(await db.getSetting('med_dose_mg') ?? '') ??
        product.doses.first;
    final started = await db.getSetting('med_started_on');
    startedOn = started == null ? null : DateTime.tryParse(started);
    notifyListeners();
  }

  Future<void> save({
    GlpProduct? product,
    double? doseMg,
    DateTime? startedOn,

    /// Records the change in the medication history. Off for silent loads.
    bool record = true,
    String note = '',
  }) async {
    final db = AppDb.instance;
    final fromProduct = this.product;
    final fromDose = this.doseMg;
    final changedProduct = product != null && product.id != fromProduct.id;
    final changedDose = doseMg != null && doseMg != fromDose;
    if (product != null) {
      this.product = product;
      await db.setSetting('med_product', product.id);
    }
    if (doseMg != null) {
      this.doseMg = doseMg;
      await db.setSetting('med_dose_mg', '$doseMg');
    }
    if (startedOn != null) {
      this.startedOn = startedOn;
      await db.setSetting('med_started_on', startedOn.toIso8601String());
    }
    // History is append-only: switching never clears logs, it just opens a new
    // chapter that the trends and the shot list can be read against.
    if (record && (changedProduct || changedDose)) {
      final existing = await db.medChanges();
      await db.insertMedChange(MedChange(
        changedAt: DateTime.now(),
        fromProduct: existing.isEmpty ? null : fromProduct.id,
        fromDose: existing.isEmpty ? null : fromDose,
        toProduct: this.product.id,
        toDose: this.doseMg,
        note: note,
      ));
    }
    notifyListeners();
  }
}

/// When the next dose is due.
///
/// Anchored to the last dose actually taken, or to a dose that was
/// deliberately skipped: skipping moves the schedule on without pretending an
/// injection happened.
DateTime? nextDoseAt({
  required Shot? last,
  required DateTime? lastSkipPlannedFor,
  required int intervalDays,
}) {
  final fromShot = last?.takenAt.add(Duration(days: intervalDays));
  final fromSkip = lastSkipPlannedFor?.add(Duration(days: intervalDays));
  if (fromShot == null) return fromSkip;
  if (fromSkip == null) return fromShot;
  return fromSkip.isAfter(fromShot) ? fromSkip : fromShot;
}

/// A dose that has not happened yet.
class ForecastDose {
  const ForecastDose(
      {required this.due, required this.site, required this.index});

  final DateTime due;

  /// Where the rotation lands for this one.
  final String site;

  /// 1 for the next dose, 2 for the one after, and so on.
  final int index;
}

/// Projects the next [count] doses from the last logged one.
///
/// The schedule is simply the last dose plus the product's interval, repeated,
/// with the injection site continuing the rotation. It is a projection, not a
/// prescription: logging a dose early or late moves everything after it.
List<ForecastDose> forecastDoses({
  required Shot? last,
  required int intervalDays,
  int count = 6,
  DateTime? from,
  int? atMinutes,
  DateTime? lastSkipPlannedFor,
}) {
  final now = from ?? DateTime.now();
  var when = last?.takenAt ?? now;
  if (lastSkipPlannedFor != null && lastSkipPlannedFor.isAfter(when)) {
    when = lastSkipPlannedFor;
  }
  var siteIndex = last == null ? -1 : injectionSites.indexOf(last.site);
  final out = <ForecastDose>[];
  for (var i = 1; i <= count; i++) {
    when = when.add(Duration(days: intervalDays));
    siteIndex = (siteIndex + 1) % injectionSites.length;
    final due = atMinutes == null
        ? when
        : DateTime(
            when.year, when.month, when.day, atMinutes ~/ 60, atMinutes % 60);
    out.add(ForecastDose(
        due: due, site: injectionSites[siteIndex], index: out.length + 1));
  }
  return out;
}

/// Body measurements and activity, the inputs behind the suggested targets.
///
/// Everything is optional: with no weight the app falls back to the generic
/// defaults rather than guessing.
class Profile extends ChangeNotifier {
  Profile._();
  static final Profile instance = Profile._();

  double? weightKg;
  double? goalWeightKg;
  double? heightCm;
  String activity = 'light';

  bool get hasWeight => (weightKg ?? 0) > 0;

  /// Body mass index, when both numbers are known.
  double? get bmi {
    final w = weightKg, h = heightCm;
    if (w == null || h == null || h <= 0) return null;
    return w / ((h / 100) * (h / 100));
  }

  /// How far there is to go, when a goal is set.
  double? get toGoalKg {
    final w = weightKg, g = goalWeightKg;
    if (w == null || g == null) return null;
    return w - g;
  }

  Future<void> load() async {
    final db = AppDb.instance;
    Future<double?> d(String k) async =>
        double.tryParse(await db.getSetting(k) ?? '');
    weightKg = await d('profile_weight_kg');
    goalWeightKg = await d('profile_goal_weight_kg');
    heightCm = await d('profile_height_cm');
    activity = await db.getSetting('profile_activity') ?? 'light';
    // A weight logged in a check-in is fresher than one typed at setup.
    final logs = await db.allLogs();
    final weighed = logs.where((l) => l.weightKg != null);
    if (weighed.isNotEmpty) weightKg = weighed.last.weightKg;
    notifyListeners();
  }

  Future<void> save({
    double? weightKg,
    double? goalWeightKg,
    double? heightCm,
    String? activity,
  }) async {
    final db = AppDb.instance;
    if (weightKg != null) {
      this.weightKg = weightKg;
      await db.setSetting('profile_weight_kg', '$weightKg');
    }
    if (goalWeightKg != null) {
      this.goalWeightKg = goalWeightKg;
      await db.setSetting('profile_goal_weight_kg', '$goalWeightKg');
    }
    if (heightCm != null) {
      this.heightCm = heightCm;
      await db.setSetting('profile_height_cm', '$heightCm');
    }
    if (activity != null) {
      this.activity = activity;
      await db.setSetting('profile_activity', activity);
    }
    notifyListeners();
  }
}
