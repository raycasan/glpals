import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../med.dart';
import '../reminders.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dose_alert.dart';

class ShotScreen extends StatefulWidget {
  final VoidCallback? onSaved;
  const ShotScreen({super.key, this.onSaved});
  @override
  State<ShotScreen> createState() => _ShotScreenState();
}

class _ShotScreenState extends State<ShotScreen> {
  List<Shot> _shots = [];
  List<DoseSkip> _skips = [];
  String _suggested = injectionSites.first;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await AppDb.instance.shots();
    final n = await AppDb.instance.suggestedSite();
    final k = await AppDb.instance.skips();
    if (mounted) {
      setState(() {
        _shots = s;
        _suggested = n;
        _skips = k;
      });
    }
  }

  Future<void> _add() async {
    final db = AppDb.instance;
    final last = await db.lastShot();
    final suggested = await db.suggestedSite();
    final doseCtrl = TextEditingController(
        text: last == null ? '2.5' : fmtDose(last.doseMg));
    final noteCtrl = TextEditingController();
    var site = suggested;
    var when = DateTime.now();
    if (!mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Log a shot 💉',
                    style: Theme.of(ctx).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text('Nice work staying on schedule.',
                    style: TextStyle(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 14),
                ProductBanner(
                    product: MedPrefs.instance.product,
                    doseMg: MedPrefs.instance.doseMg),
                const SizedBox(height: 18),
                TextField(
                  controller: doseCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Dose as prescribed',
                    suffixText: 'mg',
                    prefixIcon: Icon(Icons.medication_rounded),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text('Injection site',
                        style: Theme.of(ctx).textTheme.titleMedium),
                    const Spacer(),
                    Text('Suggested: $suggested',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in injectionSites)
                      Pill(
                        label: s,
                        emoji: siteEmoji(s),
                        color: siteColor(s),
                        selected: s == site,
                        onTap: () => setD(() => site = s),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    prefixIcon: Icon(Icons.sticky_note_2_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Pill(
                    emoji: '🕒',
                    label: DateFormat('MMM d, h:mm a').format(when),
                    color: Palette.lavender,
                    onTap: () async {
                      final d = await showDatePicker(
                          context: ctx,
                          initialDate: when,
                          firstDate: DateTime(2024),
                          lastDate: DateTime.now());
                      if (d == null || !ctx.mounted) return;
                      final t = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay.fromDateTime(when));
                      setD(() => when = DateTime(d.year, d.month, d.day,
                          t?.hour ?? when.hour, t?.minute ?? when.minute));
                    },
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Save shot'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok == true) {
      final dose = double.tryParse(doseCtrl.text) ?? 0;
      await db.insertShot(Shot(
        takenAt: when,
        doseMg: dose,
        site: site,
        note: noteCtrl.text,
        product: MedPrefs.instance.product.id,
      ));
      _load();
      widget.onSaved?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = _shots.isEmpty ? null : _shots.first;
    final med = MedPrefs.instance;
    final lastSkip = _skips.isEmpty ? null : _skips.first;
    final nextAt = nextDoseAt(
      last: last,
      lastSkipPlannedFor: lastSkip?.plannedFor,
      intervalDays: med.intervalDays,
    );
    final left = nextAt?.difference(DateTime.now());
    final due = left != null && left.isNegative;
    final forecast = forecastDoses(
      last: last,
      intervalDays: med.intervalDays,
      count: 6,
      atMinutes: ReminderPrefs.instance.shotMinutes,
      lastSkipPlannedFor: lastSkip?.plannedFor,
    );

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'shot_fab',
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Log shot'),
      ),
      body: _shots.isEmpty
          ? EmptyState(
              emoji: '💉',
              title: 'No shots yet',
              body:
                  'Log your first dose and I will keep track of the weekly cycle and site rotation for you.',
              actionLabel: 'Log first shot',
              onAction: _add,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                if (due) ...[
                  OverdueBanner(
                    due: nextAt!,
                    product: med.product,
                    onLog: _add,
                    onSkip: () async {
                      final skipped = await confirmSkipDose(context,
                          due: nextAt, product: med.product);
                      if (skipped) {
                        await _load();
                        widget.onSaved?.call();
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                ],
                SoftCard(
                  gradient: Palette.ocean,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Next shot',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: .9),
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              due ? 'Today! 🎯' : 'in ${fmtCountdown(left!)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(color: Colors.white),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .22),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text('📍 Suggested site: $_suggested',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                      const Text('💉', style: TextStyle(fontSize: 52)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SectionTitle('Forecast',
                    emoji: '🔮',
                    trailing: Text(med.product.schedule.label,
                        style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600))),
                SoftCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Column(
                    children: [
                      for (final f in forecast)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              SiteBadge(f.site, size: 38),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(DateFormat('EEE, MMM d').format(f.due),
                                        style: TextStyle(
                                            fontWeight: f.index == 1
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                            fontSize: 14)),
                                    Text(
                                        '${f.site} · ${DateFormat('h:mm a').format(f.due)}',
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            color: scheme.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                              Builder(builder: (_) {
                                final left = f.due.difference(DateTime.now());
                                final late = left.isNegative;
                                return Text(
                                  late
                                      ? 'overdue'
                                      : f.index == 1
                                          ? 'next'
                                          : 'in ${fmtCountdown(left)}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: late
                                        ? Palette.berry
                                        : f.index == 1
                                            ? Palette.coral
                                            : scheme.onSurfaceVariant,
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10, top: 2),
                        child: Text(
                          'Projected from your last dose. Logging one early or '
                          'late shifts everything after it.',
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SectionTitle('History',
                    emoji: '📖',
                    trailing: Text(
                        '${_shots.length} logged'
                        '${_skips.isEmpty ? '' : ' · ${_skips.length} skipped'}',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600))),
                for (final k in _skips)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Dismissible(
                      key: ValueKey('skip_${k.id}'),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) => confirmDelete(
                        context,
                        title: 'Remove this skip?',
                        body:
                            'The schedule will go back to counting from your last actual dose.',
                        confirmLabel: 'Remove',
                      ),
                      background: Container(
                        decoration: BoxDecoration(
                          color: Palette.berry,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 22),
                        child: const Icon(Icons.delete_outline_rounded,
                            color: Colors.white),
                      ),
                      onDismissed: (_) async {
                        await AppDb.instance.deleteSkip(k.id!);
                        _load();
                        widget.onSaved?.call();
                      },
                      child: SoftCard(
                        padding: const EdgeInsets.all(14),
                        color: Palette.berry.withValues(alpha: .10),
                        child: Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Palette.berry.withValues(alpha: .16)),
                              alignment: Alignment.center,
                              child: const Icon(Icons.skip_next_rounded,
                                  color: Palette.berry),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Dose skipped',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          color: Palette.berry)),
                                  Text(
                                    'Was due ${DateFormat('EEE, MMM d').format(k.plannedFor)}'
                                    '${k.note.isEmpty ? '' : ' · ${k.note}'}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            Text(DateFormat('MMM d').format(k.plannedFor),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  ),
                for (final s in _shots)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Dismissible(
                      key: ValueKey(s.id),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) => confirmDelete(
                        context,
                        title: 'Delete this shot?',
                        body:
                            '${fmtDose(s.doseMg)} mg on ${DateFormat('EEE, MMM d').format(s.takenAt)} will be removed, and the schedule will shift.',
                      ),
                      background: Container(
                        decoration: BoxDecoration(
                          color: Palette.berry,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 22),
                        child: const Icon(Icons.delete_outline_rounded,
                            color: Colors.white),
                      ),
                      onDismissed: (_) async {
                        await AppDb.instance.deleteShot(s.id!);
                        _load();
                        widget.onSaved?.call();
                      },
                      child: SoftCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            SiteBadge(s.site, size: 50),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${fmtDose(s.doseMg)} mg · ${s.site}'
                                      '${s.product == null ? '' : ' · ${GlpProduct.byId(s.product).brand}'}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  Text(
                                    '${relativeDay(s.takenAt)} · ${DateFormat('h:mm a').format(s.takenAt)}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant),
                                  ),
                                  if (s.note.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(s.note,
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontStyle: FontStyle.italic,
                                              color: scheme.onSurfaceVariant)),
                                    ),
                                ],
                              ),
                            ),
                            Text(DateFormat('MMM d').format(s.takenAt),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
