import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pet.dart';
import '../xp.dart';

class CheckInScreen extends StatefulWidget {
  final VoidCallback? onSaved;

  /// yyyy-MM-dd to edit. Defaults to today; the calendar passes a past day.
  final String? day;
  const CheckInScreen({super.key, this.onSaved, this.day});
  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  late String _day;
  final _weight = TextEditingController();
  final _note = TextEditingController();
  int _water = 0;
  int _protein = 0;
  final _se = {for (final k in sideEffectKeys) k: 0};

  @override
  void initState() {
    super.initState();
    _day = widget.day ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    _load();
  }

  Future<void> _load() async {
    final l = await AppDb.instance.logFor(_day);
    final mealProtein = await AppDb.instance.proteinOn(_day);
    if (!mounted) return;
    if (l == null) {
      setState(() => _protein = mealProtein);
      return;
    }
    setState(() {
      _weight.text = l.weightKg?.toString() ?? '';
      _water = l.waterMl;
      _protein = l.proteinG > 0 ? l.proteinG : mealProtein;
      _note.text = l.note;
      _se.addAll(l.sideEffects);
    });
  }

  bool get _isToday => _day == DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<void> _save() async {
    await AppDb.instance.upsertLog(DailyLog(
      day: _day,
      weightKg: double.tryParse(_weight.text),
      waterMl: _water,
      proteinG: _protein,
      sideEffects: Map.of(_se),
      note: _note.text,
    ));
    widget.onSaved?.call();
    final xp = await Xp.compute();
    if (mounted) {
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isToday
              ? 'Saved! +${xp.today.earned} XP today ${petSpecies.value.icon}'
              : 'Saved ${DateFormat('MMM d').format(DateTime.parse(_day))} ${petSpecies.value.icon}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final glasses = (Goals.waterMl / kGlassMl).ceil();
    final filled = (_water / kGlassMl).floor();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        Text(DateFormat('EEEE, MMM d').format(DateTime.parse(_day)),
            style: theme.textTheme.headlineSmall),
        Text(
            _isToday
                ? "How's today going? A quick check-in keeps your buddy growing."
                : "Filling in a past day. Saving updates that day's log.",
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.3)),
        const SizedBox(height: 18),

        // Weight
        SoftCard(
          child: Row(
            children: [
              const _Bubble(emoji: '⚖️', color: Palette.lavender),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _weight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Weight',
                      suffixText: 'kg',
                      hintText: 'Optional'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Water
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _Bubble(emoji: '💧', color: Palette.sky),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Water', style: theme.textTheme.titleMedium),
                        Text('$_water of ${Goals.waterMl} ml · tap the glasses',
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  _RoundBtn(
                      Icons.remove_rounded,
                      () => setState(
                          () => _water = (_water - kGlassMl).clamp(0, 99999))),
                  const SizedBox(width: 6),
                  _RoundBtn(Icons.add_rounded,
                      () => setState(() => _water += kGlassMl),
                      filled: true),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (var i = 0; i < glasses; i++)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _water = (i + 1 == filled)
                            ? i * kGlassMl
                            : (i + 1) * kGlassMl),
                        child: AnimatedScale(
                          scale: i < filled ? 1.1 : 1,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            i < filled
                                ? Icons.water_drop_rounded
                                : Icons.water_drop_outlined,
                            size: 30,
                            color: i < filled
                                ? Palette.sky
                                : Palette.sky.withValues(alpha: .35),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Protein
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _Bubble(emoji: '🥩', color: Palette.mint),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Protein', style: theme.textTheme.titleMedium),
                        Text('Prefilled from logged meals',
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  _RoundBtn(
                      Icons.remove_rounded,
                      () => setState(
                          () => _protein = (_protein - 10).clamp(0, 99999))),
                  const SizedBox(width: 6),
                  _RoundBtn(
                      Icons.add_rounded, () => setState(() => _protein += 10),
                      filled: true),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('$_protein g',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: (_protein / Goals.proteinG).clamp(0, 1),
                        minHeight: 12,
                        color: Palette.mint,
                        backgroundColor: Palette.mint.withValues(alpha: .15),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('goal ${Goals.proteinG} g',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Side effects
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _Bubble(emoji: '🩺', color: Palette.peach),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('How do you feel?',
                            style: theme.textTheme.titleMedium),
                        Text('Tap a face for each one',
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final k in sideEffectKeys)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Text(sideEffectEmoji[k] ?? '•',
                          style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          k.replaceAll('_', ' '),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      for (var i = 0; i < 4; i++)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _Face(
                            emoji: severityFaces[i],
                            color: severityColors[i],
                            selected: _se[k] == i,
                            tooltip: severityLabels[i],
                            onTap: () => setState(() => _se[k] = i),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        TextField(
          controller: _note,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Anything else on your mind? (optional)',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.favorite_rounded),
          label: const Text('Save check-in'),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.emoji, required this.color});
  final String emoji;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
            shape: BoxShape.circle, color: color.withValues(alpha: .16)),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 22)),
      );
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn(this.icon, this.onTap, {this.filled = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: filled ? scheme.primary : scheme.primary.withValues(alpha: .12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon,
              size: 20, color: filled ? scheme.onPrimary : scheme.primary),
        ),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({
    required this.emoji,
    required this.color,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });
  final String emoji;
  final Color color;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? color : color.withValues(alpha: .12),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: color.withValues(alpha: .4),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: AnimatedScale(
            scale: selected ? 1.15 : 1,
            duration: const Duration(milliseconds: 180),
            child: Text(emoji, style: const TextStyle(fontSize: 18)),
          ),
        ),
      ),
    );
  }
}
