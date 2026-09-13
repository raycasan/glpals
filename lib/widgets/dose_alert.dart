import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../med.dart';
import '../theme.dart';
import 'common.dart';

/// Loud banner for a dose that is already late. Overdue is the one state in
/// this app that should not be easy to scroll past, so it gets its own colour
/// and its own two actions.
class OverdueBanner extends StatelessWidget {
  const OverdueBanner({
    super.key,
    required this.due,
    required this.product,
    required this.onLog,
    required this.onSkip,
  });

  final DateTime due;
  final GlpProduct product;
  final VoidCallback onLog;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final late = DateTime.now().difference(due);
    final withinWindow = product.schedule == MedSchedule.weekly &&
        late.inDays < product.makeUpDays;
    final noun = product.injected ? 'shot' : 'dose';
    return SoftCard(
      color: Palette.berry.withValues(alpha: .12),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Palette.berry.withValues(alpha: .18)),
                alignment: Alignment.center,
                child: const Text('⚠️', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your $noun is ${fmtCountdown(late)} overdue',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                            color: Palette.berry)),
                    Text(
                        'Was due ${DateFormat('EEE, MMM d · h:mm a').format(due)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(missedDoseText(product, late),
              style: const TextStyle(fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onLog,
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        withinWindow ? Palette.mint : Palette.berry,
                    minimumSize: const Size(0, 46),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Log it now'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSkip,
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 46),
                      side: BorderSide(
                          color: Palette.berry.withValues(alpha: .5),
                          width: 1.5),
                      foregroundColor: Palette.berry),
                  icon: const Icon(Icons.skip_next_rounded, size: 18),
                  label: const Text('Skip it'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Explains what skipping means for this product, then records the skip so the
/// countdown moves to the next scheduled dose. Returns true if it was skipped.
Future<bool> confirmSkipDose(
  BuildContext context, {
  required DateTime due,
  required GlpProduct product,
}) async {
  final late = DateTime.now().difference(due);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Skip this dose?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(missedDoseText(product, late),
                style: const TextStyle(fontSize: 13.5, height: 1.45)),
            const SizedBox(height: 12),
            const Text(
              'Skipping is recorded, not hidden: the countdown moves to your '
              'next scheduled dose and the skip stays in your history so you '
              'and your prescriber can see the gap.',
              style: TextStyle(fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 12),
            const Text(
              'Two or more skipped doses in a row is worth a call to your '
              'prescriber before you restart. Tolerance fades, and they often '
              'step the dose back down for a while.',
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                  color: Palette.berry),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not yet')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
              backgroundColor: Palette.berry, minimumSize: const Size(0, 44)),
          child: const Text('Skip this dose'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  await AppDb.instance.insertSkip(DoseSkip(
    plannedFor: due,
    skippedAt: DateTime.now(),
    note: product.brand,
  ));
  return true;
}

/// Read-only banner naming the product a dose will be logged against. The
/// product is deliberately not editable here: changing it is a prescriber
/// decision, so it lives behind the warning in Settings.
class ProductBanner extends StatelessWidget {
  const ProductBanner({super.key, required this.product, required this.doseMg});
  final GlpProduct product;
  final double doseMg;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          Text(product.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${product.brand} · ${fmtDose(doseMg)} mg',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14)),
                Text('${product.molecule} · ${product.schedule.label}',
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Tooltip(
            message: 'Change this in Settings',
            child: Icon(Icons.lock_outline_rounded,
                size: 18, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
